using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = args, WebRootPath = ResolveWebRoot() });
builder.WebHost.UseUrls("http://127.0.0.1:8000");
builder.Services.AddProblemDetails();
var db = new GameDatabase();
await db.InitializeAsync();

var app = builder.Build();
app.UseExceptionHandler();
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/health", async (CancellationToken ct) =>
{
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand("SELECT 1", connection);
    await command.ExecuteScalarAsync(ct);
    return Results.Ok(new { status = "ok", database = "connected" });
});

app.MapPost("/api/sessions", async (SessionInput input, CancellationToken ct) =>
{
    var name = new string((input.PlayerName ?? "").Where(c => !char.IsControl(c)).ToArray()).Trim();
    if (name.Length == 0) name = "Jugador";
    if (name.Length > 40) name = name[..40];
    if (input.ClientSessionId == Guid.Empty)
        return Results.BadRequest(new { error = "client_session_id inválido." });
    var sessionId = input.ClientSessionId ?? Guid.NewGuid();

    await using var connection = await db.OpenAsync(ct);
    var existingName = await FindSessionName(connection, sessionId, ct);
    if (existingName is not null)
        return Results.Ok(new { id = sessionId, player_name = existingName });
    await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
    try
    {
        await using (var playerCommand = new SqlCommand(
            "INSERT INTO dbo.Players (DisplayName) OUTPUT INSERTED.PlayerId VALUES (@name)", connection, transaction))
        {
            playerCommand.Parameters.Add("@name", SqlDbType.NVarChar, 40).Value = name;
            var playerId = (int)(await playerCommand.ExecuteScalarAsync(ct))!;
            await using var sessionCommand = new SqlCommand(
                "INSERT INTO dbo.GameSessions (SessionId, PlayerId) VALUES (@session, @player)", connection, transaction);
            sessionCommand.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = sessionId;
            sessionCommand.Parameters.Add("@player", SqlDbType.Int).Value = playerId;
            await sessionCommand.ExecuteNonQueryAsync(ct);
        }
        await transaction.CommitAsync(ct);
    }
    catch (SqlException ex) when (IsUniqueViolation(ex))
    {
        await transaction.RollbackAsync(ct);
        existingName = await FindSessionName(connection, sessionId, ct);
        if (existingName is not null)
            return Results.Ok(new { id = sessionId, player_name = existingName });
        return Results.Conflict(new { error = "El identificador de sesión ya existe." });
    }
    return Results.Created($"/api/sessions/{sessionId}", new { id = sessionId, player_name = name });
});

app.MapPost("/api/attempts", async (AttemptInput input, CancellationToken ct) =>
{
    if (input.ClientAttemptId is null || input.ClientAttemptId == Guid.Empty || input.SessionId == Guid.Empty ||
        (input.Mode is not ("story" or "free" or "map_test")) ||
        input.MapId is <= 0 || (input.MapName?.Length ?? 0) > 100 ||
        (input.MapName?.Any(char.IsControl) ?? false))
        return Results.BadRequest(new { error = "Intento inválido." });
    var custom = input.Mode == "map_test";
    if (custom ? input.LevelId is not null || input.MapData is not { ValueKind: JsonValueKind.Object }
               : input.LevelId is null or <= 0 || input.MapId is not null || input.MapData is not null)
        return Results.BadRequest(new { error = "Nivel o mapa del intento inválido." });
    var mapData = custom ? input.MapData!.Value.GetRawText() : null;
    if (mapData?.Length > 524288)
        return Results.BadRequest(new { error = "Mapa demasiado grande." });
    var mapName = custom ? (input.MapName?.Trim() is { Length: > 0 } value ? value : "Mapa sin nombre") : null;

    await using var connection = await db.OpenAsync(ct);
    var existing = await FindAttempt(connection, input.ClientAttemptId.Value, ct);
    if (existing is not null)
        return existing.Value.SessionId == input.SessionId && existing.Value.LevelId == input.LevelId &&
               existing.Value.MapId == input.MapId && existing.Value.Mode == input.Mode
            ? Results.Ok(new { id = input.ClientAttemptId, started_at = UtcString(existing.Value.StartedAt) })
            : Results.Conflict(new { error = "El identificador de intento ya pertenece a otra partida." });
    if (!await SessionExists(connection, input.SessionId, ct))
        return Results.NotFound(new { error = "La sesión no existe." });
    await using var command = new SqlCommand("""
        INSERT INTO dbo.LevelAttempts
            (AttemptId, SessionId, LevelId, MapId, Mode, MapName, MapDataJson)
        OUTPUT INSERTED.StartedAt
        VALUES (@id, @session, @level, @map, @mode, @name, @data)
        """, connection);
    command.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = input.ClientAttemptId.Value;
    command.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = input.SessionId;
    command.Parameters.Add("@level", SqlDbType.Int).Value = (object?)input.LevelId ?? DBNull.Value;
    command.Parameters.Add("@map", SqlDbType.Int).Value = (object?)input.MapId ?? DBNull.Value;
    command.Parameters.Add("@mode", SqlDbType.VarChar, 20).Value = input.Mode!;
    command.Parameters.Add("@name", SqlDbType.NVarChar, 100).Value = (object?)mapName ?? DBNull.Value;
    command.Parameters.Add("@data", SqlDbType.NVarChar, -1).Value = (object?)mapData ?? DBNull.Value;
    try
    {
        var startedAt = (DateTime)(await command.ExecuteScalarAsync(ct))!;
        return Results.Created($"/api/replays/{input.ClientAttemptId}",
            new { id = input.ClientAttemptId, started_at = UtcString(startedAt) });
    }
    catch (SqlException ex) when (IsUniqueViolation(ex))
    {
        existing = await FindAttempt(connection, input.ClientAttemptId.Value, ct);
        return existing is not null && existing.Value.SessionId == input.SessionId &&
               existing.Value.LevelId == input.LevelId && existing.Value.MapId == input.MapId &&
               existing.Value.Mode == input.Mode
            ? Results.Ok(new { id = input.ClientAttemptId, started_at = UtcString(existing.Value.StartedAt) })
            : Results.Conflict(new { error = "El identificador de intento ya pertenece a otra partida." });
    }
});

app.MapPost("/api/events", async (EventInput input, CancellationToken ct) =>
{
    if (input.SessionId == Guid.Empty || input.ClientEventId == Guid.Empty || input.AttemptId == Guid.Empty || input.LevelId is <= 0 ||
        !Regex.IsMatch(input.EventType ?? "", "^[a-z][a-z0-9_]{0,39}$") ||
        !ValidSeconds(input.ElapsedSeconds) || input.FruitsCollected < 0 || input.CoinsCollected < 0)
        return Results.BadRequest(new { error = "Evento inválido." });
    if (input.Details is { ValueKind: not JsonValueKind.Object })
        return Results.BadRequest(new { error = "details debe ser un objeto JSON." });
    var details = input.Details is { ValueKind: JsonValueKind.Object } value ? value.GetRawText() : "{}";
    if (details.Length > 16384)
        return Results.BadRequest(new { error = "Detalles demasiado grandes." });

    await using var connection = await db.OpenAsync(ct);
    if (input.ClientEventId is Guid eventKey)
    {
        var existingId = await FindEvent(connection, eventKey, input.SessionId, ct);
        if (existingId is not null) return Results.Ok(new { id = existingId });
    }
    if (!await SessionExists(connection, input.SessionId, ct))
        return Results.NotFound(new { error = "La sesión no existe." });
    if (input.AttemptId is Guid eventAttempt &&
        !await AttemptMatches(connection, eventAttempt, input.SessionId, input.LevelId, false, ct))
        return Results.BadRequest(new { error = "El intento no corresponde a la sesión y al nivel." });
    await using var command = new SqlCommand("""
        INSERT INTO dbo.GameplayEvents
            (ClientEventId, SessionId, AttemptId, LevelId, EventType, ElapsedMs, FruitsCollected, CoinsCollected, DetailsJson)
        OUTPUT INSERTED.EventId
        VALUES (@client, @session, @attempt, @level, @type, @elapsed, @fruits, @coins, @details)
        """, connection);
    command.Parameters.Add("@client", SqlDbType.UniqueIdentifier).Value = (object?)input.ClientEventId ?? DBNull.Value;
    command.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = input.SessionId;
    command.Parameters.Add("@attempt", SqlDbType.UniqueIdentifier).Value = (object?)input.AttemptId ?? DBNull.Value;
    command.Parameters.Add("@level", SqlDbType.Int).Value = (object?)input.LevelId ?? DBNull.Value;
    command.Parameters.Add("@type", SqlDbType.NVarChar, 40).Value = input.EventType;
    command.Parameters.Add("@elapsed", SqlDbType.BigInt).Value = Milliseconds(input.ElapsedSeconds);
    command.Parameters.Add("@fruits", SqlDbType.Int).Value = input.FruitsCollected;
    command.Parameters.Add("@coins", SqlDbType.Int).Value = input.CoinsCollected;
    command.Parameters.Add("@details", SqlDbType.NVarChar, -1).Value = details;
    try
    {
        var id = (long)(await command.ExecuteScalarAsync(ct))!;
        return Results.Created($"/api/events/{id}", new { id });
    }
    catch (SqlException ex) when (IsUniqueViolation(ex) && input.ClientEventId is not null)
    {
        var id = await FindEvent(connection, input.ClientEventId.Value, input.SessionId, ct);
        return id is null ? Results.Conflict(new { error = "Identificador de evento duplicado." }) : Results.Ok(new { id });
    }
});

app.MapPost("/api/runs", async (RunInput input, CancellationToken ct) =>
{
    if (input.SessionId == Guid.Empty || input.ClientRunId == Guid.Empty || input.AttemptId == Guid.Empty || input.LevelId <= 0 || !ValidSeconds(input.ElapsedSeconds) ||
        input.FruitsCollected < 0 || input.FruitsTotal < 0 ||
        input.FruitsCollected > input.FruitsTotal || input.CoinsCollected < 0)
        return Results.BadRequest(new { error = "Datos del nivel inválidos." });
    var category = input.FruitsCollected == input.FruitsTotal ? "all_fruits" : "any_percent";

    await using var connection = await db.OpenAsync(ct);
    if (input.ClientRunId is Guid runKey)
    {
        var existingRun = await FindRun(connection, runKey, input.SessionId, ct);
        if (existingRun is not null) return Results.Ok(new { id = existingRun.Value.Id, category = existingRun.Value.Category });
    }
    if (!await SessionExists(connection, input.SessionId, ct))
        return Results.NotFound(new { error = "La sesión no existe." });
    if (input.AttemptId is Guid runAttempt &&
        !await AttemptMatches(connection, runAttempt, input.SessionId, input.LevelId, true, ct))
        return Results.BadRequest(new { error = "El intento no corresponde a la sesión y al nivel." });
    await using var command = new SqlCommand("""
        INSERT INTO dbo.LevelRuns
            (ClientRunId, SessionId, AttemptId, LevelId, Category, ElapsedMs, FruitsCollected, FruitsTotal, CoinsCollected)
        OUTPUT INSERTED.RunId
        VALUES (@client, @session, @attempt, @level, @category, @elapsed, @fruits, @total, @coins)
        """, connection);
    command.Parameters.Add("@client", SqlDbType.UniqueIdentifier).Value = (object?)input.ClientRunId ?? DBNull.Value;
    command.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = input.SessionId;
    command.Parameters.Add("@attempt", SqlDbType.UniqueIdentifier).Value = (object?)input.AttemptId ?? DBNull.Value;
    command.Parameters.Add("@level", SqlDbType.Int).Value = input.LevelId;
    command.Parameters.Add("@category", SqlDbType.VarChar, 20).Value = category;
    command.Parameters.Add("@elapsed", SqlDbType.BigInt).Value = Milliseconds(input.ElapsedSeconds);
    command.Parameters.Add("@fruits", SqlDbType.Int).Value = input.FruitsCollected;
    command.Parameters.Add("@total", SqlDbType.Int).Value = input.FruitsTotal;
    command.Parameters.Add("@coins", SqlDbType.Int).Value = input.CoinsCollected;
    try
    {
        var id = (long)(await command.ExecuteScalarAsync(ct))!;
        return Results.Created($"/api/runs/{id}", new { id, category });
    }
    catch (SqlException ex) when (IsUniqueViolation(ex) && input.ClientRunId is not null)
    {
        var existingRun = await FindRun(connection, input.ClientRunId.Value, input.SessionId, ct);
        return existingRun is null ? Results.Conflict(new { error = "Identificador de partida duplicado." })
            : Results.Ok(new { id = existingRun.Value.Id, category = existingRun.Value.Category });
    }
});

app.MapGet("/api/leaderboards", async (int level_id, string category, CancellationToken ct) =>
{
    if (level_id <= 0 || category is not ("any_percent" or "all_fruits"))
        return Results.BadRequest(new { error = "Nivel o categoría inválidos." });
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand("""
        SELECT TOP (10) p.DisplayName, r.ElapsedMs, r.FruitsCollected, r.CoinsCollected,
               r.RunId, r.AttemptId
        FROM dbo.LevelRuns r
        JOIN dbo.GameSessions s ON s.SessionId = r.SessionId
        JOIN dbo.Players p ON p.PlayerId = s.PlayerId
        WHERE r.LevelId = @level AND r.Category = @category
        ORDER BY r.ElapsedMs ASC, r.RunId ASC
        """, connection);
    command.Parameters.Add("@level", SqlDbType.Int).Value = level_id;
    command.Parameters.Add("@category", SqlDbType.VarChar, 20).Value = category;
    var records = new List<object>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
        records.Add(new { name = reader.GetString(0), seconds = reader.GetInt64(1) / 1000.0,
            fruits_collected = reader.GetInt32(2), coins_collected = reader.GetInt32(3),
            run_id = reader.GetInt64(4), attempt_id = reader.IsDBNull(5) ? (Guid?)null : reader.GetGuid(5) });
    return Results.Ok(records);
});

app.MapGet("/api/replays", async (int? level_id, int? map_id, CancellationToken ct) =>
{
    if (level_id is <= 0 || map_id is <= 0)
        return Results.BadRequest(new { error = "Filtro de nivel o mapa inválido." });
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand("""
        SELECT TOP (100) a.AttemptId, p.DisplayName, a.LevelId, a.MapId, a.MapName,
               a.Mode, a.StartedAt, r.CompletedAt, done.CompletedAt, r.ElapsedMs,
               done.CompletedElapsedMs, latest.ElapsedMs, r.Category,
               r.FruitsCollected, latest.FruitsCollected, r.CoinsCollected,
               latest.CoinsCollected, stats.EventCount
        FROM dbo.LevelAttempts a
        JOIN dbo.GameSessions s ON s.SessionId = a.SessionId
        JOIN dbo.Players p ON p.PlayerId = s.PlayerId
        LEFT JOIN dbo.LevelRuns r ON r.AttemptId = a.AttemptId
        OUTER APPLY (
            SELECT COUNT_BIG(*) AS EventCount FROM dbo.GameplayEvents e
            WHERE e.AttemptId = a.AttemptId
        ) stats
        OUTER APPLY (
            SELECT TOP (1) e.ElapsedMs, e.FruitsCollected, e.CoinsCollected
            FROM dbo.GameplayEvents e WHERE e.AttemptId = a.AttemptId
            ORDER BY e.ElapsedMs DESC, e.EventId DESC
        ) latest
        OUTER APPLY (
            SELECT TOP (1) e.OccurredAt AS CompletedAt, e.ElapsedMs AS CompletedElapsedMs
            FROM dbo.GameplayEvents e WHERE e.AttemptId = a.AttemptId
                AND e.EventType IN (N'level_completed', N'map_test_completed')
            ORDER BY e.ElapsedMs DESC, e.EventId DESC
        ) done
        WHERE (@level IS NULL OR a.LevelId = @level)
          AND (@map IS NULL OR a.MapId = @map)
        ORDER BY a.StartedAt DESC, a.AttemptId DESC
        """, connection);
    command.Parameters.Add("@level", SqlDbType.Int).Value = (object?)level_id ?? DBNull.Value;
    command.Parameters.Add("@map", SqlDbType.Int).Value = (object?)map_id ?? DBNull.Value;
    var replays = new List<object>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
    {
        var endedAt = !reader.IsDBNull(7) ? reader.GetDateTime(7)
            : !reader.IsDBNull(8) ? reader.GetDateTime(8) : (DateTime?)null;
        var elapsedMs = !reader.IsDBNull(9) ? reader.GetInt64(9)
            : !reader.IsDBNull(10) ? reader.GetInt64(10)
            : !reader.IsDBNull(11) ? reader.GetInt64(11) : (long?)null;
        replays.Add(new {
            id = reader.GetGuid(0), name = reader.GetString(1),
            level_id = reader.IsDBNull(2) ? (int?)null : reader.GetInt32(2),
            map_id = reader.IsDBNull(3) ? (int?)null : reader.GetInt32(3),
            map_name = reader.IsDBNull(4) ? null : reader.GetString(4), mode = reader.GetString(5),
            started_at = UtcString(reader.GetDateTime(6)),
            ended_at = endedAt is null ? null : UtcString(endedAt.Value),
            seconds = elapsedMs / 1000.0, completed = endedAt is not null,
            category = reader.IsDBNull(12) ? null : reader.GetString(12),
            fruits_collected = !reader.IsDBNull(13) ? reader.GetInt32(13)
                : !reader.IsDBNull(14) ? reader.GetInt32(14) : 0,
            coins_collected = !reader.IsDBNull(15) ? reader.GetInt32(15)
                : !reader.IsDBNull(16) ? reader.GetInt32(16) : 0,
            event_count = reader.GetInt64(17), has_replay = reader.GetInt64(17) > 0
        });
    }
    return Results.Ok(replays);
});

app.MapGet("/api/replays/{id:guid}", async (Guid id, CancellationToken ct) =>
{
    await using var connection = await db.OpenAsync(ct);
    await using var attemptCommand = new SqlCommand("""
        SELECT p.DisplayName, a.LevelId, a.MapId, a.MapName, a.MapDataJson, a.Mode,
               a.StartedAt, r.RunId, r.Category, r.ElapsedMs, r.FruitsCollected,
               r.FruitsTotal, r.CoinsCollected, r.CompletedAt
        FROM dbo.LevelAttempts a
        JOIN dbo.GameSessions s ON s.SessionId = a.SessionId
        JOIN dbo.Players p ON p.PlayerId = s.PlayerId
        LEFT JOIN dbo.LevelRuns r ON r.AttemptId = a.AttemptId
        WHERE a.AttemptId = @id
        """, connection);
    attemptCommand.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
    string name, mode;
    int? levelId, mapId;
    string? mapName, mapData;
    DateTime startedAt;
    DateTime? runCompletedAt = null;
    long? runElapsedMs = null;
    object? run = null;
    await using (var reader = await attemptCommand.ExecuteReaderAsync(ct))
    {
        if (!await reader.ReadAsync(ct)) return Results.NotFound(new { error = "Intento no encontrado." });
        name = reader.GetString(0);
        levelId = reader.IsDBNull(1) ? null : reader.GetInt32(1);
        mapId = reader.IsDBNull(2) ? null : reader.GetInt32(2);
        mapName = reader.IsDBNull(3) ? null : reader.GetString(3);
        mapData = reader.IsDBNull(4) ? null : reader.GetString(4);
        mode = reader.GetString(5);
        startedAt = reader.GetDateTime(6);
        if (!reader.IsDBNull(7))
        {
            runElapsedMs = reader.GetInt64(9);
            runCompletedAt = reader.GetDateTime(13);
            run = new { id = reader.GetInt64(7), category = reader.GetString(8),
                seconds = reader.GetInt64(9) / 1000.0, fruits_collected = reader.GetInt32(10),
                fruits_total = reader.GetInt32(11), coins_collected = reader.GetInt32(12),
                completed_at = UtcString(reader.GetDateTime(13)) };
        }
    }

    var events = new List<object>();
    DateTime? completedAt = null;
    long? completedElapsedMs = null;
    long? lastElapsedMs = null;
    await using var eventsCommand = new SqlCommand("""
        SELECT EventId, EventType, ElapsedMs, FruitsCollected, CoinsCollected,
               DetailsJson, OccurredAt
        FROM dbo.GameplayEvents WHERE AttemptId = @id
        ORDER BY ElapsedMs ASC, EventId ASC
        """, connection);
    eventsCommand.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
    await using (var reader = await eventsCommand.ExecuteReaderAsync(ct))
        while (await reader.ReadAsync(ct))
        {
            var eventType = reader.GetString(1);
            lastElapsedMs = reader.GetInt64(2);
            if (eventType is "level_completed" or "map_test_completed")
            {
                completedAt = reader.GetDateTime(6);
                completedElapsedMs = reader.GetInt64(2);
            }
            events.Add(new { id = reader.GetInt64(0), event_type = eventType,
                seconds = reader.GetInt64(2) / 1000.0, fruits_collected = reader.GetInt32(3),
                coins_collected = reader.GetInt32(4), details = ParseJson(reader.GetString(5)),
                occurred_at = UtcString(reader.GetDateTime(6)) });
        }
    var endedAt = runCompletedAt ?? completedAt;
    var seconds = (runElapsedMs ?? completedElapsedMs ?? lastElapsedMs) / 1000.0;
    return Results.Ok(new {
        attempt = new { id, name, level_id = levelId, map_id = mapId, map_name = mapName,
            mode, started_at = UtcString(startedAt),
            ended_at = endedAt is null ? null : UtcString(endedAt.Value),
            seconds, completed = endedAt is not null },
        run, events,
        map = mapData is null ? null : (object)new { id = mapId, name = mapName, data = ParseJson(mapData) }
    });
});

app.MapGet("/api/maps", async (CancellationToken ct) =>
{
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand(
        "SELECT MapId, Name, DataJson FROM dbo.CustomMaps ORDER BY UpdatedAt DESC, MapId DESC", connection);
    var maps = new List<object>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
        maps.Add(new { id = reader.GetInt32(0), name = reader.GetString(1), data = ParseJson(reader.GetString(2)) });
    return Results.Ok(maps);
});

app.MapGet("/api/maps/{id:int}", async (int id, CancellationToken ct) =>
{
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand(
        "SELECT Name, DataJson FROM dbo.CustomMaps WHERE MapId = @id", connection);
    command.Parameters.Add("@id", SqlDbType.Int).Value = id;
    await using var reader = await command.ExecuteReaderAsync(ct);
    if (!await reader.ReadAsync(ct)) return Results.NotFound(new { error = "Mapa no encontrado." });
    return Results.Ok(new { id, name = reader.GetString(0), data = ParseJson(reader.GetString(1)) });
});

app.MapPost("/api/maps", async (MapInput input, CancellationToken ct) =>
{
    if (!ValidMap(input)) return Results.BadRequest(new { error = "El mapa necesita nombre y datos JSON." });
    var name = input.Name!.Trim();
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand(
        "INSERT INTO dbo.CustomMaps (Name, DataJson) OUTPUT INSERTED.MapId VALUES (@name, @data)", connection);
    command.Parameters.Add("@name", SqlDbType.NVarChar, 100).Value = name;
    command.Parameters.Add("@data", SqlDbType.NVarChar, -1).Value = input.Data.GetRawText();
    var id = (int)(await command.ExecuteScalarAsync(ct))!;
    return Results.Created($"/api/maps/{id}", new { id, name, data = input.Data });
});

app.MapPut("/api/maps/{id:int}", async (int id, MapInput input, CancellationToken ct) =>
{
    if (id <= 0 || !ValidMap(input)) return Results.BadRequest(new { error = "Mapa inválido." });
    var name = input.Name!.Trim();
    await using var connection = await db.OpenAsync(ct);
    await using var command = new SqlCommand("""
        UPDATE dbo.CustomMaps SET Name = @name, DataJson = @data, UpdatedAt = SYSUTCDATETIME()
        WHERE MapId = @id
        """, connection);
    command.Parameters.Add("@id", SqlDbType.Int).Value = id;
    command.Parameters.Add("@name", SqlDbType.NVarChar, 100).Value = name;
    command.Parameters.Add("@data", SqlDbType.NVarChar, -1).Value = input.Data.GetRawText();
    if (await command.ExecuteNonQueryAsync(ct) == 0)
        return Results.NotFound(new { error = "Mapa no encontrado." });
    return Results.Ok(new { id, name, data = input.Data });
});

app.MapGet("/api/analytics", async (int? level_id, int? map_id, string? player_name, CancellationToken ct) =>
{
    if (level_id is <= 0 || map_id is <= 0 || (level_id is not null && map_id is not null))
        return Results.BadRequest(new { error = "Selecciona un nivel o un mapa válido, no ambos." });
    var playerName = player_name?.Trim();
    if (playerName?.Length > 40 || (playerName?.Any(char.IsControl) ?? false))
        return Results.BadRequest(new { error = "Nombre de jugador inválido." });
    if (playerName?.Length == 0) playerName = null;

    await using var connection = await db.OpenAsync(ct);
    var deathHotspots = new List<object>();
    var trampolineZones = new List<object>();
    const string locationsSql = """
        WITH Points AS (
            SELECT COALESCE(a.LevelId, e.LevelId) AS LevelId,
                   CASE WHEN COALESCE(a.LevelId, e.LevelId) IS NULL
                        THEN COALESCE(a.MapId, CASE WHEN d.LegacyMapId > 0 THEN d.LegacyMapId END)
                   END AS MapId,
                   CONVERT(nvarchar(100), COALESCE(m.Name, a.MapName,
                       NULLIF(d.LegacyMapName, N''), N'Mapa sin guardar')) AS MapName,
                   CASE WHEN e.EventType = N'trampoline_bounce' AND d.TrampolineX IS NOT NULL
                             AND d.TrampolineY IS NOT NULL THEN d.TrampolineX ELSE d.X END AS X,
                   CASE WHEN e.EventType = N'trampoline_bounce' AND d.TrampolineX IS NOT NULL
                             AND d.TrampolineY IS NOT NULL THEN d.TrampolineY ELSE d.Y END AS Y,
                   CASE WHEN e.EventType = N'trampoline_bounce' AND d.TrampolineX IS NOT NULL
                             AND d.TrampolineY IS NOT NULL THEN 1 ELSE 0 END AS ExactTrampoline
            FROM dbo.GameplayEvents e
            LEFT JOIN dbo.LevelAttempts a ON a.AttemptId = e.AttemptId
            OUTER APPLY (SELECT TRY_CONVERT(int, JSON_VALUE(e.DetailsJson, '$.map_id')) AS LegacyMapId,
                                JSON_VALUE(e.DetailsJson, '$.map_name') AS LegacyMapName,
                                TRY_CONVERT(float, JSON_VALUE(e.DetailsJson, '$.x')) AS X,
                                TRY_CONVERT(float, JSON_VALUE(e.DetailsJson, '$.y')) AS Y,
                                TRY_CONVERT(float, JSON_VALUE(e.DetailsJson, '$.trampoline_x')) AS TrampolineX,
                                TRY_CONVERT(float, JSON_VALUE(e.DetailsJson, '$.trampoline_y')) AS TrampolineY) d
            LEFT JOIN dbo.CustomMaps m ON m.MapId = COALESCE(a.MapId,
                CASE WHEN d.LegacyMapId > 0 THEN d.LegacyMapId END)
            WHERE e.EventType = @type
        ), Buckets AS (
            SELECT LevelId, MapId, CASE WHEN LevelId IS NULL THEN MapName END AS MapName,
                   CONVERT(float, CASE WHEN ExactTrampoline = 1 THEN X
                       ELSE FLOOR(X / 64.0) * 64.0 + 32.0 END) AS X,
                   CONVERT(float, CASE WHEN ExactTrampoline = 1 THEN Y
                       ELSE FLOOR(Y / 64.0) * 64.0 + 32.0 END) AS Y
            FROM Points
            WHERE X IS NOT NULL AND Y IS NOT NULL
              AND (LevelId IS NOT NULL OR MapId IS NOT NULL OR MapName <> N'Mapa sin guardar')
              AND (@level IS NULL OR LevelId = @level)
              AND (@map IS NULL OR MapId = @map)
        )
        SELECT TOP (300) LevelId, MapId, MapName, X, Y, COUNT_BIG(*) AS EventCount
        FROM Buckets
        GROUP BY LevelId, MapId, MapName, X, Y
        ORDER BY EventCount DESC, LevelId, MapId, X, Y
        """;
    foreach (var eventType in new[] { "death", "trampoline_bounce" })
    {
        await using var command = new SqlCommand(locationsSql, connection);
        command.Parameters.Add("@type", SqlDbType.NVarChar, 40).Value = eventType;
        AddAnalyticsTargetParameters(command, level_id, map_id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        var destination = eventType == "death" ? deathHotspots : trampolineZones;
        while (await reader.ReadAsync(ct))
            destination.Add(new { level_id = reader.IsDBNull(0) ? (int?)null : reader.GetInt32(0),
                map_id = reader.IsDBNull(1) ? (int?)null : reader.GetInt32(1),
                map_name = reader.IsDBNull(2) ? null : reader.GetString(2),
                x = reader.GetDouble(3), y = reader.GetDouble(4), count = reader.GetInt64(5) });
    }

    // Keep full event totals separate from the 300-zone map preview. The comparison chart
    // must not undercount a busy level when its activity spans many different zones.
    var mapEventTotals = new List<object>();
    await using (var command = new SqlCommand("""
        WITH EventMaps AS (
            SELECT COALESCE(a.LevelId, e.LevelId) AS LevelId,
                   CASE WHEN COALESCE(a.LevelId, e.LevelId) IS NULL
                        THEN COALESCE(a.MapId, CASE WHEN d.LegacyMapId > 0 THEN d.LegacyMapId END)
                   END AS MapId,
                   CONVERT(nvarchar(100), COALESCE(m.Name, a.MapName,
                       NULLIF(d.LegacyMapName, N''), N'Mapa sin guardar')) AS MapName,
                   e.EventType
            FROM dbo.GameplayEvents e
            LEFT JOIN dbo.LevelAttempts a ON a.AttemptId = e.AttemptId
            OUTER APPLY (SELECT TRY_CONVERT(int, JSON_VALUE(e.DetailsJson, '$.map_id')) AS LegacyMapId,
                                JSON_VALUE(e.DetailsJson, '$.map_name') AS LegacyMapName) d
            LEFT JOIN dbo.CustomMaps m ON m.MapId = COALESCE(a.MapId,
                CASE WHEN d.LegacyMapId > 0 THEN d.LegacyMapId END)
            WHERE e.EventType IN (N'death', N'trampoline_bounce')
        )
        SELECT LevelId, MapId, CASE WHEN LevelId IS NULL THEN MapName END AS MapName,
               SUM(CASE WHEN EventType = N'death' THEN CONVERT(bigint, 1) ELSE 0 END) AS DeathCount,
               SUM(CASE WHEN EventType = N'trampoline_bounce' THEN CONVERT(bigint, 1) ELSE 0 END) AS BounceCount
        FROM EventMaps
        WHERE (LevelId IS NOT NULL OR MapId IS NOT NULL OR MapName <> N'Mapa sin guardar')
          AND (@level IS NULL OR LevelId = @level)
          AND (@map IS NULL OR MapId = @map)
        GROUP BY LevelId, MapId, CASE WHEN LevelId IS NULL THEN MapName END
        ORDER BY LevelId, MapId, MapName
        """, connection))
    {
        AddAnalyticsTargetParameters(command, level_id, map_id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            mapEventTotals.Add(new { level_id = reader.IsDBNull(0) ? (int?)null : reader.GetInt32(0),
                map_id = reader.IsDBNull(1) ? (int?)null : reader.GetInt32(1),
                map_name = reader.IsDBNull(2) ? null : reader.GetString(2),
                deaths = reader.GetInt64(3), bounces = reader.GetInt64(4) });
    }

    // Finished official times come only from LevelRuns; the completion event must not double-count them.
    // Custom map tests have no LevelRun, so their final map_test_completed event is the result.
    var mapTimes = new List<object>();
    await using (var command = new SqlCommand("""
        WITH Completed AS (
            SELECT r.LevelId, CAST(NULL AS int) AS MapId,
                   CAST(NULL AS nvarchar(100)) AS MapName, r.ElapsedMs
            FROM dbo.LevelRuns r
            UNION ALL
            SELECT CAST(NULL AS int), a.MapId,
                   COALESCE(m.Name, a.MapName, N'Mapa sin guardar'), e.ElapsedMs
            FROM dbo.GameplayEvents e
            JOIN dbo.LevelAttempts a ON a.AttemptId = e.AttemptId AND a.Mode = 'map_test'
            LEFT JOIN dbo.CustomMaps m ON m.MapId = a.MapId
            WHERE e.EventType = N'map_test_completed'
              AND e.EventId = (SELECT TOP (1) e2.EventId FROM dbo.GameplayEvents e2
                               WHERE e2.AttemptId = e.AttemptId
                                 AND e2.EventType = N'map_test_completed'
                               ORDER BY e2.ElapsedMs DESC, e2.EventId DESC)
            UNION ALL
            SELECT CAST(NULL AS int),
                   CASE WHEN d.LegacyMapId > 0 THEN d.LegacyMapId END,
                   CONVERT(nvarchar(100), COALESCE(m.Name,
                       NULLIF(d.LegacyMapName, N''), N'Mapa sin guardar')), e.ElapsedMs
            FROM dbo.GameplayEvents e
            OUTER APPLY (SELECT TRY_CONVERT(int, JSON_VALUE(e.DetailsJson, '$.map_id')) AS LegacyMapId,
                                JSON_VALUE(e.DetailsJson, '$.map_name') AS LegacyMapName) d
            LEFT JOIN dbo.CustomMaps m ON m.MapId = d.LegacyMapId
            WHERE e.AttemptId IS NULL AND e.LevelId IS NULL AND e.EventType = N'map_test_completed'
        )
        SELECT LevelId, MapId, MapName, COUNT_BIG(*) AS CompletedCount,
               AVG(CONVERT(float, ElapsedMs)) / 1000.0 AS AvgSeconds,
               MIN(ElapsedMs) / 1000.0 AS BestSeconds,
               SUM(CONVERT(float, ElapsedMs)) / 1000.0 AS TotalSeconds
        FROM Completed
        WHERE (@level IS NULL OR LevelId = @level)
          AND (@map IS NULL OR MapId = @map)
        GROUP BY LevelId, MapId, MapName
        ORDER BY CompletedCount DESC, LevelId, MapId, MapName
        """, connection))
    {
        AddAnalyticsTargetParameters(command, level_id, map_id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            mapTimes.Add(new { level_id = reader.IsDBNull(0) ? (int?)null : reader.GetInt32(0),
                map_id = reader.IsDBNull(1) ? (int?)null : reader.GetInt32(1),
                map_name = reader.IsDBNull(2) ? null : reader.GetString(2),
                completed_count = reader.GetInt64(3), avg_seconds = reader.GetDouble(4),
                best_seconds = Convert.ToDouble(reader.GetValue(5)), total_seconds = reader.GetDouble(6) });
    }

    long attemptTimesTotal;
    await using (var command = new SqlCommand("""
        SELECT
            (SELECT COUNT_BIG(*) FROM dbo.LevelAttempts a
             JOIN dbo.GameSessions s ON s.SessionId = a.SessionId
             JOIN dbo.Players p ON p.PlayerId = s.PlayerId
             WHERE (@level IS NULL OR a.LevelId = @level)
               AND (@map IS NULL OR a.MapId = @map)
               AND (@name IS NULL OR CHARINDEX(@name, p.DisplayName) > 0))
          + (SELECT COUNT_BIG(*) FROM dbo.LevelRuns r
             JOIN dbo.GameSessions s ON s.SessionId = r.SessionId
             JOIN dbo.Players p ON p.PlayerId = s.PlayerId
             WHERE r.AttemptId IS NULL AND @map IS NULL
               AND (@level IS NULL OR r.LevelId = @level)
               AND (@name IS NULL OR CHARINDEX(@name, p.DisplayName) > 0))
        """, connection))
    {
        AddAnalyticsTargetParameters(command, level_id, map_id);
        command.Parameters.Add("@name", SqlDbType.NVarChar, 40).Value = (object?)playerName ?? DBNull.Value;
        attemptTimesTotal = (long)(await command.ExecuteScalarAsync(ct))!;
    }

    var attemptTimes = new List<(DateTime SortAt, object Row)>();
    await using (var command = new SqlCommand("""
        WITH Recent AS (
            SELECT TOP (200) a.AttemptId, p.DisplayName, a.LevelId, a.MapId,
                   a.MapName, a.Mode, a.StartedAt
            FROM dbo.LevelAttempts a
            JOIN dbo.GameSessions s ON s.SessionId = a.SessionId
            JOIN dbo.Players p ON p.PlayerId = s.PlayerId
            WHERE (@level IS NULL OR a.LevelId = @level)
              AND (@map IS NULL OR a.MapId = @map)
              AND (@name IS NULL OR CHARINDEX(@name, p.DisplayName) > 0)
            ORDER BY a.StartedAt DESC, a.AttemptId DESC
        )
        SELECT a.AttemptId, a.DisplayName, a.LevelId, a.MapId,
               COALESCE(m.Name, a.MapName), a.Mode, a.StartedAt,
               r.CompletedAt, done.CompletedAt, r.ElapsedMs, done.ElapsedMs,
               latest.ElapsedMs, r.Category, r.FruitsCollected, latest.FruitsCollected,
               r.CoinsCollected, latest.CoinsCollected,
               stats.DeathCount, stats.TrampolineCount
        FROM Recent a
        LEFT JOIN dbo.CustomMaps m ON m.MapId = a.MapId
        LEFT JOIN dbo.LevelRuns r ON r.AttemptId = a.AttemptId
        OUTER APPLY (
            SELECT TOP (1) e.ElapsedMs, e.FruitsCollected, e.CoinsCollected
            FROM dbo.GameplayEvents e WHERE e.AttemptId = a.AttemptId
            ORDER BY e.ElapsedMs DESC, e.EventId DESC
        ) latest
        OUTER APPLY (
            SELECT TOP (1) e.OccurredAt AS CompletedAt, e.ElapsedMs
            FROM dbo.GameplayEvents e
            WHERE e.AttemptId = a.AttemptId
              AND e.EventType IN (N'level_completed', N'map_test_completed')
            ORDER BY e.ElapsedMs DESC, e.EventId DESC
        ) done
        OUTER APPLY (
            SELECT COUNT_BIG(CASE WHEN e.EventType = N'death' THEN 1 END) AS DeathCount,
                   COUNT_BIG(CASE WHEN e.EventType = N'trampoline_bounce' THEN 1 END) AS TrampolineCount
            FROM dbo.GameplayEvents e WHERE e.AttemptId = a.AttemptId
        ) stats
        ORDER BY a.StartedAt DESC, a.AttemptId DESC
        """, connection))
    {
        AddAnalyticsTargetParameters(command, level_id, map_id);
        command.Parameters.Add("@name", SqlDbType.NVarChar, 40).Value = (object?)playerName ?? DBNull.Value;
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var startedAt = reader.GetDateTime(6);
            var endedAt = !reader.IsDBNull(7) ? reader.GetDateTime(7)
                : !reader.IsDBNull(8) ? reader.GetDateTime(8) : (DateTime?)null;
            var elapsedMs = !reader.IsDBNull(9) ? reader.GetInt64(9)
                : !reader.IsDBNull(10) ? reader.GetInt64(10)
                : !reader.IsDBNull(11) ? reader.GetInt64(11) : 0L;
            attemptTimes.Add((startedAt, new {
                attempt_id = (Guid?)reader.GetGuid(0), name = reader.GetString(1),
                level_id = reader.IsDBNull(2) ? (int?)null : reader.GetInt32(2),
                map_id = reader.IsDBNull(3) ? (int?)null : reader.GetInt32(3),
                map_name = reader.IsDBNull(4) ? null : reader.GetString(4),
                mode = reader.GetString(5), started_at = UtcString(startedAt),
                ended_at = endedAt is null ? null : UtcString(endedAt.Value),
                seconds = elapsedMs / 1000.0, completed = endedAt is not null,
                category = reader.IsDBNull(12) ? null : reader.GetString(12),
                fruits_collected = !reader.IsDBNull(13) ? reader.GetInt32(13)
                    : !reader.IsDBNull(14) ? reader.GetInt32(14) : 0,
                coins_collected = !reader.IsDBNull(15) ? reader.GetInt32(15)
                    : !reader.IsDBNull(16) ? reader.GetInt32(16) : 0,
                death_count = (long?)reader.GetInt64(17),
                trampoline_count = (long?)reader.GetInt64(18)
            }));
        }
    }

    if (map_id is null)
    {
        await using var command = new SqlCommand("""
            SELECT TOP (200) p.DisplayName, r.LevelId, r.CompletedAt,
                   r.ElapsedMs, r.Category, r.FruitsCollected, r.CoinsCollected
            FROM dbo.LevelRuns r
            JOIN dbo.GameSessions s ON s.SessionId = r.SessionId
            JOIN dbo.Players p ON p.PlayerId = s.PlayerId
            WHERE r.AttemptId IS NULL
              AND (@level IS NULL OR r.LevelId = @level)
              AND (@name IS NULL OR CHARINDEX(@name, p.DisplayName) > 0)
            ORDER BY r.CompletedAt DESC, r.RunId DESC
            """, connection);
        command.Parameters.Add("@level", SqlDbType.Int).Value = (object?)level_id ?? DBNull.Value;
        command.Parameters.Add("@name", SqlDbType.NVarChar, 40).Value = (object?)playerName ?? DBNull.Value;
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var completedAt = reader.GetDateTime(2);
            attemptTimes.Add((completedAt, new {
                attempt_id = (Guid?)null, name = reader.GetString(0), level_id = (int?)reader.GetInt32(1),
                map_id = (int?)null, map_name = (string?)null, mode = "historical",
                started_at = (string?)null, ended_at = UtcString(completedAt),
                seconds = reader.GetInt64(3) / 1000.0, completed = true,
                category = reader.GetString(4), fruits_collected = reader.GetInt32(5),
                coins_collected = reader.GetInt32(6), death_count = (long?)null,
                trampoline_count = (long?)null
            }));
        }
    }

    return Results.Ok(new {
        death_hotspots = deathHotspots, trampolines = trampolineZones,
        attempt_times = attemptTimes.OrderByDescending(item => item.SortAt)
            .Take(200).Select(item => item.Row).ToArray(),
        attempt_times_total = attemptTimesTotal, map_times = mapTimes,
        map_event_totals = mapEventTotals
    });
});

app.MapGet("/api/dashboard", async (CancellationToken ct) =>
{
    await using var connection = await db.OpenAsync(ct);
    await using var totalsCommand = new SqlCommand("""
        SELECT (SELECT COUNT_BIG(*) FROM dbo.GameSessions),
               (SELECT COUNT_BIG(*) FROM dbo.LevelRuns),
               (SELECT COUNT_BIG(*) FROM dbo.GameplayEvents),
               (SELECT COUNT_BIG(*) FROM dbo.CustomMaps),
               (SELECT COUNT_BIG(*) FROM dbo.GameplayEvents WHERE EventType = N'fruit_collected'),
               (SELECT COUNT_BIG(*) FROM dbo.GameplayEvents WHERE EventType = N'coin_collected')
        """, connection);
    long sessions, runs, eventsCount, mapsCount, fruits, coins;
    await using (var reader = await totalsCommand.ExecuteReaderAsync(ct))
    {
        await reader.ReadAsync(ct);
        sessions = reader.GetInt64(0);
        runs = reader.GetInt64(1);
        eventsCount = reader.GetInt64(2);
        mapsCount = reader.GetInt64(3);
        fruits = reader.GetInt64(4);
        coins = reader.GetInt64(5);
    }

    var recentRuns = new List<object>();
    await using var runsCommand = new SqlCommand("""
        SELECT TOP (12) r.LevelId, r.Category, r.ElapsedMs, r.FruitsCollected,
               r.FruitsTotal, r.CoinsCollected, p.DisplayName, r.CompletedAt,
               r.RunId, r.AttemptId
        FROM dbo.LevelRuns r
        JOIN dbo.GameSessions s ON s.SessionId = r.SessionId
        JOIN dbo.Players p ON p.PlayerId = s.PlayerId
        ORDER BY r.RunId DESC
        """, connection);
    await using (var reader = await runsCommand.ExecuteReaderAsync(ct))
        while (await reader.ReadAsync(ct))
            recentRuns.Add(new { level_id = reader.GetInt32(0), category = reader.GetString(1),
                seconds = reader.GetInt64(2) / 1000.0, fruits_collected = reader.GetInt32(3),
                fruits_total = reader.GetInt32(4), coins_collected = reader.GetInt32(5),
                name = reader.GetString(6), completed_at = UtcString(reader.GetDateTime(7)),
                run_id = reader.GetInt64(8),
                attempt_id = reader.IsDBNull(9) ? (Guid?)null : reader.GetGuid(9) });

    var recentEvents = new List<object>();
    await using var eventsCommand = new SqlCommand("""
        SELECT TOP (15) e.EventType, e.LevelId, e.ElapsedMs, e.FruitsCollected,
               e.CoinsCollected, e.DetailsJson, p.DisplayName, e.OccurredAt
        FROM dbo.GameplayEvents e
        JOIN dbo.GameSessions s ON s.SessionId = e.SessionId
        JOIN dbo.Players p ON p.PlayerId = s.PlayerId
        WHERE e.EventType <> N'position_snapshot'
        ORDER BY e.EventId DESC
        """, connection);
    await using (var reader = await eventsCommand.ExecuteReaderAsync(ct))
        while (await reader.ReadAsync(ct))
            recentEvents.Add(new { event_type = reader.GetString(0), level_id = reader.IsDBNull(1) ? (int?)null : reader.GetInt32(1),
                seconds = reader.GetInt64(2) / 1000.0, fruits_collected = reader.GetInt32(3),
                coins_collected = reader.GetInt32(4), details = ParseJson(reader.GetString(5)),
                name = reader.GetString(6), occurred_at = UtcString(reader.GetDateTime(7)) });

    return Results.Ok(new { totals = new { sessions, runs, events = eventsCount, maps = mapsCount, fruits, coins },
        recent_runs = recentRuns, recent_events = recentEvents });
});

app.Run();

static void AddAnalyticsTargetParameters(SqlCommand command, int? levelId, int? mapId)
{
    command.Parameters.Add("@level", SqlDbType.Int).Value = (object?)levelId ?? DBNull.Value;
    command.Parameters.Add("@map", SqlDbType.Int).Value = (object?)mapId ?? DBNull.Value;
}

static bool ValidSeconds(double seconds) => double.IsFinite(seconds) && seconds >= 0 && seconds <= 31536000;
static bool IsUniqueViolation(SqlException exception) => exception.Number is 2601 or 2627;
static long Milliseconds(double seconds) => (long)Math.Round(seconds * 1000, MidpointRounding.AwayFromZero);
static string UtcString(DateTime date) => DateTime.SpecifyKind(date, DateTimeKind.Utc).ToString("O");
static JsonElement ParseJson(string text) => JsonDocument.Parse(text).RootElement.Clone();
static bool ValidMap(MapInput input) => !string.IsNullOrWhiteSpace(input.Name) &&
    input.Name.Trim().Length <= 100 && !input.Name.Any(char.IsControl) &&
    input.Data.ValueKind == JsonValueKind.Object &&
    input.Data.GetRawText().Length <= 524288;
static string ResolveWebRoot()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        foreach (var candidate in new[] { Path.Combine(directory.FullName, "wwwroot"),
                     Path.Combine(directory.FullName, "backend", "wwwroot") })
            if (Directory.Exists(candidate)) return candidate;
        directory = directory.Parent;
    }
    throw new DirectoryNotFoundException("No se encontró backend/wwwroot para el panel web.");
}
static async Task<bool> SessionExists(SqlConnection connection, Guid id, CancellationToken ct)
{
    await using var command = new SqlCommand("SELECT 1 FROM dbo.GameSessions WHERE SessionId = @id", connection);
    command.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
    return await command.ExecuteScalarAsync(ct) is not null;
}
static async Task<(Guid SessionId, int? LevelId, int? MapId, string Mode, DateTime StartedAt)?>
    FindAttempt(SqlConnection connection, Guid id, CancellationToken ct)
{
    await using var command = new SqlCommand("""
        SELECT SessionId, LevelId, MapId, Mode, StartedAt
        FROM dbo.LevelAttempts WHERE AttemptId = @id
        """, connection);
    command.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
    await using var reader = await command.ExecuteReaderAsync(ct);
    return await reader.ReadAsync(ct)
        ? (reader.GetGuid(0), reader.IsDBNull(1) ? null : reader.GetInt32(1),
            reader.IsDBNull(2) ? null : reader.GetInt32(2), reader.GetString(3), reader.GetDateTime(4))
        : null;
}
static async Task<bool> AttemptMatches(SqlConnection connection, Guid attemptId, Guid sessionId,
    int? levelId, bool officialRun, CancellationToken ct)
{
    await using var command = new SqlCommand("""
        SELECT 1 FROM dbo.LevelAttempts
        WHERE AttemptId = @attempt AND SessionId = @session
          AND ((LevelId = @level) OR (LevelId IS NULL AND @level IS NULL))
          AND (@official = 0 OR Mode IN ('story', 'free'))
        """, connection);
    command.Parameters.Add("@attempt", SqlDbType.UniqueIdentifier).Value = attemptId;
    command.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = sessionId;
    command.Parameters.Add("@level", SqlDbType.Int).Value = (object?)levelId ?? DBNull.Value;
    command.Parameters.Add("@official", SqlDbType.Bit).Value = officialRun;
    return await command.ExecuteScalarAsync(ct) is not null;
}
static async Task<string?> FindSessionName(SqlConnection connection, Guid id, CancellationToken ct)
{
    await using var command = new SqlCommand("""
        SELECT p.DisplayName FROM dbo.GameSessions s
        JOIN dbo.Players p ON p.PlayerId = s.PlayerId
        WHERE s.SessionId = @id
        """, connection);
    command.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = id;
    return await command.ExecuteScalarAsync(ct) as string;
}
static async Task<long?> FindEvent(SqlConnection connection, Guid key, Guid session, CancellationToken ct)
{
    await using var command = new SqlCommand(
        "SELECT EventId FROM dbo.GameplayEvents WHERE ClientEventId = @key AND SessionId = @session", connection);
    command.Parameters.Add("@key", SqlDbType.UniqueIdentifier).Value = key;
    command.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = session;
    return await command.ExecuteScalarAsync(ct) is long id ? id : null;
}
static async Task<(long Id, string Category)?> FindRun(SqlConnection connection, Guid key, Guid session, CancellationToken ct)
{
    await using var command = new SqlCommand(
        "SELECT RunId, Category FROM dbo.LevelRuns WHERE ClientRunId = @key AND SessionId = @session", connection);
    command.Parameters.Add("@key", SqlDbType.UniqueIdentifier).Value = key;
    command.Parameters.Add("@session", SqlDbType.UniqueIdentifier).Value = session;
    await using var reader = await command.ExecuteReaderAsync(ct);
    return await reader.ReadAsync(ct) ? (reader.GetInt64(0), reader.GetString(1)) : null;
}

public sealed record SessionInput(
    [property: JsonPropertyName("player_name")] string? PlayerName,
    [property: JsonPropertyName("client_session_id")] Guid? ClientSessionId);
public sealed record EventInput(
    [property: JsonPropertyName("client_event_id")] Guid? ClientEventId,
    [property: JsonPropertyName("session_id")] Guid SessionId,
    [property: JsonPropertyName("attempt_id")] Guid? AttemptId,
    [property: JsonPropertyName("level_id")] int? LevelId,
    [property: JsonPropertyName("event_type")] string? EventType,
    [property: JsonPropertyName("elapsed_seconds")] double ElapsedSeconds,
    [property: JsonPropertyName("fruits_collected")] int FruitsCollected,
    [property: JsonPropertyName("coins_collected")] int CoinsCollected,
    [property: JsonPropertyName("details")] JsonElement? Details);
public sealed record RunInput(
    [property: JsonPropertyName("client_run_id")] Guid? ClientRunId,
    [property: JsonPropertyName("session_id")] Guid SessionId,
    [property: JsonPropertyName("attempt_id")] Guid? AttemptId,
    [property: JsonPropertyName("level_id")] int LevelId,
    [property: JsonPropertyName("elapsed_seconds")] double ElapsedSeconds,
    [property: JsonPropertyName("fruits_collected")] int FruitsCollected,
    [property: JsonPropertyName("fruits_total")] int FruitsTotal,
    [property: JsonPropertyName("coins_collected")] int CoinsCollected);
public sealed record AttemptInput(
    [property: JsonPropertyName("client_attempt_id")] Guid? ClientAttemptId,
    [property: JsonPropertyName("session_id")] Guid SessionId,
    [property: JsonPropertyName("level_id")] int? LevelId,
    [property: JsonPropertyName("map_id")] int? MapId,
    [property: JsonPropertyName("mode")] string? Mode,
    [property: JsonPropertyName("map_name")] string? MapName,
    [property: JsonPropertyName("map_data")] JsonElement? MapData);
public sealed record MapInput(string? Name, JsonElement Data);

public sealed class GameDatabase
{
    private readonly string _connectionString;

    public GameDatabase()
    {
        var user = Environment.GetEnvironmentVariable("SQL_USER");
        var password = Environment.GetEnvironmentVariable("SQL_PASSWORD");
        if (string.IsNullOrWhiteSpace(user) || string.IsNullOrEmpty(password))
            throw new InvalidOperationException("Faltan SQL_USER y/o SQL_PASSWORD en el entorno.");
        var connection = new SqlConnectionStringBuilder
        {
            DataSource = Environment.GetEnvironmentVariable("SQL_SERVER") ?? "lpc:.",
            InitialCatalog = Environment.GetEnvironmentVariable("SQL_DATABASE") ?? "DB",
            UserID = user,
            Password = password,
            TrustServerCertificate = true,
            ConnectTimeout = 5,
            ApplicationName = "FrutaEnLasRuinas.Api"
        };
        _connectionString = connection.ConnectionString;
    }

    public async Task<SqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new SqlConnection(_connectionString);
        try
        {
            await connection.OpenAsync(ct);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    public async Task InitializeAsync()
    {
        var script = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "schema.sql"));
        await using var connection = await OpenAsync(CancellationToken.None);
        foreach (var batch in Regex.Split(script, @"(?im)^\s*GO\s*$"))
        {
            if (string.IsNullOrWhiteSpace(batch)) continue;
            await using var command = new SqlCommand(batch, connection);
            await command.ExecuteNonQueryAsync();
        }
    }
}

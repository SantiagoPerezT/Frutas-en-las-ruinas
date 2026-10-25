$ErrorActionPreference = 'Stop'
$api = 'http://127.0.0.1:8000/api'
$sessionId = [guid]::NewGuid().ToString()
$eventId = [guid]::NewGuid().ToString()
$runId = [guid]::NewGuid().ToString()
$allRunId = [guid]::NewGuid().ToString()
$playerName = 'Codex QA ' + $sessionId.Substring(0, 8)
$mapId = $null
$sqlcmd = if ($env:SQLCMD_PATH) { $env:SQLCMD_PATH } else { (Get-Command sqlcmd -ErrorAction Stop).Source }
$sqlServer = if ($env:SQL_SERVER) { $env:SQL_SERVER } else { 'lpc:.' }
$sqlDatabase = if ($env:SQL_DATABASE) { $env:SQL_DATABASE } else { 'DB' }

function Send-Json($path, $method, $value) {
    Invoke-RestMethod -Uri "$api/$path" -Method $method -ContentType 'application/json' -Body ($value | ConvertTo-Json -Depth 12 -Compress)
}

try {
    $session = Send-Json 'sessions' 'Post' @{ player_name = $playerName; client_session_id = $sessionId }
    if ($session.player_name -ne $playerName) { throw 'El nombre de sesión no coincide.' }

    $event = @{ client_event_id = $eventId; session_id = $sessionId; level_id = 3; event_type = 'coin_collected'; elapsed_seconds = 8.25; fruits_collected = 2; coins_collected = 1; details = @{ item = 'CoinQA' } }
    $firstEvent = Send-Json 'events' 'Post' $event
    $retryEvent = Send-Json 'events' 'Post' $event
    if ($firstEvent.id -ne $retryEvent.id) { throw 'Reintentar un evento creó un duplicado.' }

    $run = @{ client_run_id = $runId; session_id = $sessionId; level_id = 3; elapsed_seconds = 17.5; fruits_collected = 2; fruits_total = 4; coins_collected = 1 }
    $firstRun = Send-Json 'runs' 'Post' $run
    $retryRun = Send-Json 'runs' 'Post' $run
    if ($firstRun.id -ne $retryRun.id -or $firstRun.category -ne 'any_percent') { throw 'Any% o idempotencia incorrectos.' }

    $allRun = @{ client_run_id = $allRunId; session_id = $sessionId; level_id = 3; elapsed_seconds = 23.75; fruits_collected = 4; fruits_total = 4; coins_collected = 2 }
    $allResult = Send-Json 'runs' 'Post' $allRun
    if ($allResult.category -ne 'all_fruits') { throw 'Clasificación Todas las frutas incorrecta.' }

    $anyBoard = Invoke-RestMethod -Uri "$api/leaderboards?level_id=3&category=any_percent"
    $allBoard = Invoke-RestMethod -Uri "$api/leaderboards?level_id=3&category=all_fruits"
    if (-not ($anyBoard | Where-Object { $_.name -eq $playerName -and $_.seconds -eq 17.5 })) { throw 'Nombre/tiempo de nivel 3 ausente en Any%.' }
    if (-not ($allBoard | Where-Object { $_.name -eq $playerName -and $_.seconds -eq 23.75 })) { throw 'Nombre/tiempo de nivel 3 ausente en Todas las frutas.' }

    $mapData = @{ version = 1; width = 960; height = 540; theme = 'ruins'; spawn = @{ x = 60; y = 445 }; goal = @{ x = 900; y = 445 }; platforms = @(@{ x = 0; y = 486; w = 960; h = 54 }); fruits = @(); coins = @(); saws = @(); trampolines = @() }
    $map = Send-Json 'maps' 'Post' @{ name = "Mapa QA $sessionId"; data = $mapData }
    $mapId = $map.id
    $loadedMap = Invoke-RestMethod -Uri "$api/maps/$mapId"
    if ($loadedMap.name -ne "Mapa QA $sessionId" -or $loadedMap.data.width -ne 960) { throw 'El mapa no se recuperó correctamente.' }

    $dashboard = Invoke-RestMethod -Uri "$api/dashboard"
    if ($dashboard.totals.runs -lt 2 -or $dashboard.totals.maps -lt 1) { throw 'Dashboard sin registros esperados.' }
    Write-Output 'PASS: sesión/nombre, eventos, Any% y 100% en nivel 3, idempotencia, mapa y dashboard.'
} finally {
    $mapSql = if ($null -ne $mapId) { "DELETE FROM dbo.CustomMaps WHERE MapId = $([int]$mapId);" } else { '' }
    $cleanup = "DECLARE @session uniqueidentifier = '$sessionId'; DECLARE @player int = (SELECT PlayerId FROM dbo.GameSessions WHERE SessionId=@session); DELETE FROM dbo.GameplayEvents WHERE SessionId=@session; DELETE FROM dbo.LevelRuns WHERE SessionId=@session; DELETE FROM dbo.GameSessions WHERE SessionId=@session; DELETE FROM dbo.Players WHERE PlayerId=@player; $mapSql"
    $auth = @('-E')
    $previousSqlcmdPassword = $env:SQLCMDPASSWORD
    if ($env:SQL_USER -and $env:SQL_PASSWORD) {
        $auth = @('-U', $env:SQL_USER)
        $env:SQLCMDPASSWORD = $env:SQL_PASSWORD
    }
    try {
        & $sqlcmd -S $sqlServer @auth -C -b -d $sqlDatabase -Q $cleanup -W | Out-Null
    } finally {
        if ($null -eq $previousSqlcmdPassword) {
            Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue
        } else {
            $env:SQLCMDPASSWORD = $previousSqlcmdPassword
        }
    }
}

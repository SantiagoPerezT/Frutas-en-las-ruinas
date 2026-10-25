IF OBJECT_ID(N'dbo.Players', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Players (
        PlayerId int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DisplayName nvarchar(40) NOT NULL,
        CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_Players_CreatedAt DEFAULT SYSUTCDATETIME()
    );
END
GO
IF OBJECT_ID(N'dbo.GameSessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.GameSessions (
        SessionId uniqueidentifier NOT NULL PRIMARY KEY,
        PlayerId int NOT NULL REFERENCES dbo.Players(PlayerId),
        StartedAt datetime2(3) NOT NULL CONSTRAINT DF_GameSessions_StartedAt DEFAULT SYSUTCDATETIME()
    );
END
GO
IF OBJECT_ID(N'dbo.GameplayEvents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.GameplayEvents (
        EventId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ClientEventId uniqueidentifier NULL,
        SessionId uniqueidentifier NOT NULL REFERENCES dbo.GameSessions(SessionId),
        LevelId int NULL,
        EventType nvarchar(40) NOT NULL,
        ElapsedMs bigint NOT NULL,
        FruitsCollected int NOT NULL,
        CoinsCollected int NOT NULL,
        DetailsJson nvarchar(max) NOT NULL,
        OccurredAt datetime2(3) NOT NULL CONSTRAINT DF_GameplayEvents_OccurredAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_GameplayEvents_Nonnegative CHECK ((LevelId IS NULL OR LevelId > 0) AND ElapsedMs >= 0 AND FruitsCollected >= 0 AND CoinsCollected >= 0),
        CONSTRAINT CK_GameplayEvents_DetailsJson CHECK (ISJSON(DetailsJson) = 1)
    );
END
GO
IF COL_LENGTH(N'dbo.GameplayEvents', N'ClientEventId') IS NULL
    ALTER TABLE dbo.GameplayEvents ADD ClientEventId uniqueidentifier NULL;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.GameplayEvents') AND name = N'LevelId' AND is_nullable = 0)
BEGIN
    IF OBJECT_ID(N'dbo.CK_GameplayEvents_Nonnegative', N'C') IS NOT NULL
        ALTER TABLE dbo.GameplayEvents DROP CONSTRAINT CK_GameplayEvents_Nonnegative;
    ALTER TABLE dbo.GameplayEvents ALTER COLUMN LevelId int NULL;
    ALTER TABLE dbo.GameplayEvents ADD CONSTRAINT CK_GameplayEvents_Nonnegative
        CHECK ((LevelId IS NULL OR LevelId > 0) AND ElapsedMs >= 0 AND FruitsCollected >= 0 AND CoinsCollected >= 0);
END
GO
IF OBJECT_ID(N'dbo.LevelRuns', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LevelRuns (
        RunId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ClientRunId uniqueidentifier NULL,
        SessionId uniqueidentifier NOT NULL REFERENCES dbo.GameSessions(SessionId),
        LevelId int NOT NULL,
        Category varchar(20) NOT NULL,
        ElapsedMs bigint NOT NULL,
        FruitsCollected int NOT NULL,
        FruitsTotal int NOT NULL,
        CoinsCollected int NOT NULL,
        CompletedAt datetime2(3) NOT NULL CONSTRAINT DF_LevelRuns_CompletedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_LevelRuns_Category CHECK (Category IN ('any_percent', 'all_fruits')),
        CONSTRAINT CK_LevelRuns_Nonnegative CHECK (LevelId > 0 AND ElapsedMs >= 0 AND FruitsCollected >= 0 AND FruitsTotal >= 0 AND FruitsCollected <= FruitsTotal AND CoinsCollected >= 0)
    );
END
GO
IF COL_LENGTH(N'dbo.LevelRuns', N'ClientRunId') IS NULL
    ALTER TABLE dbo.LevelRuns ADD ClientRunId uniqueidentifier NULL;
GO
IF OBJECT_ID(N'dbo.CustomMaps', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CustomMaps (
        MapId int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Name nvarchar(100) NOT NULL,
        DataJson nvarchar(max) NOT NULL,
        CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_CustomMaps_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt datetime2(3) NOT NULL CONSTRAINT DF_CustomMaps_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_CustomMaps_DataJson CHECK (ISJSON(DataJson) = 1)
    );
END
GO
IF OBJECT_ID(N'dbo.LevelAttempts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LevelAttempts (
        AttemptId uniqueidentifier NOT NULL PRIMARY KEY,
        SessionId uniqueidentifier NOT NULL REFERENCES dbo.GameSessions(SessionId),
        LevelId int NULL,
        MapId int NULL,
        Mode varchar(20) NOT NULL,
        MapName nvarchar(100) NULL,
        MapDataJson nvarchar(max) NULL,
        StartedAt datetime2(3) NOT NULL CONSTRAINT DF_LevelAttempts_StartedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_LevelAttempts_Target CHECK (
            (LevelId IS NOT NULL AND LevelId > 0 AND MapId IS NULL AND MapDataJson IS NULL AND Mode IN ('story', 'free')) OR
            (LevelId IS NULL AND Mode = 'map_test' AND MapDataJson IS NOT NULL)
        ),
        CONSTRAINT CK_LevelAttempts_MapData CHECK (MapDataJson IS NULL OR ISJSON(MapDataJson) = 1)
    );
END
GO
IF COL_LENGTH(N'dbo.GameplayEvents', N'AttemptId') IS NULL
    ALTER TABLE dbo.GameplayEvents ADD AttemptId uniqueidentifier NULL;
GO
IF COL_LENGTH(N'dbo.LevelRuns', N'AttemptId') IS NULL
    ALTER TABLE dbo.LevelRuns ADD AttemptId uniqueidentifier NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_GameplayEvents_LevelAttempts')
    ALTER TABLE dbo.GameplayEvents ADD CONSTRAINT FK_GameplayEvents_LevelAttempts
        FOREIGN KEY (AttemptId) REFERENCES dbo.LevelAttempts(AttemptId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_LevelRuns_LevelAttempts')
    ALTER TABLE dbo.LevelRuns ADD CONSTRAINT FK_LevelRuns_LevelAttempts
        FOREIGN KEY (AttemptId) REFERENCES dbo.LevelAttempts(AttemptId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LevelAttempts') AND name = N'IX_LevelAttempts_Recent')
    CREATE INDEX IX_LevelAttempts_Recent ON dbo.LevelAttempts(StartedAt DESC)
        INCLUDE (SessionId, LevelId, MapId, Mode, MapName);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LevelAttempts') AND name = N'IX_LevelAttempts_Official')
    CREATE INDEX IX_LevelAttempts_Official ON dbo.LevelAttempts(LevelId, StartedAt DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LevelAttempts') AND name = N'IX_LevelAttempts_Map')
    CREATE INDEX IX_LevelAttempts_Map ON dbo.LevelAttempts(MapId, StartedAt DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.GameplayEvents') AND name = N'IX_GameplayEvents_Attempt')
    CREATE INDEX IX_GameplayEvents_Attempt ON dbo.GameplayEvents(AttemptId, ElapsedMs, EventId)
        WHERE AttemptId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.GameplayEvents') AND name = N'IX_GameplayEvents_AnalyticsType')
    CREATE INDEX IX_GameplayEvents_AnalyticsType ON dbo.GameplayEvents(EventType, AttemptId)
        INCLUDE (LevelId, ElapsedMs, SessionId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LevelRuns') AND name = N'UX_LevelRuns_Attempt')
    CREATE UNIQUE INDEX UX_LevelRuns_Attempt ON dbo.LevelRuns(AttemptId) WHERE AttemptId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.GameplayEvents') AND name = N'IX_GameplayEvents_Session')
    CREATE INDEX IX_GameplayEvents_Session ON dbo.GameplayEvents(SessionId, EventId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.GameplayEvents') AND name = N'UX_GameplayEvents_ClientEventId')
    CREATE UNIQUE INDEX UX_GameplayEvents_ClientEventId ON dbo.GameplayEvents(ClientEventId) WHERE ClientEventId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LevelRuns') AND name = N'IX_LevelRuns_Ranking')
    CREATE INDEX IX_LevelRuns_Ranking ON dbo.LevelRuns(LevelId, Category, ElapsedMs, RunId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.LevelRuns') AND name = N'UX_LevelRuns_ClientRunId')
    CREATE UNIQUE INDEX UX_LevelRuns_ClientRunId ON dbo.LevelRuns(ClientRunId) WHERE ClientRunId IS NOT NULL;
GO

-- Ejecutar manualmente desde SQL Server Management Studio o sqlcmd.
-- Borra solamente los tiempos; conserva jugadores, actividad y mapas.
USE [DB];
GO
DELETE FROM dbo.LevelRuns;

-- =============================================================================
-- schema.sql – Zeitreihen-Tabelle für Sensor-Telemetrie
-- Ausführen via: scripts/init-database.py
-- =============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SensorReadings')
BEGIN
    CREATE TABLE dbo.SensorReadings (
        Id                BIGINT IDENTITY(1,1) PRIMARY KEY,
        DeviceId          NVARCHAR(50)  NOT NULL,
        Location          NVARCHAR(50)  NOT NULL,
        ReadingTimestamp  DATETIME2     NOT NULL,   -- Zeitstempel vom Edge Gateway (payload.timestamp)
        Temperature       DECIMAL(5,1)  NULL,       -- °C
        Humidity          DECIMAL(5,1)  NULL,       -- % relative Luftfeuchtigkeit
        SensorType        NVARCHAR(20)  NOT NULL,
        CpuTemperature    DECIMAL(5,1)  NULL,        -- °C, SoC des Pi
        IngestedAt        DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME() -- Zeitpunkt Insert durch Processor
    );

    CREATE INDEX IX_SensorReadings_DeviceId_Timestamp
        ON dbo.SensorReadings (DeviceId, ReadingTimestamp DESC);
END

-- Ohne persistenten Checkpoint-Store (Kann-Ziel, nicht Teil des Prototyps)
-- liest der Processor bei jedem Neustart die Retention des Event Hub
-- erneut von Beginn – dieselbe Nachricht kann so mehrfach ankommen. Die
-- Unique-Constraint macht den Insert idempotent, ohne die Architektur mit
-- einer zusätzlichen Storage-Komponente zu belasten. Eigene IF-Prüfung,
-- damit sie auch auf bereits bestehenden Tabellen nachgezogen wird.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_SensorReadings_Device_Timestamp')
BEGIN
    CREATE UNIQUE INDEX UQ_SensorReadings_Device_Timestamp
        ON dbo.SensorReadings (DeviceId, ReadingTimestamp);
END

-- Zweite, heterogene Datenquelle: simulierte Industrieanlage via OPC UA
-- (siehe edge-gateway/opcua-simulator/), in dieselbe Nachricht integriert.
-- Nullable, da bestehende Zeilen und ein evtl. nicht erreichbarer
-- OPC-UA-Server keine Werte liefern.
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.SensorReadings') AND name = 'MotorSpeed')
BEGIN
    ALTER TABLE dbo.SensorReadings ADD MotorSpeed DECIMAL(7,1) NULL; -- U/min
END
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.SensorReadings') AND name = 'Pressure')
BEGIN
    ALTER TABLE dbo.SensorReadings ADD Pressure DECIMAL(5,2) NULL; -- bar
END
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.SensorReadings') AND name = 'FlowRate')
BEGIN
    ALTER TABLE dbo.SensorReadings ADD FlowRate DECIMAL(6,1) NULL; -- l/min
END

-- =============================================================================
-- views.sql – Views für Power BI (Live-Ansicht + Zeitreihenauswertung)
-- Ausführen via: scripts/init-database.py (liest schema.sql UND views.sql)
-- =============================================================================

-- Neuester Wert pro Gerät – für Live-Kacheln/KPI-Cards in Power BI.
-- Power BI (DirectQuery) fragt diese View bei jedem Refresh neu ab, dadurch
-- zeigt sie immer den aktuellsten in der DB gespeicherten Sensorwert.
CREATE OR ALTER VIEW dbo.vw_LatestReadings AS
SELECT
    DeviceId,
    Location,
    ReadingTimestamp,
    Temperature,
    Humidity,
    CpuTemperature,
    MotorSpeed,
    Pressure,
    FlowRate,
    -- ReadingTimestamp ist Lokalzeit (Europe/Zurich, siehe edge-gateway),
    -- daher Vergleich gegen die ebenfalls nach Lokalzeit umgerechnete
    -- aktuelle Zeit statt SYSUTCDATETIME() direkt (sonst 2h/1h Versatz je
    -- nach Sommer-/Winterzeit).
    DATEDIFF(SECOND, ReadingTimestamp,
             CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'W. Europe Standard Time' AS DATETIME2)
    ) AS SecondsSinceReading
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY DeviceId ORDER BY ReadingTimestamp DESC) AS rn
    FROM dbo.SensorReadings
    WHERE DeviceId = 'rpi-edge-01'  -- nur das reale Produktivgerät; schliesst
                                     -- Lasttest- und alte Testgeräte-Identitäten aus,
                                     -- die sonst als veraltete Zusatzzeilen erscheinen
) latest
WHERE rn = 1;
GO

-- Stündliche Aggregation – für die Zeitreihenauswertung über längere
-- Zeiträume. Deutlich weniger Zeilen als die Rohdaten, damit Power-BI-
-- Charts über Tage/Wochen performant bleiben.
CREATE OR ALTER VIEW dbo.vw_HourlyAggregates AS
SELECT
    DeviceId,
    Location,
    DATEADD(HOUR, DATEDIFF(HOUR, 0, ReadingTimestamp), 0) AS HourBucket,
    AVG(Temperature)     AS AvgTemperature,
    MIN(Temperature)     AS MinTemperature,
    MAX(Temperature)     AS MaxTemperature,
    AVG(Humidity)         AS AvgHumidity,
    MIN(Humidity)         AS MinHumidity,
    MAX(Humidity)         AS MaxHumidity,
    AVG(CpuTemperature)   AS AvgCpuTemperature,
    AVG(MotorSpeed)       AS AvgMotorSpeed,
    MIN(MotorSpeed)       AS MinMotorSpeed,
    MAX(MotorSpeed)       AS MaxMotorSpeed,
    AVG(Pressure)         AS AvgPressure,
    MIN(Pressure)         AS MinPressure,
    MAX(Pressure)         AS MaxPressure,
    AVG(FlowRate)         AS AvgFlowRate,
    MIN(FlowRate)         AS MinFlowRate,
    MAX(FlowRate)         AS MaxFlowRate,
    COUNT(*)              AS ReadingCount
FROM dbo.SensorReadings
WHERE DeviceId = 'rpi-edge-01'  -- siehe vw_LatestReadings
GROUP BY DeviceId, Location, DATEADD(HOUR, DATEDIFF(HOUR, 0, ReadingTimestamp), 0);
GO

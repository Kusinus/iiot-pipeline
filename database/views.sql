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
    DATEDIFF(SECOND, ReadingTimestamp, SYSUTCDATETIME()) AS SecondsSinceReading
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY DeviceId ORDER BY ReadingTimestamp DESC) AS rn
    FROM dbo.SensorReadings
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
    COUNT(*)              AS ReadingCount
FROM dbo.SensorReadings
GROUP BY DeviceId, Location, DATEADD(HOUR, DATEDIFF(HOUR, 0, ReadingTimestamp), 0);
GO

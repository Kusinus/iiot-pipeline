-- =============================================================================
-- load_test_analysis.sql - Auswertung Lasttest gemaess Kapitel 5/6
-- Ausfuehren in DBeaver NACH jeder Teststufe (Fensterzeiten aus dem
-- load_test.py-Log uebernehmen: "Fenster (lokale Zeit): ... bis ...").
-- ReadingTimestamp ist lokale Schweizer Zeit (Edge-seitig gesetzt, ohne
-- Offset) -> Konvertierung ueber AT TIME ZONE fuer korrekten UTC-Vergleich
-- mit IngestedAt (UTC, serverseitig per SYSUTCDATETIME() gesetzt).
-- =============================================================================

DECLARE @WindowStart DATETIME2 = '2026-09-04T20:00:00';  -- anpassen: Fensterstart
DECLARE @WindowEnd   DATETIME2 = '2026-09-04T20:10:00';  -- anpassen: Fensterende
DECLARE @DeviceIdPattern NVARCHAR(50) = 'rpi-edge-01-sim%';  -- anpassen: DEVICE_ID-Praefix

WITH Latenzen AS (
    SELECT
        DeviceId,
        ReadingTimestamp,
        IngestedAt,
        DATEDIFF(
            MILLISECOND,
            ReadingTimestamp AT TIME ZONE 'W. Europe Standard Time' AT TIME ZONE 'UTC',
            IngestedAt
        ) AS LatenzMs
    FROM dbo.SensorReadings
    WHERE DeviceId LIKE @DeviceIdPattern
      AND ReadingTimestamp BETWEEN @WindowStart AND @WindowEnd
)
SELECT
    COUNT(*)                                                   AS AnzahlZeilen,
    COUNT(DISTINCT DeviceId)                                   AS AnzahlGeraete,
    MIN(LatenzMs)                                              AS LatenzMinMs,
    AVG(LatenzMs)                                              AS LatenzAvgMs,
    MAX(LatenzMs)                                              AS LatenzMaxMs,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY LatenzMs) OVER () AS LatenzP50Ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY LatenzMs) OVER () AS LatenzP95Ms
FROM Latenzen;

-- Erwartete Nachrichtenzahl zum Vergleich (fuer Verlustrate):
-- AnzahlGeraete * (Fensterdauer_Sekunden / SEND_INTERVAL_SEC)
-- z.B. 5 Geraete * (600s / 15s) = 200 erwartete Zeilen

-- Optional: Duplikate/uebersprungene Nachrichten sind NICHT in der Tabelle
-- sichtbar (Unique-Constraint verhindert den Insert) - dafuer die Processor-
-- Logs pruefen (Azure Portal -> Container Apps -> processor -> Log stream,
-- Filter auf "Duplikat").

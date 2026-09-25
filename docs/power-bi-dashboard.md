# Power-BI-Dashboard – Anleitung (Phase 5)

## Voraussetzungen

- Power BI Desktop (Windows; auf Fedora/Linux notfalls via Power BI Service
  im Browser mit demselben DirectQuery-Prinzip, oder eine Windows-VM/-Rechner).
- Netzwerkzugriff auf `sql-pipeline-dev-swn-ghxzap.database.windows.net`,
  Port 1433 (Azure SQL) – von deinem aktuellen Netzwerk aus muss die
  öffentliche IP in der SQL-Server-Firewall freigeschaltet sein (siehe unten,
  gleiches Prinzip wie `az sql server firewall-rule create`).
- SQL-Login: `sqladmin` / Passwort aus `parameters/dev.secrets.env`
  (Feld `SQL_ADMIN_PASSWORD`) – oder Azure-AD-Anmeldung mit dem als
  AAD-Admin auf dem SQL-Server hinterlegten Konto (siehe
  `parameters/dev.bicepparam`).

## 1. Firewall-Freigabe für deinen Power-BI-Rechner

Falls Power BI Desktop nicht auf demselben Rechner läuft, dessen IP schon
freigeschaltet ist:

```bash
# Eigene öffentliche IP ermitteln
curl -s https://api.ipify.org

az sql server firewall-rule create \
  --resource-group rg-iiot-pipeline-dev-swn-001 \
  --server sql-pipeline-dev-swn-ghxzap \
  --name AllowPowerBI \
  --start-ip-address <DEINE-IP> --end-ip-address <DEINE-IP>
```

## 2. Datenquelle verbinden (DirectQuery)

1. Power BI Desktop → **Daten abrufen** → **Azure SQL-Datenbank**.
2. Server: `sql-pipeline-dev-swn-ghxzap.database.windows.net`
   Datenbank: `sensordata`
3. **Datenkonnektivitätsmodus: DirectQuery** wählen (nicht "Importieren")
   – die Views sind bewusst dafür ausgelegt, dass Power BI bei jedem
   Aktualisieren live gegen die DB fragt (siehe Kommentar in
   `database/views.sql`), damit das Dashboard aktuelle Werte zeigt statt
   eines gecachten Snapshots.
4. Anmeldung: SQL-Server-Authentifizierung (`sqladmin` + Passwort) oder
   Microsoft-Konto (Azure AD).
5. Im Navigator auswählen:
   - `dbo.vw_LatestReadings` (Live-Kacheln)
   - `dbo.SensorReadings` (Rohdaten-Zeitreihe)
   - `dbo.vw_HourlyAggregates` (Stunden-Trend und Lückenanalyse)

## 3. Umgesetzter Report

Der Report `iiot-pipeline-sensordata-report` ist live mit einem separat
publizierten Semantic Model (`iiot-pipeline-sensordata-model`) verbunden und
kombiniert alle drei Quellen auf einer gemeinsamen Report-Seite:

| Bereich | Quelle | Feld(er) | Zweck |
|---|---|---|---|
| Live-Kacheln | `dbo.vw_LatestReadings` | `Temperature`, `Humidity`, `CpuTemperature` (Zusammenfassung "Erster Wert") | Zuletzt erfasster Messwert je Grösse |
| Zeitreihe | `dbo.SensorReadings` | X = `ReadingTimestamp`, Y = `Temperature`, `Humidity`, `CpuTemperature` | Verlauf einzelner Messpunkte, bewusst ohne Vorab-Aggregation |
| Stunden-Trend | `dbo.vw_HourlyAggregates` | X = `HourBucket`, Y = Stundenmittelwerte | Übersicht über längere Zeiträume |
| Lückenanalyse | `dbo.vw_HourlyAggregates` | X = `HourBucket`, Y = `ReadingCount` | Erkennung von Erfassungsunterbrüchen (fehlende Balken) |

Hinweise:

- Die Live-Kacheln müssen auf `vw_LatestReadings` (nicht auf
  `SensorReadings`) gebunden sein, sonst zeigen sie den Durchschnitt über die
  gesamte Historie statt des aktuellsten Werts.
- Im Stunden-Trend zieht Power BI über Datenlücken eine gerade Linie
  (Interpolationsartefakt). Massgeblich für Unterbrüche ist ausschliesslich
  der `ReadingCount`-Chart.
- Eine Kachel für `MotorSpeed` (OPC-UA-Simulator) ist noch nicht ergänzt; die
  Felder sind in beiden Views vorhanden.

## 4. Aktualisierung / "Live"-Charakter

Mit DirectQuery fragt Power BI die Views bei jedem manuellen Refresh (oder
automatischem Refresh im Power BI Service, falls dort veröffentlicht) live
gegen die DB ab – kein Scheduled-Refresh-Setup mit Gateway nötig, solange
lokal in Power BI Desktop gearbeitet wird.

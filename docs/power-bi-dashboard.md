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
   - `dbo.vw_LatestReadings` (Live-Kacheln, Seite 1)
   - `dbo.SensorReadings` (Rohdaten mit Zeitstempel für die Zeitreihe, Seite 2)

## 3. Empfohlene Visuals

**Seite 1 – Live-Ansicht** (Basis: `vw_LatestReadings`, ein Wert pro Gerät):

| Visual | Feld(er) | Zweck |
|---|---|---|
| Kachel (Card) | `Temperature` (aktuellster Wert `rpi-edge-01`) | Momentanwert Temperatur |
| Kachel (Card) | `Humidity` | Momentanwert Luftfeuchtigkeit |
| Kachel (Card) | `SecondsSinceReading` | "Wie alt ist der Wert?" – zeigt Ausfälle sofort (z.B. > 30 s bei 15 s-Intervall = Problem) |
| Tabelle | `DeviceId`, `Location`, `ReadingTimestamp`, `Temperature`, `Humidity`, `CpuTemperature` | Übersicht aller Geräte (aktuell: nur `rpi-edge-01`, aber Struktur ist mehrgerätefähig) |

**Seite 2 – Zeitreihenauswertung** (Basis: `dbo.SensorReadings`, Rohdaten mit
Zeitstempel – bewusst ohne Vorab-Aggregation, damit einzelne Messpunkte statt
Stundenmittelwerte sichtbar sind):

| Visual | Feld(er) | Zweck |
|---|---|---|
| Liniendiagramm | X = `ReadingTimestamp`, Y = `Temperature`, `Humidity`, `CpuTemperature` | Verlauf der einzelnen Messwerte über die Zeit |
| Slicer | `Location` bzw. Datumsbereich auf `ReadingTimestamp` | Filterung |

Bei grösseren Zeiträumen wächst die Punktzahl entsprechend der
Sende-Frequenz (alle 15s) – für eine performantere, vorab aggregierte
Alternative steht `dbo.vw_HourlyAggregates` (Avg/Min/Max pro Stunde) bereit,
wurde im umgesetzten Report aber nicht verwendet.

## 4. Aktualisierung / "Live"-Charakter

Mit DirectQuery fragt Power BI die Views bei jedem manuellen Refresh (oder
automatischem Refresh im Power BI Service, falls dort veröffentlicht) live
gegen die DB ab – kein Scheduled-Refresh-Setup mit Gateway nötig, solange
lokal in Power BI Desktop gearbeitet wird.

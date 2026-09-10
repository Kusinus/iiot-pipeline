# Lasttest-Bericht: IIoT Cloud-Pipeline

> Durchgeführt am 04.09.2026, ca. 21:00–22:00 UTC (23:00–00:00 MESZ).
> Beleg-Artefakt zu Kapitel "Skalierbarkeit / Lasttest" gemäss
> `assets/Fragekatalog_Evaluation_Semesterarbeit.md`, Abschnitt 4.

## 1. Ziel und Ausgangslage

Die Pipeline wird produktiv nur von **einem** physischen DHT22-Sensor gespeist
(alle 15s eine Nachricht). Um belastbare Aussagen zu Skalierbarkeit und
Systemgrenzen treffen zu können, wurde Last synthetisch erzeugt: ein
Python-Skript simuliert *N* virtuelle Geräte, die parallel Telemetrie an den
Azure IoT Hub senden — methodisch wie im Fragekatalog empfohlen.

**Bewusste Design-Entscheidung:** Der Lastgenerator lief **auf dem
Raspberry Pi selbst**, nicht auf einem Entwickler-Laptop. Damit nimmt die
synthetische Last denselben Netzwerkpfad (MQTT über WebSockets, Port 443,
durch dieselbe OPNsense-Firewall) wie der reale Edge-Gateway-Container —
das Testergebnis ist damit repräsentativ für die tatsächliche
Produktionsumgebung, nicht nur für die Anbindung eines Büro-Laptops.

## 2. Architektur des Lasttests

```
Raspberry Pi (Lastgenerator)
  └─ run_load_test.py (asyncio, N × IoTHubDeviceClient)
        │  MQTT über WebSockets, Port 443
        ▼
  Azure IoT Hub (iot-pipeline-dev-swn-ghxzap, SKU F1 / Free Tier)
        │  Event Hub (eingebettet)
        ▼
  Processor (Azure Container App, 1 Replica, kein Autoscaling)
        ▼
  Azure SQL Serverless (dbo.SensorReadings)
```

- **N virtuelle Geräte** wurden als eigene Device-Identities im IoT Hub
  angelegt (`loadtest-01` … `loadtest-200`), damit jede simulierte
  Nachricht eine eigene, plausible `deviceId` trägt statt die reale
  `rpi-edge-01`-Identität zu missbrauchen.
- Jedes virtuelle Gerät sendet ein Payload strukturell identisch zum realen
  Edge-Gateway (Temperatur, Feuchtigkeit, CPU-Temp, Motordrehzahl, Druck,
  Durchfluss), markiert mit `"sensorType": "LOADTEST"` zur klaren
  Unterscheidbarkeit von echten Messwerten in der SQL-Tabelle.
- Provisionierung erfolgte über die Azure CLI (`az iot hub device-identity
  create`), der eigentliche Sendevorgang über die offizielle
  `azure-iot-device`-SDK (dieselbe Bibliothek wie im Edge-Gateway,
  `edge-gateway/app/requirements.txt`).

**Skripte** (in `load-test/`):
| Datei | Zweck |
|---|---|
| `provision_devices.sh` | Legt N Test-Geräte im IoT Hub an, schreibt Connection Strings nach `devices.json` |
| `run_load_test.py` | Simuliert N Geräte parallel für eine definierte Dauer/Rate, protokolliert nach `results.csv` |
| `cleanup_devices.sh` | Entfernt alle Test-Geräte-Identitäten wieder |

## 3. Testdurchführung — Stufenweise Lasterhöhung

Alle Schritte: 1 Nachricht/s pro Gerät, 15 Sekunden Dauer, Ziel-Gesamtlast
= Geräteanzahl.

| Geräte | Ziel-Last | Gesendet / Fehler | Ist-Durchsatz | Latenz Ø | Latenz p95 | Latenz max |
|---:|---:|---:|---:|---:|---:|---:|
| 1   | 1 msg/s   | 14/0   | 0.87 msg/s | 130.6 ms | 261.2 ms | 261.2 ms |
| 5   | 5 msg/s   | 70/0   | 4.27 msg/s | 124.6 ms | 167.5 ms | 216.1 ms |
| 10  | 10 msg/s  | 140/0  | 8.18 msg/s | 127.8 ms | 211.1 ms | 217.9 ms |
| 25  | 25 msg/s  | 350/0  | 18.70 msg/s| 127.6 ms | 207.4 ms | 221.3 ms |
| 50  | 50 msg/s  | 700/0  | 32.28 msg/s| 129.8 ms | 218.7 ms | 235.7 ms |
| 100 | 100 msg/s | 1400/0 | 49.86 msg/s| 131.4 ms | 222.9 ms | 247.4 ms |
| 200 | 200 msg/s | 2800/0 | 69.03 msg/s| 136.0 ms | 220.0 ms | 281.6 ms |

Rohdaten: [`results.csv`](results.csv).

**Beobachtung 1 — Latenz bleibt konstant:** Die Sende-Latenz (Zeit für
`send_message()`, MQTT-QoS-1-Bestätigung durch IoT Hub) bleibt über den
gesamten getesteten Bereich (1–200 gleichzeitige Geräte) nahezu konstant
bei ~125–136 ms im Mittel. **Kein einziger Sendefehler** auf
IoT-Hub-Seite in diesen sieben Stufen. Der F1-Free-Tier-Hub zeigt bis
200 gleichzeitige simulierte Geräte keine erkennbare Verschlechterung der
Antwortzeit.

**Beobachtung 2 — Durchsatz-Plateau ab ~100 Geräten:** Der *Ziel*-Durchsatz
(1 msg/s × Geräteanzahl) wird ab 50 Geräten zunehmend verfehlt
(Ist/Ziel-Verhältnis: 50 → 65 %, 100 → 50 %, 200 → 35 %). Da die Latenz pro
Nachricht dabei gleich bleibt, ist die wahrscheinlichste Erklärung der
**TLS/WebSocket-Verbindungsaufbau vieler gleichzeitiger virtueller Geräte**,
der einen wachsenden Teil des 15-Sekunden-Testfensters beansprucht (200
gleichzeitige TLS-Handshakes auf einem Raspberry Pi 5), nicht eine
Drosselung durch den IoT Hub. Diese Hypothese wurde nicht abschliessend
isoliert (siehe Abschnitt 5, Einschränkung).

## 4. Kontrolltest (30s) — Skript-Bug entdeckt und behoben

Um Verbindungsaufbau-Overhead von Dauerlast zu trennen, wurde ein
Kontrolltest mit 50 Geräten über 30s statt 15s angesetzt.

**Befund:** Der Testprozess hing unbegrenzt fest. Ursache: `run_load_test.py`
rief `await client.send_message(msg)` ohne Timeout auf. Bei einem
Verbindungsabbruch blockierte dieser Aufruf unbegrenzt, während die SDK im
Hintergrund-Thread endlos `ConnectionDroppedError` protokollierte, ohne dass
mein Code das abfangen konnte (die Exception entsteht in einem separaten
Thread, nicht im `await`).

**Fix:** `send_message()` und `connect()` wurden mit
`asyncio.wait_for(..., timeout=...)` abgesichert, sodass ein
Verbindungsabbruch als Fehler gezählt wird statt den gesamten Testlauf zu
blockieren (siehe `run_load_test.py`, `run_device()`).

## 5. Ursachenanalyse — Warum brachen auch nach dem Fix Verbindungen ab?

Nach dem Fix trat weiterhin ein reproduzierbares Muster auf: **jede** Sendung
über ein 30s-Fenster schlug fehl — sogar bei nur **einem** einzigen
virtuellen Gerät. Da dieses Verhalten unerwartet war, wurde systematisch
eingegrenzt:

| Hypothese | Test | Ergebnis |
|---|---|---|
| Pi-Ressourcenerschöpfung (CPU/RAM durch viele gleichzeitige Verbindungen) | `ps`, `free`, `/proc/loadavg`, `ss` auf dem Pi während des Fehlers geprüft | **Widerlegt**: Load 0.03, 5 GB frei RAM, keine hängenden Prozesse, keine CLOSE-WAIT-Sockets |
| Bug/Zustand spezifisch in meinem Lauf-Skript oder dieser SDK-Client-Instanz | Unabhängige Sonde via `az iot device send-d2c-message` (eigener Prozess, eigene SDK-Instanz, vom Laptop statt vom Pi) gegen `loadtest-01` | **Widerlegt**: identischer Fehler auch über einen komplett unabhängigen Kanal |
| Gerätespezifische Drosselung wegen häufiger Reconnects (loadtest-01 wurde in jeder Teststufe wiederverwendet) | Dieselbe Sonde gegen `loadtest-150` (nur 1× zuvor verwendet) | **Widerlegt**: identischer Fehler, unabhängig von Reconnect-Historie des Geräts |
| Hub-weites Problem statt gerätespezifisch | Verbindungsstatus des **realen** Produktivgeräts `rpi-edge-01` geprüft | **Bestätigt**: auch das reale Gerät verlor die Verbindung, `disconnected result code 7`, Container-Neustart brachte keine Besserung (serverseitige Ablehnung) |
| Azure-Monitor-Metriken zur Bestätigung | `connect.success`, `connectedDeviceCount`, `d2c.telemetry.ingress.sendThrottle` für den Hub abgefragt | **0 erfolgreiche Verbindungen, 0 verbundene Geräte über 20+ Minuten hubweit** |

**Ursache gefunden:** Ein rein lesender Control-Plane-Aufruf
(`az iot hub device-identity list`, keine Geräteverbindung) lieferte den
entscheidenden Hinweis:

```
IotHubQuotaExceeded: Total number of messages on the IoT Hub exceeded
the allocated quota.
```

Die **Tagesquote des F1-Free-Tiers (8'000 Nachrichten/Tag)** wurde durch
die kumulierte Last (reales Gerät + Teststufen 1–200, insgesamt
**5'474 erfolgreich gezählte Testnachrichten**, zzgl. eines Anteils aus dem
später hart abgebrochenen 30s/50-Geräte-Lauf, der keine finale Zählung mehr
schrieb) überschritten. **Wichtige Erkenntnis:** Die zuvor abgefragte
Azure-Monitor-Metrik `d2c.telemetry.ingress.allProtocol` zeigte zu diesem
Zeitpunkt nur 237 Nachrichten an — diese Metrik ist demnach **erheblich
verzögert/unzuverlässig für eine Live-Budgetkontrolle** während eines
Lasttests und darf nicht als Echtzeit-Referenz verwendet werden.

**Effekt der überschrittenen Quote:** Sobald die Tagesquote erreicht ist,
lehnt IoT Hub F1 *sämtliche* Operationen ab — nicht nur weitere
Telemetrie-Sendungen, sondern auch Verbindungsversuche unbeteiligter
Geräte (inkl. des realen Sensors) und sogar rein lesende
Verwaltungsoperationen. Das erklärte rückwirkend alle beobachteten
Symptome (Verbindungsabbrüche bei 1 wie bei 50 Geräten, hubweite 0-Connects,
kein Erfolg durch Container-Neustart).

## 6. Auswirkung auf den Produktivbetrieb

Der Lasttest hat die **reale Datenerfassung temporär unterbrochen**: der
Edge-Gateway-Container (`rpi-edge-01`) konnte ab ca. 21:23 UTC bis zum
Zurücksetzen der Tagesquote (00:00 UTC) keine Messwerte mehr übertragen.
Dies ist eine bewusst in Kauf genommene, im Rahmen einer Testumgebung
vertretbare Konsequenz, sollte aber in der Arbeit **explizit als
Limitation/Learning** benannt werden: synthetische Lasttests gegen
Free-Tier-Ressourcen sollten nach Möglichkeit gegen eine separate
Hub-Instanz laufen, um Produktivbetrieb nicht zu gefährden.

**Kein Datenverlust in der Datenbank:** Da lediglich keine neuen Werte
gesendet werden konnten (keine fehlerhaften/korrumpierten Einträge), sind
keine Bereinigungsmassnahmen an `dbo.SensorReadings` nötig. Die 200
Lasttest-Geräte-Identitäten wurden nach Testende vollständig aus dem IoT
Hub entfernt (`cleanup_devices.sh`), sodass die Geräteliste wieder nur das
reale Produktivgerät enthält.

## 7. Beantwortung der Fragekatalog-Fragen (Abschnitt 4)

| Frage | Antwort |
|---|---|
| Wie simulierst du Last jenseits des einen physischen Sensors? | Python-Lastskript mit N virtuellen Device-Identities, ausgeführt auf dem Pi selbst für realistischen Netzwerkpfad (siehe Abschnitt 2) |
| Welche Metriken misst du unter Last? | Ist-Durchsatz, Sende-Latenz (Ø/p95/max), Fehlerrate — gemessen clientseitig; Azure-Monitor-Metriken (`connect.success`, `connectedDeviceCount`, `sendThrottle`) für Hub-Perspektive |
| Bei welcher Last stösst welche Komponente zuerst an eine Grenze? | **Die Tagesquote des IoT-Hub-F1-Tiers (8'000 Nachrichten/Tag)** — nicht Durchsatz/Sekunde, nicht Latenz, nicht Container-App-Skalierung. Bis 200 gleichzeitige Geräte / 15s-Fenster traten **keine** durchsatz- oder latenzbedingten Fehler auf; die Grenze war ausschliesslich das kumulierte Tagesvolumen. |
| Ist das Autoscaling der Container App konfiguriert/getestet? | **Nein** — `az containerapp show` bestätigt `minReplicas: 1, maxReplicas: 1, rules: null`. Die Verarbeitungsschicht läuft auf fixer Instanzzahl; unter der getesteten Last (bis 2'800 Nachrichten in 15s-Bursts) wurde dies nicht zum Engpass, da die Tagesquote vorher greift. |
| Übertragbarkeit trotz Single-Sensor-Setup? | Der synthetische Lasttest lief über denselben Netzwerkpfad/dieselbe SDK wie der reale Sensor, wodurch die Ergebnisse (Latenz, Fehlerverhalten) direkt auf das Produktivsystem übertragbar sind — mit der expliziten Limitation, dass Free-Tier-Quoten reale Lasttests aktiv einschränken/gefährden. |

## 8. Zusammenfassung / Kernaussagen für die Arbeit

1. **IoT Hub F1 hält Latenz und Fehlerrate bis mindestens 200 simulierte
   Geräte konstant** (~130 ms Ø, 0 Fehler) — der Hub selbst ist im
   getesteten Lastbereich nicht der Flaschenhals.
2. **Die tatsächliche, zuerst erreichte Grenze ist die Tagesquote**
   (8'000 Nachrichten/Tag), nicht Durchsatz oder Latenz — eine bewusste,
   im Projekt bereits dokumentierte Kostenentscheidung (Free Tier), deren
   Konsequenz hier erstmals real reproduziert und belegt wurde.
3. **Bei Quota-Überschreitung fällt der gesamte Hub aus**, nicht nur die
   verursachenden Verbindungen — ein relevanter Punkt für die
   Diskussion der Betriebssicherheit von Shared/Free-Tier-Ressourcen.
4. Ein Implementierungsfehler im Testskript selbst (fehlendes Timeout bei
   `send_message()`) führte zunächst zu einem irreführenden Befund
   (scheinbarer Verbindungsabbruch-Bug) und wurde durch systematisches
   Ausschlussverfahren (Ressourcen → Skript → Gerät → Hub) korrekt auf die
   eigentliche Ursache zurückgeführt — gutes Beispiel für methodisch
   sauberes Debugging, dokumentierbar als Prozess-Learning.
5. Die Container-App-Verarbeitungsschicht läuft ohne Autoscaling
   (fixe 1 Instanz) — unter der getesteten Last kein beobachtbarer
   Engpass, aber auch nicht differenziert testbar, da die Tagesquote
   vorher limitiert.

## 9. Artefakte

- Testskripte: `load-test/provision_devices.sh`, `load-test/run_load_test.py`, `load-test/cleanup_devices.sh`
- Rohdaten: `load-test/results.csv`
- Dieser Bericht: `load-test/LASTTEST_BERICHT.md`

# Row-Count-Abgleich & Ende-zu-Ende-Latenz: Bericht

> Analyse durchgeführt am 10.09.2026, gegen die Produktivdaten in
> `dbo.SensorReadings` (Zeitraum 26.08.–09.09.2026) und die Azure-Monitor-
> Metriken des IoT Hub. Beleg-Artefakt zu Kapitel 6.1/6.2 (Funktionalität/
> Performance), ergänzt Kapitel 5 (Methodik) um die dort noch offenen
> Prüfmethoden "Row-Count-Abgleich Hub↔DB" und "volle E2E-Latenz inkl.
> Processor/SQL".

## 1. Methodik

**Row-Count-Abgleich:** Tageswerte (UTC-Kalendertag) der IoT-Hub-Metrik
`d2c.telemetry.ingress.success` (Total, hub-weit über alle Geräte) wurden den
tatsächlich in `dbo.SensorReadings` vorhandenen Zeilen desselben UTC-Tages
gegenübergestellt (`ReadingTimestamp`, nach Europe/Zurich→UTC konvertiert,
über **alle** Geräte/SensorTypes summiert, damit Lasttest- und
Simulator-Traffic nicht fälschlich als Abweichung erscheinen).

**E2E-Latenz:** `IngestedAt` (UTC, durch `SYSUTCDATETIME()` beim INSERT
gesetzt) minus `ReadingTimestamp` (lokale Zeit ohne Offset, siehe
`edge-gateway/app/main.py`, nach UTC konvertiert). Diese Differenz deckt die
**gesamte** Pipeline ab: MQTT-Sendung → IoT Hub → Event Hub → Processor →
SQL-Insert – nicht nur den Hub-Ingress wie beim Lasttest
(`LASTTEST_BERICHT.md`, dort nur Sende-Latenz bis zur MQTT-QoS-1-Bestätigung).

Beide Verfahren nutzen ausschliesslich bereits vorhandene, produktiv
gesammelte Daten (read-only SQL-Abfrage via `pytds`, `az monitor metrics
list`) – kein zusätzlicher Testlauf nötig.

## 2. Row-Count-Abgleich – Ergebnis

| UTC-Tag | Hub (`d2c.telemetry.ingress.success`) | DB (`SensorReadings`, alle Typen) | Differenz |
|---|---:|---:|---:|
| 26.08. | 3'162 | 3'166 | +4 |
| 27.08. | 5'693 | 5'694 | +1 |
| 28.08. | 5'697 | 5'696 | −1 |
| 29.08. | 5'692 | 5'693 | +1 |
| 30.08. | 5'696 | 5'695 | −1 |
| 31.08. | 5'692 | 5'401 | **−291** |
| 01.09. | 5'505 | 0 | **−5'505** |
| 02.09. | 5'698 | 0 | **−5'698** |
| 03.09. | 5'629 | 0 | **−5'629** |
| 04.09. | 10'577 | 6'920 | **−3'657** |
| 05.09. | 5'694 | 5'696 | +2 |
| 06.09. | 5'697 | 5'698 | +1 |
| 07.09. | 5'696 | 5'695 | −1 |
| 08.09. | 4'855 | 4'852 | −3 |

**Befund 1 – Normalbetrieb ist 1:1 abgeglichen:** An allen Tagen ausserhalb
des Vorfalls (26.–30.08., 05.–08.09.) stimmen Hub- und DB-Zählung bis auf
±1–4 Nachrichten exakt überein (Abweichung durch Tagesgrenzen-Rundung bei der
UTC/Lokalzeit-Konvertierung, nicht durch Datenverlust – siehe Abschnitt 4).
Das bestätigt: unter Normalbedingungen erreicht **jede** vom Hub
angenommene Nachricht auch die Datenbank; die Idempotenz-Absicherung über den
Unique Index (`DeviceId`, `ReadingTimestamp`, siehe `database/schema.sql`)
verursacht keine stillen Duplikate oder Lücken.

**Befund 2 – Realer Datenverlust 31.08.–04.09.:** Über diesen Zeitraum
akzeptierte der Hub **20'780 Nachrichten mehr**, als in der Datenbank
ankamen (291 + 5'505 + 5'698 + 5'629 + 3'657). Am 01.–03.09. fehlen die
Werte des Produktivgeräts vollständig (0 Zeilen trotz Hub-Empfang), am
31.08. und 04.09. teilweise.

## 3. Ursachenanalyse des Datenverlusts

**Ursache (Aussage des Autors, 10.09.2026):** Im betroffenen Zeitraum lief
das Startguthaben der Subscription "Azure for Students" ab; der Autor musste
sich mit einer Kreditkarte neu anmelden, um die Nutzung fortzusetzen. Dies
erklärt, weshalb der Processor (Container App, kostenpflichtige
Rechenleistung) über mehrere Tage nicht lief, während der IoT Hub F1
(kostenloser Free-Tier) weiterhin Nachrichten annahm – die Hub-Metrik zeigt
für 01.–03.09. durchgehend normale Empfangswerte (5'505–5'698/Tag), obwohl
in der Datenbank für diese drei Tage keine einzige Zeile ankam. Zusätzlich
führte der Autor um den 31.08. einen (undokumentierten, dem Lasttest vom
04.09. vorausgehenden) Test durch, bei dem möglicherweise die
IoT-Hub-Tagesquote überschritten wurde – dies passt zum partiellen (statt
vollständigen) Ausfall an genau diesem Tag (−291 von 5'692 Zeilen, siehe
Tabelle oben).

**Warum der Verlust trotz Wiederanlaufs endgültig war:** Der Processor
besitzt **keinen persistenten Checkpoint-Store** (bewusste, bereits in
`database/schema.sql` dokumentierte Design-Entscheidung) und die
Event-Hub-Retention der Dev-Umgebung beträgt gemäss `modules/iot-hub.bicep`
(`retentionDays = 1` für `environment != 'prod'`) nur **1 Tag**. Das
Abo-Problem dauerte länger als diese Retention – die während des Ausfalls
im Event Hub zwischengespeicherten Nachrichten alterten heraus, **bevor**
der wieder angelaufene Processor sie konsumieren konnte. Der Verlust liegt
damit ausserhalb der Idempotenz-Absicherung (die nur Duplikate abfängt,
keine Retention-Überschreitung) und war nicht mehr aufholbar – konsistent
mit dem in Abschnitt 2 gemessenen Muster (0 Zeilen für 01.–03.09., nur der
zeitlich jüngste Teil des Backlogs vom 04.09. wurde nach Wiederanlauf noch
rechtzeitig verarbeitet, siehe die Mehrstunden-Latenzen in Abschnitt 4).

Ergänzend geprüfte, aber verworfene Indizien:
- Die Container-App-Revision (`ca-pipeline-dev-swn-ghxzap--opcua180253`) ist
  seit dem initialen Deployment am 26.08. durchgehend die einzige aktive
  Revision – ein Redeploy scheidet als Ursache aus.
- Das Monitoring-Modul (Log Analytics) ist gemäss Roadmap nicht aktiviert,
  daher lässt sich der genaue Ausfallzeitpunkt/-verlauf nicht mehr
  nachträglich aus Container-App-Logs rekonstruieren, nur aus der
  Row-Count-Differenz.

**Einordnung für die Arbeit:** Der Befund ist wissenschaftlich verwertbar und
aufschlussreicher als ein lückenloser Abgleich: Er demonstriert empirisch
eine bereits im Code kommentierte, aber bisher nicht real beobachtete Grenze
der Architektur (fehlender Checkpoint-Store + kurze Dev-Retention ⇒
Datenverlustrisiko bei Prozessorausfall > Retentionsdauer) – ausgelöst durch
ein reales, für Free-/Studenten-Tier-Umgebungen typisches Betriebsrisiko
(Ablauf des Startguthabens). Gehört inhaltlich nach Kapitel 6.1
(Funktionalität, als Ist-Befund) und in die Diskussion Kapitel 7 (Grenzen
der Untersuchung / Wartbarkeit – Empfehlung: `retentionDays` erhöhen
und/oder Checkpoint-Store nachrüsten für einen produktiven Einsatz;
Kosten-/Lizenzgrenzen-Diskussion um das Startguthaben-Risiko ergänzen).

## 4. Ende-zu-Ende-Latenz – Ergebnis

**Wichtiger Störfaktor zuerst:** Der Pi hat keine batteriegepufferte RTC und
kein funktionierendes NTP (bekanntes, bereits dokumentiertes Problem, siehe
`edge-gateway/docs/raspberry-pi-setup.md` / `httpdate-fix.service`). Die
naive Differenz `IngestedAt − ReadingTimestamp` zeigt dadurch einen
**messbaren, linear wachsenden Uhren-Drift** von ca. **1 Sekunde pro Tag**
(Mittelwert bei "sauberen" Messungen: 27.08. −0,1 s → 31.08. −3,9 s → 07.09.
−10,6 s, jeweils zurückgesetzt auf ~0 nach einem Neustart/Clock-Fix). Dieser
Drift ist selbst ein dokumentierenswerter Befund (quantifiziert die
Auswirkung des bekannten NTP/OPNsense-Problems), verfälscht aber die
rohe Latenzmessung um bis zu ±12 s an einzelnen Tagen.

**Bereinigte Messung:** Für Zeilen mit `0 s ≤ Δ ≤ 60 s` (Normalbetrieb ohne
Backlog-Ausreisser, n = 3'710 von 54'715 Zeilen – die übrigen sind entweder
durch obigen Uhren-Drift leicht negativ oder durch den Datenverlust-Vorfall/
Lasttest als Mehrstunden-Backlog nicht repräsentativ) ergibt sich für die
**tatsächliche E2E-Verarbeitungslatenz** (MQTT-Sendung bis SQL-Insert):

| Kennzahl | Wert |
|---|---:|
| n (verwertbare Messpunkte) | 3'710 |
| Minimum | 0,00 s |
| Mittelwert | 0,41 s |
| Median | 0,31 s |
| p95 | 0,63 s |
| Maximum | 56,9 s |
| Standardabweichung | 1,89 s |

Die Pipeline verarbeitet Nachrichten unter Normalbedingungen also in
**unter einer Sekunde** von der MQTT-Sendung bis zum sichtbaren
SQL-Datensatz (deutlich schneller als das 15-Sekunden-Sendeintervall) –
konsistent mit der im Lasttest gemessenen Hub-Ingress-Latenz von ~125–136 ms
(dort nur bis zur QoS-1-Bestätigung, hier zusätzlich Event-Hub-Consume und
SQL-Insert durch den Processor).

**Backlog-Ereignisse (nicht in obiger Tabelle):** Zusätzlich zeigen die Daten
einen kurzen Backlog beim initialen Deployment (26.08., bis zu 6,4 h, durch
`starting_position="-1"` beim ersten Prozessorstart – Event Hub wird ab
Retentionsbeginn statt "live" gelesen) sowie einen mehrstündigen Backlog am
04.–05.09. im Zusammenhang mit dem Lasttest (IoT-Hub-Quota-Überschreitung,
siehe `LASTTEST_BERICHT.md`). Diese sind methodisch keine "E2E-Latenz",
sondern Ausfall-/Wiederanlauf-Zeiten und gehören separat in die Diskussion
der Betriebssicherheit.

## 5. Aktueller Betriebszustand (Stand 10.09.2026, zu prüfen)

Die letzte Zeile des Produktivgeräts (`rpi-edge-01`, DHT22) stammt vom
**08.09.2026, 22:25:54 Uhr** (lokal) – seither (> 36 h) keine neuen Werte,
obwohl der Processor (Container App) gemäss `az containerapp show`
weiterhin `runningStatus: Running` meldet. Ein SSH-Zugriff auf den Pi
(172.16.20.104) war während dieser Analyse nicht möglich (Verbindung
timeout – vermutlich weil der Auswertungsrechner aktuell nicht im
Testnetzwerk hinter der OPNsense hängt). **Vom Autor zu prüfen:** ob der Pi/
Edge-Gateway aktuell tatsächlich offline ist (Stromausfall, Netzwerk,
Container gestoppt) – relevant sowohl für die Datenerfassung bis zur Abgabe
als auch als möglicher weiterer Beleg für Kapitel 6.5 (Wartbarkeit).

## 6. Artefakte

- Dieser Bericht: `load-test/ROWCOUNT_LATENZ_BERICHT.md`
- Rohabfragen (nicht Teil des Repos, nur zur Nachvollziehbarkeit dieser
  Session verwendet): `pytds`-Skripte gegen `dbo.SensorReadings`, `az
  monitor metrics list --metric d2c.telemetry.ingress.success`

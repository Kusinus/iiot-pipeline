# Redeployment-Test in eine frische Ressourcengruppe: Bericht

> Durchgeführt am 10.09.2026, ca. 07:00–07:30 UTC. Beleg-Artefakt zu
> Kapitel 6.3 (Reproduzierbarkeit).

## 1. Ziel und Vorgehen

Nachweis, dass sich die gesamte Infrastruktur (nicht nur einzelne Module)
über die bestehende IaC (`main.bicep`, `scripts/deploy.sh`) unattended in
eine **neue, leere Ressourcengruppe** deployen lässt – inkl. Zeitmessung je
Phase und einer abschliessenden funktionalen Verifikation (nicht nur
"Deployment erfolgreich", sondern ein echtes Ende-zu-Ende-Testtelegramm
durch die neu erstellte Pipeline).

**Bewusste Abweichung von der Dev-Umgebung:** Es wurde die Umgebung `test`
statt `dev` verwendet (`parameters/test.bicepparam`, SKU S1 statt F1 für den
IoT Hub), da pro Subscription nur ein kostenloser F1-Tarif erlaubt ist
(siehe `modules/iot-hub.bicep`) und der produktive Dev-Hub für diesen Test
nicht angetastet werden sollte. `parameters/test.bicepparam` war zuvor nur
unvollständig gepflegt (fehlende Pflichtparameter) und wurde im Rahmen
dieses Tests vervollständigt (siehe Commit-Historie).

Neue Ressourcengruppe: `rg-iiot-pipeline-redeploy-swn-001` (switzerlandnorth).

## 2. Zeitmessung

| Phase | Befehl | Dauer |
|---|---|---:|
| Resource Group + vollständiges Bicep-Deployment (IoT Hub, Azure SQL, Container Apps Environment, ACR, Log Analytics, Container App mit Platzhalter-Image) | `scripts/deploy.sh test rg-iiot-pipeline-redeploy-swn-001` | **6 min 17 s** (davon 5 min 50 s reine Bicep-Deployment-Dauer laut Azure, Rest: RG-Erstellung + Output-Abfrage) |
| Datenbankschema + Views anlegen | `scripts/init-database.py` | **< 1 s** |
| Processor-Image bauen und in ACR pushen | `az acr build --registry ... --image processor:redeploytest ./processor` | **64 s** |
| Container App auf reales Image umstellen | `az deployment group create` (erneuter Bicep-Lauf mit `processorImage`-Override) | **1 min 13 s** |
| **Gesamt (Infrastruktur bis lauffähige Pipeline)** | | **≈ 8 min 35 s** |

Zum Vergleich: Der ursprüngliche Dev-Aufbau (26.08.2026) wurde nicht mit
derselben systematischen Zeitmessung durchgeführt – dieser Wert ist damit
der erste belastbare End-to-End-Zeitwert für ein komplettes Redeployment.

## 3. Funktionale Verifikation (nicht nur "Deployment Succeeded")

Ein Bicep-Deployment kann formal erfolgreich sein, ohne dass die Pipeline
tatsächlich funktioniert (z.B. falsche Connection Strings zwischen
Modulen). Deshalb wurde zusätzlich ein echtes Testtelegramm durch die neu
erstellte Pipeline geschickt:

1. Temporäre Geräte-Identität `redeploy-e2e-test` im neuen IoT Hub
   angelegt (`az iot hub device-identity create`).
2. Eine reale Telemetrie-Nachricht (identische Struktur wie das
   Edge-Gateway-Payload) per `azure-iot-device`-SDK über MQTT/WebSockets
   gesendet.
3. Nach wenigen Sekunden in der neuen Datenbank verifiziert:

   ```
   DeviceId            redeploy-e2e-test
   Location             redeploy-test
   ReadingTimestamp      2026-09-10 09:28:33.79 (lokal)
   Temperature            22.2
   Humidity               44.4
   IngestedAt (UTC)       2026-09-10 07:28:34.43
   ```

   E2E-Latenz ≈ 0,65 s – konsistent mit den in
   `load-test/ROWCOUNT_LATENZ_BERICHT.md` für die Dev-Umgebung gemessenen
   Werten (Median 0,31 s, p95 0,63 s), obwohl es sich um eine komplett neu
   erstellte Infrastruktur (neuer Hub, neue Datenbank, neuer Processor,
   neues frisch gebautes Container-Image) handelt.
4. Testgeräte-Identität danach wieder entfernt.

**Ergebnis: Die reproduzierte Pipeline ist funktional identisch zur
Dev-Umgebung**, nicht nur strukturell (gleiche Ressourcentypen), sondern
nachweislich end-to-end lauffähig.

## 4. Aufgetretenes Problem (Transparenzhinweis, kein IaC-Defekt)

Beim Umstellen der Container App auf das reale Prozessor-Image wurde
zunächst versucht, statt der von Bicep bereits eingerichteten
Admin-Credential-Authentifizierung eine Managed-Identity-basierte
ACR-Authentifizierung nachzurüsten (`az containerapp registry set
--identity system`). Dieser Befehl hing über 10 Minuten fest und wurde
serverseitig abgebrochen; die Container App blieb danach in einem
inkonsistenten Zustand ("ContainerAppOperationInProgress"), der auch durch
Abwarten nicht von selbst auflöste. Behoben wurde dies durch Löschen und
bicep-basiertes Neuerstellen ausschliesslich der Container-App-Ressource
(`az containerapp delete` + erneuter `az deployment group create`) – die
übrigen Ressourcen (IoT Hub, SQL, ACR) waren davon nicht betroffen.

**Einordnung:** Dies ist kein Defekt der Infrastructure-as-Code-Definition
selbst (die von Bicep vorgesehene Admin-Credential-Authentifizierung
funktionierte von Anfang an korrekt und ungeändert), sondern eine
unnötige, selbst verursachte Komplikation durch einen nachträglichen
manuellen Eingriff ausserhalb der IaC. Die eigentliche
Reproduzierbarkeits-Kennzahl (Abschnitt 2, Zeile 1: reine
Bicep-Deployment-Dauer) ist davon nicht betroffen – der erste
`az deployment group create`-Lauf war beim ersten Versuch erfolgreich,
ohne manuelle Nacharbeit. Für die Wartbarkeits-Diskussion (Kapitel 6.5)
ist der Vorfall dennoch relevant: Ein "stecken gebliebener" Provisioning-
Zustand bei Azure Container Apps liess sich nicht per Warten, sondern nur
per Ressourcen-Neuerstellung beheben.

## 5. Aufräumen

`rg-iiot-pipeline-redeploy-swn-001` verursacht laufende Kosten (S1-IoT-Hub,
Log Analytics), solange sie besteht. Empfehlung: nach Abschluss dieses
Tests löschen (`az group delete --name
rg-iiot-pipeline-redeploy-swn-001`), sofern nicht für weitere Prüfungen
benötigt.

## 6. Artefakte

- Dieser Bericht: `load-test/REDEPLOY_BERICHT.md`
- Ergänzte Parameterdatei: `parameters/test.bicepparam`
- Neu angelegte Secrets-Datei (nicht versioniert): `parameters/test.secrets.env`

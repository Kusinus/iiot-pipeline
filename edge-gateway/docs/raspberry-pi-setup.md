# Raspberry Pi 5 – Einmaliges Setup

Diese Schritte werden **einmal pro Raspberry Pi** ausgeführt (z.B. nach dem
Flashen einer neuen SD-Karte), bevor `docker compose up -d` funktioniert.
Getestet auf Raspberry Pi 5, Raspberry Pi OS / Debian 13 (trixie), aarch64.

## Kurzform (automatisiert)

Schritte 1+2 (DHT-Overlay + Docker + docker-Gruppe) sind in einem
idempotenten Script zusammengefasst:

```bash
bash edge-gateway/scripts/bootstrap-pi.sh 4
sudo reboot   # falls das Script darauf hinweist
```

Danach direkt weiter mit Schritt 3 (Projekt übertragen). Die manuellen
Einzelschritte unten dokumentieren, was das Script im Detail macht.

## 1. DHT22-Kernel-Treiber aktivieren

Der DHT22 (an GPIO4 / physischer Pin 7) wird über den Linux-Kernel-Treiber
gelesen (Device-Tree-Overlay `dht11`, unterstützt auch DHT22) statt über
eine Python-GPIO-Bibliothek. Das übernimmt das Timing-kritische Protokoll
zuverlässiger als Userspace-Python und braucht im Container keine
Sonderrechte.

```bash
bash edge-gateway/scripts/setup-dht-overlay.sh 4
sudo reboot
```

Nach dem Neustart prüfen:

```bash
cat /sys/bus/iio/devices/iio:device0/name                       # erwartet: dht11@4
cat /sys/bus/iio/devices/iio:device0/in_temp_input               # z.B. 26300 = 26.3°C
cat /sys/bus/iio/devices/iio:device0/in_humidityrelative_input   # z.B. 42400 = 42.4% RH
```

## 2. Docker Engine installieren

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

Danach ab- und wieder anmelden (neue SSH-Session), damit die
Gruppenmitgliedschaft aktiv wird. Test:

```bash
docker ps
```

## 3. Projekt auf den Pi übertragen

```bash
rsync -avz --exclude='.env' edge-gateway/ pi-host:~/edge-gateway/
# oder: git clone/pull des Repos auf dem Pi
```

## 4. Gerät im IoT Hub registrieren

`setup-device.sh` ruft die Azure CLI auf – entweder auf dem Pi oder (so wie
wir es gemacht haben) auf dem Dev-Rechner ausführen. Falls `az` dort noch
fehlt:

```bash
# Fedora: azure-cli ist direkt im Standard-Repo, kein Drittanbieter-Repo nötig
sudo dnf install -y azure-cli python3-pip
az login --use-device-code   # Code im Browser unter aka.ms/devicelogin eingeben
az account set --subscription "<Name der richtigen Subscription>"
```

`python3-pip` wird gebraucht, damit `az extension add --name azure-iot`
funktioniert (die Erweiterung installiert sich selbst via pip; ohne
`python3-pip` schlägt das mit `ModuleNotFoundError: No module named 'pip'`
fehl).

Danach das Gerät registrieren und `.env` befüllen:

```bash
cd edge-gateway
bash scripts/setup-device.sh <iothub-name> rpi-edge-01 <resource-group>
```

Befüllt `.env` mit dem echten Device-Connection-String (nicht in Git
einchecken, siehe `.gitignore`). Wurde `.env` auf dem Dev-Rechner erzeugt,
per `scp` auf den Pi übertragen und danach lokal löschen:

```bash
scp edge-gateway/.env pi-host:~/edge-gateway/.env
rm edge-gateway/.env
```

## 5. Container bauen und starten

```bash
docker compose up -d --build
docker compose logs -f
```

## Systemuhr: NTP (UDP/123) im Testnetz unzuverlässig

Der Pi hat keine gepufferte RTC – nach längerem Stromverlust fällt die Uhr
auf einen alten Stand zurück (`fake-hwclock` rettet nur den letzten
bekannten Stand vor dem Shutdown, keine echte Live-Zeit). Eigentlich
korrigiert NTP das beim Boot automatisch, aber in diesem Testnetz blieb
`systemd-timesyncd` dauerhaft `System clock synchronized: no` – ein
direkter NTP-Test (rohe UDP/123-Anfrage) gegen mehrere grosse Server
(Cloudflare, Google, `pool.ntp.org`) blieb ganz ohne Antwort, obwohl
DNS-Auflösung und TCP/443 zu beliebigen Hosts einwandfrei funktionieren.
Selbst nach Freigabe von UDP/123 in der OPNsense-Firewall kam weiterhin
keine Antwort zurück – vermutlich blockt ein IPS/Suricata-Modul NTP
zusätzlich zur reinen Portregel (häufiger Default wegen NTP-Amplification-
Angriffen), das war zum Testzeitpunkt nicht abschliessend geklärt.

Eine falsche Systemzeit lässt die TLS-Zertifikatsprüfung fehlschlagen –
sowohl beim `docker pull` (Image-Build) als auch bei der MQTT-Verbindung
des Edge Gateway zum IoT Hub (`certificate has expired or is not yet
valid`). Workaround, unabhängig vom NTP-Ausgang: Die Uhr wird stattdessen
per HTTPS-Date-Header gesetzt (Port 443 ist ohnehin offen) – als
systemd-Service, der vor `docker.service` läuft:

```bash
sudo bash edge-gateway/scripts/setup-httpdate-fix.sh
```

Getestet inkl. vollständigem Reboot: Der Service läuft beim Hochfahren,
setzt die Uhr, und erst danach startet Docker den Container – keine
TLS-Fehler mehr, auch nicht nach Stromverlust/Neustart.

## Firewall: MQTT über HTTPS/Port 443 statt Port 8883

Der Azure IoT SDK verbindet standardmässig per MQTT auf **Port 8883**. In
Schul-/Firmennetzwerken ist dieser Port häufig durch die Firewall
blockiert, während **Port 443 (HTTPS)** offen ist. Das haben wir hier auch
so angetroffen: `docker compose logs` zeigte `ConnectionFailedError`, ein
Verbindungstest bestätigte es:

```bash
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/<hub-name>.azure-devices.net/8883' \
  && echo "8883 offen" || echo "8883 blockiert"
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/<hub-name>.azure-devices.net/443' \
  && echo "443 offen" || echo "443 blockiert"
```

Der Azure IoT SDK unterstützt für genau diesen Fall **MQTT über
WebSockets**, das über Port 443 statt 8883 läuft. In `main.py` genügt dafür
ein Flag beim Erstellen des Clients:

```python
client = IoTHubDeviceClient.create_from_connection_string(
    CONNECTION_STRING, websockets=True
)
```

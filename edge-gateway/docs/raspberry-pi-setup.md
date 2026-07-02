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

```bash
cd edge-gateway
bash scripts/setup-device.sh <iothub-name> rpi-edge-01 <resource-group>
```

Befüllt `.env` mit dem echten Device-Connection-String (nicht in Git
einchecken, siehe `.gitignore`).

## 5. Container bauen und starten

```bash
docker compose up -d --build
docker compose logs -f
```

## Warum kein `privileged: true` / keine GPIO-Bibliothek?

Auf dem Pi 4 war `/dev/gpiomem` + Adafruit Blinka üblich. Auf dem Pi 5
(RP1-Chip) bricht dieser Ansatz: Blinka braucht dort zusätzlich das Paket
`lgpio`, das auf dem Pi ohne vorgefertigtes Wheel aus dem Quellcode gebaut
werden muss (`swig` als Build-Abhängigkeit), und der Container bräuchte
`privileged: true` mit Zugriff auf `/dev/gpiomem0`. Das haben wir
ausprobiert (funktioniert, aber deutlich mehr Angriffsfläche und
Build-Zeit). Der Kernel-Treiber-Ansatz kommt ohne beides aus: reines
Python, unprivilegierter Container, nur Lesezugriff auf zwei sysfs-Werte.

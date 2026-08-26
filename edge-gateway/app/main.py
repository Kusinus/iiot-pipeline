"""
Edge Gateway – DHT22 Sensor → Azure IoT Hub
CAS Cloud Computing | Markus Abegglen | Deleproject AG

Liest Temperatur und Luftfeuchtigkeit vom DHT22 sowie die CPU-Temperatur
des Pi und sendet die Werte als JSON-Telemetrie via MQTT an den Azure IoT Hub.

Der DHT22 wird über den Kernel-Treiber ausgelesen (Device-Tree-Overlay
"dht11", unterstützt auch DHT22), nicht über eine Python-GPIO-Bibliothek.
Das Timing-kritische Protokoll übernimmt der Kernel, Python liest nur
noch die fertigen Werte aus /sys/bus/iio. Voraussetzung auf dem Pi:
  dtoverlay=dht11,gpiopin=4  in /boot/firmware/config.txt (+ Reboot)
  siehe scripts/setup-dht-overlay.sh
"""

import os
import json
import time
import logging
import signal
from datetime import datetime
from zoneinfo import ZoneInfo

from azure.iot.device import IoTHubDeviceClient, Message
from asyncua.sync import Client as OpcUaClient

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S"
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Konfiguration aus Umgebungsvariablen
# ---------------------------------------------------------------------------
CONNECTION_STRING = os.environ["IOTHUB_DEVICE_CONNECTION_STRING"]
DEVICE_ID         = os.environ.get("DEVICE_ID", "rpi-edge-01")
LOCATION          = os.environ.get("LOCATION", "luetschental")
SEND_INTERVAL_SEC = int(os.environ.get("SEND_INTERVAL_SEC", "15"))

# Zeitstempel werden bewusst in Schweizer Lokalzeit gesendet und so auch in
# der Datenbank gespeichert (kein UTC) – ZoneInfo berücksichtigt automatisch
# die Sommer-/Winterzeit-Umstellung (CEST/CET).
LOCAL_TZ = ZoneInfo("Europe/Zurich")

# DHT22 an GPIO4, ausgelesen über den Kernel-Treiber (Device-Tree-Overlay
# "dht11", unterstützt auch DHT22). Voraussetzung auf dem Pi:
#   dtoverlay=dht11,gpiopin=4   in /boot/firmware/config.txt (+ Reboot)
# siehe scripts/setup-dht-overlay.sh
DHT_TEMPERATURE_FILE = "/sys/bus/iio/devices/iio:device0/in_temp_input"
DHT_HUMIDITY_FILE    = "/sys/bus/iio/devices/iio:device0/in_humidityrelative_input"

CPU_THERMAL_ZONE = "/sys/class/thermal/thermal_zone0/temp"

# Zweite, heterogene Datenquelle (siehe Themenantrag): simulierte
# Industrieanlage (Motordrehzahl/Druck/Durchfluss) via OPC UA, läuft als
# eigener Container auf dem Pi (siehe opcua-simulator/).
OPCUA_ENDPOINT       = os.environ.get("OPCUA_ENDPOINT", "opc.tcp://opcua-simulator:4840/freeopcua/server/")
OPCUA_NAMESPACE_URI  = "http://iiot-pipeline.local/opcua-sim"

# ---------------------------------------------------------------------------
# Graceful Shutdown
# ---------------------------------------------------------------------------
running = True

def shutdown(signum, frame):
    global running
    log.info("Shutdown Signal empfangen, beende Gateway...")
    running = False

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

# ---------------------------------------------------------------------------
# CPU-Temperatur (SoC) auslesen
# ---------------------------------------------------------------------------
def read_cpu_temperature() -> float | None:
    """Liest die SoC-Temperatur des Raspberry Pi aus dem Thermal-Sysfs."""
    try:
        with open(CPU_THERMAL_ZONE) as f:
            return round(int(f.read().strip()) / 1000.0, 1)
    except (OSError, ValueError) as e:
        log.warning("CPU-Temperatur konnte nicht gelesen werden: %s", e)
        return None

# ---------------------------------------------------------------------------
# OPC-UA-Client (zweite Datenquelle: simulierte Industrieanlage)
# ---------------------------------------------------------------------------
class OpcUaReader:
    """
    Liest Motordrehzahl/Druck/Durchfluss vom OPC-UA-Simulator. Verbindung
    ist unabhängig vom DHT22 – ist der OPC-UA-Server (noch) nicht
    erreichbar, werden die DHT22-Werte trotzdem weiter gesendet, nur mit
    leeren OPC-UA-Feldern (None).
    """

    def __init__(self):
        self._client = None
        self._nodes = None
        self._connect()

    def _connect(self):
        try:
            client = OpcUaClient(url=OPCUA_ENDPOINT)
            client.connect()
            idx = client.get_namespace_index(OPCUA_NAMESPACE_URI)
            asset = client.nodes.objects.get_child(f"{idx}:IndustrialAsset")
            self._nodes = {
                "motorSpeed": asset.get_child(f"{idx}:MotorSpeed"),
                "pressure":   asset.get_child(f"{idx}:Pressure"),
                "flowRate":   asset.get_child(f"{idx}:FlowRate"),
            }
            self._client = client
            log.info("Verbunden mit OPC-UA-Server ✓")
        except Exception as e:
            log.warning("OPC-UA-Server nicht erreichbar (Simulator noch am Starten?): %s", e)
            self._client = None
            self._nodes = None

    def read(self) -> dict:
        if self._client is None:
            self._connect()
        if self._client is None:
            return {"motorSpeed": None, "pressure": None, "flowRate": None}

        try:
            return {name: node.read_value() for name, node in self._nodes.items()}
        except Exception as e:
            log.warning("OPC-UA-Lesefehler, verbinde neu: %s", e)
            self._client = None
            return {"motorSpeed": None, "pressure": None, "flowRate": None}

# ---------------------------------------------------------------------------
# Telemetrie-Nachricht aufbauen
# ---------------------------------------------------------------------------
def read_sensor() -> dict | None:
    """
    Liest DHT22 über den Kernel-Treiber aus. Gibt None zurück wenn die
    Lesung fehlschlägt (DHT22 hat ~10% Fehlerrate, das ist normal).
    """
    try:
        with open(DHT_TEMPERATURE_FILE) as f:
            temperature = int(f.read().strip()) / 1000.0
        with open(DHT_HUMIDITY_FILE) as f:
            humidity = int(f.read().strip()) / 1000.0

        return {
            "deviceId":       DEVICE_ID,
            "location":       LOCATION,
            # Naiver String ohne Offset (z.B. "2026-08-26T16:16:15.847686") –
            # die Uhrzeit selbst ist schon lokal, kein UTC-Suffix, damit die
            # DB den Wert unverändert als Lokalzeit übernimmt.
            "timestamp":      datetime.now(LOCAL_TZ).replace(tzinfo=None).isoformat(),
            "temperature":    round(temperature, 1),   # °C
            "humidity":       round(humidity, 1),       # %
            "sensorType":     "DHT22",
            "cpuTemperature": read_cpu_temperature()    # °C, SoC des Pi
        }

    except (OSError, ValueError) as e:
        # DHT22-typische Timing-Fehler — kein Problem, nächste Runde
        log.warning("DHT22 Lesefehler (normal): %s", e)
        return None

# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------
def main():
    log.info("Edge Gateway startet | Device: %s | Interval: %ss",
             DEVICE_ID, SEND_INTERVAL_SEC)

    opcua_reader = OpcUaReader()

    # MQTT über WebSockets (Port 443) statt Port 8883 – in vielen Netzwerken
    # (Schule, Firmen-WLAN) ist 8883 durch die Firewall blockiert, 443 nicht.
    client = IoTHubDeviceClient.create_from_connection_string(
        CONNECTION_STRING, websockets=True
    )
    client.connect()
    log.info("Verbunden mit Azure IoT Hub ✓")

    consecutive_errors = 0

    try:
        while running:
            payload = read_sensor()

            if payload:
                payload.update(opcua_reader.read())

                msg = Message(json.dumps(payload))
                msg.content_encoding = "utf-8"
                msg.content_type     = "application/json"

                # Eigenschaften für IoT Hub Routing (später nützlich)
                msg.custom_properties["sensorType"] = "DHT22"
                msg.custom_properties["location"]   = LOCATION

                client.send_message(msg)
                log.info("Gesendet: T=%.1f°C | H=%.1f%% | CPU=%s°C | Motor=%s U/min | Druck=%s bar | Fluss=%s l/min | %s",
                         payload["temperature"], payload["humidity"], payload["cpuTemperature"],
                         payload["motorSpeed"], payload["pressure"], payload["flowRate"], payload["timestamp"])
                consecutive_errors = 0
            else:
                consecutive_errors += 1
                if consecutive_errors >= 5:
                    log.error("5 aufeinanderfolgende Fehler – prüfe Verkabelung!")
                    consecutive_errors = 0

            time.sleep(SEND_INTERVAL_SEC)

    finally:
        log.info("Trenne Verbindung zum IoT Hub...")
        client.disconnect()
        log.info("Edge Gateway beendet.")

if __name__ == "__main__":
    main()

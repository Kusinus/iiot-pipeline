"""
load_test.py – Lasttest gemaess Kapitel 5 (Methodik der Evaluation)
CAS Cloud Computing | Markus Abegglen | Deleproject AG

Simuliert N virtuelle Sensoren ueber die bestehende Edge-Gateway-
Geraete-Identitaet (eine MQTT-Verbindung zum Azure IoT Hub, wie bei einem
Gateway, das mehrere Sensoren aggregiert - das Feld "deviceId" im JSON-
Payload ist von der IoT-Hub-Geraeteauthentifizierung entkoppelt und wird
downstream (SQL) als eigenstaendige Sensor-Kennung verwendet).

Nicht Teil der Produktions-Codebasis (edge-gateway/) - dient ausschliesslich
der Durchfuehrung des in Kapitel 5 vorgeschlagenen Testplans (1/5/10/20
simulierte Geraete, 15s-Intervall, 10-Minuten-Fenster) und schreibt nichts
an der bestehenden Architektur um.

Verwendung:
    cd edge-gateway && cp env.example .env   # falls noch nicht geschehen,
                                              # echten Connection String eintragen
    cd ..
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r edge-gateway/app/requirements.txt -r edge-gateway/opcua-simulator/requirements.txt
    python3 edge-gateway/opcua-simulator/server.py &          # lokal auf Port 4840
    NUM_VIRTUAL_SENSORS=5 DURATION_SEC=600 python3 scripts/load_test.py
"""

import os
import sys
import json
import time
import random
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from azure.iot.device import IoTHubDeviceClient, Message
from asyncua.sync import Client as OpcUaClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# .env manuell einlesen (kein python-dotenv im requirements.txt der App)
# ---------------------------------------------------------------------------
def load_env_file(path):
    if not os.path.isfile(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

load_env_file(os.path.join(os.path.dirname(__file__), "..", "edge-gateway", ".env"))

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
try:
    CONNECTION_STRING = os.environ["IOTHUB_DEVICE_CONNECTION_STRING"]
except KeyError:
    sys.exit("FEHLER: IOTHUB_DEVICE_CONNECTION_STRING fehlt (edge-gateway/.env anlegen, siehe env.example)")

DEVICE_ID          = os.environ.get("DEVICE_ID", "rpi-edge-01")
LOCATION           = os.environ.get("LOCATION", "luetschental")
SEND_INTERVAL_SEC  = int(os.environ.get("SEND_INTERVAL_SEC", "15"))
NUM_VIRTUAL_SENSORS = int(os.environ.get("NUM_VIRTUAL_SENSORS", "1"))
DURATION_SEC        = int(os.environ.get("DURATION_SEC", "600"))
OPCUA_ENDPOINT      = os.environ.get("OPCUA_ENDPOINT", "opc.tcp://localhost:4840/freeopcua/server/")
OPCUA_NAMESPACE_URI = "http://iiot-pipeline.local/opcua-sim"

LOCAL_TZ = ZoneInfo("Europe/Zurich")


class OpcUaReader:
    """Wie edge-gateway/app/main.py: eine gemeinsame Verbindung fuer alle
    virtuellen Sensoren (eine reale Anlage liefert dieselben Werte an alle)."""

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
            log.info("Verbunden mit OPC-UA-Simulator ✓")
        except Exception as e:
            log.warning("OPC-UA-Simulator nicht erreichbar: %s", e)
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


class VirtualSensor:
    """Erzeugt plausible DHT22-aehnliche Werte per Random Walk (kein
    Sprungrauschen wie bei echtem DHT22, da hier nur die Pipeline-Last
    interessiert, nicht die Sensorcharakteristik)."""

    def __init__(self, sensor_id: str):
        self.sensor_id = sensor_id
        self.temperature = round(random.uniform(19.0, 24.0), 1)
        self.humidity = round(random.uniform(35.0, 55.0), 1)

    def read(self) -> dict:
        self.temperature = round(min(max(self.temperature + random.uniform(-0.3, 0.3), 15), 30), 1)
        self.humidity = round(min(max(self.humidity + random.uniform(-1.0, 1.0), 20), 70), 1)
        return {"temperature": self.temperature, "humidity": self.humidity}


def main():
    log.info("Lasttest startet | %s virtuelle Sensoren | Intervall %ss | Dauer %ss",
              NUM_VIRTUAL_SENSORS, SEND_INTERVAL_SEC, DURATION_SEC)

    sensors = [VirtualSensor(f"{DEVICE_ID}-sim{n:02d}") for n in range(1, NUM_VIRTUAL_SENSORS + 1)]
    opcua_reader = OpcUaReader()

    client = IoTHubDeviceClient.create_from_connection_string(CONNECTION_STRING, websockets=True)
    client.connect()
    log.info("Verbunden mit Azure IoT Hub ✓")

    start = time.monotonic()
    start_wall = datetime.now(LOCAL_TZ).replace(tzinfo=None)
    sent_total = 0
    errors_total = 0

    try:
        while time.monotonic() - start < DURATION_SEC:
            tick_start = time.monotonic()
            opcua_values = opcua_reader.read()
            ts = datetime.now(LOCAL_TZ).replace(tzinfo=None).isoformat()

            for sensor in sensors:
                payload = {
                    "deviceId": sensor.sensor_id,
                    "location": LOCATION,
                    "timestamp": ts,
                    "sensorType": "DHT22-SIM",
                    "cpuTemperature": None,
                    **sensor.read(),
                    **opcua_values,
                }
                try:
                    msg = Message(json.dumps(payload))
                    msg.content_encoding = "utf-8"
                    msg.content_type = "application/json"
                    msg.custom_properties["sensorType"] = "DHT22-SIM"
                    msg.custom_properties["location"] = LOCATION
                    client.send_message(msg)
                    sent_total += 1
                except Exception as e:
                    errors_total += 1
                    log.warning("Sendefehler bei %s: %s", sensor.sensor_id, e)

            log.info("Tick: %d Nachrichten gesendet (kumuliert %d, Fehler %d)",
                      len(sensors), sent_total, errors_total)

            elapsed_tick = time.monotonic() - tick_start
            time.sleep(max(0.0, SEND_INTERVAL_SEC - elapsed_tick))
    finally:
        client.disconnect()
        end_wall = datetime.now(LOCAL_TZ).replace(tzinfo=None)
        log.info("=" * 70)
        log.info("Lasttest beendet | Geraete=%d | Gesendet=%d | Fehler=%d",
                  NUM_VIRTUAL_SENSORS, sent_total, errors_total)
        log.info("Fenster (lokale Zeit, fuer SQL-Auswertung): %s  bis  %s",
                  start_wall.isoformat(), end_wall.isoformat())
        log.info("=" * 70)


if __name__ == "__main__":
    main()

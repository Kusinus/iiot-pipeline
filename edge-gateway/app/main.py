"""
Edge Gateway – DHT22 Sensor → Azure IoT Hub
CAS Cloud Computing | Markus Abegglen | Deleproject AG

Liest Temperatur und Luftfeuchtigkeit vom DHT22 und sendet
die Werte als JSON-Telemetrie via MQTT an den Azure IoT Hub.
"""

import os
import json
import time
import logging
import signal
import sys
from datetime import datetime, timezone

import board
import adafruit_dht
from azure.iot.device import IoTHubDeviceClient, Message

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
LOCATION          = os.environ.get("LOCATION", "uetendorf")
SEND_INTERVAL_SEC = int(os.environ.get("SEND_INTERVAL_SEC", "10"))
DHT_GPIO_PIN      = os.environ.get("DHT_GPIO_PIN", "D4")   # GPIO4 = Pin 7

# ---------------------------------------------------------------------------
# DHT22 Sensor initialisieren
# ---------------------------------------------------------------------------
def get_dht_pin(pin_name: str):
    """Gibt das board.Pin Objekt für den konfigurierten GPIO-Pin zurück."""
    try:
        return getattr(board, pin_name)
    except AttributeError:
        log.error("Ungültiger GPIO-Pin: %s. Verwende D4.", pin_name)
        return board.D4

dht_sensor = adafruit_dht.DHT22(get_dht_pin(DHT_GPIO_PIN), use_pulseio=False)

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
# Telemetrie-Nachricht aufbauen
# ---------------------------------------------------------------------------
def read_sensor() -> dict | None:
    """
    Liest DHT22 aus. Gibt None zurück wenn Lesung fehlschlägt
    (DHT22 hat ~10% Fehlerrate, das ist normal).
    """
    try:
        temperature = dht_sensor.temperature
        humidity    = dht_sensor.humidity

        if temperature is None or humidity is None:
            log.warning("DHT22: Lesung leer, wird übersprungen.")
            return None

        return {
            "deviceId":    DEVICE_ID,
            "location":    LOCATION,
            "timestamp":   datetime.now(timezone.utc).isoformat(),
            "temperature": round(temperature, 1),   # °C
            "humidity":    round(humidity, 1),       # %
            "sensorType":  "DHT22"
        }

    except RuntimeError as e:
        # DHT22-typische Timing-Fehler — kein Problem, nächste Runde
        log.warning("DHT22 RuntimeError (normal): %s", e)
        return None

# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------
def main():
    log.info("Edge Gateway startet | Device: %s | Interval: %ss | Pin: %s",
             DEVICE_ID, SEND_INTERVAL_SEC, DHT_GPIO_PIN)

    client = IoTHubDeviceClient.create_from_connection_string(CONNECTION_STRING)
    client.connect()
    log.info("Verbunden mit Azure IoT Hub ✓")

    consecutive_errors = 0

    try:
        while running:
            payload = read_sensor()

            if payload:
                msg = Message(json.dumps(payload))
                msg.content_encoding = "utf-8"
                msg.content_type     = "application/json"

                # Eigenschaften für IoT Hub Routing (später nützlich)
                msg.custom_properties["sensorType"] = "DHT22"
                msg.custom_properties["location"]   = LOCATION

                client.send_message(msg)
                log.info("Gesendet: T=%.1f°C | H=%.1f%% | %s",
                         payload["temperature"], payload["humidity"],
                         payload["timestamp"])
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
        dht_sensor.exit()
        log.info("Edge Gateway beendet.")

if __name__ == "__main__":
    main()

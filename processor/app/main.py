"""
Processor – Azure IoT Hub (Event Hub) → Azure SQL Serverless
CAS Cloud Computing | Markus Abegglen | Deleproject AG

Liest die Sensor-Telemetrie aus dem eingebetteten Event Hub des IoT Hub
(Consumer Group "processor") und schreibt jede Nachricht als Zeile in die
Azure-SQL-Tabelle dbo.SensorReadings (siehe database/schema.sql).
"""

import os
import json
import logging
import signal
import threading
from decimal import Decimal, InvalidOperation

import pytds
from azure.eventhub import EventHubConsumerClient

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S"
)
log = logging.getLogger(__name__)
logging.getLogger("azure").setLevel(logging.WARNING)  # SDK-eigenes Logging dämpfen

# ---------------------------------------------------------------------------
# Konfiguration aus Umgebungsvariablen
# ---------------------------------------------------------------------------
EVENTHUB_CONNECTION_STRING = os.environ["EVENTHUB_CONNECTION_STRING"]
EVENTHUB_NAME              = os.environ["EVENTHUB_NAME"]
CONSUMER_GROUP             = os.environ.get("CONSUMER_GROUP", "processor")

SQL_SERVER   = os.environ["SQL_SERVER"]
SQL_DATABASE = os.environ["SQL_DATABASE"]
SQL_USER     = os.environ["SQL_USER"]
SQL_PASSWORD = os.environ["SQL_PASSWORD"]

# Debian-Basisimage (wie python:3.11-slim) – gleicher Pfad wie auf Fedora-Dev-Laptop.
SQL_CAFILE = os.environ.get("SQL_CAFILE", "/etc/ssl/certs/ca-certificates.crt")

INSERT_SQL = """
    INSERT INTO dbo.SensorReadings
        (DeviceId, Location, ReadingTimestamp, Temperature, Humidity, SensorType, CpuTemperature,
         MotorSpeed, Pressure, FlowRate)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
"""

# ---------------------------------------------------------------------------
# SQL-Verbindung
# ---------------------------------------------------------------------------
def connect_sql():
    # validate_host=False: umgeht einen Kompatibilitätsbug in python-tds 1.17.1
    # mit neueren pyOpenSSL-Versionen (siehe scripts/init-database.py).
    return pytds.connect(
        server=SQL_SERVER, database=SQL_DATABASE,
        user=SQL_USER, password=SQL_PASSWORD,
        cafile=SQL_CAFILE, validate_host=False,
        autocommit=True,
    )

def to_decimal(value) -> Decimal | None:
    if value is None:
        return None
    try:
        return Decimal(str(value))
    except InvalidOperation:
        return None

# ---------------------------------------------------------------------------
# Event-Handler
# ---------------------------------------------------------------------------
class Processor:
    def __init__(self):
        self.conn = connect_sql()
        log.info("Verbunden mit Azure SQL ✓")

    def insert(self, payload: dict):
        row = (
            payload.get("deviceId"),
            payload.get("location"),
            payload.get("timestamp"),
            to_decimal(payload.get("temperature")),
            to_decimal(payload.get("humidity")),
            payload.get("sensorType"),
            to_decimal(payload.get("cpuTemperature")),
            to_decimal(payload.get("motorSpeed")),
            to_decimal(payload.get("pressure")),
            to_decimal(payload.get("flowRate")),
        )
        try:
            with self.conn.cursor() as cur:
                cur.execute(INSERT_SQL, row)
        except pytds.IntegrityError:
            # Verletzt die Unique-Constraint (DeviceId, ReadingTimestamp):
            # Nachricht wurde bereits verarbeitet (siehe Kommentar in
            # database/schema.sql zum fehlenden Checkpoint-Store) – Insert
            # ist damit idempotent, kein Fehler.
            log.info("Bereits vorhanden, übersprungen (Duplikat)")
        except pytds.Error as e:
            log.warning("SQL-Fehler, verbinde neu: %s", e)
            self.conn = connect_sql()
            with self.conn.cursor() as cur:
                cur.execute(INSERT_SQL, row)

    def on_event(self, partition_context, event):
        if event is None:
            return
        try:
            payload = json.loads(event.body_as_str(encoding="utf-8"))
            self.insert(payload)
            log.info("Gespeichert: %s | T=%s°C | H=%s%% | Motor=%s U/min | %s",
                      payload.get("deviceId"), payload.get("temperature"),
                      payload.get("humidity"), payload.get("motorSpeed"), payload.get("timestamp"))
        except (json.JSONDecodeError, KeyError) as e:
            log.warning("Ungültige Nachricht übersprungen: %s", e)
        partition_context.update_checkpoint(event)

# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------
def main():
    log.info("Processor startet | Event Hub: %s | Consumer Group: %s",
              EVENTHUB_NAME, CONSUMER_GROUP)

    processor = Processor()
    client = EventHubConsumerClient.from_connection_string(
        EVENTHUB_CONNECTION_STRING,
        consumer_group=CONSUMER_GROUP,
        eventhub_name=EVENTHUB_NAME,
    )

    def shutdown(signum, frame):
        log.info("Shutdown-Signal empfangen, beende Processor...")
        # client.close() muss aus einem anderen Thread als dem blockierenden
        # receive()-Aufruf kommen, sonst reagiert der Prozess erst nach dem
        # SIGKILL-Timeout (z.B. bei Container-Apps-Neustarts/Skalierung).
        threading.Thread(target=client.close, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    with client:
        # starting_position="-1": von Beginn der Retention lesen, damit beim
        # ersten Start kein bereits eingetroffenes Telemetrie verloren geht.
        client.receive(on_event=processor.on_event, starting_position="-1")

if __name__ == "__main__":
    main()

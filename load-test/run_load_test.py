"""
Lasttest – simuliert N virtuelle Geräte, die parallel Telemetrie an den
Azure IoT Hub senden, um Last jenseits des einen physischen DHT22-Sensors
zu erzeugen (siehe assets/Fragekatalog_Evaluation_Semesterarbeit.md).

Läuft auf dem Raspberry Pi, damit die Last denselben Netzwerkpfad
(MQTT über WebSockets, Port 443) nimmt wie der reale Edge-Gateway-Container.

Verwendung:
    python3 run_load_test.py --devices-file devices.json --num-devices 10 \
        --rate 1 --duration 15 --results-csv results.csv
"""

import argparse
import asyncio
import json
import random
import statistics
import time
from datetime import datetime, timezone
from pathlib import Path

from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message


def build_payload(device_id: str, seq: int) -> dict:
    return {
        "deviceId": device_id,
        "location": "loadtest",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "temperature": round(random.uniform(15, 30), 1),
        "humidity": round(random.uniform(30, 70), 1),
        "sensorType": "LOADTEST",
        "cpuTemperature": round(random.uniform(40, 60), 1),
        "motorSpeed": round(random.uniform(1000, 3000), 1),
        "pressure": round(random.uniform(1, 10), 2),
        "flowRate": round(random.uniform(5, 50), 1),
        "seq": seq,
    }


async def run_device(device_id: str, conn_str: str, rate: float, duration: float,
                      latencies: list, failures: list):
    client = IoTHubDeviceClient.create_from_connection_string(conn_str, websockets=True)
    interval = 1.0 / rate
    seq = 0
    try:
        await asyncio.wait_for(client.connect(), timeout=15.0)
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            payload = build_payload(device_id, seq)
            msg = Message(json.dumps(payload))
            msg.content_encoding = "utf-8"
            msg.content_type = "application/json"

            t0 = time.monotonic()
            try:
                await asyncio.wait_for(client.send_message(msg), timeout=5.0)
                latencies.append((time.monotonic() - t0) * 1000)
            except Exception as e:
                failures.append(f"{device_id}: {e!r}")
            seq += 1
            await asyncio.sleep(interval)
    except Exception as e:
        failures.append(f"{device_id} (fatal): {e!r}")
    finally:
        try:
            await asyncio.wait_for(client.shutdown(), timeout=5.0)
        except Exception:
            pass


async def main_async(args):
    devices = json.loads(Path(args.devices_file).read_text())[:args.num_devices]
    if len(devices) < args.num_devices:
        raise SystemExit(
            f"devices.json enthält nur {len(devices)} Geräte, "
            f"{args.num_devices} angefordert – provision_devices.sh mit höherer Anzahl neu laufen lassen."
        )

    latencies: list = []
    failures: list = []

    print(f"Starte Lasttest: {args.num_devices} Geräte x {args.rate} msg/s "
          f"über {args.duration}s (Ziel: {args.num_devices * args.rate:.1f} msg/s gesamt)")

    t_start = time.monotonic()
    await asyncio.gather(*[
        run_device(d["deviceId"], d["connectionString"], args.rate, args.duration, latencies, failures)
        for d in devices
    ])
    elapsed = time.monotonic() - t_start

    sent = len(latencies)
    failed = len(failures)
    total = sent + failed
    throughput = sent / elapsed if elapsed > 0 else 0
    avg_lat = statistics.mean(latencies) if latencies else 0
    p95_lat = statistics.quantiles(latencies, n=20)[18] if len(latencies) >= 20 else max(latencies, default=0)
    max_lat = max(latencies, default=0)

    print(f"  Gesendet: {sent}/{total} | Fehler: {failed} | "
          f"Ist-Durchsatz: {throughput:.1f} msg/s | "
          f"Latenz avg={avg_lat:.0f}ms p95={p95_lat:.0f}ms max={max_lat:.0f}ms")
    if failures:
        print(f"  Erste Fehler: {failures[:3]}")

    results_path = Path(args.results_csv)
    is_new = not results_path.exists()
    with results_path.open("a") as f:
        if is_new:
            f.write("timestamp,num_devices,rate_per_device,duration_s,target_msg_s,"
                     "sent,failed,actual_msg_s,avg_latency_ms,p95_latency_ms,max_latency_ms\n")
        f.write(f"{datetime.now(timezone.utc).isoformat()},{args.num_devices},{args.rate},"
                f"{args.duration},{args.num_devices * args.rate:.1f},{sent},{failed},"
                f"{throughput:.2f},{avg_lat:.1f},{p95_lat:.1f},{max_lat:.1f}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--devices-file", default="devices.json")
    parser.add_argument("--num-devices", type=int, required=True)
    parser.add_argument("--rate", type=float, default=1.0, help="Nachrichten/s pro Gerät")
    parser.add_argument("--duration", type=float, default=15.0, help="Testdauer in Sekunden")
    parser.add_argument("--results-csv", default="results.csv")
    asyncio.run(main_async(parser.parse_args()))

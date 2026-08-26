"""
OPC-UA-Simulationsserver – simuliert eine Industrieanlage (Motor/Pumpe)
CAS Cloud Computing | Markus Abegglen | Deleproject AG

Da am Standort Luetschental keine echte OPC-UA-fähige Anlage angeschlossen
ist, erzeugt dieser Server plausible, leicht schwankende Werte für
Motordrehzahl, Druck und Durchfluss – als zweite, heterogene Datenquelle
neben dem DHT22-Sensor (siehe Themenantrag: "heterogene Datenquellen").
"""

import asyncio
import logging
import random
import signal

from asyncua import Server

logging.basicConfig(level=logging.WARNING)

ENDPOINT = "opc.tcp://0.0.0.0:4840/freeopcua/server/"
NAMESPACE_URI = "http://iiot-pipeline.local/opcua-sim"

async def main():
    server = Server()
    await server.init()
    server.set_endpoint(ENDPOINT)
    server.set_server_name("IIoT Pipeline OPC-UA Simulator")

    idx = await server.register_namespace(NAMESPACE_URI)
    asset = await server.nodes.objects.add_object(idx, "IndustrialAsset")

    motor_speed = await asset.add_variable(idx, "MotorSpeed", 1450.0)  # U/min
    pressure    = await asset.add_variable(idx, "Pressure", 4.2)       # bar
    flow_rate   = await asset.add_variable(idx, "FlowRate", 120.0)     # l/min
    for var in (motor_speed, pressure, flow_rate):
        await var.set_writable()

    # SIGTERM/SIGINT per Event statt Exception behandeln, damit der Server
    # sofort sauber beendet statt erst nach dem Docker-SIGKILL-Timeout.
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop_event.set)

    async with server:
        print(f"OPC-UA-Simulator läuft auf {ENDPOINT}")
        while not stop_event.is_set():
            await motor_speed.write_value(round(1450.0 + random.uniform(-15, 15), 1))
            await pressure.write_value(round(4.2 + random.uniform(-0.3, 0.3), 2))
            await flow_rate.write_value(round(120.0 + random.uniform(-5, 5), 1))
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=2)
            except asyncio.TimeoutError:
                pass
    print("OPC-UA-Simulator beendet.")

if __name__ == "__main__":
    asyncio.run(main())

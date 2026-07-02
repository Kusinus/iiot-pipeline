# =============================================================================
# Dockerfile – IIoT Edge Gateway (DHT22 → Azure IoT Hub)
# Basis: python:3.11-slim (ARM64 kompatibel für Raspberry Pi 5)
#
# Der DHT22 wird über den Kernel-Treiber gelesen (siehe main.py), daher
# braucht der Container keine GPIO-Systempakete – nur reines Python.
# =============================================================================

FROM python:3.11-slim

WORKDIR /app

# Dependencies zuerst (Docker Layer-Cache nutzen)
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Applikationscode
COPY app/main.py .

# Kein Root-User im Container
RUN useradd -m edgeuser
USER edgeuser

CMD ["python", "-u", "main.py"]

# =============================================================================
# Dockerfile – IIoT Edge Gateway (DHT22 → Azure IoT Hub)
# Basis: python:3.11-slim (ARM64 kompatibel für Raspberry Pi 4)
# =============================================================================

FROM python:3.11-slim

# Systempakete für DHT22 / GPIO Zugriff
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        libgpiod2 \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*

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

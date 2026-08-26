# =============================================================================
# Dockerfile – IIoT Processor (IoT Hub Event Hub → Azure SQL)
# Läuft später in Azure Container Apps.
# =============================================================================

FROM python:3.11-slim

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/main.py .

RUN useradd -m processoruser
USER processoruser

CMD ["python", "-u", "main.py"]

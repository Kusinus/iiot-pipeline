# =============================================================================
# Dockerfile – OPC-UA-Simulationsserver (simulierte Industrieanlage)
# =============================================================================

FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

RUN useradd -m opcuauser
USER opcuauser

EXPOSE 4840

CMD ["python", "-u", "server.py"]

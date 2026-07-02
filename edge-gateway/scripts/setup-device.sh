#!/usr/bin/env bash
# =============================================================================
# setup-device.sh – Gerät im IoT Hub registrieren und .env befüllen
# Ausführen (auf dem Pi oder lokal mit Azure CLI):
#   bash scripts/setup-device.sh
# =============================================================================

set -euo pipefail

IOTHUB_NAME="${1:-}"
DEVICE_ID="${2:-rpi-edge-01}"
RESOURCE_GROUP="${3:-rg-iiot-pipeline-dev-swn-001}"

if [[ -z "$IOTHUB_NAME" ]]; then
  echo "Verwendung: bash setup-device.sh <iothub-name> [device-id] [resource-group]"
  echo "Beispiel:   bash setup-device.sh iot-pipeline-dev-swn-abc123 rpi-edge-01 rg-iiot-pipeline-dev-swn-001"
  exit 1
fi

echo "🔧 Registriere Gerät '$DEVICE_ID' im IoT Hub '$IOTHUB_NAME'..."

# Gerät erstellen (falls noch nicht vorhanden)
az iot hub device-identity create \
  --hub-name "$IOTHUB_NAME" \
  --device-id "$DEVICE_ID" \
  --output table 2>/dev/null || echo "   (Gerät existiert bereits)"

# Connection String abrufen
echo ""
echo "🔑 Hole Connection String..."
CONN_STR=$(az iot hub device-identity connection-string show \
  --hub-name "$IOTHUB_NAME" \
  --device-id "$DEVICE_ID" \
  --query connectionString \
  --output tsv)

# .env Datei im edge-gateway Ordner befüllen
ENV_FILE="$(dirname "$0")/../.env"
cp "$(dirname "$0")/../env.example" "$ENV_FILE"
sed -i "s|IOTHUB_DEVICE_CONNECTION_STRING=.*|IOTHUB_DEVICE_CONNECTION_STRING=${CONN_STR}|" "$ENV_FILE"
sed -i "s|DEVICE_ID=.*|DEVICE_ID=${DEVICE_ID}|" "$ENV_FILE"

echo ""
echo "✅ .env Datei befüllt: $ENV_FILE"
echo ""
echo "Nächste Schritte auf dem Raspberry Pi:"
echo "  1. edge-gateway/ Ordner auf den Pi kopieren (z.B. via scp oder git pull)"
echo "  2. cd edge-gateway"
echo "  3. docker compose up -d"
echo "  4. docker compose logs -f"

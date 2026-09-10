#!/usr/bin/env bash
# Löscht alle in devices.json aufgeführten Lasttest-Geräte wieder aus dem IoT Hub.
set -euo pipefail

HUB="iot-pipeline-dev-swn-ghxzap"
RG="rg-iiot-pipeline-dev-swn-001"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_FILE="$DIR/devices.json"

jq -r '.[].deviceId' "$DEVICES_FILE" | while read -r DEVICE_ID; do
  az iot hub device-identity delete -n "$HUB" -g "$RG" -d "$DEVICE_ID" --output none
  echo "  Gelöscht: $DEVICE_ID"
done
echo "Fertig: alle Lasttest-Geräte entfernt."

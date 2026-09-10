#!/usr/bin/env bash
# Legt N temporäre Lasttest-Geräte (loadtest-01 .. loadtest-NN) im IoT Hub an
# und schreibt ihre Connection Strings nach devices.json.
# Verwendung: ./provision_devices.sh [ANZAHL]
set -euo pipefail

HUB="iot-pipeline-dev-swn-ghxzap"
RG="rg-iiot-pipeline-dev-swn-001"
COUNT="${1:-50}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/devices.json"

HOSTNAME=$(az iot hub show -n "$HUB" -g "$RG" --query properties.hostName -o tsv)

echo "[]" > "$OUT.tmp"
for i in $(seq -w 1 "$COUNT"); do
  DEVICE_ID="loadtest-$i"
  KEY=$(az iot hub device-identity create -n "$HUB" -g "$RG" -d "$DEVICE_ID" \
        --query authentication.symmetricKey.primaryKey -o tsv 2>/dev/null || \
        az iot hub device-identity connection-string show -n "$HUB" -g "$RG" -d "$DEVICE_ID" \
        --query connectionString -o tsv | sed -n 's/.*SharedAccessKey=//p')
  CONN="HostName=$HOSTNAME;DeviceId=$DEVICE_ID;SharedAccessKey=$KEY"
  jq --arg id "$DEVICE_ID" --arg conn "$CONN" '. + [{"deviceId": $id, "connectionString": $conn}]' \
     "$OUT.tmp" > "$OUT.tmp2" && mv "$OUT.tmp2" "$OUT.tmp"
  echo "  Provisioniert: $DEVICE_ID"
done
mv "$OUT.tmp" "$OUT"
echo "Fertig: $COUNT Geräte in $OUT"

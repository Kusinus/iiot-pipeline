#!/usr/bin/env bash
# =============================================================================
# setup-dht-overlay.sh – DHT22 Kernel-Treiber auf dem Pi aktivieren
# Einmalig auf dem Raspberry Pi ausführen (danach Neustart nötig):
#   bash scripts/setup-dht-overlay.sh [gpio-pin]
# =============================================================================

set -euo pipefail

GPIO_PIN="${1:-4}"
CONFIG_FILE="/boot/firmware/config.txt"
OVERLAY_LINE="dtoverlay=dht11,gpiopin=${GPIO_PIN}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config-Datei nicht gefunden: $CONFIG_FILE"
  exit 1
fi

if grep -qF "$OVERLAY_LINE" "$CONFIG_FILE"; then
  echo "✅ Overlay bereits gesetzt: $OVERLAY_LINE"
else
  echo "🔧 Füge Overlay hinzu: $OVERLAY_LINE"
  echo "$OVERLAY_LINE" | sudo tee -a "$CONFIG_FILE" > /dev/null
  echo ""
  echo "⚠️  Neustart nötig, damit der DHT22 an GPIO${GPIO_PIN} ausgelesen werden kann:"
  echo "   sudo reboot"
fi

#!/usr/bin/env bash
# =============================================================================
# bootstrap-pi.sh – Einmaliges System-Setup auf einem frisch geflashten Pi
# Idempotent: kann gefahrlos mehrfach ausgeführt werden.
# Ausführen auf dem Raspberry Pi:
#   bash scripts/bootstrap-pi.sh [dht-gpio-pin]
# =============================================================================

set -euo pipefail

DHT_GPIO_PIN="${1:-4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEEDS_REBOOT=false

echo "🔧 DHT22 Kernel-Treiber (GPIO${DHT_GPIO_PIN})..."
OVERLAY_OUTPUT="$(bash "$SCRIPT_DIR/setup-dht-overlay.sh" "$DHT_GPIO_PIN")"
echo "$OVERLAY_OUTPUT"
if grep -q "Neustart nötig" <<< "$OVERLAY_OUTPUT"; then
  NEEDS_REBOOT=true
fi

echo ""
echo "🔧 Docker Engine..."
if command -v docker &> /dev/null; then
  echo "✅ Docker bereits installiert ($(docker --version))"
else
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
  rm /tmp/get-docker.sh
fi

if id -nG "$USER" | grep -qw docker; then
  echo "✅ $USER ist bereits in der docker-Gruppe"
else
  echo "🔧 Füge $USER zur docker-Gruppe hinzu..."
  sudo usermod -aG docker "$USER"
  NEEDS_REBOOT=true
fi

echo ""
if [[ "$NEEDS_REBOOT" == true ]]; then
  echo "⚠️  Neustart nötig, damit Overlay/Gruppenrechte aktiv werden: sudo reboot"
else
  echo "✅ System bereit. Weiter mit: scripts/setup-device.sh"
fi

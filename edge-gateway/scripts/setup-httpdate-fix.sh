#!/usr/bin/env bash
# =============================================================================
# setup-httpdate-fix.sh – Systemuhr per HTTPS-Zeitstempel setzen
# Einmalig auf dem Raspberry Pi ausführen:
#   sudo bash scripts/setup-httpdate-fix.sh
#
# Hintergrund: Der Pi hat keine gepufferte RTC (RTC-Zeit fällt bei
# Stromverlust auf 1970 zurück) und NTP (UDP/123) wird im Testnetz nicht
# zuverlässig beantwortet. Ohne korrekte Zeit schlägt die TLS-Zertifikats-
# prüfung beim Docker-Pull und bei der MQTT-Verbindung zum IoT Hub fehl
# (z.B. "certificate has expired or is not yet valid"). Dieser Fix holt die
# Uhrzeit stattdessen aus dem HTTP-Date-Header einer HTTPS-Antwort (Port 443
# ist bereits für IoT Hub / Docker Hub offen) und setzt sie vor dem Start
# von Docker – unabhängig davon, ob NTP später funktioniert oder nicht.
# =============================================================================

set -euo pipefail

SCRIPT_PATH="/usr/local/bin/httpdate-fix.sh"
SERVICE_PATH="/etc/systemd/system/httpdate-fix.service"
TIME_SOURCE_URL="https://www.microsoft.com"

echo "🔧 Installiere ${SCRIPT_PATH}..."
sudo tee "$SCRIPT_PATH" > /dev/null <<EOF
#!/bin/bash
# Setzt die Systemuhr per HTTPS-Date-Header (Workaround: NTP/UDP-123 im
# Testnetz unzuverlässig). Wird vor docker.service ausgeführt.
set -euo pipefail

for i in \$(seq 1 10); do
  HTTP_DATE=\$(curl -fsSI --max-time 5 "${TIME_SOURCE_URL}" 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
  if [[ -n "\$HTTP_DATE" ]]; then
    date -s "\$HTTP_DATE"
    echo "Systemuhr gesetzt via HTTPS-Header: \$HTTP_DATE"
    exit 0
  fi
  sleep 3
done

echo "Konnte Systemuhr nicht per HTTPS setzen (Netzwerk nicht bereit?)" >&2
exit 1
EOF
sudo chmod +x "$SCRIPT_PATH"

echo "🔧 Installiere ${SERVICE_PATH}..."
sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Systemuhr per HTTPS-Zeitstempel setzen (Workaround: NTP/UDP-123 im Testnetz unzuverlaessig)
Wants=network-online.target
After=network-online.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "🔧 Aktiviere Service..."
sudo systemctl daemon-reload
sudo systemctl enable --now httpdate-fix.service

echo ""
echo "✅ Fertig. Status:"
sudo systemctl status httpdate-fix.service --no-pager

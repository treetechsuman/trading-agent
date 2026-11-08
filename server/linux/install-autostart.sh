#!/bin/sh
# Run as trader with sudo (asks for trader's password once):
#   sh ~/install-autostart.sh
# Installs mt5.service + the limited sudo rule, waits for MT5 to be closed
# (File > Exit), then starts MT5 through systemd.
set -e
sudo install -m 644 /home/trader/mt5.service /etc/systemd/system/mt5.service
sudo install -m 440 /home/trader/sudoers-trader-mt5 /etc/sudoers.d/trader-mt5
sudo visudo -c -q
sudo systemctl daemon-reload
echo "Waiting for MT5 to be closed (File > Exit in MT5)..."
while pgrep -f terminal64.exe >/dev/null; do sleep 2; done
sudo systemctl enable --now mt5
sleep 5
systemctl is-active mt5 && echo MT5_SERVICE_OK

#!/bin/sh
# Stop MT5 cleanly on the Linux server: ask it to close, WAIT until it has
# really exited (it saves the chart profile on the way out), then stop the
# systemd service before its 20 s auto-restart kicks in.
#
# Do not call `systemctl stop mt5` straight after taskkill: on 2026-11-08 that
# killed MT5 mid-save and left chart01.chr 0 bytes (gotobi did not load).
# Start again with: sudo -n systemctl start mt5
export DISPLAY=:1 WINEPREFIX=/home/trader/.mt5 WINEDEBUG=-all
running() { pgrep -f 'terminal6[4]\.exe' >/dev/null; }   # [4] stops pgrep matching itself

if ! running; then
    sudo -n systemctl stop mt5
    echo "MT5 was not running; service stopped"
    exit 0
fi
wine taskkill /im terminal64.exe >/dev/null 2>&1
i=0
while running && [ $i -lt 90 ]; do sleep 1; i=$((i + 1)); done
sudo -n systemctl stop mt5
if running; then
    echo "MT5 did not exit within 90 s; systemd stop forced it" >&2
    exit 1
fi
echo "MT5 closed cleanly after ${i}s; service stopped"

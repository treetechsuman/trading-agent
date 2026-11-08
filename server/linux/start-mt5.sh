#!/bin/sh
# Started by mt5.service. Runs the FP Markets MT5 terminal under Wine on
# the VNC desktop. Kept as a script so the Windows path needs no systemd
# backslash escaping.
export DISPLAY=:1
export WINEPREFIX=/home/trader/.mt5
export WINEDEBUG=-all
exec /usr/bin/wine "C:\\Program Files\\FP Markets MetaTrader 5\\terminal64.exe"

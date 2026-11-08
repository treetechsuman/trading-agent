#!/bin/sh
# Show the last N lines (default 15) of today's MT5 terminal log, filtered.
D="$HOME/.mt5/drive_c/Program Files/FP Markets MetaTrader 5/logs"
F="$D/$(date -u +%Y%m%d).log"
[ -f "$F" ] || F="$(ls -t "$D"/*.log | grep -v metaeditor | head -1)"
iconv -f UTF-16LE -t UTF-8 "$F" | grep -E "${2:-Network|Terminal|Experts}" | tail -n "${1:-15}"

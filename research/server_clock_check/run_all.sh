#!/bin/sh
# Runs the probe over spring (Mar 1 - Apr 7) and autumn (Oct 18 - Nov 12) windows, 2018-2025.
cd "$(dirname "$0")/../.."
for y in 2018 2019 2020 2021 2022 2023 2024 2025; do
  for w in spring autumn; do
    if [ $w = spring ]; then f=$y.03.01; t=$y.04.07; else f=$y.10.18; t=$y.11.12; fi
    tag=${y}_$w
    python scripts/run_backtest.py research/server_clock_check/v1 --symbol EURUSD.r --timeframe M1 \
      --from $f --to $t --out-dir research/server_clock_check/v1/runs/$tag --set InpTag=$tag --report-tag $tag | tail -1
  done
done

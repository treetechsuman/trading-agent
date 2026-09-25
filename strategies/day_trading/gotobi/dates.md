# gotobi — date ranges

- **In-sample (optimization):** 2017.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Matches the informal "real ticks 2017-2026" window the strategy spec itself
was tested against, leaving three full recent years untouched for a genuine
out-of-sample check. All parameter sweeps and logic iteration happen only
against the in-sample range. Out-of-sample is used once, unmodified, as a
final check.

## Pairs
USDJPY, EURJPY, GBPJPY — one EA, backtested independently per pair since
MT5's standard Strategy Tester only trades the chart's own symbol. Each
pair's in-sample/out-of-sample runs live in their own subfolder inside the
version folder (`v1/USDJPY/`, `v1/EURJPY/`, `v1/GBPJPY/`), each with its own
config.ini/report/journal. Position sizing (0.5% risk each) and safety
ledgers (consecutive losses, daily loss, drawdown) are tracked per EA
instance/pair, matching how it runs live (one copy of the EA per pair's
chart). The 1.5%-of-account combined exposure across all three pairs on a
gotobi day is a live-trading property, not something the single-symbol
tester can directly simulate.

# liquidity_sweep_reversal — date ranges

- **In-sample (optimization):** 2021.01.01 – 2023.12.31
- **Out-of-sample (validation):** 2024.01.01 – 2025.12.31

Same split as `overlap_deviation_scalp`, for comparability across this
project's scalping attempts.

## Origin
Built after deep research (2026-09-23) into what's actually documented to
work in retail FX microstructure, following the user's "think out of the
box" instruction after two prior scalping lines (`overlap_momentum_scalp`,
`overlap_deviation_scalp` — 17 combinations total) were graveyarded.
Research findings that shaped this strategy:

- FX majors (including the textbook-best AUDUSD/NZDUSD pair) are
  correlated but not reliably cointegrated — ruled out naive stat-arb/
  pairs trading.
- Triangular arbitrage is not viable for single-broker retail execution
  (needs sub-millisecond, multi-broker infrastructure) — ruled out.
- Academic literature confirms genuine short-horizon FX predictability
  exists from order-flow effects, but is fragile against transaction
  costs — consistent with this project's own empirical findings.
- Liquidity-sweep/stop-hunt reversal (price wicks through a resting
  swing high/low, then closes back inside the prior range) is a
  documented, structurally distinct retail/institutional pattern not yet
  tested in this project — every prior scalping attempt used a
  statistical rolling-average threshold on price action, not concrete
  recent price structure.

## Session
Full London session through the NY overlap (08:00-16:00 London =
10:00-18:00 server), the window that performed best in
`overlap_deviation_scalp`'s own testing.

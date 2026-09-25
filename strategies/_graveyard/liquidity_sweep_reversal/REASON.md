# Why liquidity_sweep_reversal was retired

Built 2026-09-23 after deep external research (per user's "think out of
the box" instruction) into a genuinely different signal category:
fading a wick that sweeps through a recent swing high/low and closes
back inside the prior range — a documented liquidity-grab/stop-hunt
pattern, based on concrete price structure rather than the statistical
rolling-average thresholds used in every prior scalping attempt in this
project.

## What was tested

GBPUSD.r, M5, full London session (08:00-16:00 London), 2021-2023
in-sample. An 8-combination sweep across `SwingLookback` (12/20/30 bars)
and `MinSweepPips` (2.0/4.0/6.0, how convincingly the wick must clear the
level):

| Lookback | MinSweepPips | Trades | PF | Win rate |
|---|---|---|---|---|
| 12 | 2.0 (default) | 828 | 0.90 | 46.1% |
| 12 | 4.0 | 574 | 0.81 | 45.0% |
| 12 | 6.0 | 372 | 0.88 | 44.4% |
| 20 | 2.0 | 528 | 0.86 | 46.4% |
| 20 | 4.0 | 874 | **0.95** | 47.8% |
| 20 | 6.0 | 320 | **0.95** | 46.9% |
| 30 | 4.0 | 744 | 0.91 | 46.8% |
| 30 | 6.0 | 292 | 0.90 | 45.2% |

**No combination crossed a profit factor of 1.0.** Unlike
`overlap_deviation_scalp`'s sweeps (which found clear peaks above 1.0
before failing out-of-sample), this mechanism plateaus in the 0.86-0.95
range regardless of lookback window or selectivity. Out-of-sample
testing was not run — there is no in-sample result worth validating.

## Conclusion

This closes out the "think out of the box" investigation. Combined with
external research conducted the same day (see below), the overall
picture across this project's full scalping effort (17 combinations in
`overlap_momentum_scalp`/`overlap_deviation_scalp`, plus this 8-combination
sweep — 25+ backtested configurations total) is now well-supported by
outside evidence, not just internal trial and error:

- **FX majors are correlated but not reliably cointegrated** (confirmed
  even for the textbook-best AUDUSD/NZDUSD pair) — rules out naive
  statistical arbitrage/pairs trading as an alternative.
- **Triangular arbitrage is not viable for single-broker retail
  execution** (needs sub-millisecond, multi-broker infrastructure;
  60% of real opportunities last under 1 second) — rules that out too.
- **Genuine short-horizon FX predictability from order flow is real and
  academically documented, but explicitly described in the literature as
  "very short in duration and extremely volatile with regard to
  transaction costs"** — consistent with everything found empirically in
  this project: signals that work in one volatility regime (2021-2023)
  decay or reverse in another (2024-2025).
- **MT5's tick volume is not real volume** (a raw price-change counter,
  not order size), explaining why a volume-confirmation filter added no
  value in `overlap_deviation_scalp` v5.
- Retail scalping literature is explicit that professional/successful
  scalpers need 60-75%+ win rates to overcome realistic spread+commission
  — no signal tested in this project (mean-reversion, momentum, or
  liquidity-sweep) got anywhere close; all clustered in the 44-56% range.

**The honest conclusion**: this account's execution (retail spread +
fixed per-lot commission) combined with data actually available through
MT5 (OHLCV bars + tick-count-only "volume") does not appear to support a
discoverable, tradeable scalping edge using any of the well-documented
retail approaches — mean reversion, momentum continuation, or
liquidity-sweep reversal, with or without volume confirmation, across
multiple pairs, timeframes, and session windows.

## What would actually be needed (unchanged from prior conclusions, now more confident)

- Real Level 2/order-book or tick-imbalance data — not derivable from
  MT5 bars, tick volume included.
- A materially lower-commission or rebate-paying execution venue.
- Infrastructure this project doesn't have: low-latency VPS co-located
  with the broker, the kind of setup the literature says separates
  successful scalpers from unsuccessful ones.
- Absent those, treating scalping as **not currently viable on this
  account**, and directing further strategy-development effort toward
  day-trading timescales (where `gotobi` already found a real, if thin,
  edge) rather than continuing to search for a scalping edge that the
  external evidence suggests may not exist within reach of retail
  MT5-based tools.

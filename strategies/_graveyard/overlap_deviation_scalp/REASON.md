# Why overlap_deviation_scalp was retired

Direct continuation of the retired `overlap_momentum_scalp` line (see
that folder's `REASON.md`). That line's only real finding was that
fading price's deviation from a short moving average showed genuine
directional signal (win rate consistently near/above 50%) but lost
money to this account's fixed commission at high trade frequency.
`overlap_deviation_scalp` tested whether that signal could be made
economically viable and whether it would survive out-of-sample —
across every reasonable lever, autonomously, per user instruction to
keep iterating until a live candidate was found or the space was
reasonably exhausted.

## What was tested (13 combinations total, London/NY session, EURUSD.r/GBPUSD.r/USDJPY/GBPJPY.r)

| # | Variant | In-sample | Out-of-sample |
|---|---|---|---|
| 1 | v1, GBPUSD, default (M1, mult=2.0) | PF 0.88 | — |
| 2 | v1, USDJPY, default | PF 0.41 (wrong direction entirely) | — |
| 3 | v1, GBPJPY, default | PF 0.83 | — |
| 4 | v1, GBPUSD, tuned selectivity (mult=4.0) | PF 1.02, 221 trades | — |
| 5 | v1, GBPUSD, tuned selectivity + hold time (mult=4.0, hold=30) | **PF 1.09, 485 trades, all metrics healthy** | **PF 0.84, -$675** |
| 6 | v1, GBPJPY, same locked settings | PF 0.99 (flat) | not pursued (aggregate drag) |
| 7 | v2, GBPUSD, M5 default (mult=2.0) | PF 0.80 | — |
| 8 | v2, GBPUSD, M5 tuned (mult=3.0) | **PF 1.15, 500 trades, best yearly distribution yet** | **PF 0.84, -$521** |
| 9 | v3, GBPUSD, M5 continuation (wrong direction test) | PF 0.71 (confirms fade is correct direction) | — |
| 10 | v4, GBPUSD, M5 fade, full London session (not just overlap) | **PF 1.09, 1230 trades, every year individually profitable, win rate 50.6-51.1% every year** | **PF 0.81, 727 trades, win rate dropped to 46.35% — large-sample, statistically confident failure** |
| 11 | v5, GBPUSD, v4 + volume confirmation filter | PF 1.07, 796 trades, less consistent by year than v4 | not run — no evidence it would fare better |

## Conclusion

Every lever was tested: **direction** (fade beats continuation decisively
and consistently — confirmed twice, M1 and M5), **bar granularity** (M5
slightly better than M1), **symbol** (GBP-based pairs >> EURUSD > USDJPY,
which never fit the mechanism), **selectivity threshold** (real, non-
monotonic peaks found, not just "more selective is always better"),
**hold time** (a genuine 30-minute peak identified and fixed a real
design flaw — 68-73% of trades were previously hitting an arbitrary
15-minute cutoff before reaching their target), **session width** (the
full London session outperformed the overlap alone, both in trade count
and per-trade quality), and **volume confirmation** (added no
discriminable value).

Every one of these was a genuine, principled improvement over the
previous attempt — and every one of them still failed out-of-sample.
The best result (variant #10) is also the most statistically confident
failure: both the in-sample success (1230 trades, no losing year, win
rate stable within a single percentage point across three years) and
the out-of-sample failure (727 trades, win rate dropped 4-5 points) are
backed by large enough samples that neither result is a fluke. The
edge that appeared reliably in 2021-2023 did not persist into 2024-2025.

This pattern — strong 2021-2023 in-sample performance not repeating in
2024-2025 — is not unique to this strategy. `gotobi` and
`wm_fix_reversal` in this same project both showed a similar shape (their
strongest years were 2020-2022, an unusually volatile stretch: COVID
crash, aggressive Fed hikes), though both of those still held a *smaller*
positive edge out-of-sample rather than flipping negative. Scalping
timescales appear to concentrate this same regime-dependence into a much
sharper, all-or-nothing form: the mean-reversion micro-edge that existed
during 2021-2023's volatility appears to have genuinely diminished or
disappeared in the calmer 2024-2025 window, rather than just weakening.

## What would need to be true to revisit scalping here

Same as `overlap_momentum_scalp`'s own conclusion, now with much more
evidence behind it:
- A **materially lower-commission execution venue.**
- **Real order-book/tick-imbalance data**, not derivable from standard
  MT5 bars (even with volume confirmation added).
- A **volatility-regime filter** that only trades this mechanism during
  demonstrably high-volatility stretches (which would cut frequency
  further, worsening the commission problem that motivated
  `overlap_momentum_scalp`'s pivot to selectivity in the first place —
  a fundamental tension between "trade often enough to overcome fixed
  costs" and "only trade when the regime actually supports the edge"
  that this investigation was not able to resolve).
- Accepting this account's realistic scalping ceiling is likely close to
  zero with currently-available data, and treating any future scalping
  attempt as needing a fundamentally different data/execution setup, not
  another variation on price-action mean reversion.

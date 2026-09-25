# london_orb v2 — review

**Symbol:** EURUSD.r · **Timeframe:** M15 · **In-sample:** 2018.01.01–2022.12.31
**Changes from v1:** bar-close breakout confirmation (not tick touch) +
15-pip minimum range-size filter.

## Results (v1 baseline vs v2)

| Metric | v1 | v2 |
|---|---|---|
| Total Net Profit | -$8,134.32 | -$3,133.09 |
| Profit Factor | 0.81 | **0.80** |
| Max Drawdown (balance) | 85.25% | **42.36%** |
| Expected Payoff | -$6.27 | -$12.33 |
| Total Trades | 1,297 | **254** |
| Win rate (overall) | 31.84% | **32.68%** |
| Win rate long / short | 32.10% / 31.60% | 31.50% / 33.86% |
| Max consecutive losses | 14 (-$895.72) | 18 (-$1,348.59) |

Full detail in [journal.csv](journal.csv).

## Assessment

**Still not viable — and this result is more informative than v1's, not
less.** The fix cut trade count by 80% (1,297 → 254) and roughly halved
drawdown (85% → 42%), exactly as expected from filtering out noise entries.
But **the win rate barely moved (31.8% → 32.7%) and profit factor didn't
move at all (0.81 → 0.80)**.

That's the key signal: bar-close confirmation and the range-size filter
successfully removed a lot of low-quality, whipsaw-prone entries — but the
entries that survived the filter are statistically just as unprofitable as
the ones that got filtered out. If the range breakout genuinely predicted
continuation, filtering for "more genuine" breakouts should have raised
the win rate. It didn't.

**Conclusion: two structurally different entry filters on the same
underlying thesis ("a break beyond the pre-London range predicts
continuation") both land at ~32% win rate and ~0.80 profit factor. That's
strong evidence the thesis itself is wrong for EURUSD at this session/
timeframe** — not that the filter needs more work. I don't think another
round of entry-filter tuning on this same concept is worth running; the
signal doesn't appear to carry information in either version.

## Proposed next step

**Retire `london_orb`** — move it to `_graveyard/` with this finding — and
design a different day-trading concept from scratch rather than continuing
to iterate on range-breakout-continuation. Two directions worth
considering for the next strategy:

- **Mean-reversion instead of continuation**: if a break beyond the range
  doesn't predict continuation, it's worth directly testing whether it
  predicts a *reversion* back into the range instead (fade the breakout).
  The data we already have hints at this — both versions lose money going
  *with* the breakout.
- **A different signal entirely**: e.g. a momentum/trend filter (higher-
  timeframe trend + intraday pullback entry) rather than a session-range
  concept at all.

**Awaiting your direction before starting a new strategy** — graveyard
`london_orb` and pick one of the above, or something else entirely.

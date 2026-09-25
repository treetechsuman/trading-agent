# london_orb v3 — review

**Symbol:** EURUSD.r · **Timeframe:** M15 · **In-sample:** 2018.01.01–2022.12.31
**Changes from v2:** added a higher-timeframe trend filter (H4, price vs
50-period SMA) — only take the breakout if it agrees with the H4 trend
direction. Kept v2's bar-close confirmation + 15-pip minimum range filter.

## Results (all three versions)

| Metric | v1 (touch) | v2 (close+range filter) | v3 (+ trend filter) |
|---|---|---|---|
| Profit Factor | 0.81 | 0.80 | **0.78** |
| Max Drawdown | 85.25% | 42.36% | 36.04% |
| Total Trades | 1,297 | 254 | 201 |
| Win rate (overall) | 31.84% | 32.68% | **33.33%** |
| Expected Payoff | -$6.27 | -$12.33 | -$13.16 |

Full detail in [journal.csv](journal.csv).

## Assessment

**Still not viable, and the trend filter changed almost nothing.** Win
rate moved from 32.7% to 33.3% (within noise for a 201-trade sample) and
profit factor actually ticked slightly down, not up. If counter-trend
breakouts were the ones dragging the average down, filtering them out
should have produced a visible jump in win rate or profit factor. It
didn't.

**Three structurally different filters — tick-touch, bar-close + minimum
range, and bar-close + range + higher-timeframe trend alignment — all
converge on the same ~32-33% win rate and ~0.78-0.81 profit factor.**
That convergence across genuinely different filtering logic is the
strongest evidence yet that this isn't a filtering problem at all: a break
beyond the pre-London range on EURUSD.r simply doesn't carry predictive
information about continuation, in-trend or not, on this timeframe.

## Recommendation

**Retire `london_orb` to `_graveyard/`.** I don't think a fourth structural
variant on the same "breakout = continuation" thesis is a good use of
compute — three independent tests of that thesis have now failed
identically. Worth noting for the next strategy: every version lost money
specifically by trading *with* the breakout direction, which is at least
suggestive (not yet tested) that fading the breakout — betting on reversion
back into the range — could behave differently. That's a genuinely
different thesis, not a variant of this one, so it'd deserve its own fresh
strategy folder rather than a v4 here.

**Awaiting your direction on the next strategy concept** — mean-reversion/
fade of the range, a momentum/trend-following approach unrelated to
session ranges, or something else.

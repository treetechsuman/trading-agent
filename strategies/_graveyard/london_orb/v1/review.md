# london_orb v1 — review

**Symbol:** EURUSD.r · **Timeframe:** M15 · **In-sample:** 2018.01.01–2022.12.31
**Model:** every tick based on real ticks · **Account:** live FPMarkets-Live
contract specs/commission (via Login=YOUR_ACCOUNT_LOGIN in the tester)

## Results

| Metric | Value |
|---|---|
| Total Net Profit | **-$8,134.32** (on $10,000 start) |
| Profit Factor | **0.81** |
| Max Drawdown (balance) | **85.25%** |
| Expected Payoff (expectancy) | -$6.27/trade |
| Sharpe Ratio | -5.00 |
| Recovery Factor | -0.85 |
| Total Trades | 1,297 (413 won / 884 lost) |
| Win rate | 31.8% overall — 32.10% long, 31.60% short |
| Avg win / Avg loss | $84.06 / -$44.61 |
| Max consecutive losses | 14 trades, -$895.72 |

Full trade-by-trade detail in [journal.csv](journal.csv).

## Assessment

**Not viable as designed — this is a clear no, not a borderline case.** An
85% drawdown would have wiped out almost the entire account; profit factor
below 1 means it loses money before even considering that real spread/
commission are already included in this run (via `Model=4` real ticks +
the live account's contract specs).

Trade count (1,297 over 5 years) is statistically sufficient — this isn't a
small-sample fluke, it's a consistent negative edge.

What the numbers point to:
- **The win rate (31.8%) sits just under the breakeven threshold for a 1:2
  risk:reward ratio (33.3%), even before costs.** Long and short win rates
  are nearly identical (32.10% vs 31.60%), so there's no directional bias
  to exploit — the breakout signal itself isn't predictive enough for this
  reward:risk ratio.
- **1,297 trades over ~1,300 trading days in the period is close to one
  trade per day.** The 3-pip breakout buffer is barely filtering anything,
  so most days produce a trade regardless of whether the "breakout" has any
  real follow-through — this smells like a lot of noise/whipsaw entries
  rather than a small number of high-conviction setups.
- Losses cluster in streaks (14 in a row at one point) rather than being
  evenly distributed, consistent with a filter that isn't discriminating
  real breakouts from range noise.

## Proposed next step

This looks like a **structural problem** (entry filter is too loose /
exit ratio doesn't match the actual win rate the setup produces), not
something a pure numeric sweep of the existing knobs is likely to fully
fix — but the cheap thing to check first is whether tightening the
existing numeric inputs alone gets it viable before rewriting logic:

1. **Try a parameter sweep first** on `BreakoutBufferPips` (3 → 10/15/20),
   `SLMultiplier`/`TPMultiplier` (test 1:1 and 1.5:1 in addition to the
   current 1:2), and `RangeStartHour`/`RangeEndHour` (the 06:00–08:00
   window is a guess, not derived from data) — cheap to run, tells us if
   this entry concept has any life in it at all.
2. **If the sweep doesn't get profit factor comfortably above 1 with a
   sane drawdown, treat it as a logic problem**, not a tuning problem, and
   redesign the entry filter — likely candidates: require the breakout to
   be confirmed by a bar *close* beyond the range (not just a tick touch,
   which is what v1 does) to cut down on whipsaws, and/or add a minimum
   range-size filter so we only trade days where the pre-London range
   reflects real consolidation rather than a random narrow/wide box.

## Sweep results (2018–2022, in-sample)

Ran the cheap check first: 11 combinations of `BreakoutBufferPips` (3/10/20)
× `SLMultiplier`/`TPMultiplier` (1:1, 1:1.5, 1.5:1, 1:2), plus the v1
baseline. Full grid in [sweep/sweep_results.csv](sweep/sweep_results.csv).

| Buffer | SL:TP | Profit Factor | Max DD | Trades |
|---|---|---|---|---|
| 3 | 1:2 (baseline) | 0.81 | 85.25% | 1,297 |
| 3 | 1:1 | 0.79 | 82.76% | 1,297 |
| 3 | 1.5:1 | 0.79 | 74.86% | 1,297 |
| 10 | 1:1 | 0.83 | 69.63% | 1,286 |
| 10 | 1.5:1 | 0.82 | 64.05% | 1,286 |
| 20 | 1:1.5 | **0.86 (best)** | 64.93% | 1,142 |
| 20 | 1.5:1 | 0.83 | 58.22% | 1,143 |

**Every single combination stayed below profit factor 1**, and even the
best one (buffer=20 pips, SL:TP=1:1.5) still had a 65% max drawdown.
Widening the buffer from 3→20 pips only cut trade count by ~12% (1,297 →
1,142) with no meaningful improvement in win rate — confirming this isn't
a noise-filtering problem, the range breakout itself just isn't predictive
of continuation on EURUSD.r regardless of how it's filtered or how the
reward:risk is set.

**Conclusion: this is a structural problem with the entry signal, not a
tuning problem.** Confirms the hypothesis from the initial review — moving
to v2 means redesigning entry/exit logic, not more parameter search on
this same setup.

**Awaiting approval before starting v2.** Proposed v2 direction: require
the breakout to be confirmed by a bar *close* beyond the range (not a tick
touch, which is what v1/this sweep both used) and add a minimum range-size
filter so only genuine consolidation days generate a signal. Let me know
if you'd like that direction, a different logic redesign, or to shelve
`london_orb` and try a different strategy concept entirely.

# wm_fix_reversal — strategy description

**Status: PARKED (2026-09-22).** v2 fixed v1's diagnosed problem
(out-of-sample trade frequency collapse) by making the spike threshold
volatility-adaptive instead of a fixed pip count — that fix worked
cleanly. But the larger, more honest out-of-sample sample it produced
(158 trades vs. v1's 26) revealed the underlying edge is thinner than
v1's small sample suggested (PF ~1.04-1.06 per pair out-of-sample) —
comparable in thinness to `london_range_fade`, parked the same day for
the same reason. Briefly set to `live_candidate` on the user's own
instruction; the one open thread that might have justified it — a
hinted diversification benefit from trading EUR+GBP together, since each
pair's losing out-of-sample year didn't coincide — was tested directly
with a combined-account portfolio harness ([v2_portfolio/review.md](v2_portfolio/review.md))
and **failed**: combined drawdown is worse than either pair alone (came
within half a point of the 15% kill-switch in-sample), because 24% of
shared-event trading days saw both pairs lose simultaneously. Re-parked
after seeing that result. See [v2/review.md](v2/review.md) for the full
original writeup.

**Current version:** v2 (locked `MinSpikeVsAvgMultiplier=2.0`) ·
**Previous version:** v1 (locked `MinSpikeSizePips=12`, superseded — kept
for comparison, see [v2/comparison.md](v2/comparison.md)) · **Symbols:**
EURUSD.r, GBPUSD.r · **Timeframe:** M1 ·
**Compiled EA:** `v2/strategy.mq5` (v1 kept at `v1/strategy.mq5` for
comparison, not deleted per project convention)

## What it does

Fades the volatility spike around the WM/Reuters 4pm London FX fix — the
benchmark rate index funds, custodians, and pension funds use to execute
large currency rebalancing trades.

1. **Measure the spike** — track price from 15:55 to 16:02 London time
   (17:55-18:02 this broker's server time, a flat +2h offset that holds
   year-round since this broker's EET/EEST DST dates currently match
   UK/EU's).
2. **Filter (v2, volatility-adaptive)** — skip the day unless the measured
   move is at least `MinSpikeVsAvgMultiplier` (locked at 2.0) times the
   rolling 20-day average of the fix-window's own recent moves, with a
   5-pip absolute floor. v1 used a fixed `MinSpikeSizePips=12` instead —
   see comparison.md for why that was replaced.
3. **Fade it** — sell if price rose into the fix, buy if it fell. Unlike
   `gotobi`, the direction isn't fixed; it depends on which way that
   day's rebalancing flow pushed price.
4. **Manage the trade** — stop-loss and take-profit both set at 1x the
   measured spike size (stop beyond the spike, target back toward the
   pre-fix level).
5. **Exit** — market close 30 minutes after the measurement window closes
   if SL/TP haven't already fired. Flat by 22:00 server time regardless.
6. **Position size** — 1% of equity risked per trade.

## Why this approach

Built after `london_range_fade` investigation concluded there was no
clean, generalizable fix for its thin edge and unexplained 2018 losses.
Rather than keep tuning a vague "pre-London session range" pattern, this
strategy anchors to a specific, real, published institutional-flow
mechanism (like `gotobi` did successfully). v1's fixed-pip filter looked
strong in-sample but its out-of-sample trade frequency collapsed
~85-90% in calmer 2023-2025 conditions (a fixed absolute threshold
doesn't adapt to changing ambient volatility) — v2 fixed that specific
problem by making the threshold relative to recent volatility instead,
the same technique already proven in `london_range_fade` v2's own filter.

## Performance (see [v2/review.md](v2/review.md) / [v2/comparison.md](v2/comparison.md) for full detail)

| | In-sample (2017.08-2022) | Out-of-sample (2023-2025, used once) |
|---|---|---|
| EURUSD PF / trades / max DD | 1.23 / 167 / 8.7-9.2% | 1.06 / 73 / 7.5-7.6% |
| GBPUSD PF / trades / max DD | 1.07 / 142 / 9.3-10.2% | 1.04 / 85 / 6.9-7.1% |

**Frequency collapse is fixed** — EURUSD 2023 went from 0 trades (v1) to
29 (v2); out-of-sample rates now roughly match in-sample rates on both
pairs. But the larger, more honest out-of-sample sample this produced
(158 trades vs. v1's 26) reveals a thinner edge than v1's small sample
suggested — v1's eye-catching OOS profit factor (2.03/1.19) turned out to
be a small-sample artifact, not a real signal.

## Known limitations / open questions

- **The edge is thin, now confirmed on an adequate sample rather than
  assumed from a thin one.** PF ~1.04-1.23 across all four pair/period
  cuts — comparable in magnitude to `london_range_fade`'s own PF
  ~1.05-1.14. Two independently-designed strategies landing in the same
  thin-edge territory is itself a signal about realistic edge sizes for
  short-hold EURUSD/GBPUSD day trades on this account's cost structure.
- **Each pair has one real losing year in the 3-year out-of-sample
  window** (EURUSD 2025: -$351; GBPUSD 2024: -$400) — though they don't
  coincide, hinting at a diversification benefit from trading both
  together that hasn't been tested directly (no portfolio harness built
  yet, unlike `gotobi`'s `v1_portfolio`).
- **This broker's clean EURUSD.r/GBPUSD.r tick history starts ~2017.07.31**
  — the same cutover independently found for the JPY crosses in `gotobi`.
  Can't extend in-sample further back on this broker.

## Files

- `v1/` — original fixed-threshold version (`MinSpikeSizePips=12`),
  kept for comparison. `v1/sweep/` has the pip-threshold sweep; `v1/review.md`
  has the original investigation and the frequency-collapse diagnosis
  that motivated v2.
- `v2/strategy.mq5` — current version, volatility-adaptive threshold
  (`MinSpikeVsAvgMultiplier=2.0`).
- `v2/sweep/` — the in-sample multiplier sweep (1.0-4.0x) that led to the
  locked value.
- `v2/review.md` — the redesign's full writeup and assessment.
- `v2/comparison.md` — v1 vs. v2 side by side, and in-sample vs.
  out-of-sample for v2.
- `v2/GBPUSD/` — GBPUSD's own in-sample run and `validation/` out-of-sample.
- `v2/validation/` — EURUSD's out-of-sample run.
- `v2_portfolio/` — combined-account test harness (one EA, both symbols,
  one shared account) that tested and disproved the diversification
  hint. `v2_portfolio/review.md` has the finding (worse combined
  drawdown, 24% same-day correlated losses).
- `dates.md` — date ranges and the broker tick-history ceiling note.

# month_end_fix_reversal — strategy description

**Status: `live_candidate` (2026-09-23) — my own genuine recommendation,
not user-overridden.** Validated in-sample, out-of-sample, and as a
combined 3-pair portfolio. Verdict: ready for live at reduced size (start
EUR/GBP only). See [VERDICT.md](VERDICT.md).

**Version:** v1 · **Symbols:** EURUSD.r, GBPUSD.r, USDJPY · **Timeframe:**
M1 · **Compiled EA:** `v1/strategy.mq5` (also `v1_portfolio/strategy.mq5`
for the combined-account test harness)

## What it does

Fades the WM/Reuters 4pm London FX fix volatility spike, restricted to
the final days of the month — the window FX-flow research identifies as
when institutional currency-hedge rebalancing flow actually concentrates.

1. **Calendar filter** — only active within the last `TradeLastNDaysOfMonth`
   (3 default) calendar days of the month.
2. **Measure the spike** — track price from 15:55 to 16:02 London time
   (17:55-18:02 server), identical to `wm_fix_reversal`'s mechanism.
3. **Filter** — skip unless the move clears a volatility-adaptive
   threshold (`MinSpikeVsAvgMultiplier=2.0` x rolling 20-day average of
   the fix window's own recent moves) — the exact same locked parameters
   as `wm_fix_reversal` v2, reused unchanged.
4. **Fade it** — sell if price rose into the fix, buy if it fell.
5. **Manage the trade** — stop-loss and take-profit both at 1x the
   measured spike size; market close 30 minutes after the window if
   neither hit.
6. **Position size** — 1% of equity risked per trade.

## Why this approach

Direct descendant of `wm_fix_reversal`, which faded *every* day's fix
spike and found only a thin edge (PF ~1.04-1.06 out-of-sample) — parked
as borderline. Rather than abandon the underlying WM-fix mechanism
entirely, this version tests whether narrowing to the specific days
FX-flow research says the flow actually concentrates produces a cleaner
signal than applying the same fade to every day indiscriminately.
Built with **zero parameter sweeping** — the already-locked mechanism
was reused unchanged, and exactly one pre-specified filter was added
based on external research, before any results were seen. This is a
methodologically stronger process than most other strategies in this
project, several of which produced misleadingly strong in-sample results
by sweeping thresholds and picking the best-looking one.

## Performance (see [v1/review.md](v1/review.md) / [v1_portfolio/review.md](v1_portfolio/review.md) for full detail)

| | In-sample (2018-2022) | Out-of-sample (2023-2025, used once) |
|---|---|---|
| EURUSD PF / trades | 1.12 / 35 | **2.21** / 19 |
| GBPUSD PF / trades | 1.67 / 37 | **2.05** / 21 |
| USDJPY PF / trades | 1.14 / 48 | **1.42** / 16 |
| Combined portfolio PF / trades / max DD | 1.25 / 119 / 6.48-7.02% | **2.08** / 55 / **4.39-5.63%** |

**Every pair improved out-of-sample, no exceptions** — the strongest,
most consistent result produced in this project's search for a new
specific-event strategy (which discarded three scalping lines and one
academic-literature attempt before this).

## Known limitations / open questions

- **Absolute trade count is thin** — 174-176 combined trades across the
  full 8-year window, still under this project's 200-trade significance
  bar, inherent to trading only ~3 qualifying days/month.
- **USDJPY is the weakest pair** — real edge (PF 1.14/1.42) but
  meaningfully higher drawdown than EUR/GBP; the verdict recommends
  starting without it.
- **24.2% of multi-pair trading days see every pair lose together**
  (checked directly in the portfolio harness) — real correlated risk on
  the worst days, though it doesn't compound into severe drawdown at
  this strategy's low monthly frequency the way it did for
  `wm_fix_reversal`'s daily version.
- **Live execution quality at the fix is unverified** — same category of
  risk as `gotobi`'s own open caveat: a well-known, published,
  potentially crowded event that backtesting's tick replay can't fully
  validate.

## Files

- `v1/strategy.mq5` — the EA, reusing `wm_fix_reversal` v2's locked
  parameters plus the month-end calendar filter.
- `v1/review.md` — full per-pair in-sample/out-of-sample writeup.
- `v1/GBPUSD/`, `v1/USDJPY/` — those pairs' own in-sample runs and
  `validation/` out-of-sample subfolders.
- `v1_portfolio/` — combined 3-pair account test harness and its own
  `validation/` out-of-sample run.
- `v1_portfolio/review.md` — the combined-account finding and
  correlated-loss analysis.
- `VERDICT.md` — the live-readiness assessment and reasoning.
- `dates.md` — date ranges, origin, and research citations.

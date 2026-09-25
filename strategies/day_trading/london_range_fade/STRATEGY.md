# london_range_fade — strategy description

**Status: TRADEABLE — marked by user for review (2026-09-17). Not yet
approved for live capital; holding here pending further review.**

**Version:** v2 · **Symbol:** EURUSD.r · **Timeframe:** M15 · **Compiled
EA:** `v2/strategy.mq5` (also compiled at
`MQL5\Experts\EAFactory\london_range_fade\v2\strategy.ex5` in the terminal)

## What it does

Trades one setup per day: fades a break of the pre-London consolidation
range, betting on reversion back into the range rather than continuation.

1. **Build a range** from the price action between 06:00–08:00 (server
   time) — the pre-London session. Tracks the high and low over that
   2-hour window using completed M15 bars.
2. **Filter the range** — skip the day entirely if:
   - The range is narrower than 15 pips (too tight to be meaningful
     consolidation), or
   - The range is more than 2x the rolling 20-day average range (an
     abnormal, volatility-shock day — e.g. this filter was added
     specifically because the strategy lost money trading through the
     March 2020 COVID crash).
3. **Wait for a break** — once the range is set (at 08:00) and passes the
   filter, watch for a completed 15-minute bar to *close* more than 10
   pips beyond the range high or low. (Requiring a closed bar, not just an
   intrabar touch, cuts down on whipsaw entries — an earlier version that
   traded on any tick touching the level performed much worse.)
4. **Fade it** — if price closed above the range, sell (betting it comes
   back down); if it closed below, buy (betting it comes back up). One
   trade maximum per day.
5. **Manage the trade** — stop-loss and take-profit are both set at 1x the
   day's range size: the stop sits beyond the breakout extreme (room for
   it to extend a bit before invalidating), the target sits back across
   the range.
6. **Position size** — risks 1% of current account equity per trade,
   calculated from the actual stop-loss distance and the symbol's tick
   value (not a fixed lot size).
7. **Flat by end of day** — any open position is force-closed at 20:00
   server time. This is a day-trading strategy; it never holds overnight.

## Why this approach (brief history)

An earlier strategy (`london_orb`, now in `_graveyard/`) traded the same
kind of session-range breakout but bet on *continuation* instead of
reversion. Three different entry filters on that thesis all converged on
the same ~32% win rate and a profit factor around 0.80 — clear evidence
continuation didn't work for this setup. Every one of those losing trades
was, definitionally, a trade this strategy's opposite (fading) would have
won — which is the direct motivation for `london_range_fade`.

## Performance (see individual review.md / comparison.md files for full detail)

| | In-sample (2018–2022) | Out-of-sample (2023–2025, used once) |
|---|---|---|
| Profit Factor | 1.08 | 1.10 |
| Win rate | 53.5% | 54.9% |
| Max drawdown | 9.58% | 6.06% |
| Trades | 202 (~40/yr) | 71 (~24/yr) |

Out-of-sample matched in-sample closely — no sign of curve-fitting. But
the edge is thin (profit factor never comfortably above 1 in any test),
2018 is a confirmed losing year with no identified fix, and absolute
returns are modest (~$1,100 combined profit on a $10,000 account across
the full 8 years tested).

## Known limitations / open questions

- **2018 loses money for an unknown reason.** Unlike 2020 (COVID crash,
  fixed by the volatility filter), 2018's losses are diffuse across the
  year with no obvious single cause identified yet.
- **Two years had too few trades to be statistically meaningful**
  (2019: 2 trades in-sample; 2024: 5 trades out-of-sample) — the setup
  simply doesn't fire often in some years, which itself may be worth
  understanding.
- **The edge has never exceeded profit factor ~1.14** in any
  configuration tested (parameter sweep, robustness check, or
  out-of-sample) — it is real but small, and could plausibly be eroded by
  live execution costs (slippage, requotes, news-driven spread widening)
  that the backtest may not fully capture.

## Files

- `v1/` — first working version of the fade concept (buffer=3, no
  volatility filter). `v1/sweep/` and `v1/robustness/` hold the parameter
  sweep and yearly-breakdown analysis that led to the locked config.
- `v2/` — current/locked version (buffer=10, + rolling-average volatility
  filter). `v2/robustness/` has its own yearly breakdown; `v2/validation/`
  has the out-of-sample run, journal, and `comparison.md`.
- `VERDICT.md` — the live-readiness assessment and reasoning.
- `dates.md` — the in-sample/out-of-sample date ranges used throughout.

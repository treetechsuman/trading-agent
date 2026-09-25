# Why london_breakout_retest was retired

User-specified London-session breakout-continuation strategy: Asian-range
(00:00-06:00 UTC) breakout, entered not on the impulse but on a pullback
retest of the broken boundary with a rejection-candle confirmation
(pin bar / engulfing), plus an H1 directional-context filter. EURUSD.r,
GBPUSD.r, USDJPY, M15, in-sample 2017-2022.

All three pairs lost money: PF 0.86/0.79/0.56, win rate 34.48%/30.41%/
25.29%, 565 trades combined (over this project's 200-trade bar). All
three independently ground down to their spec'd 15% max-drawdown safety
stop and then traded zero times for the rest of the window (USDJPY: Nov
2018, dead ~4.1 years; GBPUSD.r: Nov 2020, dead ~2.1 years; EURUSD.r: May
2021, dead ~1.6 years) — confirmed via full equity-curve reconstruction
to be the spec's own (no-auto-resume) drawdown stop working as designed,
not a synchronized correlated-loss event or a position-sizing bug (risk
per trade stayed a consistent ~0.5% of equity throughout, no scale-up
after losses). The three very different trip dates rule out a shared
calendar-event explanation — each pair independently has a persistently
negative edge.

Root cause: the underlying win rate (25-34%) is well under the ~33.3%
breakeven line a 2R take-profit target requires, on two of three pairs
by a wide margin. EOD-flat exit truncating some winners short of 2R is a
real but secondary contributor (~0.15-0.20 PF on EURUSD alone). This is
the same failure signature already found for `london_orb` (discarded
2026-09-17, ~32-33% win rate / PF ~0.78-0.81 across three structurally
different entry filters): "breakout predicts continuation" has no real
edge on these pairs. Adding a materially more selective entry gate
(mandatory retest + rejection-candle confirmation, on top of an H1
directional filter) did not fix it — two of three pairs came in at a
*worse* win rate than any `london_orb` variant. Entry-filter
sophistication does not fix a thesis-level problem; see
`researcher/lessons.md` for the generalized version of this lesson.

Full detail: `strategies/day_trading/london_breakout_retest/v1/review.md`.

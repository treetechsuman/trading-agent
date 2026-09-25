# yen_fiscal_repatriation v1 — review

**Symbols:** USDJPY, EURJPY.r, GBPJPY.r · **Timeframe:** M1 (tick-driven) ·
**In-sample:** 2017.01.01–2022.12.31 · Sell-only, 00:15 UTC entry / 09:00 UTC
clock exit, 40-pip stop, no take-profit, trades only within the final 15
calendar days of March and September.

## Headline stats (per pair)

| Metric | USDJPY | EURJPY.r | GBPJPY.r |
|---|---|---|---|
| Trades | 120 | 107 | 110 |
| Win rate | 45.83% | 44.86% | 47.27% |
| Profit factor | 0.83 | 0.91 | 1.12 |
| Net profit ($10k start) | -$316.70 | -$162.00 | +$293.44 |
| Expectancy/trade | -$2.64 | -$1.51 | +$2.67 |
| Max balance DD | 5.18% | 3.80% | 3.78% |
| Max equity DD | 5.32% | 4.01% | 6.57% |

Combined: 337 trades, net -$185.26 (three independent $10k accounts, not a
shared portfolio). All three pairs individually well under the 200-trade
significance bar; combined trade count is also under 200. Treat everything
below as provisional in the strict statistical sense, but the internal
consistency of the diagnosis (confirmed independently three ways) is strong
enough to act on.

Known data-availability artifact confirmed: EURJPY.r/GBPJPY.r show zero
trades in the March 2017 window (broker JPY-cross history is clean only
from ~mid-2017 onward); USDJPY (deeper history) traded it normally. Not a
strategy finding, per dates.md.

## Diagnosis (full per-trade reconstruction, all three journals)

I reconstructed each pair's year-by-year and March-vs-September P&L
directly from `journal.csv` (balance-column deltas cross-checked against
the reported net profit for all three pairs — every reconciliation matched
exactly, so this breakdown is trustworthy).

**1. The September leg is the primary loss driver, the March leg is net
positive in aggregate.**

| Leg (combined, 3 pairs) | Net P&L | Trades (approx) |
|---|---|---|
| March (fiscal year-end) | +$124.67 | ~167 |
| September (fiscal half-year) | -$309.93 | ~170 |

This lines up with the citation asymmetry already flagged in dates.md: the
March leg has much stronger external corroboration (BIS commentary, IMF
chapter, "12 of 16 years / 75%" seasonal-flow stat) than the September leg
("to a lesser extent," desk commentary only, no comparable multi-decade
stat). The backtest result tracks the citation strength almost exactly —
a genuinely encouraging sign that this isn't random.

**2. But the March leg alone is not a robust edge either — it's "one good
year carries the average," the exact pattern this project has flagged
before (gotobi's 2025, wm_fix_reversal's small-sample trap).** Per-pair,
per-year March P&L:

- USDJPY March: 2017 +80, 2018 +55, 2019 +11, 2020 +17, **2021 -141**, 2022
  +19 (net +$41)
- EURJPY March: 2018 +4, 2019 +98, **2020 -136**, 2021 +2, 2022 -18 (net
  -$50)
- GBPJPY March: 2018 +160, **2019 +236**, **2020 -232**, **2021 -162**,
  2022 +131 (net +$133)

Combined March P&L is dominated by 2019 (+$345 across EUR/GBP alone) and
nearly wiped out by 2020 (COVID volatility shock hit EUR/GBP March legs
for a combined -$368 — same stop-out signature seen in
`london_range_fade`'s and `wm_fix_reversal`'s own COVID-quarter findings).
Drop 2019 and 2020 and the March leg is close to flat across all three
pairs.

**3. Stop-outs cluster in identifiable macro/volatility-regime periods,
not randomly.** ~20-25% of all trades close via the 40-pip stop rather
than the 09:00 clock exit (loss ≈ -$47 to -$52, consistent with the stop
size). These cluster hard in:
- **March 2020** (COVID vol shock — EUR/GBP March legs, 4-6 consecutive
  stop-outs each)
- **USDJPY Sept 2022**: all 5 trades in that window stopped out
  consecutively, triggering the spec's own 6-consecutive-loss pause
  (confirmed: row 116's loss + these 5 = exactly 6 consecutive losses,
  which is why the window is truncated to 5 trades instead of the usual
  ~10-11 — verified this is the safety rule firing correctly, not a data
  gap)
- **USDJPY 2021 (both legs) and 2022**: this was the start of the
  BOJ-ultra-easy/Fed-hiking secular yen-weakening trend — a macro force
  directly opposing this strategy's short-JPY-cross thesis, large enough
  to swamp the seasonal flow for two consecutive years (-$283 in 2021,
  -$214 in 2022 for USDJPY alone)

**4. No clean within-window timing pattern.** Checked whether the last 3
trading days of each 15-day window outperform the full window (the
hypothesis that flow concentrates near fiscal-period-end, so
`FiscalWindowDays=15` might be diluting signal with early, un-concentrated
days). Result across USDJPY's 6 March windows: last-3-days beat the rest
in 3 of 6 years and lost in the other 3, with no consistent sign or
magnitude pattern (COVID-2020's last-3-days was the single worst
sub-period; 2022's was the best). No evidence `FiscalWindowDays=15` is the
problem, and no evidence a narrower window would help — this rules out
"window too wide" as a motivated fix.

## Is there a single, motivated refinement?

I looked for one specifically, per this project's house rule (no blind
parameter sweeps). The most obvious candidate — **drop the September leg,
keep March only** — is well-motivated (matches the citation-strength
asymmetry) and would flip the combined result from -$185 to +$125. But
digging one level deeper into *why* March is positive shows it is not
because the mechanism reliably produces a small edge every window; it's
because one strong year (2019) outweighs one COVID-driven bad year (2020),
with the rest roughly flat. Removing September doesn't fix the underlying
issue — the whole strategy's P&L, on either leg, is dominated by a small
number of macro/volatility-regime episodes unrelated to the seasonal
mechanism (COVID crash, 2021-2022 secular yen weakening) rather than by
a steady realization of the seasonal flow itself. A "March-only" v2 would
be locking in exactly the kind of small-sample, single-good-year artifact
this project's lessons.md repeatedly warns against (wm_fix_reversal v1,
overlap_deviation_scalp v1-v4) — the fact that it's traceable to a
real citation asymmetry doesn't rescue it from that pattern once the
per-year data is inspected.

No other single, causally-motivated fix presents itself: the stop-outs
aren't concentrated at a fixable time-of-day or window-position, the
losses aren't explained by cost drag (average per-trade P&L swings of
$40-50 dwarf typical spread/commission on these pairs), and the direction
(sell JPY crosses) is exactly what the mechanism specifies — this isn't a
direction bug.

## Decision: discard

This is the second strategy in this project (after `intraday_momentum_carry`)
where a well-corroborated external mechanism did not survive contact with
backtesting — but through a different failure mode. `intraday_momentum_carry`
failed because the academic effect itself was too thin/generic once applied
to a single retail FX instrument. This one fails because a real, specific,
well-cited seasonal flow exists but is **small relative to the macro/
volatility-regime forces (COVID shock, multi-year currency trends) that
dominate any 8.75-hour directional bet with a 40-pip stop and no take-
profit** — the seasonal signal is real but not the dominant force acting
on these pairs during the specific windows it fires in, and no single,
honest parameter change fixes that (it would require either predicting
which years the macro regime favors the seasonal flow — not something
this strategy's own logic can do — or abandoning the naked-directional
structure entirely, which is really a different strategy, not a
refinement of this one).

Moving to `strategies/_graveyard/yen_fiscal_repatriation/REASON.md`.

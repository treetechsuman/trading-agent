# wm_fix_reversal v1 — review

**Symbols:** EURUSD.r (primary, results at `v1/` root), GBPUSD.r (`v1/GBPUSD/`)
· **Timeframe:** M1 · **In-sample:** 2017.08.01–2022.12.31 (extended from
2018.01.01 after the initial sweep — see below) · **Locked parameter:**
`MinSpikeSizePips=12`

## How this version got here

1. **v1 baseline (15 pips default)** on EURUSD 2018-2022 looked
   spectacular — PF 2.25, 66% win rate, 1% max drawdown — but only 38
   trades. Far below this project's 200-trade significance bar.
2. **Swept `MinSpikeSizePips`** from 6 to 20 pips (see
   `sweep/sweep_results.csv`). Found a clear, mechanistically sensible
   pattern: routine small fix-window moves (6-10 pips) show almost no
   edge (PF ~1.04-1.10), only genuinely large moves (15+ pips) show a
   strong one. But the strong-looking end of that range is also the
   thinnest-sample end — a real risk that the improvement is a small-N
   artifact, not a real escalating edge.
3. **Locked 12 pips** as the most defensible balance (84 trades, PF 1.13)
   rather than cherry-picking the best-looking number off a shrinking
   sample.
4. **Yearly breakdown at the locked threshold revealed 2018 as a clear
   loser** (PF 0.67, -$278, 50% win rate) — while 2019-2022 were all
   solidly positive. Notably, `london_range_fade` (a different EURUSD
   mean-reversion day strategy) *also* loses money in 2018, suggesting
   2018 may simply have been a hard regime for this whole category on
   this pair, not a flaw unique to either strategy.
5. **Extended in-sample back to 2017.08.01** — this broker's EURUSD.r
   tick history is clean no further back than ~2017.07.31 (same cutover
   date independently found for the JPY crosses in `gotobi`). This raised
   the EURUSD sample to 99 trades — still below 200.
6. **Extended to GBPUSD.r** (same locked rules, no changes) to pool
   samples toward statistical significance, the same move that worked for
   `gotobi`. Combined in-sample: **284 trades** (99 EUR + 185 GBP) —
   finally clears the 200-trade bar.

## In-sample results (2017.08–2022.12, locked config)

| Metric | EURUSD | GBPUSD |
|---|---|---|
| Trades | 99 | 185 |
| Profit factor | 1.25 | 1.12 |
| Win rate | 59.6% | 55.7% |
| Net profit | $663.13 | $668.52 |
| Max drawdown | 4.68-5.09% | **10.14-10.86%** |

**GBPUSD's drawdown is notably worse than EURUSD's**, and its yearly
breakdown is rockier: losing years in 2017 (partial, -$343), 2018
(-$135), and 2019 (-$51), only turning solidly positive from 2020
onward. EURUSD shows the same *shape* (weak 2017-2019, strong 2020-2022)
but less severely. This temporal pattern — both pairs weak in the earlier
years, strong 2020-2022 — is worth flagging on its own: either the edge
genuinely strengthened in recent years (2020-2022 included the COVID
crash and the 2022 Fed-hike cycle, both unusually volatile), or the
earlier years are simply too thin to trust either way.

## Out-of-sample results (2023-2025, used once, unmodified)

| Metric | EURUSD | GBPUSD |
|---|---|---|
| Trades | **7** | **19** |
| Profit factor | 2.03 | 1.19 |
| Net profit | $204.87 | $126.55 |
| Max drawdown | 1.07-1.98% | 3.05-3.08% |

**The headline finding is not the profit factor — it's that trade
frequency collapsed.** EURUSD went from ~18.3 qualifying trades/year
in-sample to ~2.3/year out-of-sample; GBPUSD from ~34.3/year to ~6.3/year.
**EURUSD had zero qualifying trades in all of 2023.** Per-trade quality
held up fine (both pairs still profitable, no sign the *direction* of the
edge broke), but there simply weren't enough 12+ pip fix-window spikes to
trade in the out-of-sample period to say anything with confidence.

This is consistent with 2020-2022 (in-sample's strongest years) being an
unusually high-volatility stretch — COVID crash, then an aggressive
Fed-hike cycle — that a fixed absolute-pips threshold happened to fire on
often. 2023-2025 was comparatively calm for much of its span (2025 alone
picked up 6 of the 7 EURUSD OOS trades and 7 of GBPUSD's 19, echoing a
similar late-2025 volatility pickup already seen independently in
`gotobi`'s out-of-sample results).

## Assessment

**This is a genuinely interesting lead, not a validated strategy.** The
core thesis (fade large WM/Reuters fix spikes) has a sensible mechanism
and the per-trade quality signal has never broken across five separate
tests (in-sample both pairs, out-of-sample both pairs). But:

- **Combined out-of-sample sample is only 26 trades** — nowhere near
  enough to confirm the edge survives into calmer market conditions.
- **The strategy may be volatility-regime-dependent** in a way that
  isn't obvious from in-sample data alone — a fixed pip threshold doesn't
  adapt to changing baseline volatility, so it may simply go dormant for
  extended stretches (as EURUSD did for all of 2023) rather than failing
  outright. That's a meaningfully different risk profile than a strategy
  that trades steadily but loses.
- **GBPUSD's drawdown (10%+) and rocky early years** are a real
  weak point that EURUSD alone doesn't show.

## Proposed next step

I would **not** call this live-grade, and I don't think forcing more
tuning is the right move (per the project's own out-of-sample discipline
— this isn't "weak, so re-optimize," it's "too infrequent to know yet").
Two honest paths from here:

1. **Let it run longer in observation** — this needs more calendar time
   (or a volatility-adaptive threshold instead of a fixed pip count,
   which would be a genuinely new v2 design, not a re-tuned v1) before
   its true frequency and consistency can be judged.
2. **Treat it as a discarded/parked idea** for now, given the thin
   out-of-sample sample, and revisit if market volatility picks up.

**Awaiting your direction.**

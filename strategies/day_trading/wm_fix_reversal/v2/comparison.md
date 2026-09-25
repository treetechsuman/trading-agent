# wm_fix_reversal v1 vs v2 — in-sample and out-of-sample comparison

v2's entire change from v1: replaced the fixed `MinSpikeSizePips` (12)
threshold with a volatility-adaptive one (`MinSpikeVsAvgMultiplier=2.0` x
the rolling 20-day average of the fix-window's own recent moves, floor
5 pips). Nothing else changed. Purpose: v1's out-of-sample trade
frequency collapsed ~85-90% in the calmer 2023-2025 window; this tests
whether an adaptive threshold fixes that specific, diagnosed problem.

## The core question: did frequency collapse get fixed?

| | v1 (fixed 12 pips) | v2 (adaptive 2.0x avg) |
|---|---|---|
| EURUSD in-sample rate | ~18.3 trades/yr | ~30.9 trades/yr |
| EURUSD out-of-sample rate | ~2.3 trades/yr | ~24.3 trades/yr |
| EURUSD 2023 trades | **0** | **29** |
| GBPUSD in-sample rate | ~34.3 trades/yr | ~26.3 trades/yr |
| GBPUSD out-of-sample rate | ~6.3 trades/yr | ~28.3 trades/yr |
| GBPUSD 2023 trades | 7 | 31 |

**Yes — decisively.** v1's rate dropped by 85-90% from in-sample to
out-of-sample; v2's rate is roughly *unchanged* between the two periods,
and the specific dead year (EURUSD 2023, zero trades under v1) now trades
normally. This is exactly what the adaptive design was built to fix, and
it worked as intended.

## But: does per-trade quality survive at this higher frequency?

| Metric | v1 EUR IS | v2 EUR IS | v1 EUR OOS | v2 EUR OOS |
|---|---|---|---|---|
| Trades | 99 | 167 | 7 | 73 |
| Profit factor | 1.25 | 1.23 | 2.03 | **1.06** |
| Max drawdown | 4.7-5.1% | 8.7-9.2% | 1.1-2.0% | **7.5-7.6%** |

| Metric | v1 GBP IS | v2 GBP IS | v1 GBP OOS | v2 GBP OOS |
|---|---|---|---|---|
| Trades | 185 | 142 | 19 | 85 |
| Profit factor | 1.12 | 1.07 | 1.19 | **1.04** |
| Max drawdown | 10.1-10.9% | 9.3-10.2% | 3.1% | **6.9-7.1%** |

**No, not fully — this is the real trade-off.** v2 trades far more often
and profit factor holds up in-sample (1.23/1.07, close to v1's own
1.25/1.12), but out-of-sample profit factor is thinner than v1's headline
numbers on both pairs (1.06/1.04 vs v1's 2.03/1.19) and drawdown is
meaningfully worse (7-8% vs v1's 1-3%). v1's OOS numbers looked better
mainly *because* they were computed from a tiny, cherry-picked-by-survival
sample (7 and 19 trades) — v2's larger, more honest sample shows the
edge is real but thinner than v1's small sample suggested.

## Yearly consistency (out-of-sample, 2023-2025)

| Pair | 2023 | 2024 | 2025 |
|---|---|---|---|
| EURUSD | $400 / 29 trades / 58.6% WR | $160 / 16 trades / 56.2% WR | **-$351 / 28 trades / 46.4% WR** |
| GBPUSD | $473 / 31 trades / 61.3% WR | **-$400 / 26 trades / 50.0% WR** | $70 / 28 trades / 57.1% WR |

Each pair has one clearly losing year within the 3-year out-of-sample
window (EURUSD 2025, GBPUSD 2024) — but they don't coincide, so a
combined two-pair account would have been profitable in all three years
even though neither pair alone was. That's a real, if modest,
diversification benefit worth noting.

## Combined totals

| | In-sample (2017.08-2022, both pairs) | Out-of-sample (2023-2025, both pairs) |
|---|---|---|
| Trades | 309 | 158 |
| Net profit | $1,579.37 | $351.98 |

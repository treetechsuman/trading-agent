# london_range_fade v2 — in-sample vs out-of-sample comparison

**Config validated (locked, no changes from in-sample):** EURUSD.r, M15,
`BreakoutBufferPips=10`, `MinRangeSizePips=15`, `SLMultiplier=TPMultiplier=1`,
`MaxRangeVsAvgMultiplier=2.0` (skip if today's pre-London range > 2x the
rolling 20-day average), `RiskPercent=1`. Model=4 (real ticks), tested
against account YOUR_ACCOUNT_LOGIN's real contract specs/commission.

## Headline comparison

| Metric | In-sample (2018–2022) | Out-of-sample (2023–2025) |
|---|---|---|
| Profit Factor | 1.08 | **1.10** |
| Net Profit | $777 | $333 |
| Max Drawdown | 9.58% | **6.06%** |
| Win rate | 53.47% | 54.93% |
| Sharpe Ratio | 4.66 | 2.87 |
| Total Trades | 202 (~40/yr) | 71 (~24/yr) |

**No out-of-sample degradation** — profit factor and win rate are both
essentially unchanged (within a couple points), and drawdown is actually
better out-of-sample. This is the opposite of the classic overfitting
signature (great in-sample, collapses out-of-sample), which is a genuine
point in this strategy's favor.

## Out-of-sample yearly breakdown

(Pure analysis of the single approved validation run's trade journal — no
additional backtests were run against 2023-2025.)

| Year | Net Profit | Trades |
|---|---|---|
| 2023 | +$333 | 13 |
| 2024 | -$319 | **5** |
| 2025 | +$319 | 53 |

Same pattern as in-sample: performance isn't perfectly smooth year to
year. 2024 was a loser, but on only 5 trades — too few to draw a real
conclusion from (similar to 2019's near-empty in-sample year). Unlike
2018/2020 in-sample (each ~50-60 trades on a full year), there's no
out-of-sample year with a large-enough sample to call it a confirmed
losing regime the way 2018 was in-sample.

## Note: a second parsing bug found and fixed here

While reconciling per-trade profit against the reported total, found that
`journal.csv` was not including commission in each trade's profit (MT5
charges commission per leg as a separate balance deduction, not folded
into the deal's "Profit" field) — fixed in `parse_report.py`. This only
affected the per-trade CSV display; the summary metrics above come
directly from MT5's own Results table and were never affected.

## Overall assessment

This is a real, if thin, edge that held up reasonably well out-of-sample —
not a curve-fit that collapsed on unseen data. But it's still not a strong
result: profit factor has stayed in a narrow 1.05–1.14 band across every
honest test (never comfortably above it), one in-sample year (2018) is a
confirmed, unexplained loser that no filter fixed, and absolute returns
are modest (~$1,100 combined over the full 8-year span tested on a $10k
account — roughly 1-2%/year). See the final verdict below.

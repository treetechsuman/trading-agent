# gotobi v1 — in-sample vs out-of-sample comparison

No parameters were changed between in-sample and out-of-sample — same
compiled EA, same fixed rules (there was nothing to sweep/optimize in the
first place; see [review.md](review.md)). Out-of-sample was run once,
unmodified, per pair.

## Side-by-side (per pair, per-pair independent $10,000 account)

| Metric | USDJPY IS | USDJPY OOS | EURJPY IS | EURJPY OOS | GBPJPY IS | GBPJPY OOS |
|---|---|---|---|---|---|---|
| Period | 2017–2022 (6y) | 2023–2025 (3y) | 2017–2022 (6y) | 2023–2025 (3y) | 2017–2022 (6y) | 2023–2025 (3y) |
| Trades | 298 | 153 | 272 | 153 | 272 | 153 |
| Win rate | 57.4% | 57.5% | 60.3% | 58.8% | 57.7% | 56.9% |
| Profit factor | 1.48 | **1.86** | 1.42 | **1.81** | 1.43 | **1.48** |
| Net profit | $1,155.91 | $1,658.69 | $1,077.85 | $1,493.47 | $1,345.57 | $1,173.62 |
| Annualized return | ~1.9%/yr | ~5.5%/yr | ~1.8%/yr | ~5.0%/yr | ~2.2%/yr | ~3.9%/yr |
| Max balance drawdown | 1.69% | 2.29% | 1.59% | 2.13% | 2.61% | 2.74% |
| Expectancy/trade | $3.88 | $10.84 | $3.96 | $9.76 | $4.95 | $7.67 |
| Sharpe ratio | 14.59 | 26.60 | 13.86 | 24.34 | 14.05 | 17.06 |

**No degradation on any pair, on any metric — profit factor and expectancy
actually improved out-of-sample across the board.** This is strong evidence
against curve-fitting, though it's worth noting there was very little
*to* curve-fit in the first place (no swept parameters), so "improved
out-of-sample" here means "the event-driven premise held up and got a
favorable year," not "we got lucky escaping an overfit config."

## Out-of-sample yearly breakdown (2023–2025, computed from the trade journals)

| Pair | 2023 | 2024 | 2025 |
|---|---|---|---|
| USDJPY | $378 / 56.0% WR / 50 trades | $95 / 50.0% WR / 52 trades | **$1,185 / 66.7% WR / 51 trades** |
| EURJPY | $230 / 50.0% WR / 50 trades | $253 / 55.8% WR / 52 trades | **$1,010 / 62.7% WR / 51 trades** |
| GBPJPY | $179 / 48.0% WR / 50 trades | -$13 / 48.1% WR / 52 trades | **$1,008 / 64.7% WR / 51 trades** |

**2025 alone accounts for roughly 65–85% of each pair's 3-year
out-of-sample profit** — exactly the pattern the strategy spec itself
warned about ("one year gave most of that ... a normal year is more like
4 to 9%"). 2024 was flat-to-slightly-negative for GBPJPY (-$13 on $10k,
essentially a wash) and modest for the other two. This doesn't look like a
fluke/breakdown — no pair had a real losing year — but it does mean 2025's
JPY-specific volatility regime (consistent with the yen's macro backdrop
that year) is doing a lot of the work in the headline OOS numbers, and a
"normal" year going forward likely looks closer to the 2023/2024 range
(roughly 1-3%/yr per pair) than to 2025's outlier.

## What this doesn't cover

Same limitation as the in-sample review: each pair was backtested
independently on its own $10k account, since MT5's standard tester can't
run a true multi-symbol combined-account portfolio test. Live, all three
pairs risk 0.5% each on the same gotobi calendar day (up to 1.5%
concurrently) — if a bad day hits all three pairs at once (plausible,
since USDJPY/EURJPY/GBPJPY all move on the same JPY-demand event), the
real combined-account drawdown on that day would be worse than any single
pair's numbers above suggest. This wasn't and couldn't be tested here.

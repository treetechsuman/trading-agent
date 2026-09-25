# wm_fix_reversal v2_portfolio — review

**Purpose:** test a specific hypothesis raised in v2's review — each pair
had exactly one losing out-of-sample year that didn't coincide (EURUSD
2025, GBPUSD 2024), hinting a combined EUR+GBP account might be more
consistently profitable than either pair alone. This harness runs both
pairs from one EA instance against one shared account (same pattern as
`gotobi/v1_portfolio`) to test that directly.

## Result: the hypothesis does not hold. Combined drawdown is worse, not better.

| Metric | EURUSD alone | GBPUSD alone | Combined account |
|---|---|---|---|
| In-sample PF | 1.23 | 1.07 | 1.16 |
| In-sample max DD | 8.7-9.2% | 9.3-10.2% | **14.56-15.44%** |
| Out-of-sample PF | 1.06 | 1.04 | 1.04 |
| Out-of-sample max DD | 7.5-7.6% | 6.9-7.1% | **9.11-9.67%** |

Combined-account drawdown is **worse than either individual pair, in both
periods** — in-sample drawdown came within half a point of this project's
15% kill-switch. Profit factor is a simple blend of the two pairs, no
better and no worse than expected from averaging.

## Why: same-event correlation, not diversification

Checked directly: on the 59 days both pairs traded (same fix event, same
day), **14 days (24%) had both pairs lose simultaneously** — real,
material correlated risk. Worst combined-loss days lost $175-226 in a
single day, roughly double what a typical single-pair loss looks like,
because the two pairs' losses stack rather than offset on a bad fix day.

The original hint (different *years* had different pairs losing) was
real but the wrong level to look at. Annual P&L totals can differ even
while individual *days* correlate strongly — and drawdown is driven by
clustered daily losses, not annual totals. A pair that's profitable for
the year can still have several individual bad fix-days that land in the
same week as the other pair's bad fix-days, and those are exactly the
stretches that define max drawdown.

## Conclusion

This closes the one open question from v2's review, and it closes in the
wrong direction. There is no diversification benefit to trading
EUR+GBP together on this thesis — if anything, combining them concentrates
risk on shared bad fix-days rather than spreading it. Combined with the
already-thin per-pair profit factor (1.04-1.06 out-of-sample), this
strengthens rather than weakens the case that `wm_fix_reversal` is not
live-grade: not only is the edge thin, the natural way to try to make it
more attractive (trade both pairs together) makes the risk profile worse,
not better.

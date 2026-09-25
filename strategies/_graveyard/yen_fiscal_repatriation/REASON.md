# Why yen_fiscal_repatriation was retired

Sold USDJPY/EURJPY.r/GBPJPY.r (00:15 UTC entry, 09:00 UTC clock exit, 40-pip
stop, no take-profit) within the final 15 calendar days of March and
September, on the well-corroborated thesis that Japanese institutional
investors (life insurers, pension funds, megabanks) repatriate FX and add
hedges ahead of Japan's fiscal year-end/half-year — see dates.md for
citations (BIS Quarterly Review, Hattori & Shin 2007, practitioner desk
research), independently verified via live web search post-hoc.

In-sample 2017-2022: USDJPY PF 0.83 (-$317, 120 trades), EURJPY.r PF 0.91
(-$162, 107 trades), GBPJPY.r PF 1.12 (+$293, 110 trades). Combined -$185
across 337 trades.

Full per-trade reconstruction (see v1/review.md) found the September leg
net negative across all three pairs (-$310 combined) and the March leg net
positive (+$125 combined) — matching the citation-strength asymmetry
(March is the well-documented leg, September is "to a lesser extent" per
dates.md). But the March leg's positive total is itself an artifact of one
strong year (2019) outweighing one COVID-vol-shock year (2020), not a
steady realization of the seasonal flow — the same "one good year carries
the average" pattern this project has flagged repeatedly elsewhere. Losses
concentrate in identifiable macro/volatility-regime episodes (COVID crash
March 2020, the 2021-2022 secular BOJ-ultra-easy/Fed-hiking yen-weakening
trend that directly opposed this strategy's short-JPY-cross thesis for two
consecutive years) rather than being spread evenly, and no within-window
timing pattern (last-3-days vs full 15-day window) was found to motivate a
narrower window.

No single, causally-motivated refinement survived scrutiny: dropping the
September leg looked promising at first but the remaining March-only
result is itself a small-sample artifact once inspected year by year, not
a real fix. This project's house rule is to discard rather than sweep
parameters when no clear causal fix exists — that's the case here.

**General lesson**: a real, well-corroborated, specifically-named
institutional flow (stronger sourcing here than `intraday_momentum_carry`
had) can still fail to survive backtesting for a *different* reason than
"the academic effect is too generic/thin" — here the mechanism is real but
small relative to the macro-trend/volatility-regime forces that dominate a
directional, stop-loss-only, no-take-profit bet over an 8.75-hour window.
Citation quality alone (named participants, concrete calendar trigger) is
necessary but not sufficient for live-readiness — it still has to be
checked against whether the instrument's dominant macro regime during the
backtest window was fighting the thesis, which only the trade-level data
can reveal.

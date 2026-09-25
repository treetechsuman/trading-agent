# gotobi v1 — review

**Symbols:** USDJPY, EURJPY.r, GBPJPY.r · **Timeframe:** M1 (tick-driven, timeframe is
cosmetic) · **In-sample:** 2017.01.01–2022.12.31

**Backtest methodology note:** MT5's standard Strategy Tester only trades
the chart's own symbol, so this EA — designed to run as one copy per pair's
chart — was backtested as **three independent single-symbol runs**, each on
its own fresh $10,000 account. Position sizing (0.5% risk/trade) and the
safety ledgers (consecutive losses, daily loss, drawdown) are per-pair by
design (matches how it runs live: separate EA instances). What this setup
**cannot** show is the combined-account effect of all three pairs risking
0.5% each on the same calendar day (up to 1.5% concurrently) — if losses on
a bad gotobi day cluster across all three pairs (plausible, since USDJPY/
EURJPY/GBPJPY all move on the same JPY-demand event), a true combined
account would see deeper drawdown spikes than any single pair shows here.
Flagging this as a real gap, not just a formality — see Assessment.

## Aggregate in-sample results (2017–2022, per pair)

| Metric | USDJPY | EURJPY.r | GBPJPY.r |
|---|---|---|---|
| Total trades | 298 | 272 | 272 |
| Win rate | 57.4% | 60.3% | 57.7% |
| Profit factor | 1.48 | 1.42 | 1.43 |
| Net profit ($10k start) | $1,155.91 | $1,077.85 | $1,345.57 |
| Expectancy/trade | $3.88 | $3.96 | $4.95 |
| Max balance drawdown | 1.69% | 1.59% | 2.61% |
| Sharpe ratio | 14.59 | 13.86 | 14.05 |
| Recovery factor | 5.41 | 5.10 | 3.99 |
| Max consecutive losses | 6 | 6 | 6 |
| Avg profit / avg loss trade | $20.97 / -$19.13 | $22.35 / -$20.25 | $28.49 / -$23.63 |

Full journals: [USDJPY/journal.csv](USDJPY/journal.csv),
[EURJPY/journal.csv](EURJPY/journal.csv), [GBPJPY/journal.csv](GBPJPY/journal.csv).

Annualized return per pair (own $10k account): USDJPY ~1.9%/yr, EURJPY
~1.8%/yr, GBPJPY ~2.2%/yr — consistent with the spec's own "small edge"
framing, not the headline 9.8%/yr figure (that number came from the spec's
own combined multi-symbol test over a different, apparently more favorable
window that included 2025).

**Every pair independently hit the 6-consecutive-loss safety pause at least
once** during this window (confirmed in the tester log: USDJPY paused
2019.02 and 2021.03, EURJPY.r and GBPJPY.r both paused 2022.11) and correctly
resumed trading the following month with no code intervention — the safety
rule fired exactly as designed rather than sitting untested.

## Yearly breakdown (robustness check across 2017–2022)

| Pair | Year | PF | Net profit | Max DD | Trades | Win rate |
|---|---|---|---|---|---|---|
| USDJPY | 2017 | 1.48 | $187 | 1.65% | 46 | 67.4% |
| USDJPY | 2018 | 1.27 | $106 | 1.40% | 51 | 54.9% |
| USDJPY | 2019 | 1.17 | $56 | 1.12% | 50 | 48.0% |
| USDJPY | 2020 | 1.45 | $170 | 1.02% | 50 | 54.0% |
| USDJPY | 2021 | 1.07 | $20 | 1.06% | 51 | 58.8% |
| USDJPY | **2022** | **2.00** | **$574** | 0.99% | 50 | 62.0% |
| EURJPY.r | 2017* | 1.03 | $5 | 0.94% | 21 | 61.9% |
| EURJPY.r | 2018 | 1.65 | $251 | 1.42% | 51 | 70.6% |
| EURJPY.r | 2019 | 1.50 | $208 | 1.04% | 52 | 57.7% |
| EURJPY.r | 2020 | 1.18 | $84 | 0.95% | 50 | 52.0% |
| EURJPY.r | 2021 | 1.51 | $160 | 0.75% | 51 | 60.8% |
| EURJPY.r | 2022 | 1.49 | $335 | 1.57% | 47 | 59.6% |
| GBPJPY.r | 2017* | 1.32 | $75 | 0.76% | 21 | 52.4% |
| GBPJPY.r | 2018 | 1.50 | $269 | 1.58% | 51 | 58.8% |
| GBPJPY.r | 2019 | 1.53 | $267 | 1.31% | 52 | 53.8% |
| GBPJPY.r | 2020 | 1.41 | $205 | 1.00% | 50 | 58.0% |
| GBPJPY.r | 2021 | 1.79 | $233 | 0.63% | 51 | 64.7% |
| GBPJPY.r | 2022 | 1.25 | $220 | 2.62% | 47 | 55.3% |

\* 2017 has fewer trades for the JPY crosses because this broker's
EURJPY.r/GBPJPY.r tick history only starts 2017.07.25 — a broker data-history
limit, not a strategy issue (USDJPY's history goes back further). Treat both
2017 rows as partial-year, lower-confidence data points.

Full data: [robustness/yearly_results.csv](robustness/yearly_results.csv).

**Every single pair-year combination (18/18) had a profit factor above
1.0** — no losing year for any pair across the whole in-sample window. That
is the strongest evidence here: this isn't one good year carrying a flat or
negative average.

## What worked / what to flag

- **Consistency is the real finding.** 18/18 profitable pair-years, small
  and tightly-clustered drawdowns (0.6%–2.6%), win rates clustered around
  50-70% matching the spec's "6 in 10 trades win" expectation. This looks
  like a genuine small structural edge, not curve-fit noise.
- **USDJPY 2022 is an outlier** — PF 2.00 and $574 profit vs. $20-190 in
  every other USDJPY year. It doesn't fail any other year (unlike
  london_range_fade's 2018/2020 pattern), so I don't think it's masking a
  problem, but it does mean the USDJPY aggregate number is flattered by one
  standout year. Worth knowing before setting expectations for out-of-sample.
- **The edge is thin per-trade, exactly as the spec warned.** Average winner
  is only $2-8 bigger than the average loser in dollar terms per pair. The
  spec's own caution — "if costs rise by about 3 pips, it disappears" — is
  the single biggest risk to watch in out-of-sample and live.
- **Per-pair safety ledgers worked as designed** (6-loss pause fired and
  auto-resumed correctly), but since they're independent per pair, a
  simultaneous bad stretch across all three pairs would not be caught by
  any single pair's ledger — only a combined-account view would catch that,
  which this backtest setup can't produce.
- **Trade counts are adequate**: ~270-300 trades per pair over 6 years,
  in line with the spec's ~50/year estimate. Not huge, but not the "too few
  to be meaningful" territory either.

## Proposed next step

I'd call v1 solid enough to move to **out-of-sample validation
(2023-2025)** as-is — no parameters were swept or tuned here (this is a
fixed-rule, event-driven strategy with no free parameters to optimize
against; the only "parameters" are broker-clock times taken directly from
the spec and a fixed 20-pip stop / 0.5% risk / 3-pip spread cap, none of
which were fit to this data). Since there's nothing to optimize, the
in-sample/out-of-sample split mainly checks whether the event-driven premise
still holds and whether costs have crept up, not whether I curve-fit
something.

**Awaiting your direction** — go to out-of-sample validation, or would you
like me to dig into anything first (e.g. re-check the USDJPY 2022 trades
individually, or examine whether the daily-loss/drawdown safety rules would
have ever actually bound during any of these periods)?

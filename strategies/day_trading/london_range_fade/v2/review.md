# london_range_fade v2 — review

**Symbol:** EURUSD.r · **Timeframe:** M15 · **In-sample:** 2018.01.01–2022.12.31
**Changes from v1 (locked config: buffer=10, SL=TP=1, min_range=15):** added
a filter that skips the day if the pre-London range is more than 2x the
rolling average of the last 20 days' ranges — targeting the COVID-crash
drag identified in v1's yearly breakdown.

## Important: infrastructure bug found and fixed mid-investigation

While building this version I found that **MT5's Strategy Tester does not
reliably fall back to an EA's own coded default inputs when a config file
omits `[TesterInputs]`.** It can silently reuse a value left over from a
previous test of a *different* EA, if that EA happened to declare an input
with the same name (all our EAs share names like `BreakoutBufferPips`
since each version is copied from the last). My first attempt at this
filter used daily ATR as the volatility yardstick and appeared to have zero
effect — turned out to be partly this caching issue plus (see below) a
genuine design mismatch.

**Fixed in `scripts/common.py`/`run_backtest.py`**: every backtest now
auto-extracts all `input` declarations straight from `strategy.mq5` and
writes a complete, explicit `[TesterInputs]` section every time, so a run
can never silently inherit stale values again. I re-verified this fix
directly (a run with an absurd override producing zero trades, then the
same run repeated with no override reproducing the EA's actual coded
defaults exactly).

**Confidence in prior results:** the `london_range_fade` v1 sweep and
yearly-robustness numbers already reported are unaffected — those runs all
passed explicit `--set` values for every parameter that mattered. The
`london_orb` v2/v3 "initial" backtests (before their own sweeps) are the
ones I can't fully vouch for in hindsight, since those specific runs relied
on coded defaults with no explicit override. Given `london_orb`'s
conclusion rested on the *sweep* results (which did use explicit values
throughout) converging with those initial runs, I don't believe this
changes the london_orb verdict, but flagging it for transparency rather
than quietly letting it slide.

## First filter attempt: daily ATR (didn't work)

Comparing a 2-hour session range to *daily* ATR(14) is comparing different
time scales — a 2-hour range is naturally a small fraction of a full day's
typical movement, so no sane multiplier on daily ATR ever flagged
anything. Confirmed empirically: results were bit-for-bit identical to the
no-filter config. Fixed by comparing the range instead to a rolling
average of its *own* recent history (last 20 days), an apples-to-apples
comparison — this is what's reported below.

## Results (rolling-average filter, threshold = 2x recent average)

| Metric | v1 (locked, no vol filter) | v2 (+ vol filter) |
|---|---|---|
| Profit Factor | 1.14 | 1.08 |
| Net Profit | $1,620 | **$777** |
| Max Drawdown | 10.12% | **9.58%** |
| Total Trades | 250 | 202 |
| Win rate | 34.4% | **53.5%** |

### Yearly breakdown

| Year | v1 PF / Net | v2 PF / Net | Changed? |
|---|---|---|---|
| 2018 | 0.97 / -$83 | **0.87 / -$359** | Worse |
| 2019 | 39.76 / $338 (4 trades) | 43.74 / $194 (2 trades) | Still meaningless (too few trades) |
| 2020 | 0.91 / -$276 | **1.12 / +$253** | **Recovered, as hypothesized** |
| 2021 | 2.06 / $753 | 1.67 / $369 | Worse |
| 2022 | 1.19 / $856 | 1.13 / $535 | Worse |

Full data in [robustness/yearly_results.csv](robustness/yearly_results.csv).

## Assessment

**Mixed result — the filter did exactly what it was designed to do, but
that wasn't enough to fix the underlying consistency problem.** 2020
recovered from a losing year to a winning one, confirming the COVID-crash
hypothesis was correct. But:
- **2018 got worse, not better** — confirms that 2018's losses were never
  event-driven (as suspected in v1's review) and this filter doesn't
  address whatever *is* wrong with 2018.
- **2021 and 2022 both got worse too** — the filter isn't free; cutting 48
  trades to remove the COVID drag also cut some of the trades that were
  working in the good years.
- Net effect: total profit across the 5 years dropped (~$1,600 → ~$800-1,000
  depending on how you sum it), win rate normalized a lot (34%→53%, now much
  closer to the ~50/50 you'd expect from a 1:1 SL:TP mean-reversion setup),
  and drawdown improved slightly.

I don't think this is a clean "problem solved" — it traded some profit and
one fixed failure mode for a still-unexplained one (2018). Whether that
trade is worth it depends on what you're optimizing for: if the goal is
avoiding tail-risk blowups in live trading, removing the COVID-style
failure mode has real value even at a profit cost. If the goal is best
risk-adjusted return, 2018's unresolved weakness means this still isn't a
strategy I'd call "consistent across years."

## Options from here

1. **Investigate 2018 directly** (same way I did for 2020) — pull the
   trade-by-trade journal, look for a pattern, and see if a different filter
   addresses it specifically.
2. **Accept the current trade-off and move to out-of-sample validation**
   (2023-2025) with v2's config — treating the yearly inconsistency as a
   known limitation to report in the final verdict rather than something to
   keep chasing.
3. **Revert to v1's config (no volatility filter)** if a few really bad
   years is an acceptable risk given the higher average profit — go to
   out-of-sample with that instead.

**Awaiting your direction.**

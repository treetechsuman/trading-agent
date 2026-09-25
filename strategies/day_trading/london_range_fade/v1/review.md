# london_range_fade v1 — review

**Symbol:** EURUSD.r · **Timeframe:** M15 · **In-sample:** 2018.01.01–2022.12.31
**Concept:** fade a bar-close break beyond the pre-London range (06:00–08:00
server time) rather than follow it — same range-building/filter mechanics
as `london_orb` v2/v3 (bar-close confirmation, 15-pip minimum range size),
opposite trade direction, 1:1 SL:TP off the range size.

## Results

| Metric | Value |
|---|---|
| Total Net Profit | **+$383.03** (on $10,000 start) |
| Profit Factor | **1.02** |
| Max Drawdown (balance) | **17.85%** |
| Expected Payoff | +$1.51/trade |
| Sharpe Ratio | **0.90** |
| Recovery Factor | 0.21 |
| Total Trades | 254 (96 won / 158 lost) |
| Win rate | 37.80% overall — 37.01% long, 38.58% short |
| Avg win / Avg loss | $164.03 / -$93.46 |
| Max consecutive losses | 10 trades, -$822.24 |

Full detail in [journal.csv](journal.csv).

## Assessment

**First positive result after 3 failed london_orb attempts — but it's a
thin edge, not yet a robust one.** Profit factor 1.02 is barely above
breakeven; net profit of $383 over 5 years on a $10k account (254 trades)
is a small return for the drawdown taken (17.85%). This is a genuine
directional improvement (confirms the fade hypothesis over continuation),
but I wouldn't call it "found an edge" yet at these numbers — it's within
range of what small overfitting or a slightly different cost assumption
could erase.

Notable: avg win ($164.03) is ~1.75x avg loss ($93.46) despite the SL and
TP being symmetric (both = 1x range size). That asymmetry is likely coming
from the EOD force-flat rule interrupting some losing trades before they
reach full SL while winners more often run to full TP — worth confirming
this isn't an artifact before reading too much into it.

Long and short performed almost identically (37.01% vs 38.58% win rate),
same as the continuation version — still no directional bias, which is
expected for a range-based signal on a symmetric pair.

## Proposed next step

Unlike london_orb (where sweeping a structurally dead thesis was pointless
because three different filters all landed at the same win rate), this
thesis shows a real, if small, signal — worth the cheap check of a
parameter sweep before judging it further. Propose sweeping:
- `SLMultiplier` / `TPMultiplier` (test tighter targets like 0.75:1, 1:0.75,
  and wider stops like 1.5:1, since the current 1:1 might not be the best
  ratio for a mean-reversion exit)
- `BreakoutBufferPips` (5/10 in addition to the current 3) — a bigger
  buffer means fading a more decisive/exhausted break, which might raise
  win rate
- `MinRangeSizePips` (10/20/25) — check sensitivity to the consolidation
  threshold

## Sweep results (2018–2022, in-sample)

One-at-a-time sensitivity check around the baseline (SL=1, TP=1, buffer=3,
min_range=15 → PF 1.02), then a combined test of the two most promising,
full-sample-size changes. Full grid in
[sweep/sweep_results.csv](sweep/sweep_results.csv).

| Change from baseline | Profit Factor | Net Profit | Max DD | Trades | Sharpe |
|---|---|---|---|---|---|
| baseline | 1.02 | $383 | 17.85% | 254 | 0.90 |
| SL 0.75x | 1.02 | $328 | 14.79% | 254 | 1.41 |
| TP 0.75x | 0.95 | -$488 | 11.18% | 254 | -2.81 |
| SL 1.5x | 1.11 | $1,028 | 10.44% | 254 | 4.60 |
| TP 1.5x | 1.02 | $245 | 17.39% | 254 | 0.75 |
| buffer 5 pips | 1.09 | $1,025 | 14.16% | 253 | 4.39 |
| **buffer 10 pips** | **1.14** | **$1,620** | **10.12%** | 250 | 6.86 |
| min_range 10 pips | 0.90 | -$2,691 | 31.49% | 615 | -5.00 |
| min_range 20 pips | 1.42 | $1,969 | 7.03% | **112** | 15.75 |
| min_range 25 pips | 1.25 | $474 | 3.30% | **47** | 8.44 |
| SL 1.5x + buffer 10 (combined) | 1.04 | $336 | 9.63% | 250 | 1.66 |

Two things stand out:

1. **`BreakoutBufferPips=10` alone is the strongest full-sample-size
   result**: PF 1.14, net profit $1,620 (4.2x the baseline), drawdown down
   to 10.12%, on essentially the same trade count as baseline (250 vs
   254). Requiring a more decisive break before fading it works better
   than the 3-pip default — this looks like a legitimate improvement, not
   noise.
2. **`MinRangeSizePips=20` looks even better on paper (PF 1.42, DD 7%) but
   only produces 112 trades over 5 years (~22/year).** That's a real
   statistical-significance concern — per the project convention, a
   result on this few trades needs to be treated cautiously, not taken at
   face value. The monotonic-looking improvement breaks down at
   min_range=25 (PF drops back to 1.25 on just 47 trades), which is more
   consistent with a small sample bouncing around than a real, stable
   relationship.
3. **Combining SL 1.5x with buffer 10 didn't compound as hoped** (PF only
   1.04) — win rate jumped to 60% but average loss grew faster than
   average win, netting out worse than buffer 10 alone. Interactions
   between these parameters aren't simply additive.

## Recommendation

**Lock in `BreakoutBufferPips=10` (keep SL=TP=1, MinRangeSizePips=15) as
the v1 configuration** — it's a clean, full-sample-size improvement over
every metric versus the original baseline, without the statistical-
significance risk of the min_range=20 result. That result (PF 1.42) is
worth keeping in mind as a candidate for a follow-up if the trade-count
concern can be resolved (e.g. it holds up in the multi-window check
below), but I wouldn't promote it to "the" configuration yet on 112 trades.

**Proposed next step: run the multi-window robustness check** (per project
convention) with `BreakoutBufferPips=10` locked, across a few other
historical windows not used for this sweep, to see whether the edge holds
generally or was specific to 2018–2022. I'd also spot-check `MinRangeSizePips=20`
in the same pass since it's cheap to include.

## Multi-window robustness check

**Caveat on methodology:** real tick data for EURUSD.r on this
installation doesn't extend before ~2018 (confirmed via probes: 0% real
ticks in both a 2015 and a 2017 test window), so there's no genuinely
separate historical window available without eating into the reserved
2023–2025 out-of-sample range. Instead, this breaks the already-approved
2018–2022 period into individual years with the locked config
(`BreakoutBufferPips=10`, SL=TP=1, `MinRangeSizePips=15`) to check
consistency. This is weaker evidence than a truly independent window would
be — it's the same underlying data the sweep was tuned on, just sliced —
but it directly answers "was the aggregate result carried by one or two
good years," which is exactly the failure mode this check exists to catch.
Full data in [robustness/yearly_results.csv](robustness/yearly_results.csv).

| Year | Profit Factor | Net Profit | Max DD | Trades |
|---|---|---|---|---|
| 2018 | 0.97 | -$83 | 10.11% | 62 |
| 2019 | 39.76 | +$338 | 0.03% | **4** |
| 2020 | 0.91 | -$276 | 10.04% | 61 |
| 2021 | 2.06 | +$753 | 1.27% | 22 |
| 2022 | 1.19 | +$856 | 8.26% | 99 |

**This is a yellow flag, not a green light.** The aggregate PF 1.14 over
the full period is not consistent across years:
- **2018 and 2020 are losing years** (PF 0.97 and 0.91) on reasonable
  trade counts (62 and 61) — not small-sample noise, a real negative
  result in those years.
- **2019 had only 4 trades** — far too few to mean anything; its PF of
  39.76 is a sample-size artifact, not a real result.
- **2021 and 2022 are the years carrying the whole aggregate result**
  (+$753 and +$856, against -$83 and -$276 in the losing years).

This matches the "one good year carrying the average" failure pattern the
project's final-verdict criteria explicitly warns about. I don't think
this qualifies as "the edge holds generally" — it looks more like the edge
is real only in some volatility/trend regimes (2021-2022) and absent or
negative in others (2018, 2020), and I don't yet know what distinguishes
them (worth checking: 2020 includes the COVID volatility shock, which
could plausibly break a mean-reversion assumption if ranges get blown
through rather than reverted).

## Where this leaves the strategy

Not ready to call this "found an edge" and move to out-of-sample
validation with confidence — that would risk treating a coincidence as
confirmation. Options from here:
1. **Investigate the 2018/2020 losing years** — check whether a regime
   filter (e.g. skip trading when recent volatility is abnormally high,
   which might catch 2020's COVID period) recovers consistency without
   just curve-fitting to make 2018/2020 look better in hindsight.
2. **Run out-of-sample validation anyway**, eyes open that in-sample
   evidence is mixed — if 2023-2025 also comes back inconsistent, that's a
   clean "not ready" verdict; if it's unexpectedly consistent, that's
   still informative (though I'd stay skeptical of one more good number).
3. **Treat this as inconclusive and try a different structural angle**
   rather than sinking more time into this specific setup.

**Awaiting your call on which direction to take.**

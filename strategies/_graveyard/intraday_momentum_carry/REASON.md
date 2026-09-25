# Why intraday_momentum_carry was retired

Built 2026-09-23 per the user's "go for day trading" instruction,
directly implementing a published, peer-reviewed academic finding —
Gao, Han, Li & Zhou (2018, *Journal of Financial Economics*): a market's
first half-hour return predicts its last half-hour return in the same
direction, extended by Baltussen, van Vliet & Ye (2021) to 60+ futures
across equities, bonds, commodities, and currencies over 40+ years, both
papers reporting robustness to transaction costs. This is categorically
stronger external evidence than the internally-invented technical
patterns behind every prior strategy in this project except `gotobi`
and `wm_fix_reversal` (which are anchored to real, specific institutional
flow events, not academic return-predictability studies).

## What was tested

London session (08:00-16:00 London = 10:00-18:00 server), 2018-2022
in-sample, sign-only construction (no magnitude filter, faithful to the
literature) with only one addition of this project's own: a stop-loss
(the papers study pure hold-to-close return predictability, not a
specific risk-management discipline).

| Test | Trades | PF | Win rate |
|---|---|---|---|
| EURUSD.r, 20-pip stop (v1 default) | 451 | 0.82 | 49.5% |
| EURUSD.r, 30-pip stop | 803 | 0.84 | 49.6% |
| EURUSD.r, 50-pip stop | 1070 | 0.79 | 48.8% |
| EURUSD.r, 75-pip stop | 1175 | 0.81 | 49.0% |
| EURUSD.r, 100-pip stop | 1175 | 0.81 | 49.0% |
| GBPUSD.r, 20-pip stop | 151 | 0.67 | 43.1% |
| EURUSD.r, 60/60-min windows (vs. 30/30), 30-pip stop | 780 | 0.88 | 49.7% |

**Every configuration stayed below profit factor 1.0**, across two
pairs, five stop widths, and two measurement-window sizes. Win rate
never meaningfully cleared 50% in any test. (Trade count varies sharply
with stop width — not a bug: tight stops produce more frequent quick
stop-outs, which cluster into consecutive-loss streaks that trip this
project's standard 6-loss safety pause far more often, skipping many
trading days; wider stops rarely get hit intraday, so almost every day
reaches the scheduled session-close exit instead.)

## Why the literature's finding likely doesn't transfer directly here

- **Instrument/session mismatch**: Baltussen et al.'s currency evidence
  is on FX *futures* (CME-style exchange-defined sessions), not spot FX.
  Spot FX has no genuine daily open/close discontinuity the way an
  exchange session does — the "informed trader" mechanism the original
  papers describe may depend on that discontinuity in a way that doesn't
  map cleanly onto a London-session convention chosen for spot majors.
- **The direct FX-specific evidence found in research (Elaut et al.,
  RUB-USD) was narrow and crisis-specific** (studied during a financial
  crisis), not a broad, calm-market validation for major pairs — a
  meaningfully different claim than "this works generally on FX majors."
- **The effect's own reported strength is weak per-observation**: Gao et
  al. report a predictive R² of only ~1.6%, comparable to *monthly*-
  frequency predictability elsewhere. That's a real, statistically
  significant signal in a large panel of many instruments/days
  aggregated — but on any single FX pair's single daily realization, a
  1.6% R² signal is easily overwhelmed by realistic retail transaction
  costs, exactly the same "real but too small for retail costs" pattern
  found independently in this project's scalping research (order-flow
  imbalance predictability was described in the literature the same
  way — real, but "extremely volatile with regard to transaction
  costs").

## Conclusion

This is now the third distinct, well-researched mechanism this project
has tested and rejected on the same underlying theme: **a genuine,
published, real return-predictability effect exists, but is too thin
relative to this account's realistic transaction costs to trade
profitably in isolation on a single instrument.** This mirrors the
scalping investigation's own conclusion almost exactly, now confirmed at
day-trading timescale too — the "too thin for retail costs" problem
isn't specific to scalping's ultra-short holding periods.

**The throughline across this whole project's actual successes**
(`gotobi`, and to a lesser extent `wm_fix_reversal`) **vs. its failures**
(`london_orb`, `london_range_fade`'s thin edge, all scalping attempts,
and now this) is specificity: strategies anchored to a *specific,
named, explainable institutional flow event* (Japanese corporate gotobi
payments, WM/Reuters fix rebalancing) have found real, if sometimes
thin, edges. Strategies built on *generic statistical patterns* —
whether internally-invented technical rules or externally-published
academic anomalies studied on different instruments/markets — have
consistently failed to clear this account's costs once tested honestly.
Worth treating as the primary design principle for any future strategy
in this project: look for a specific, named flow or event first, not a
generic pattern, however well-published.

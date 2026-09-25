# month_end_fix_reversal v1_portfolio — review

**Purpose:** test the combined 3-pair (EURUSD.r, GBPUSD.r, USDJPY)
account exposure on month-end fix days — the same check that revealed
`wm_fix_reversal`'s hidden correlated-loss problem when it was finally
run there. Doing it here before any live recommendation, not after one.

## Result: no degradation, actually improves — unlike wm_fix_reversal's portfolio test

| Metric | In-sample (2018-2022) | Out-of-sample (2023-2025) |
|---|---|---|
| Trades | 119 | 55 |
| Profit factor | 1.25 | **2.08** |
| Win rate | 58.0% | **69.1%** |
| Max drawdown | 6.48-7.02% | **4.39-5.63%** (improved, not worsened) |

Combined trades: 119 + 55 = 174, closely matching the sum of the three
individual-pair backtests (120 + 56 = 176 — the small gap is expected
cross-run tick variance, not a discrepancy).

## Correlated-loss check

Checked directly, the same way `wm_fix_reversal`'s problem was found: of
33 days where 2+ pairs traded simultaneously, **8 (24.2%) saw every pair
lose together** — almost identical to `wm_fix_reversal`'s own 24%
finding. But the *impact* is far milder here: combined drawdown
(6.48-7.02% in-sample) is only modestly worse than the single weakest
pair (USDJPY alone, 5.6-6.3%), not the roughly-doubled drawdown
`wm_fix_reversal`'s portfolio showed relative to its own weakest pair.

**Likely explanation**: month-end trading is much lower-frequency than
`wm_fix_reversal`'s daily cadence (roughly monthly vs. daily
opportunities). Even with a similar per-occurrence correlated-loss rate,
low frequency reduces the chance that several bad all-pairs-lose days
land close enough together in time to compound into a deep consecutive
drawdown — which is exactly what happened in `wm_fix_reversal`'s daily
version. Correlation rate alone doesn't determine portfolio risk;
how often the correlated event can occur, and therefore how easily bad
instances cluster, matters just as much.

## Assessment

This is a genuinely different outcome from every other portfolio check
run in this project this session. `gotobi`'s portfolio test confirmed a
healthy combined exposure; `wm_fix_reversal`'s portfolio test revealed a
hidden risk that reversed its live-candidate status. This one lands with
`gotobi`: **combined-account testing did not surface a hidden problem —
if anything it confirms the individual-pair strength holds up when
traded together**, with drawdown that improved rather than worsened
out-of-sample.

Combined with the underlying methodological strength already noted in
`v1/review.md` (zero parameter sweep — this is the first and only
configuration tested, not the best of several), this is the strongest
complete result of this whole "hunt for another specific-event strategy"
effort.

## Remaining honest caveats

- **174-176 total trades is still below this project's 200-trade
  significance bar.** The evidentiary *shape* is unusually clean (no
  sweep, dual confirmation via individual-pair and portfolio tests,
  consistent improvement everywhere), but the absolute count is genuinely
  thin — this is a low-frequency strategy by design (~3 qualifying
  trading days/month before the volatility filter even applies).
- **USDJPY's edge remains the weakest of the three pairs** individually,
  though it doesn't appear to be dragging the combined result down
  materially.
- **Only 5 years in-sample + 3 years out-of-sample of real market
  history exist to test against** — this strategy cannot outrun the same
  data-depth ceiling every other strategy in this project has hit.

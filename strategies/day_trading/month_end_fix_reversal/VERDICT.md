# month_end_fix_reversal — live-readiness verdict

**Version validated:** v1 (reuses `wm_fix_reversal` v2's already-locked
mechanism unchanged, adding one pre-specified calendar filter — trade
only within 3 calendar days of month-end — chosen from external research
before any results were seen, not selected from a swept range). EURUSD.r,
GBPUSD.r, USDJPY, each backtested independently and as a true combined
3-pair portfolio (`v1_portfolio/`, same pattern as `gotobi`'s own
portfolio harness).

## Evidence summary

- **Methodologically clean, unlike several other strategies tested this
  session**: this is the first and only configuration tested — no
  parameter sweep was performed. Every prior "strong in-sample, fails
  out-of-sample" case in this project (`wm_fix_reversal` v1,
  `overlap_deviation_scalp` v1-v4) came from sweeping several thresholds
  and locking whichever looked best, a process that produces
  better-looking numbers as the sample shrinks independent of real edge.
  This result carries none of that risk.
- **In-sample (2018-2022), per pair**: EURUSD PF 1.12 (35 trades), GBPUSD
  PF 1.67 (37 trades), USDJPY PF 1.14 (48 trades). Combined portfolio: PF
  1.25 (119 trades), max drawdown 6.48-7.02%.
- **Out-of-sample (2023-2025, used once), per pair**: every single pair
  *improved*, no exceptions — EURUSD PF 2.21 (19 trades), GBPUSD PF 2.05
  (21 trades), USDJPY PF 1.42 (16 trades). Combined portfolio: PF 2.08
  (55 trades), max drawdown 4.39-5.63% — **lower than in-sample**, not
  higher.
- **Combined-account exposure tested directly, unlike the individual-pair
  numbers alone could show**: 24.2% of days with 2+ pairs trading saw
  every pair lose together (nearly identical to `wm_fix_reversal`'s own
  24% finding), but the drawdown *impact* stayed mild — only modestly
  worse than the single weakest pair (USDJPY), not doubled the way
  `wm_fix_reversal`'s portfolio was. Likely explanation: month-end's
  roughly-monthly frequency gives correlated-loss days far less chance
  to cluster into a deep consecutive drawdown than `wm_fix_reversal`'s
  daily cadence did.

## Verdict: Ready for live at reduced size — genuinely strong evidence, but still a thin absolute sample

**This is the cleanest positive result produced in this project's
"hunt for another specific-event strategy" effort** (which discarded
three scalping lines and one academic-literature day-trading attempt
before this). No sweep, consistent improvement across every pair and at
the portfolio level, and a combined-account check that resolved
favorably rather than surfacing a hidden problem the way it did for
`wm_fix_reversal`.

**Two reasons this isn't an unqualified "go":**

1. **Absolute trade count remains thin** — 174-176 combined trades across
   the full 8-year test window, still under this project's own 200-trade
   significance bar, purely because this strategy only gets ~3 qualifying
   calendar days a month before the volatility filter narrows it further.
   The evidentiary *quality* is unusually clean for this project, but
   clean process doesn't manufacture more historical occurrences to test
   against — there's a hard data-depth ceiling here that more
   sophisticated analysis can't remove.
2. **Live execution quality at the fix is the one thing backtesting
   can't verify** — same category of risk flagged in `gotobi`'s own
   verdict. The WM/Reuters 4pm fix is a well-known, heavily-traded,
   published event; whether real fills during month-end (when this
   project's own research says institutional flow is at its most
   concentrated, i.e. likely the most crowded and highest-slippage
   moment of the whole month) match the historical tick replay closely
   enough for this edge to survive is unverifiable without live data.

**Recommendation:** go live, but start with EURUSD.r and GBPUSD.r only
(the two stronger, lower-drawdown pairs) at reduced size for the first
2-3 month-end cycles, specifically to confirm real fills match backtest
assumptions before adding USDJPY (the weakest of the three) and scaling
to full size. Given this strategy trades only ~3 times a month, "the
first 2-3 month-end cycles" is a meaningfully longer real-world
observation period than it sounds — closer to 2-3 months of calendar
time than 2-3 trading days.

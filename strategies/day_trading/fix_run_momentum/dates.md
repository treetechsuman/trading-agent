# fix_run_momentum — date ranges

- **In-sample (optimization):** 2018.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same split used across every other day_trading strategy in this project
(gotobi, month_end_fix_reversal, wm_fix_reversal, nfp_fade,
yen_fiscal_repatriation, london_breakout_retest) for cross-strategy
comparability. All parameter sweeps and logic iteration happen only
against the in-sample range. Out-of-sample is used once, unmodified, as a
final check. No strategy-specific reason to deviate from this precedent
was found (EURUSD.r/GBPUSD.r/USDJPY tick-history depth was already
confirmed adequate from this start date by `gotobi` and
`month_end_fix_reversal`'s own backtests on the same three symbols).

## Broker-clock conversion note
The WM/Reuters fix is defined in **London local time** (16:00:00) for all
three symbols traded here (this is a London-session event, not
pair-specific/Tokyo-session like `gotobi`). Reusing `wm_fix_reversal`'s
already-verified conversion: this broker's server time (EET/EEST) shifts
DST on the same calendar dates as UK/EU clocks, and is always exactly 2
hours ahead of London time in both the winter and summer halves of the
year (EET UTC+2 vs GMT UTC+0; EEST UTC+3 vs BST UTC+1 — same 2h gap
either way). So the broker-clock entry time is a flat, constant London
time + 2 hours, year-round: **18:00:00 server time for the 16:00:00
London fix**, for EURUSD.r, GBPUSD.r, and USDJPY alike. Re-verify this
assumption if UK/EU DST rules ever diverge from each other again (same
caveat wm_fix_reversal's dates.md already flags).

# wm_fix_reversal — date ranges

- **In-sample (optimization):** 2017.08.01 – 2022.12.31 (extended from the
  original 2018.01.01 start on 2026-09-22, after a parameter sweep and
  yearly breakdown at the locked threshold left only 84 in-sample trades
  -- well below this project's 200-trade significance bar. Probed this
  broker's EURUSD.r tick history and found clean "every tick" data only
  starts ~2017.07.31 -- data further back exists but is too sparse,
  producing same-tick garbage trades (same issue independently found for
  the JPY crosses in `gotobi`, apparently a broker-wide history cutover
  around mid-to-late 2017). This is as far back as this in-sample range
  can be pushed on this broker.)
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same split as `london_range_fade` and `gotobi`, for cross-strategy
comparability. All parameter sweeps and logic iteration happen only
against the in-sample range. Out-of-sample is used once, unmodified, as a
final check.

## Broker-clock conversion note
The WM/Reuters fix is defined in **London local time** (16:00:00), which
observes its own GMT/BST daylight-saving schedule. This broker's server
time (EET/EEST) currently shifts DST on the *same* calendar dates as
UK/EU clocks (last Sunday of March / last Sunday of October), and EET is
always exactly 2 hours ahead of London time through both the winter and
summer halves of the year (EET UTC+2 vs GMT UTC+0; EEST UTC+3 vs BST
UTC+1 — same 2h gap either way). So unlike `gotobi` (Tokyo doesn't
observe DST, so its UTC offset to this broker needed a month-based
branch), **this strategy's broker-clock entry time is a flat, constant
London time + 2 hours, year-round: 18:00:00 server time for the 16:00:00
London fix.** Worth re-verifying this assumption if UK/EU DST rules ever
diverge from each other again.

# FP Markets server clock — which DST rule? (checked 2026-10-17)

## Answer: (a) NY close + 7. The server follows **US** DST, not EU DST.

Server = UTC+3 from the 2nd Sunday of March to the 1st Sunday of November,
and UTC+2 otherwise. Server midnight is always 17:00 New York.

So during the two US/EU mismatch windows each year, the server is UTC+3
while London is on GMT:
- 2nd Sun Mar → last Sun Mar
- last Sun Oct → 1st Sun Nov

In those weeks the London 4pm fix lands at **19:00 server, not 18:00**.
The EET/EEST assumption in older `dates.md` files (wm_fix_reversal,
nfp_fade) is wrong for those weeks. The `fix_w_drift` v1 spec's
"NY close + 7" assumption is correct.

## Method

The probe EA is `v1/strategy.mq5`. It never trades. It ran in the Strategy
Tester only (Model=4 real ticks, EURUSD.r, Tester account login), and no
other terminal64 was running. It records one row per server minute: tick
count, min/max spread, and bid range.

It ran over 16 windows: Mar 1–Apr 7 and Oct 18–Nov 12 for every year
2018–2025 (`run_all.sh`; per-run configs/reports are in `v1/runs/`). The raw
CSVs are in `%APPDATA%\MetaQuotes\Terminal\Common\Files\server_clock_<year>_<season>.csv`.
They are outside the repo and are not committed.

Weekdays were classified as "mismatch" (US on DST, EU not) or "normal" by
`analyze.py`, with output in `analysis_output.txt`. `excess.py`, with
output in `excess_output.txt`, runs the per-year, baseline-normalized
version of the checks.

## Evidence

**1. Rollover spread spike (decisive).** The widest spread around the
daily rollover lands at **00:00 server on every Tue–Fri of every year**,
mismatch weeks included. Comparing the 23:xx and 00:xx maxima day by day
gives:

| Days | Spike at 23:xx | Spike at 00:xx |
|---|---|---|
| All 272 days | 0 | 272 |
| Of which mismatch days | 0 | 112 |

An EET server would show this spike at 23:00 server during mismatch
weeks, because NY 17:00 = 21:00 UTC = 23:00 EET.

**2. London-fix tick spike moves to 19:00 in mismatch weeks.**

Mean ticks per minute across all years:

| Server time | Normal weekdays | Mismatch weekdays |
|---|---|---|
| ~18:50 (baseline) | ~105 | ~150 |
| 18:00 | **205** | 170 |
| 19:00 | 125 | **235** |

In mismatch weeks, the 18:57–19:00 burst looks exactly like the
17:57–18:00 burst on normal days.

Day by day, the bigger tick burst landed as follows:

| Days | 18:00 bigger | 19:00 bigger |
|---|---|---|
| Normal days | 199 | 14 |
| Mismatch days | 32 | 108 |

The 2018–2021 mismatch weeks are near-unanimous for 19:00. The fix spike
is a weaker signal from 2022 on, and some of those mismatch weeks are
mixed: autumn 2022, spring 2023 and spring 2025. In those years the
rollover check (1) is still 100%, so the rule did not change.

**3. Weekend open: not informative.** The first tick after the weekend is
always Monday 00:00:00–00:01 server. The broker's symbol session starts
at server midnight, so this can't tell the two clocks apart.

## month_end_fix_reversal v3 (live; window 17:55–18:02 server, flat year-round)

On mismatch days, 18:00 server = **15:00 London**, one hour before the fix.
On those days the EA:
- measures the 14:55–15:02 London move;
- fades it at 18:02 server;
- is flat by 18:32 server (15:32 London), before the real fix at 19:00 server.

So those are not fix trades at all. Those days also feed non-fix samples
into the 20-day adaptive spike history.

Weekday month-end days (last 3 calendar days) in mismatch weeks, from
`check_live_eas.py` (output in `check_live_eas_output.txt`):

| Year | Mismatch month-end days |
|---|---|
| 2018 | Oct 29, 30, 31 |
| 2019 | Mar 29; Oct 29, 30, 31 |
| 2020 | Oct 29, 30 |
| 2021 | none |
| 2022 | Oct 31 |
| 2023 | Oct 30, 31 |
| 2024 | Mar 29; Oct 29, 30, 31 |
| 2025 | Oct 29, 30, 31 |
| **2026** | **Oct 29 (Thu), Oct 30 (Fri) — 12–13 days from today, live** |
| 2027 | none |

That's about 2–4 eligible days a year, nearly all in late October. The
mis-measured history samples are more: every mismatch weekday, about 15 a
year.

Trades the backtests opened on mismatch days, all at 18:02 server:

| Symbol | Trades on mismatch days | Net P&L | Dates (P&L) |
|---|---|---|---|
| EURUSD.r | 3 of 54 | +43.19 | 2024-03-29 (−26.73), 2024-10-30 (+94.74), 2024-10-31 (−24.82) |
| GBPUSD.r | 3 of 58 | −63.42 | 2024-10-30, 2024-10-31, 2025-10-29 |
| USDJPY | 4 of 63 | +2.45 | 2019-03-29, 2020-10-30, 2023-10-30, 2024-10-31 |

Every one of these is in the validation (out-of-sample) set except
USDJPY's 2019 and 2020 trades, which are in-sample.

Impact on the backtest stats is negligible: 10 of 175 trades, net
about −18. But on those days the live EA trades a window that isn't the
fix, and the next two such days are **2026-10-29 and 2026-10-30**. The
backtest is internally consistent with this behavior (the Tester uses the
same server clock), so the published PF already includes these 10
non-fix trades.

## gotobi v2 (live; 03:45 server Mar–Oct, 02:45 Nov–Feb, for 00:45 UTC)

The month-based rule is correct except between Mar 1 and the 2nd Sunday
of March, and between Nov 1 and the 1st Sunday of November. Its source
comment says "server leads UTC by 3h Mar-Oct", which is wrong at both
ends.

- **Early March:** the EA uses 03:45, but the server is still UTC+2. It
  enters at 01:45 UTC (10:45 JST), about 50 minutes **after** the 09:55
  JST Tokyo fix it's trying to front-run.
- **Early November:** the EA uses 02:45, but the server is still UTC+3.
  It enters at 23:45 UTC the previous day (08:45 JST), an hour early, and
  exits at 09:20 JST, before the fix.

Affected gotobi weekdays:

| Year | Dates |
|---|---|
| 2017 | Mar 10 |
| 2018 | Mar 5 |
| 2019 | Mar 5 |
| 2020 | Mar 5 |
| 2021 | Mar 5, Mar 10, Nov 5 |
| 2022 | Mar 10 |
| 2023 | Mar 10 |
| 2024 | Mar 5 |
| 2025 | Mar 5 |
| 2026 | Mar 5 (already passed) |
| 2027 (next live) | Mar 5, Mar 10, Nov 5 |

The v1 backtests traded all of these at the mistimed hour. USDJPY had 11
trades, net +90.43, of which +92.38 is 2025-03-05 alone. Without that day
the mistimed trades are about flat. This is far from what drives the
edge, but those days are not a gotobi trade as designed. Nothing changes
live before 2027-03-05.

## Not done (by design)
No strategy, spec, registry, or live-side file was touched, and nothing
was committed. Possible fixes are for the user to decide:
- Make month_end_fix_reversal's fix hour 19 on mismatch days.
- Switch gotobi's summer/winter boundary to the US DST dates.
- Re-run the affected backtests.
- Correct the wm_fix_reversal/nfp_fade `dates.md` notes.

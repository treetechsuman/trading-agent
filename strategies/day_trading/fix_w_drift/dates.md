# fix_w_drift — date ranges

- **In-sample (optimization):** 2015.01.01 – 2019.12.31
- **Out-of-sample (validation):** 2020.01.01 – 2025.12.31

Both ranges were **confirmed by the user on 2026-10-17** (relayed by the
orchestrator), as CLAUDE.md requires for a new strategy family. This
deliberately departs from the project's usual 2018-2022 / 2023-2025 split:

- **In-sample 2015-2019 falls inside the source paper's own sample.**
  Krohn, Mueller & Whelan (JF 2024) use 1999-2019. So in-sample is a
  *replication check*: does the documented pattern show up on this
  broker's prices, with this account's real costs, in years where the
  paper says it existed?
- **Out-of-sample 2020-2025 comes after publication.** The working paper
  was public from about 2019-2020. This window is the real test of whether
  the effect survived being published. Use it **once, unmodified**. If it
  comes out weak, report that as the finding. Do not re-tune against it.

## Data-availability caveat: Backtester must check this before the first full run

This project has found, independently and more than once
(`wm_fix_reversal/dates.md`, `wm_fix_reversal/STRATEGY.md`,
`backtester/lessons.md`, `gotobi/v1/review.md`), that this broker's
**clean every-tick history for EURUSD.r/GBPUSD.r starts only around
2017.07.31**. Earlier data exists but is sparse enough to produce
same-tick garbage trades. This strategy enters and exits at fixed clock
times, so sparse ticks would directly corrupt its entry and exit prices
(the fill would be whatever stale tick happens to sit nearest 09:00 or
18:00).

**Required first step (Backtester):** probe tick density for both symbols
on a short 2015 window (for example 2015.03.02-2015.03.13) and a short 2016
window before running the full in-sample range. Look for normal M1 tick
counts in the 09:00-16:15 and 18:00-23:45 server windows and no
same-second entry/exit pairs.

- If 2015-2017.07 is clean, run the confirmed range as written.
- If it is sparse, as the earlier findings predict, **stop and ask the
  user through the orchestrator** whether to run in-sample as
  **2017.08.01 – 2019.12.31**. That is a subset of the confirmed range,
  still inside the paper's sample, and still about 600 trades per leg per
  pair, above the 200-trade bar. Do not silently shorten or extend the
  user-confirmed range, and do not fall back to a non-tick model to cover
  the gap.

## Broker-clock assumption: verify before trusting any result

The spec treats the server clock as **New York close + 7**: server
00:00 = 17:00 US Eastern all year, following **US** DST rules (this was the
basis given for this strategy, and is consistent with
`live-manager/lessons.md`'s note that gotobi's March switch is wrong
"between 1 Mar and the US DST date"). **Older strategy docs in this repo
assume the opposite**: an EET/EEST clock that follows **EU** DST
(`wm_fix_reversal/dates.md`, `fix_run_momentum/dates.md`,
`nfp_fade/dates.md`). The two assumptions agree except during the
EU/US DST-mismatch weeks, which are exactly the days this spec shifts.
nfp_fade's earlier "DST spot-check" doesn't settle the question: it read
the EA's own entry timestamps, which only echo the EA's computed time.

v1/spec.json (`dst_handling.verification`) defines an empirical check
from price data: when does each week's first tick arrive during a
mismatch week, and where does the London-fix tick-volume spike land. It
must pass before any in-sample result is reviewed.

## Mismatch periods in the test window (server-date ranges, inclusive)

US DST starts on the 2nd Sunday of March and ends on the 1st Sunday of
November. EU DST starts and ends on the last Sunday of March and of
October. The mismatch runs [US start, EU start) and [EU end, US end).

| Year | Spring mismatch | Autumn mismatch |
|---|---|---|
| 2015 | Mar 08 – Mar 28 | Oct 25 – Oct 31 |
| 2016 | Mar 13 – Mar 26 | Oct 30 – Nov 05 |
| 2017 | Mar 12 – Mar 25 | Oct 29 – Nov 04 |
| 2018 | Mar 11 – Mar 24 | Oct 28 – Nov 03 |
| 2019 | Mar 10 – Mar 30 | Oct 27 – Nov 02 |
| 2020 | Mar 08 – Mar 28 | Oct 25 – Oct 31 |
| 2021 | Mar 14 – Mar 27 | Oct 31 – Nov 06 |
| 2022 | Mar 13 – Mar 26 | Oct 30 – Nov 05 |
| 2023 | Mar 12 – Mar 25 | Oct 29 – Nov 04 |
| 2024 | Mar 10 – Mar 30 | Oct 27 – Nov 02 |
| 2025 | Mar 09 – Mar 29 | Oct 26 – Nov 01 |

The ranges are hand-derived from the calendar rules. The US
first-Sunday-of-November dates match `nfp_fade/dates.md`'s independently
checked 2017-2025 table. EA Coder computes these per year from the rules,
not from this table; the table is for cross-checking.

## Symbols

EURUSD.r and GBPUSD.r, M1, one independent single-symbol run per pair.
These are the paper's two European-leg currencies with positive Table IX
results. JPY is excluded because the paper finds the yen does the
opposite on these windows.

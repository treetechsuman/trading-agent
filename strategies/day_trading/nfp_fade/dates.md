# nfp_fade — date ranges

- **In-sample (optimization):** 2017.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Standard split, matching `gotobi`/`wm_fix_reversal`/`month_end_fix_reversal`/
`yen_fiscal_repatriation`, for cross-strategy comparability. Same known
caveat as those strategies: this broker's clean tick history for
EURUSD.r/GBPUSD.r/USDJPY starts roughly mid-to-late 2017 (broker-wide
history cutover, independently found in `wm_fix_reversal`'s and `gotobi`'s
own investigations) — expect 2017 to contribute few or no trades and treat
that as a known data-availability artifact, not a strategy finding. All
parameter iteration (there is none planned for v1 — see spec.json) would
only ever happen against the in-sample range; out-of-sample is used once,
unmodified.

## Origin

Built 2026-09-23 per the user's explicit approval to formalize NFP-spike
fading into a strategy, based on research presented and confirmed before
this spec was written:

- **Linda Raschke & Larry Connors, "Street Smarts" (1996)** — describes a
  "News Strategy" used by professional bond/currency traders: fade the
  market's initial, often overdone reaction to a scheduled 8:30am ET
  economic release, on the premise that the fastest/least-informed
  reaction (headline algos, momentum chasers) frequently overshoots before
  slower, more considered positioning brings price back.
- **Current practitioner sources** independently describe the same
  fade-the-initial-overreaction structure specifically around NFP release
  events — corroboration for the specific-report application, not just
  the general "fade scheduled news" framing.

## How this differs structurally from wm_fix_reversal / month_end_fix_reversal

Both prior "measure a spike, then fade it" strategies in this project
(`wm_fix_reversal`, `month_end_fix_reversal`) fade the **WM/Reuters 4pm
London FIX** — a mechanical, technical liquidity event. A large, known
volume of orders is contractually required to execute at one reference
rate at one fixed clock time every trading day; the resulting spike is a
structural/technical artifact of concentrated order execution, not a
reaction to new information. Its size varies with the day's rebalancing
flow, but there is no "was the fix a surprise" dimension — it happens
every day regardless.

**NFP is fundamentally different in character**: it is a scheduled
**economic data release** (once a month, not once a day) whose price
impact depends on the **surprise magnitude versus the consensus
forecast** — a data-driven, information-content-dependent event, not a
mechanical execution event. Because market participants are reacting to
genuinely new information rather than executing pre-committed rebalancing
orders, NFP's moves are typically **larger, more binary, and more
violent** than a fixing spike: a big surprise can produce a real,
sustained repricing (not just a reversible liquidity blip), while a
near-consensus print produces almost no reaction at all. This difference
is why this spec's every numeric parameter (measurement window, threshold
multiplier, SL/TP ratio, position size) was independently re-derived
rather than copied from `wm_fix_reversal`'s locked values — see
`v1/spec.json`'s `*_reasoning` fields for the full reasoning behind each.

## Key operational decisions (summary — full reasoning in spec.json)

- **Measurement window: T+0 to T+10 minutes** (release to release+10min).
  Longer than `wm_fix_reversal`'s ~7-minute fix-bracketing window because
  NFP's initial algorithmic/headline reaction typically keeps developing
  for several minutes, unlike a fix's near-instantaneous print. Entering
  at T+10 (not T+0) also sidesteps the worst of the release-instant
  spread-widening spike.
- **Threshold: `MinSpikeSizePipsFloor=15`, `MinSpikeVsAvgMultiplier=1.2`**
  (vs. `wm_fix_reversal`'s floor=5, multiplier=2.0). NFP's calendar
  trigger already selects for scheduled, potentially market-moving events
  — unlike the fix, which happens on every one of ~250 trading days/year
  and needs a strict filter to separate genuine large-flow days from
  routine noise. A 2.0x bar on an already-event-selected, already
  low-frequency (~12/year/pair) sample would over-filter it toward
  statistical insignificance; 1.2x only screens out near-consensus prints
  with little real reaction.
- **SL/TP: `SLMultiplier=1.0`, `TPMultiplier=1.3`** (vs. their 1.0/1.0).
  Stop kept disciplined at 1x (a fade bet needs a fast exit if the move
  turns out to be a genuine trend-confirming surprise, not more room —
  same lesson `yen_fiscal_repatriation` learned the hard way). Target
  extended to 1.3x because NFP reversions, per practitioner accounts, more
  often overshoot back through the pre-release level than a fixing
  reversion does (fix reversions return to a mechanical rate-driven
  equilibrium; NFP reversions are driven by momentum unwind and second-
  wave fundamental repositioning, which can carry further).
- **Position sizing: 0.5% of equity/trade** (vs. their 1.0%). This is an
  unvalidated first attempt at this event category (unlike the fix
  strategies, which had already proven the mechanism before being
  extended), and NFP's larger measured spikes mechanically produce wider
  stop distances — 0.5% keeps dollar risk proportionate rather than
  compounding "bigger move" with "bigger risk-per-trade."
- **Hold-time backstop: 60 minutes** after the measurement window closes
  (vs. their 30) — NFP's larger initial move plausibly needs more time to
  fully mean-revert than a fix spike does.

## US-Eastern-DST × broker-server-DST combined conversion — read carefully

This is the highest-risk part of this spec to get wrong, and is a
genuinely separate problem from `gotobi`/`yen_fiscal_repatriation`'s own
broker-clock handling, because **two independent daylight-saving
calendars are in play simultaneously**, and they change on different
calendar dates in most years:

1. **US federal DST** (governs when 8:30am US Eastern = what UTC time):
   - **EST (UTC-5, winter):** from the **first Sunday of November**
     through the **second Sunday of March**.
   - **EDT (UTC-4, summer):** from the **second Sunday of March** through
     the **first Sunday of November**.
2. **Broker server DST** (this broker's server clock, presumed EU/Cyprus-
   based EET/EEST, per the already-validated pattern used in
   `gotobi`/`yen_fiscal_repatriation`'s hardcoded "03:45 server Mar-Oct /
   02:45 server Nov-Feb" table, which implies a UTC+3 summer / UTC+2
   winter broker offset):
   - **EET (UTC+2, winter):** from the **last Sunday of October** through
     the **last Sunday of March**.
   - **EEST (UTC+3, summer):** from the **last Sunday of March** through
     the **last Sunday of October**.

**Important deviation from simply reusing gotobi's table**: `gotobi`'s
table is a whole-calendar-month simplification ("all of March = summer
server time"), which is imprecise for the first ~3-4 weeks of March and
October (the real EU cutover happens near the end of those months, not
the start) — a simplification that is presumably tolerable for `gotobi`'s
own trading days (5th/10th/15th/20th/25th/month-end, spread across the
whole month). **NFP's trigger day is always in days 1-7 of the month**,
which for March and October is **always before** the real EU cutover date
(day ~25-31) — so blindly applying gotobi's whole-month simplification
would put March/October NFP on the *wrong side* of the broker's own DST
transition (a full 1-hour error). This spec instead uses the **exact**
last-Sunday-of-March / last-Sunday-of-October rule for the broker side, to
avoid manufacturing an error gotobi's own trading calendar doesn't happen
to expose.

### The algorithm (code-friendly)

For a given NFP trigger date (the computed first Friday of the month):

1. Compute `first_friday` (the trigger date itself).
2. **US side**: compute `second_sunday_of_march` and
   `first_sunday_of_november` for that year.
   - If the trigger month is **Apr-Oct**: US is EDT (UTC-4). (Always —
     these months sit fully inside the DST period.)
   - If the trigger month is **Dec-Feb**: US is EST (UTC-5). (Always.)
   - If the trigger month is **March**: US is **always EST (UTC-5)** —
     `first_friday` (day 1-7) is mathematically always before
     `second_sunday_of_march` (day 8-14, since the earliest possible
     second Sunday is the 8th).
   - If the trigger month is **November**: **compare `first_friday` to
     `first_sunday_of_november` for that year** — if `first_friday` is
     *after* `first_sunday_of_november`, US has already switched to EST
     (UTC-5); otherwise it's still EDT (UTC-4). **This is NOT a rare edge
     case — it varies year to year and the EDT-still case is actually the
     more common of the two (see the 9-year check below).**
3. Convert 8:30am ET to UTC using the US-side offset from step 2.
4. **Broker side**: compute `last_sunday_of_march` and
   `last_sunday_of_october` for that year.
   - If the trigger month is **Apr-Sep**: broker is EEST (UTC+3). (Always
     — fully inside the EU summer period.)
   - If the trigger month is **Nov-Feb**: broker is EET (UTC+2). (Always
     — fully inside the EU winter period; October's cutover has already
     passed by November.)
   - If the trigger month is **March**: broker is **always EET (UTC+2)**
     — `first_friday` (day 1-7) is always before `last_sunday_of_march`
     (day ~25-31).
   - If the trigger month is **October**: broker is **always EEST
     (UTC+3)** — `first_friday` (day 1-7) is always before
     `last_sunday_of_october` (day ~25-31).
5. Add the broker-side offset from step 4 to the UTC time from step 3 to
   get server time.

### Resulting server-time table (derived, not assumed)

| Trigger month | US side | Broker side | UTC release | **Server time** |
|---|---|---|---|---|
| Jan | EST (-5) | EET (+2) | 13:30 | **15:30** |
| Feb | EST (-5) | EET (+2) | 13:30 | **15:30** |
| Mar | EST (-5) always | EET (+2) always | 13:30 | **15:30** |
| Apr | EDT (-4) | EEST (+3) | 12:30 | **15:30** |
| May | EDT (-4) | EEST (+3) | 12:30 | **15:30** |
| Jun | EDT (-4) | EEST (+3) | 12:30 | **15:30** |
| Jul | EDT (-4) | EEST (+3) | 12:30 | **15:30** |
| Aug | EDT (-4) | EEST (+3) | 12:30 | **15:30** |
| Sep | EDT (-4) | EEST (+3) | 12:30 | **15:30** |
| Oct | EDT (-4) always | EEST (+3) always | 12:30 | **15:30** |
| **Nov** | **EDT (-4) in most years** / EST (-5) in others (compute per year) | EET (+2) always | 12:30 or 13:30 | **14:30 (common) or 15:30 (less common)** |
| Dec | EST (-5) | EET (+2) | 13:30 | **15:30** |

The combined US+broker offset is a constant **+7 hours** from ET to
server time in every case *except* November in years where the US hasn't
yet switched back to standard time by the first Friday — during that
window the broker (already on winter EET since late October) is +6 hours
from ET instead, giving server time **14:30** rather than **15:30**. This
is a well-known, real phenomenon (the ~1-4 week gap each autumn where the
EU has already fallen back but the US hasn't yet) — not a modeling
artifact.

### 9-year hand cross-check of the November case (2017-2025, this project's full test window)

| Year | Nov 1 weekday | First Friday (NFP date) | First Sunday (US DST end) | Friday vs. Sunday | US offset at NFP | Server time |
|---|---|---|---|---|---|---|
| 2017 | Wed | Nov 3 | Nov 5 | before | EDT (-4) | 14:30 |
| 2018 | Thu | Nov 2 | Nov 4 | before | EDT (-4) | 14:30 |
| 2019 | Fri | Nov 1 | Nov 3 | before | EDT (-4) | 14:30 |
| 2020 | Sun | Nov 6 | Nov 1 | **after** | EST (-5) | 15:30 |
| 2021 | Mon | Nov 5 | Nov 7 | before | EDT (-4) | 14:30 |
| 2022 | Tue | Nov 4 | Nov 6 | before | EDT (-4) | 14:30 |
| 2023 | Wed | Nov 3 | Nov 5 | before | EDT (-4) | 14:30 |
| 2024 | Fri | Nov 1 | Nov 3 | before | EDT (-4) | 14:30 |
| 2025 | Sat | Nov 7 | Nov 2 | **after** | EST (-5) | 15:30 |

Each row checked against real, independently-known US DST end dates for
that year (first Sunday of November) — all nine matched the rule
mechanically derived above. **7 of 9 years land in the 14:30 "still EDT"
case; only 2020 and 2025 land in the 15:30 "already EST" case** — this
means the November edge case is the *majority* outcome for this project's
test window, not a rare corner case, and must be computed per-year in the
EA, not hardcoded to either value.

### Confidence level — explicit flag

- **High confidence** in the algorithm itself: the US "second Sunday of
  March / first Sunday of November" and EU "last Sunday of March / last
  Sunday of October" DST rules are long-standing, well-documented, fixed
  legal rules (US since 2007, EU since the 1990s) — this is deterministic
  calendar math, not a guess, and the 9-year hand-check above matches
  real known US DST transition dates exactly.
- **Moderate-to-high confidence, but not independently re-verified here**,
  that this broker's actual server clock follows the generic EU
  last-Sunday convention in every year of the 2017-2025 test window — this
  is an assumption inherited from `gotobi`/`yen_fiscal_repatriation`'s
  already-in-use hardcoded Mar-Oct/Nov-Feb table (which implies the same
  underlying EU-DST offsets), not a fresh confirmation against this
  broker's actual historical tick timestamps.
- **Explicit ask of Backtester**: before trusting this strategy's
  results, spot-check actual bar timestamps in the downloaded history
  against a few of the specific dates/times derived above — e.g. confirm
  a visible volatility spike at server time **15:30** on 2018.01.05 (Jan),
  **15:30** on 2024.03.08 (Mar), **15:30** on 2024.10.04 (Oct), and
  **14:30** (not 15:30) on 2023.11.03 and 2024.11.01 (the "still EDT"
  November case) — and ideally cross-reference a couple of these against
  the actual published BLS NFP release calendar to also confirm the
  first-Friday calendar rule didn't miss a shifted release date.

## Pairs

EURUSD.r, GBPUSD.r, USDJPY — same three pairs as `month_end_fix_reversal`,
reusing already-validated symbol-naming for this broker. NFP is a USD
event and moves all USD pairs, so this mirrors that strategy's pair
selection rather than `wm_fix_reversal`'s EUR/GBP-only set. One EA,
backtested independently per pair first (own subfolder per pair, matching
`gotobi`/`month_end_fix_reversal`'s layout); a combined-account portfolio
check (same pattern as `gotobi/v1_portfolio`,
`month_end_fix_reversal/v1_portfolio`) should follow once single-pair
results are reviewed, given all three pairs share the same USD-side
trigger and could plausibly correlate on losing days the same way
`wm_fix_reversal`'s pairs did (confirmed correlated but survivable for
`month_end_fix_reversal`; confirmed correlated and NOT survivable for
`wm_fix_reversal`) — check this directly per this project's now-standard
practice rather than assuming either outcome.

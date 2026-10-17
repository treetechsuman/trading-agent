# Research note: next day-trading candidate (2026-10-17)

Desk research only. Nothing has been coded or backtested yet.

## What's already been learned in this project

13 strategies tested. The only ones that survived (gotobi, month_end_fix_reversal)
trade a **specific, named institutional flow** at a fixed clock time. Generic
technical setups (ORB, breakout-retest, sweep reversal, intraday momentum, MA
deviation scalps) all failed after real costs. A further lesson from the fix
work: in a run-then-revert pattern, the reversion half is the tradeable one.

## Recommended candidate: the "fix W" intraday dollar pattern

**Source:** Krohn, Mueller & Whelan, *Foreign Exchange Fixings and Returns
around the Clock*, Journal of Finance 79(1), 2024, 541–578
(doi:10.1111/jofi.13306). G9 currencies, 5-minute data, 1999–2019.

**Finding:** the USD systematically appreciates into each of the three big
fixes (Tokyo 9:55 JST, ECB 14:15 CET, London WM/R 16:00) and depreciates
afterwards. t-stats are 4.5–11.7. Their explanation is dealer inventory risk
from unconditional dollar demand at the fixes. That's a named-flow mechanism,
the same family as this project's winners. Supporting evidence: Ranaldo (SNB
WP 2007-03) and Breedon & Ranaldo (SNB WP 2011-04) find that currencies
depreciate during their own local trading hours, which is the same phenomenon.

**Their tradeable windows (Table IX, ET clock), EUR and GBP:**

| Leg | Window (ET) | Position | EUR gross %/yr (SR) | EUR @50% indicative spread | GBP gross (SR) |
|---|---|---|---|---|---|
| Pre-ECB | 02:00 → 08:15 | long USD (sell EURUSD/GBPUSD) | 8.88 (1.37) | 5.45 (0.76) | 5.79 (0.81) |
| Post-London fix | 11:00 → 17:00 | short USD (buy EURUSD/GBPUSD) | 6.88 (1.23) | 3.19 (0.43) | 6.66 (1.34) |
| Both | | | 15.75 (2.01) | 8.64 (1.03) | 12.45 (1.57) |

JPY is the exception: it loses on the European legs because the yen
appreciates during its own local hours. The Tokyo-fix legs have been flat or
negative for EUR/GBP since around 2013 (their Fig. 7), so the European legs
are the ones to test.

**Back-of-envelope check against this account's costs:** the gross edge is
about 3–4 bps, roughly 3–4 EURUSD pips per leg per day. This account's
round-trip cost is about 0.8 pip (about $2.8/lot/side commission, seen in the
`wm_fix_reversal` journals, plus about 0.2 pip raw spread). Roughly 75% of the
gross would survive, if the pattern still exists. Hedged against that:

- **Decay:** the paper's sample ends in 2019 and the working paper has been
  public since 2019–2020. 2020–2025 is therefore a genuine post-publication
  out-of-sample test. This is the main unknown.
- **Thin per-trade signal:** a 3-pip mean against tens of pips of noise per
  window means win rate will be close to 50% and each trade is close to a coin
  flip. The edge only shows up over hundreds of trades. There will be about
  250 trades per year per leg per pair, well above the 200-trade bar.
- **Exit before NY rollover:** 17:00 ET is rollover, when spreads blow out,
  so close around 16:45 ET.

## Mapping to this broker's server clock

Server time is NY close + 7 (server 00:00 = 17:00 ET all year, and it follows
US DST), so the ET windows map to fixed server times:

- Pre-ECB: sell at 09:00 server, close at 15:15 server.
- Post-London fix: buy at 18:00 server, close at 23:45 server.

For both legs, check the EU/US DST-mismatch weeks (March and late
October/November). The ECB and London fixes move one hour against the
server clock then. **The NY+7 assumption is unverified.** Older dates.md
files (wm_fix_reversal, nfp_fade) assume an EET clock on EU DST dates. If
NY+7 is right, `month_end_fix_reversal`'s flat 17:55–18:02 window falls an
hour early in those weeks. Researcher's fix_w_drift spec makes a price-based
clock check a gate before the first full run.

## Draft spec outline (for Researcher to formalise)

- `day_trading/fix_w_drift`: EURUSD.r and GBPUSD.r, M1, two independent legs
  as inputs (`EnablePreECB`, `EnablePostLondon`) so each can be tested on its
  own.
- Fixed clock entry and exit. No signal filter in v1, so v1 is a pure
  replication. Spread filter: max 1.0 pip at entry. Catastrophe SL only (for
  example 3x the rolling 20-day window range). No TP.
- Fixed fractional risk per trade, plus the standard 15% drawdown hard stop
  and the chart panel.
- Proposed dates: in-sample 2015–2019 (inside the paper's sample, so a
  replication check). Out-of-sample 2020–2025 (post-publication). The user
  must confirm the dates per CLAUDE.md.
- **Live conflict:** `month_end_fix_reversal` trades the same symbols at
  18:00 server on the last three days of the month. Use a distinct magic
  number, and decide whether to skip those days.

## Weaker candidates looked at and not recommended

- **Pre-FOMC dollar drift** (Karnaukh, *The Dollar Ahead of FOMC Target Rate
  Changes*: Sharpe 0.93, about 25 bps per event). It only works when fed funds
  futures signal a move, and that data isn't in MT5. About 8 events a year is
  far below the 200-trade bar. Lee & Wang (RAPS 2025) also find most of the
  drift reverses 12–24 hours after the announcement.
- **10am NY option-expiry pinning:** only broker commentary, no measured
  evidence. Skipped.

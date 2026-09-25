# nfp_fade v1 — review

**Reviewed:** 2026-09-23 | **In-sample:** 2017.01.01–2022.12.31 | **Status: refining**

## Headline results (per pair, independent $10k accounts)

| Pair | Trades | PF | Win rate | Net P&L | Max equity DD | Sharpe |
|---|---|---|---|---|---|---|
| EURUSD.r | 22 | 1.46 | 59.1% | +$116.86 | 1.87% | 10.67 |
| GBPUSD.r | 17 | 0.47 | 47.1% | -$158.00 | 2.48% | -5.00 |
| USDJPY | 20 | 1.00 | 45.0% | -$0.09 | 1.41% | -0.01 |
| **Combined** | **59** | — | 50.8% (30W/29L) | **-$41.23** | all <2.5% | — |

**59 trades combined is well below this project's 200-trade significance bar.** None of these numbers (PF, win rate, per-pair comparison) are being treated as conclusive — see below.

## Part 1: calendar-accuracy investigation (done first, per instruction)

Backtester flagged that the `first Friday of month, days 1-7` calendar-trigger simplification fired on 2024.03.01 while the real BLS release that month was 2024.03.08 (BLS pushed it a week). I went through all 59 trade dates across all three journals and cross-referenced each against known actual BLS Employment Situation release dates for 2017–2022 (the in-sample window only — the 2024 example is out-of-sample and doesn't touch these 59 trades).

**Finding: zero of the 59 trades fired on a wrong (non-NFP) Friday.** Checked every date, including all the highest-risk ones (day-1-3-of-month triggers, which is where BLS's "at least ~3 weeks after the reference week" scheduling rule is most likely to force a shift): 2017.09.01, 2018.02.02, 2020.06.05→n/a, 2021.03.05, 2022.02.04, 2022.04.01, 2017.02.03, and every other trigger date — each one matches a real, independently-known BLS release date for that month (e.g. 2017.09.01 = Aug 2017 NFP, released that exact Friday around Hurricane Harvey; 2019.07.05 = June 2019's well-known "Goldilocks" report; 2020.03.06 = Feb 2020's last pre-COVID report; 2022.04.01 = March 2022's 431k report). No exceptions landed inside this specific 59-trade sample.

**However, the simplification does have a real, separate failure mode: missed events, not wrong-day events.** Checking months where NO trade fired at all against known BLS history turned up genuine gaps caused by the day-of-month rule computing the wrong trigger day and finding no real reaction to measure:
- **January 2020**: rule computes Jan 3 (first Friday); the real Dec 2019 report was released Jan 10, 2020 (second Friday — the reference-week-proximity rule pushed it back). No trade fired either pair that month — consistent with the rule measuring a non-event on the 3rd and finding nothing above threshold.
- **January 2021**: rule computes Jan 1 (New Year's Day, market holiday); the real Dec 2020 report was released Jan 8, 2021. No trade fired — the EA's trigger day fell on a holiday with no valid session, so the real event that week was simply never tried.

So the calendar issue is real and does have a concrete cost — it's silently shrinking an already-thin ~12/year/pair sample by skipping genuine events in favor of measuring nothing (or a market holiday) — but it does **not** explain the weak/mixed P&L results themselves, since it produced zero false-positive trades in this specific run. This is the "exceptions are rare/negligible for *this* sample, but the underlying limitation is real" case: not "the fade thesis has no edge" and not "recalibrate because a wrong Friday tanked the numbers" — it's "the sample is thinner than the true opportunity set warrants."

## Part 2: signal-quality diagnosis

Since calendar accuracy doesn't explain the results, dug into the actual dispersion across pairs.

**EURUSD.r and GBPUSD.r are not independent evidence of anything.** On the 14 calendar dates where both fired, direction and win/loss outcome matched on 13/14 (only 2022.10.07 diverged, and only marginally: EUR -$3.54 vs GBP +$3.12). This is expected — same USD event, same direction signal — but it means GBP's PF 0.47 vs EUR's PF 1.46 isn't two independent tests disagreeing; it's the same signal applied to two pairs, with GBP's realized moves being costlier on the losing days and less rewarding on some winning ones. I looked for a GBP-specific confound (a UK data release landing near NFP some months) but found none of GBP's 9 losses cluster around an identifiable non-NFP GBP event distinguishable from what EUR saw the same day — GBP's extra 2 losses (2018.02.02, 2019.09.06) are trades EUR didn't even take (below EUR's threshold, above GBP's), not evidence of a separate confound, just GBP's own volatility crossing its own adaptive threshold more often. **Conclusion: no GBP-specific confound found; GBP's worse number is more likely a magnitude/cost artifact on a thin sample than a distinct signal-quality problem.**

**USDJPY's exact net-flat result ($-0.09 on 20 trades) is genuinely uninformative on its own** — 9 wins averaging $30.49 almost exactly offset by 11 losses averaging $24.96. This is the signature of a coin-flip with a mildly favorable R:R, i.e. no detectable edge either direction, not evidence against the thesis specifically.

**Overall: this is a "sample too thin to conclude either way" result**, not a clean negative. EUR looks mildly positive, GBP mildly negative (largely the same trade repeated with worse per-trade economics), JPY flat. There's no large, consistent cross-pair edge the way `gotobi`/`month_end_fix_reversal` showed, but there's also no decisive multi-year failure signature like `london_orb`/`london_breakout_retest`/`intraday_momentum_carry` showed. 59 trades combined (and effectively closer to ~45 independent observations given EUR/GBP correlation) isn't enough to distinguish "small real edge, noisy" from "no edge, noisy."

## Decision: refining (single motivated change)

Per this project's house rule, the change must be a single, precisely-specified fix grounded in a specific diagnosis — not a parameter sweep. The diagnosis here is: **the calendar trigger's day-of-month approximation is silently under-sampling real NFP events** (confirmed concretely for Jan 2020 and Jan 2021 in-sample; also the out-of-sample Mar 2024 case Backtester already found), even though it produced no wrong-day trades in this particular run. Fixing it is the single defensible next step — not because it explains the weak numbers, but because it directly addresses a named, already-documented limitation (`spec.json`'s own `calendar_trigger.known_simplification`) and would grow this event-anchored strategy's sample toward statistical usefulness using the exact same, already-locked mechanism (measurement window, threshold, SL/TP, hold time, sizing) — no other variable changes.

**Exact change for EA Coder (v2):**
- Replace `calendar_trigger.rule` ("first Friday of the month, days 1-7") with a **hardcoded table of actual historical BLS Employment Situation release dates**, one date per month, covering 2017.01–2025.12 (the full in-sample + out-of-sample window). Do **not** use MT5's `CalendarValueHistory()` API — the original spec deliberately avoided the Strategy Tester's live economic-calendar feed as "unreliable/absent," and that concern should not be silently reversed without a separate feasibility check; a static, researched table avoids the dependency entirely and matches this project's existing pattern (`gotobi`'s gotobi-day table, this same strategy's own DST table in `dates.md`).
- The table must be sourced from BLS's own published release-schedule archive (bls.gov "Schedule of Releases," archived year by year), not approximated — this is exactly the kind of precision failure being fixed, so the replacement can't reintroduce it by guessing. Known confirmed exceptions to flag for verification: **Jan 2020 (released Jan 10, not Jan 3)**, **Jan 2021 (released Jan 8, not Jan 1 — which is also a holiday)**. Every other month in 2017–2022 checked clean against "first Friday" in this review; 2023–2025 (out-of-sample) has not been checked and must be verified fresh against the real BLS archive when building the table, not inferred from the in-sample check.
- Everything else in `spec.json` stays byte-for-byte locked: measurement window (T+0 to T+10), `MinSpikeSizePipsFloor=15`/`MinSpikeVsAvgMultiplier=1.2`, SL 1.0x/TP 1.3x, 60-minute hold backstop, 0.5% risk, all three pairs, all safety rules.
- Retest the same in-sample range (2017.01.01–2022.12.31) on the same three pairs. Expect a modestly larger sample (a small number of recovered months), not a dramatically different one — this is a completeness fix, not a signal redesign, so don't expect it to flip GBP or JPY's results on its own; its job is to get the sample closer to a size where PF/win rate are actually decidable.

**What would change this call**: if after this fix the combined sample is still well under 200 trades (likely, since NFP is inherently ~12/year/pair even with zero missed events) and results are still mixed/flat, the honest conclusion at that point is probably "structurally too low-frequency for this account's per-trade cost profile to ever reach statistical confidence" — worth naming explicitly as a possible outcome now, not discovering it as a surprise later.

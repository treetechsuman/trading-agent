characteristics — execution-quality risk matters proportionally more here
than in `wm_fix_reversal`'s 30-minute version; (3) IS→OOS directional
coherence per pair, per the `nfp_fade`/`month_end_fix_reversal` contrast
above, before trusting any aggregate PF number.

No backtest yet — spec.json and dates.md only. Next actor is EA Coder.
See `strategies/day_trading/fix_run_momentum/v1/spec.json` and `dates.md`.

## day_trading/fix_run_momentum v1 — discarded: the momentum half of the fix's V-shaped pattern has no edge; the fade half is the tradeable one (2026-09-25)

**What was tried**: go WITH the pre-fix directional run into the WM/Reuters
4pm London fix (momentum continuation) — enter at 17:59:00 server (1 min
before the fix), exit 2 minutes later at 18:01:00 server, SL/TP both sized
at 1.0x the measured 3-minute pre-fix run, on EURUSD.r/GBPUSD.r/USDJPY.
Deliberately the untested "other half" of the same documented V-shaped
pattern `wm_fix_reversal` already fades (post-fix reversion).

**What happened**: all 6 legs (3 pairs x in-sample 2018-2022/out-of-sample
2023-2025) lost money — PF 0.18-0.72, 632 combined trades (comfortably
clears the 200-trade bar, so this is a well-evidenced negative result, not
a thin sample). USDJPY in-sample max drawdown (15.08%) sat right at the
project's 15% kill-switch. Mechanism check (reading the raw journal, not
just the summary stats — same discipline `nfp_fade`'s review established):
~95% of trades in every leg exit via the fixed 2-minute time backstop
rather than tagging SL/TP, so with a near-1:1 payout the outcome is
effectively "did price keep moving the same direction for 2 more minutes"
— and win rate came in **at or below the ~50% breakeven point in 5 of 6
legs** (as low as 27.1% for USDJPY in-sample), the opposite signature of
what a momentum-continuation thesis predicts.

I also did a manual journal-ledger cross-check (summing every trade's raw
`profit` value and confirming against the running `balance_after` column)
before trusting the reported PF numbers, after noticing `summary.csv`'s
"average profit trade" x "average loss trade" x win/loss counts implied a
*positive* net that didn't match the reported net-negative result. The raw
ledger confirmed the reported negative numbers directly (balance ended
exactly at starting balance minus the reported net loss); the average-trade
mismatch was a cosmetic reporting quirk, not a sign trade outcomes were
mis-recorded. **Worth repeating as a habit**: when a summary stat's implied
arithmetic doesn't reconcile (avg-win x win-count vs avg-loss x loss-count
should roughly equal net profit), reconstruct from the raw per-trade ledger
before either trusting or second-guessing the parsed summary — in this case
it confirmed the summary was right, but it could as easily have caught a
real parsing bug.

Two spec-translation judgment calls EA Coder flagged (an internally
contradictory `entry_time` field; `MinHistoryToAdapt=20` vs. the value
`wm_fix_reversal` v2 actually uses, 5) were both explicitly checked against
the data before accepting the negative result as a thesis failure rather
than a v1-specific bug — neither survived scrutiny as a plausible cause
(entry_time's 17:59:00 resolution was the only internally-consistent
reading available; MinHistoryToAdapt's effect is capped at ~20 daily
evaluations out of a 1,300+ day window, only loosens rather than tightens
selectivity during that window, and losses show no concentration in the
early trades on spot-check). **Adjusting for next time**: when a coder
flags a judgment call alongside a negative result, don't just note it and
move on — explicitly reason through the mechanism and magnitude of what
that judgment call could have changed, the same rigor as checking a
mechanical bug hypothesis, before concluding "thesis failure" vs.
"implementation issue." Both conclusions look identical from the top-line
numbers alone; only tracing the actual mechanism distinguishes them.

**What I'm adjusting/taking forward — a refinement of the standing
"specific named institutional flow" meta-finding, now split by which half
of a run-then-revert pattern is tradeable**: this project has now tested
both halves of the exact same documented WM/Reuters fix V-shaped pattern
on the same instruments with the same adaptive-threshold design lineage.
The reversion/fade half (`wm_fix_reversal`) found a thin but real positive
edge (OOS PF ~1.04-1.06). The momentum/run half (`fix_run_momentum`) found
a decisively negative edge across every pair and window (PF 0.18-0.72,
win rate at or below breakeven in 5/6 legs). **This is not just "one more
named-flow strategy failed" — it's informative about WHICH half of a
documented run-then-revert institutional pattern is likely to have
retail-detectable signal: the reversion, not the continuation.** A
plausible mechanism: by the time a retail-resolution (1-minute-bar) signal
can detect the pre-fix run, the aggressive dealer positioning that created
it is largely already priced in or already being unwound by the larger
players who caused it — so chasing the run itself is chasing exhausted
momentum, while the reversion that follows is the more mechanically
persistent (if still thin) part of the pattern. **Going forward, when a
documented flow/event produces a two-phase price pattern (spike-then-fade,
run-then-revert), treat the fade/reversion phase as the higher-prior
candidate to test first**, rather than treating both halves as equally
likely to have edge — `nfp_fade`'s own spike-then-fade mechanism (thin,
ultimately discarded on noise grounds, not a direction problem) and now
this pair both point the same way. This doesn't mean momentum trades are
never viable in this project (`intraday_momentum_carry`'s failure was for
different, generic-signal reasons) — it's specifically about the two
phases of ONE already-identified event-driven V-pattern.

Registry: `day_trading/fix_run_momentum` set to `discarded`, current_version
v1. See `strategies/day_trading/fix_run_momentum/v1/review.md` and
`strategies/_graveyard/fix_run_momentum/REASON.md`.

## Cointegration/pairs-trading -- attempted direct verification, inconclusive (2026-09-26)

User asked (after being shown a third-party StatArb/pairs-trading EA
concept) whether the standing literature-only finding -- "FX majors are
correlated but not reliably cointegrated, even for the textbook-best
AUDUSD/NZDUSD pair" (`strategies/_graveyard/liquidity_sweep_reversal/REASON.md`)
-- was worth checking directly against this broker's own historical data
rather than trusting outside literature alone. Agreed it was worth doing.
Built a non-trading price-export utility
(`research/cointegration_check/v1/`) to pull daily closes for ~20 candidate
pairs and a `test_cointegration.py` script (Engle-Granger via statsmodels)
to test them properly. **The data-export step never completed** -- two
separate multi-hour hangs in the Strategy Tester harness (see
`backtester/lessons.md`'s 2026-09-26 entry for the technical detail) --
and the user asked to step back rather than keep debugging it.

**Status: still an open question, not resolved either way.** The
literature-only finding remains the only evidence on file. If revisited,
don't repeat the same Tester-based CSV-export approach without first
proving it on a trivial case (one symbol, a few months) -- see the
backtester lessons entry for exactly where it hung. The EA source and
analysis script are left in `research/cointegration_check/v1/` for
whoever picks this up.

## day_trading/fix_w_drift v1 — spec created, not yet coded (2026-10-17)

**What's being tried**: a pure replication of Krohn, Mueller & Whelan
(JF 2024) Table IX, European legs, on EURUSD.r/GBPUSD.r M1. Leg A SELLs
09:00 → 15:15 server (02:00 → 08:15 ET, into the ECB fix). Leg B BUYs
18:00 → 23:45 server (11:00 → 16:45 ET, after the London fix). Fixed
clock times, no signal filter, nothing swept. Catastrophe-only SL
(max(30p, 1.5x D1 ATR20)), no TP, 0.5% risk at the SL. Dates
user-confirmed: IS 2015-2019 (inside the paper's sample), OOS 2020-2025
(post-publication). See `strategies/day_trading/fix_w_drift/v1/spec.json`
and `dates.md`.

**Things found while writing the spec, worth remembering:**

1. **The repo disagrees with itself about the server clock.** Older docs
   (`wm_fix_reversal/dates.md`, `fix_run_momentum/dates.md`,
   `nfp_fade/dates.md`) assume EET/EEST with **EU** DST dates. The basis
   for this strategy, and `live-manager/lessons.md`'s note on gotobi's
   March switch, say the clock is **NY close + 7, following US** DST.
   The two only differ in the EU/US mismatch weeks (about 3-4 weeks a
   year), which is exactly why nobody noticed. nfp_fade's "DST
   spot-check PASSED" doesn't settle it, because it read the EA's own
   entry timestamps and those just echo the EA's computed time.
   **Lesson: a timing check has to come from price or tick evidence
   (when the week's first tick arrives, where the fix volume spike sits),
   never from the EA's own fills.** fix_w_drift's spec makes that check
   a gate before any in-sample result is reviewed.
2. **If NY+7 is right, the live month_end_fix_reversal is mistimed on a
   few days a year.** Its measurement window is a flat 17:55-18:02
   server. In the autumn mismatch week, 18:00 server is 15:00 London, an
   hour before the fix, and that week overlaps the October month-end
   window every year (e.g. Oct 29-31 2023). Some years the same is true
   of late March (e.g. Mar 29 2019 and 2024). The research README's line
   that month_end "already handles the London side" is wrong under NY+7.
   This needs its own follow-up, separate from fix_w_drift. Not acted on
   here: it's a live strategy and not in this task's scope.
3. **month_end v3 handles positions at symbol level**
   (`PositionSelect(_Symbol)` for its exit check and its 22:00 EOD
   close). On this hedging account that can see another EA's position on
   the same symbol. That drove the decision to have Leg B skip
   month_end's exact last-3-calendar-days window, and to require
   ticket+magic position handling in fix_w_drift.
4. **The standard InpMaxConsecutiveLosses=6 doesn't fit a high-frequency,
   coin-flip-per-trade strategy.** At about a 50% win rate and about 500
   trades a year it would fire about 4 times a year and pause until the
   next month, suppressing perhaps 20-30% of trades by chance. Set to 12
   here. **Calibrate the ledger thresholds to each strategy's trade
   frequency and win rate rather than copying the defaults.**
5. **Clearing the 200-trade bar is not the same as having statistical
   power.** At the paper's own per-leg Sharpe, a fully intact effect gives
   an expected gross t of only about 1.9-2.7 per leg/pair over this
   in-sample window, and about half that net. The review has to use a
   mean-pips t-stat and the direction across all 4 leg/pair cells, not PF
   on one cell.
6. **Tick-history depth again**: clean EURUSD.r/GBPUSD.r ticks probably
   start around 2017.07.31, so the user-confirmed 2015 start may be
   unusable. I flagged it for a probe plus user re-confirmation rather
   than changing the confirmed dates. **When a user proposes dates, check
   them against known data limits before writing them in.**

Also noticed: this `lessons.md` starts mid-sentence (line 1 is
"characteristics — ..."), so the earlier entries look truncated in the
working copy. `git status` showed this file as modified. Worth checking
against git HEAD before anything else overwrites it. Left as found and
appended only.

Registry: `day_trading/fix_w_drift` added, status `new`, v1.

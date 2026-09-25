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

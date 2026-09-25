# Why fix_run_momentum was retired

Momentum-continuation strategy on the WM/Reuters 4pm London FX fix: enter
WITH the pre-fix 3-minute directional run at 17:59:00 server (1 min before
the fix), exit 2 minutes later at 18:01:00 server, on EURUSD.r/GBPUSD.r/
USDJPY. The deliberate "other half" of the same documented V-shaped fix
pattern `wm_fix_reversal` (parked) already tested by fading the post-fix
spike instead.

Tested across 3 pairs x 2 windows (2018-2022 in-sample, 2023-2025
out-of-sample, used once) — **every one of the 6 legs lost money**: PF
0.18-0.72, all negative net profit, 632 combined trades (clears the
200-trade significance bar comfortably — not a thin-sample result). USDJPY
in-sample max drawdown (15.08%) sat right at the project's 15% kill-switch
threshold.

Mechanism check: ~95% of trades exit via the fixed 2-minute time backstop
rather than tagging SL/TP, so with SL/TP sized symmetrically (1:1) the
outcome is effectively "did price keep moving the same direction for 2 more
minutes" — and win rate came in at or below the ~50% breakeven point in 5 of
6 legs (as low as 27.1% for USDJPY in-sample), the opposite signature of
what a momentum-continuation thesis predicts.

Two spec-translation judgment calls (an internally-contradictory
`entry_time` field, and a `MinHistoryToAdapt=20` vs. the value
`wm_fix_reversal` v2 actually uses) were checked and ruled out as
explanations — see `v1/review.md` for the detailed reasoning on each. Both
are immaterial relative to a multi-year, multi-pair, in-sample-and-out-of-
-sample negative result of this size and consistency.

**Conclusion:** the pre-fix momentum/"banging the close" half of this
documented flow does not have a retail-detectable edge at 1-minute entry
resolution with a 2-minute hold — read together with `wm_fix_reversal`'s
own thin-but-positive result fading the *other* half of the same V-shaped
pattern, this suggests the reversion side of a run-then-revert fix pattern
is the tradeable half, not the momentum side (plausibly because the
aggressive dealer positioning is already unwound by large players faster
than a 3-minute pre-fix window can capture, or because the momentum signal
at this resolution is dominated by noise rather than the underlying flow).
See `strategies/day_trading/fix_run_momentum/v1/review.md` for full detail,
including a manual journal-ledger cross-check corroborating the reported
PF/net-profit numbers independently of the parsed summary stats.

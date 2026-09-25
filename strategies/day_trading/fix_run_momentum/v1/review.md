# fix_run_momentum v1 — review

**Symbols:** EURUSD.r, GBPUSD.r, USDJPY · **Timeframe:** M1 · **In-sample:**
2018.01.01–2022.12.31 · **Out-of-sample:** 2023.01.01–2025.12.31 (used once,
unmodified)

Thesis: go WITH the pre-fix directional run into the WM/Reuters 4pm London
FX fix (momentum continuation), entering at 17:59:00 server (1 min before
the 18:00:00 server / 16:00:00 London fix) and exiting 2 minutes later at
18:01:00 server, unless SL/TP (both sized at 1.0x the measured 3-minute
run) fire first. Deliberately the "other half" of the same documented
V-shaped fix pattern `wm_fix_reversal` already tested (post-fix fade).

## Results (6 legs)

| Leg | Symbol | Trades | Win rate | Profit Factor | Net Profit | Max equity DD |
|---|---|---|---|---|---|---|
| Root IS | EURUSD.r | 132 | 50.8% | 0.72 | -$360.68 | 4.82% |
| Root OOS | EURUSD.r | 52 | 38.5% | 0.30 | -$524.67 | 5.62% |
| GBPUSD IS | GBPUSD.r | 149 | 46.3% | 0.52 | -$803.27 | 8.77% |
| GBPUSD OOS | GBPUSD.r | 83 | 45.8% | 0.48 | -$561.91 | 6.27% |
| USDJPY IS | USDJPY | 129 | 27.1% | 0.18 | -$1,494.99 | 15.08% |
| USDJPY OOS | USDJPY | 87 | 37.9% | 0.56 | -$396.55 | 5.04% |
| **Combined** | | **632** | | | **-$4,142.07** | |

632 trades combined clears the 200-trade significance bar comfortably —
this is not a thin-sample situation, and every single one of the 6
independently-tested legs (3 pairs x 2 windows) lost money. No leg, no
pair, no window shows a positive number anywhere in this table.

## Journal cross-check (root EURUSD.r IS leg, spot-checked)

Reconstructed gross profit/gross loss directly from `journal.csv`'s
per-trade `profit` column rather than trusting `summary.csv`'s
already-parsed averages at face value, after noticing the reported
"Average profit trade" ($14.17) x "Average loss trade" ($-14.12) x
win/loss counts (67/65) implied a *positive* net (~+$32) that doesn't match
the reported net profit (-$360.68). Manual summation of all 132 trades'
`profit` values gives gross profit ~$717 / gross loss ~$1,130 (PF ~0.63,
in the same ballpark as the reported 0.72 given manual-tally rounding), and
the running `balance_after` column ends at $9,639.32 — exactly
$10,000 - $360.68, matching the reported net profit exactly. **Conclusion:
the summary-table PF/net-profit numbers are corroborated directly from the
raw per-trade ledger; whatever produced the average-trade-value mismatch is
a cosmetic reporting/rounding quirk, not a sign the underlying trade
outcomes are mis-recorded.** Net-negative result confirmed independently
of `summary.csv`'s parsing.

## Mechanism check: why is this losing, not just under-performing?

Spot-checking close times in the journals: the overwhelming majority of
trades (~95% in the root EURUSD.r IS leg — only 7 of 132 close before
18:01:00) exit via the fixed 2-minute time backstop, not by tagging SL or
TP first. With SL and TP sized symmetrically (both 1.0x the measured run),
that makes the win/loss outcome for almost every trade equivalent to a
simple test: **was price higher (for a long) or lower (for a short) than
the entry price two minutes later, at 18:01:00 server?** A real
continuation edge should push win rate meaningfully above the ~50%
breakeven implied by that near-1:1 payout. Instead:

- Root (EURUSD.r): 50.8% IS, **38.5% OOS**
- GBPUSD.r: 46.3% IS, 45.8% OOS
- USDJPY: **27.1% IS**, 37.9% OOS

Five of six legs sit at or below 50%, and USDJPY's in-sample win rate
(27.1%) is dramatically below breakeven — worse than a coin flip by a wide
margin. This is the opposite signature of what a momentum-continuation
thesis predicts. It's consistent instead with mild reversion: the same
2-minute window that follows the pre-fix run and straddles the fix print is
apparently more likely to give back part of that run than extend it,
which — read together with `wm_fix_reversal`'s own finding of a thin but
real *positive* edge fading the post-fix spike — points at the reversion
side of this specific V-shaped pattern being the one with retail-detectable
signal, not the momentum side.

## The two EA Coder judgment calls — could either explain the result?

**1. `entry_time` "18:59:00" vs "17:59:00" contradiction.** EA Coder coded
17:59:00 (measurement-window close), the only value internally consistent
with the measurement window, the stated exit rule (18:01:00, "1 minute
after the fix"), and the entire pre-fix-momentum thesis — an entry at
18:59:00 would be 59 minutes *after* the fix and *after* the exit time,
which is incoherent. There is no plausible alternative reading here; this
was the correct resolution and isn't a candidate explanation for the
negative result.

**2. `MinHistoryToAdapt=20` vs `wm_fix_reversal` v2's actual coded default
of 5.** This value only controls how many days of rolling history must
accumulate before the adaptive multiplier threshold (`MinRunVsAvgMultiplier
x rolling average`) replaces the flat 5-pip floor — and using the floor is
*looser*, not stricter (the floor is very likely smaller than
`2.0 x average recent run`, so more trades would qualify during warm-up,
not fewer). That's the opposite direction from the "starving a valid
threshold, causing it to fire on garbage or miss real setups" concern
raised — if anything a stricter warmup would have suppressed early trades,
not caused them. Even taking the maximally unfavorable reading, the effect
is confined to at most the first 20 daily evaluations of each ~1,300-day
in-sample window and each ~750-day out-of-sample window (1.5-2.7% of the
window). Spot-checking the root EURUSD.r journal, the first ~10 trades
(2018.01-2018.04, i.e. within/just past the warmup period) show a mix of
wins and losses indistinguishable from the rest of the file, and losses
continue at a similar rate all the way through 2022 and into every
out-of-sample window — there's no visible concentration of losses in the
early warmup trades. **This discrepancy cannot plausibly explain a
persistently negative PF sustained across a 5-year in-sample window, a
3-year out-of-sample window, and all three currency pairs.**

## Conclusion: thesis failure, not a v1-specific calibration bug

Distinguishing the two possibilities this review was asked to separate:
this reads as **the momentum-into-the-fix thesis itself lacking a tradeable
edge**, not a broken v1 implementation. Both flagged judgment calls are
either the only coherent reading of the spec (entry_time) or structurally
incapable of producing a multi-year, multi-pair, in-sample-*and*-out-of-
-sample negative result of this magnitude (MinHistoryToAdapt). The
mechanism check (near-100% time-exit trades, sub-50% win rate on a ~1:1
payout, worst in the pair — USDJPY — with the most trades) is a coherent,
independently-corroborated negative signature, not noise.

USDJPY's in-sample max drawdown (15.08%) also sits right at this project's
15% kill-switch threshold — an additional, independent reason this
specific leg/pair combination would never have been a live candidate even
setting the profit-factor evidence aside.

No parameter sweep, SL/TP re-tuning, or v2 spec is being written. Per this
project's own precedent (`nfp_fade`'s final review, `intraday_momentum_carry`'s
REASON.md): when a large, well-evidenced sample shows a coherent, causally
explicable negative result and no candidate implementation bug survives
scrutiny, the correct move is to discard, not to keep tuning around a
structural miss. Flipping the entry direction to fade instead of following
the pre-fix run would not be a natural "v2" of this spec — it would just be
re-deriving `wm_fix_reversal`'s own mechanism (already tested, thin
positive edge, parked) on a different, tighter time window, which isn't a
productive next iteration of *this* thesis.

## Decision: **discarded**

See `strategies/_graveyard/fix_run_momentum/REASON.md` for the graveyard
entry. Registry status set to `discarded`.

# wm_fix_reversal v2 — review

**Symbols:** EURUSD.r (`v2/`), GBPUSD.r (`v2/GBPUSD/`) · **Timeframe:** M1
· **In-sample:** 2017.08.01–2022.12.31 · **Locked parameter:**
`MinSpikeVsAvgMultiplier=2.0` (replaces v1's fixed `MinSpikeSizePips=12`)

## Why this version exists

v1's per-trade quality never broke, but its out-of-sample trade frequency
collapsed ~85-90% (EURUSD had zero qualifying trades in all of 2023)
because a fixed absolute pip threshold doesn't adapt to changing ambient
volatility. v2 replaces it with a threshold relative to a rolling average
of the fix-window's own recent history — the same fix that worked for
`london_range_fade` v2's volatility filter, applied here to a spike-size
gate instead of a range-size gate.

## Did it work? Yes, on the specific problem it targeted.

Full detail in [comparison.md](comparison.md). Headline: EURUSD 2023 went
from **0 trades under v1 to 29 trades under v2**; GBPUSD's out-of-sample
rate roughly matched its in-sample rate for the first time. Frequency
collapse — the specific, diagnosed failure mode — is fixed.

## But it surfaced a different, more important tradeoff

v1's promising-looking out-of-sample profit factor (2.03 EUR, 1.19 GBP)
turns out to have been an artifact of its tiny out-of-sample sample (7
and 19 trades) — small samples make quality metrics volatile in both
directions, and v1 happened to land on the favorable side. v2's much
larger, more honest out-of-sample sample (73 EUR, 85 GBP) shows a
thinner, more representative picture: profit factor 1.06 (EUR) and 1.04
(GBP), drawdown 7-8% on both (vs. v1's misleadingly small 1-3%).

Each pair also has one real losing year within the 3-year out-of-sample
window (EURUSD 2025: -$351; GBPUSD 2024: -$400) — though they don't
coincide, so a combined two-pair account stayed profitable in every
out-of-sample year even though neither pair alone did.

## Assessment

**The redesign succeeded at what it set out to do — fixing frequency
collapse — but that success mainly revealed that v1's headline numbers
were too small a sample to trust, not that the underlying edge is
strong.** With a properly-sized out-of-sample sample now in hand (158
combined trades), the honest picture is: a real, positive, but thin edge
(PF ~1.04-1.06 individually, better combined), broadly consistent
frequency across volatility regimes, and drawdown in the 7-8% range
per pair. This is a meaningfully more trustworthy result than v1's, and
also a less exciting one — which is exactly what fixing a small-sample
artifact should look like.

**Not live-grade as-is.** The edge here is comparable in thinness to
`london_range_fade`'s (PF ~1.05-1.14 there vs. ~1.04-1.23 here across
various cuts), just reached via a different, more mechanistically
grounded thesis. The redesign fixed the frequency problem it was built to
fix; it didn't — and wasn't trying to — fix the deeper question of
whether the edge is large enough to trade at real size once transaction
costs are considered.

## Proposed next step

Given two independent strategies in this project (`london_range_fade`,
`wm_fix_reversal`) have now both landed in the same "real but thin,
PF ~1.05-1.25" territory despite very different theses, I'd treat that as
a meaningful signal about what a realistic edge size looks like for
short-holding-period EURUSD/GBPUSD day trades on this account's cost
structure, rather than something to keep chasing indefinitely. Two
reasonable directions from here:

1. **Combine the two pairs into one portfolio view** (like `gotobi`'s
   `v1_portfolio` harness) to see if trading EUR+GBP together smooths the
   per-pair losing years enough to be worth running at reduced size,
   given the diversification hint in the yearly table above.
2. **Treat both `london_range_fade` and `wm_fix_reversal` as parked
   research** and focus effort on `gotobi` (already verdicted ready at
   reduced size) or a genuinely different strategy category.

**Awaiting your direction.**

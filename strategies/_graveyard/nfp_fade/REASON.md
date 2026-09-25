# Why nfp_fade was discarded

Faded the initial overreaction to the monthly US Non-Farm Payrolls (NFP)
release on EURUSD.r/GBPUSD.r/USDJPY, per Linda Raschke & Larry Connors'
"Street Smarts" (1996) "News Strategy" and corroborating current
practitioner sources — see `strategies/day_trading/nfp_fade/dates.md`
for the full thesis and parameter derivation.

## The multi-version journey

- **v1**: day-of-month calendar approximation for the NFP trigger date.
  59 combined trades, too thin to conclude either way (EUR PF 1.46, GBP
  PF 0.47, JPY PF 1.00 net-flat). Investigation confirmed a real
  false-negative calendar gap — the approximation silently skipped real
  BLS releases falling outside days 1-7 of the month (Jan 2020's real
  release was the 10th, Jan 2021's was the 8th) — refined to v2.
- **v2**: replaced the approximation with a hardcoded 108-entry table of
  actual historical BLS release dates (2017-2025). Grew the sample to 67
  trades (GBP PF 0.47→0.73, JPY PF 1.00→1.31). Reviewing the v1→v2 diff
  initially (and, as it turned out, wrongly) diagnosed a second bug:
  three independently-typed per-symbol NFP tables silently disagreeing
  with each other. Sent to v3 to fix.
- **v3**: EA Coder checked that premise against the actual codebase
  before coding and found it didn't hold — `nfp_fade` has always been
  exactly one shared `strategy.mq5` file (generic against `_Symbol`),
  never three independently-typed tables that could drift apart. A full
  audit of all 108 table entries against BLS's documented scheduling
  rule found zero anomalies. v3 as built is a confirmed no-op vs v2
  (diff-verified: version string/comments only). The false diagnosis was
  corrected in `v3/review.md`, and v2's already-verified 67-trade
  in-sample result (net +$122.11 combined; EUR PF 1.46, GBP PF 0.73, JPY
  PF 1.31) stood as the genuine in-sample picture — thin (<200-trade
  bar) but not a structural red flag, so the strategy proceeded to its
  one-shot out-of-sample validation rather than being discarded on
  in-sample alone.

## The out-of-sample result

Out-of-sample (2023-2025, run once, unmodified, on v3's locked config):
EURUSD.r 14 trades/PF 0.91/-$11.84, GBPUSD.r 15 trades/PF 1.72/+$93.85,
USDJPY 14 trades/PF 0.71/-$53.18. Combined: 43 trades/net +$28.83.

**No pair held its in-sample sign or magnitude.** EUR flipped from
solidly positive (PF 1.46) to roughly flat-negative (PF 0.91). JPY
flipped from modestly positive (PF 1.31) to clearly negative (PF 0.71).
GBP flipped from the weakest, only net-negative in-sample pair (PF 0.73)
to the strongest out-of-sample pair (PF 1.72). This is the exact inverse
of `month_end_fix_reversal`'s out-of-sample result, where every one of
its three pairs *improved* out-of-sample with no exceptions — the
cleanest positive result this project has produced. nfp_fade's
three-different-directions pattern is structurally what pure chance
produces when split three ways at n=14-15/pair, not what an
underpowered-but-real edge should look like (a real edge should on
average point the same direction with wider error bars, not flip
direction on every single pair).

Combined in-sample + out-of-sample: 110 trades, net +$150.94 across
three independent $10,000 accounts over roughly 9 years — economically
negligible even setting aside statistical significance, and still well
under this project's 200-trade bar (a ceiling this strategy can never
clear at its ~12 events/year/pair native frequency, regardless of
further iteration).

**A specific, mechanism-level explanation was found, not just inferred
from the summary stats**: inspecting the raw out-of-sample trade
journals directly showed 86% of trades (37/43) exit via the strategy's
own 60-minute hold-time backstop rather than its stop-loss or
take-profit. Only 6 of 43 trades resolved on a price-based exit before
the timer — 5 were stop-losses, and only **1 single trade across all 43**
ever reached the 1.3x reversion take-profit target. The strategy's
nominal mechanism (measure the spike, fade it, capture the reversion) is
essentially never completing within the specified window; most trades
are effectively directional bets marked to market after an hour, which
plausibly explains why the aggregate result looks like noise rather than
an underpowered signal.

## Why this doesn't justify a v4

That mechanism-level finding (target rarely reached — try a wider
take-profit or longer hold window) is a real, causally specific
diagnosis, not a hopeful guess. It was deliberately not acted on:

1. This project's house rule is explicit — out-of-sample results are
   reported as a finding, not used to motivate a further tweak. Widening
   the take-profit/hold window now, having just seen this combination
   underperform out-of-sample, would be exactly the re-optimization the
   rule exists to prevent.
2. NFP's ~12 events/year/pair frequency means a v4 tested on the same
   in-sample window would still land around 60-70 combined trades at
   best — nowhere near the 200-trade bar — while consuming the one
   already-spent out-of-sample look on this event a second time.
3. Three versions and four review cycles were already spent on this
   strategy without an unambiguously positive in-sample result at any
   point (GBP was net-negative in every version through v2).

## General lesson

See `researcher/lessons.md` for the full generalizable version: **whether
an out-of-sample result *improves* (like `month_end_fix_reversal`, every
pair, no exceptions) or *sign-flips* (like this strategy, every pair, in
different directions) is itself diagnostic of real edge vs. noise at
thin sample sizes** — a real-but-underpowered edge should on average
point the same direction with wider error bars, not flip direction
incoherently across every tested instrument. Also: when a "measure a
spike, then fade it to a target" mechanism is used, check what fraction
of trades actually reach that target before the hold-time backstop fires
— a low completion rate (1/43 here) is a concrete, checkable early
warning that the strategy isn't doing what its own thesis describes,
worth checking at the in-sample review stage in future spike-fade
designs, before ever spending the one-shot out-of-sample look.

Full detail: `strategies/day_trading/nfp_fade/VERDICT.md`,
`strategies/day_trading/nfp_fade/v3/review.md`,
`strategies/day_trading/nfp_fade/v3/comparison.md`.

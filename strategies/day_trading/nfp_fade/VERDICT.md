# nfp_fade — live-readiness verdict

**Version validated:** v3 (confirmed functional no-op vs v2 — see
[v3/review.md](v3/review.md); v2's calendar-completeness fix and v3's
premise-correction are both data-integrity work, not signal changes).
EURUSD.r, GBPUSD.r, USDJPY, each backtested independently per pair
(own `$10,000` account) — no combined-portfolio harness was built, since
the per-pair result below never cleared the bar that would have
justified spending that additional effort.

## Evidence summary

| Pair | IS (2017-2022) trades / PF / net | OOS (2023-2025, used once) trades / PF / net | OOS win rate | OOS max eq DD |
|---|---|---|---|---|
| EURUSD.r | 22 / **1.46** / +$116.86 | 14 / **0.91** / -$11.84 | 50.00% | 0.78% |
| GBPUSD.r | 20 / **0.73** / -$96.04 | 15 / **1.72** / +$93.85 | 53.33% | 0.68% |
| USDJPY | 25 / **1.31** / +$101.29 | 14 / **0.71** / -$53.18 | 35.71% | 1.21% |
| **Combined** | **67 / net +$122.11** | **43 / net +$28.83** | — | all <2% |

**No pair held its in-sample sign or magnitude out-of-sample.** EUR
flipped from solidly positive (PF 1.46) to roughly flat-negative (PF
0.91). JPY flipped from modestly positive (PF 1.31) to clearly negative
(PF 0.71). GBP flipped from the weakest in-sample pair (PF 0.73, the
only net-negative one) to the strongest out-of-sample pair (PF 1.72).
Three pairs, three different directions of movement — no coherent
pattern.

Combined IS+OOS across both windows: **110 trades, net +$150.94** spread
across three independent $10,000 accounts over roughly 9 years of
history. That is an economically negligible return (~0.5% of one
account's capital, spread across three accounts and nine years) even
before asking whether it's statistically distinguishable from zero — and
110 trades remains well under this project's 200-trade significance bar,
confirming this was always going to be a data-thin strategy at ~12
qualifying events/year/pair, a ceiling no amount of further version
iteration removes.

Drawdown was never a concern at any point — every pair, every window,
stayed under 2% max equity drawdown. This is not a strategy that failed
by blowing up; it failed by having no measurable edge at the sample
sizes achievable here.

## Is this "real edge, noisy at n=14-15/pair" or "no edge, this is what noise looks like split three ways"?

Weighed honestly, this is the noise case, for three separate reasons:

1. **The sign-flip pattern itself.** A real edge that's merely
   underpowered at n=14-15/pair should on average point the same
   direction it did in-sample, just with wider error bars — that's what
   `month_end_fix_reversal` (this project's positive contrast case)
   showed: every pair improved out-of-sample, no exceptions, the
   opposite of "some flip up, some flip down." Here, exactly one pair out
   of three moved in the same direction as its in-sample sign
   (technically none did — GBP moved from negative to strongly positive,
   the largest swing of all three, in the direction *least* consistent
   with a persistent edge). A pattern where the strongest in-sample pair
   (EUR) goes flat-negative and the weakest in-sample pair (GBP) becomes
   the best-performing one is exactly the shape three independent
   near-zero-edge coin flips produce, not what a real, common,
   USD-driven edge with correlated pairs should produce.
2. **Win rates cluster around 50% with no consistent skew.** 50.00%,
   53.33%, 35.71% — averaging to almost exactly a coin flip across the
   43 OOS trades, with no pair showing a durable edge in either
   direction.
3. **A specific, mechanism-level explanation for why this looks like
   noise, found by inspecting the raw OOS journals directly** (not
   inferred from the summary stats alone): **86% of OOS trades (37/43)
   exit via the 60-minute hold-time backstop, not via the stop-loss or
   take-profit.** Only 6 of 43 trades hit either price-based exit before
   the timer — 5 of those 6 were stop-losses (the fade going wrong), and
   only **1 single trade across all 43** actually reached the 1.3x
   take-profit target (JPY, 2024.01.05). That means the strategy's
   nominal mechanism — measure the spike, fade it, ride the reversion to
   a 1.3x target — essentially never completes within the 60-minute
   window as specified. In practice, the overwhelming majority of trades
   are not "captured reversions," they are directional bets marked to
   market at an arbitrary clock time an hour after entry — a much
   noisier, closer-to-random outcome than the thesis intends. This is
   consistent with, and helps explain, why the aggregate result looks
   like pure noise rather than a real-but-underpowered signal: for most
   trades, the mechanism the edge depends on isn't actually finishing
   before the position closes.

## Was the underlying "fade the NFP spike" thesis fairly tested, or is this an implementation artifact?

Partially fairly tested, with one genuine, specific calibration issue
identified late. The Street Smarts / practitioner sourcing for
fading an initial overreaction to scheduled news is a real,
well-documented microstructure phenomenon — the thesis itself isn't
what this result indicts. But every numeric parameter that operationalized
it here (T+10 entry, 15-pip/1.2x threshold, SL 1.0x/TP 1.3x of measured
spike, 60-minute hold) was Researcher's own reasoned-but-untested
translation of the general principle (see `dates.md`'s `*_reasoning`
fields) — not fit to data (good, avoids curve-fitting), but also never
independently checked against how long a genuine NFP reversion actually
takes before this OOS run exposed it. The finding above (target reached
in 1 of 43 trades) is a legitimate, causally specific diagnosis that a
wider take-profit allowance or longer hold window *might* do better —
this is not "the thesis is false," it's "this specific window/target
combination doesn't let the reversion finish."

**That diagnosis is not, however, grounds for a v4.** Three reasons:

1. **This project's own out-of-sample discipline is explicit**: "if
   out-of-sample results look weak, report it as a finding — do NOT go
   back and re-optimize in response to it." Widening the TP or hold
   window now, having just seen that the current combination underperforms
   out-of-sample, is re-optimizing in response to an OOS result by
   definition, regardless of how mechanistically well-motivated the
   diagnosis is.
2. **The sample ceiling doesn't move.** NFP happens ~12 times/year/pair.
   A v4 tested on the same in-sample window would still land around
   60-70 trades/pair combined at best — nowhere near the 200-trade bar —
   and would consume the one already-spent out-of-sample look on this
   strategy family a second time, this time with the added complication
   that the change was motivated by having seen OOS results once already.
3. **Three versions and four review cycles have already gone into this
   strategy** (v1's calendar-approximation gap, v2's completeness fix,
   v3's false-premise correction and the OOS run itself) without ever
   producing an unambiguously positive number even in-sample (GBP was
   net-negative in every version through v2). The realistic ceiling for
   this specific event, at this account's trade frequency, is a
   permanently thin, noisy sample — a structural property of the
   strategy, not a bug still to be found.

## Verdict: Discard

This is a clean discard, not a borderline call. Unlike
`london_range_fade`/`wm_fix_reversal` (parked, genuinely mixed/thin
but not sign-flipping), nfp_fade's out-of-sample result actively
contradicts its in-sample result on every pair, in different directions,
with win rates clustering at chance and a mechanism-level explanation
(target reached in 1/43 trades) for why. This is what the null result
looks like at this sample size, not a real edge waiting for more data —
and more data isn't available at anything better than ~12 events/year/pair,
so waiting doesn't fix the sample-size problem the way it might for a
higher-frequency strategy.

**What would change this call**: a materially different measurement
mechanism (not just a wider TP/hold window on the same T+10/15-pip/1.2x
skeleton) validated with zero further parameter sweeping against a full
fresh in-sample run, specifically designed so the take-profit is actually
reachable within the hold window based on measured historical
time-to-reversion (not guessed) — and even then, this event's inherent
~12/year/pair frequency means any future attempt should expect to stay
below the 200-trade bar for years regardless of design quality. Given
that ceiling, this thesis is not recommended for further iteration
unless the account's opportunity set changes (e.g., adding more USD
pairs beyond EUR/GBP/JPY to increase combined frequency, which was
flagged but not pursued here).

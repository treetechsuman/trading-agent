# london_breakout_retest v1 — review

**Symbols:** EURUSD.r, GBPUSD.r, USDJPY (independent single-symbol runs,
own $10,000 account each) · **Execution TF:** M15, H1 context filter ·
**In-sample:** 2017.01.01–2022.12.31 · **Zero parameters swept** — first
specified configuration, per this project's "single pre-specified
configuration first" convention.

## Headline stats

| Metric | EURUSD.r | GBPUSD.r | USDJPY |
|---|---|---|---|
| Total trades | 261 | 217 | 87 |
| Win rate | 34.48% | 30.41% | 25.29% |
| Profit factor | 0.86 | 0.79 | 0.56 |
| Net profit ($10k start) | -$1,224.26 | -$1,513.94 | -$1,349.30 |
| Expectancy/trade | -$4.69 | -$6.98 | -$15.51 |
| Avg win / avg loss | $85.74 / -$47.91 | $87.33 / -$45.42 | $77.01 / -$46.82 |
| Max consecutive losses | 10 | 13 | 10 |
| Max balance DD | 15.02% | 15.14% | 15.17% |
| Max equity DD (intraday) | 15.80% | 15.80% | 15.42% |
| Sharpe | -5.00 | -5.00 | -5.00 |

All three pairs are net losers, and combined (565 trades) comfortably
clears this project's 200-trade significance bar — these numbers are not
provisional.

## The drawdown-threshold coincidence: diagnosed, not a bug

Backtester flagged all three pairs landing at/just above the 15%
kill-switch in the same run as worth checking directly. Reconstructed the
full equity curve from each pair's `journal.csv` (`balance_after` column,
cross-checked against each summary's Balance Drawdown Absolute/Maximal —
all three matched to the cent):

- **USDJPY**: peaked at $10,197.41 (2018.02.02), last trade closed
  2018.11.09 at $8,650.70 — a 15.17% balance drawdown, matching the
  reported max exactly. **Zero trades after 2018.11.09** for the
  remaining ~4.1 years of the 2017–2022 window.
- **GBPUSD.r**: never closed above the $10,000 starting deposit at any
  point in the whole run (confirmed: Balance Drawdown Absolute =
  $1,513.94 = net loss exactly, i.e. peak balance = initial deposit).
  Last trade closed 2020.11.30 at $8,486.06 (15.14% DD). **Zero trades
  for the remaining ~2.1 years.**
- **EURUSD.r**: peaked at $10,225.10 (2017.03.02), last trade closed
  2021.05.19 at $8,775.74 — balance DD 14.99–15.02%, but equity DD
  (intraday floating loss) hit 15.80%, over the stop. **Zero trades for
  the remaining ~1.6 years.**

This is **spec-compliant behavior, not a bug**: `spec.json`'s
`safety_rules.max_drawdown_stop_percent: 15.0` has no stated resume
condition (unlike `consecutive_loss_pause`, which explicitly resumes
"first day of next month") — the EA halting permanently once tripped is
exactly what was specified, matching how Live Manager's own external
15% kill-switch is meant to behave. Lot sizing was also checked directly
across all three journals: dollar risk per trade stays consistently
~$45-55 (~0.5% of then-current equity) throughout, including immediately
before and after loss streaks — **no evidence of scale-up-after-loss**;
the varying lot sizes (0.08–1.29) are just the expected consequence of
constant-$-risk sizing against a variable wick-anchored stop distance.

**Conclusion on the coincidence**: this is a real, informative strategy
property, not a synchronized-event artifact or an execution bug. The
three pairs tripped the stop at three *very different* calendar dates
(Nov 2018, Nov 2020, May 2021) — ruling out a shared single-day
correlated-loss event as the explanation. What they share instead is a
persistently negative edge (PF 0.56–0.86) that reliably grinds equity
down until it crosses 15%, at which point the safety rule — working
exactly as designed — shuts the pair off for good. The 15%-ish landing
value across all three is simply the stop threshold doing its job three
times independently. This is a *worse* finding for the strategy than an
unlucky single drawdown episode would be: the safety net, not a
mean-reverting edge, is the only reason these accounts didn't decline
further.

## Why the win rate is low: thesis failure, not a fixable exit/pip issue

Checked each candidate specific-fix hypothesis directly:

- **JPY pip-conversion bug?** No. USDJPY loss/win dollar magnitudes track
  the other two pairs almost exactly (avg loss -$46.82 vs -$47.91/-$45.42
  for EUR/GBP), and a manual pip-value check on an individual trade
  (0.41 lots, 28.2-pip move → $98.50) matches USDJPY's standard retail
  pip value. Risk sizing is correctly calibrated per pair.
- **USDJPY's low trade count (87 vs 261/217) — structural or a bug?**
  Neither — it's fully explained by USDJPY tripping the kill-switch
  earliest (Nov 2018, ~10-16 months into the window vs. the other two
  pairs trading 2-3x longer before their own stops fired). No evidence
  of a JPY-specific setup-formation shortfall independent of the
  drawdown-stop timing.
- **EOD-flat cutting winners short of 2R?** Real, but a secondary
  contributor, not the primary driver. Several trades close exactly at
  18:00 server time with small partial gains well under the theoretical
  2R (e.g. EURUSD: +$26.74, +$18.80, +$12.22, +$31.76 against a typical
  full win of ~$85-100). Back-of-envelope: at EURUSD's actual 34.48% win
  rate, a *full* 2R win/1R loss structure with zero EOD truncation would
  produce PF ≈ (0.3448×2)/(0.6552×1) ≈ 1.05 — thin, but not the observed
  0.86. EOD truncation accounts for roughly that ~0.15-0.20 PF gap, not
  the underlying shortfall.
- **Underlying win rate itself (25-34%)**: this is the dominant problem.
  Breakeven at a clean 2R target requires ≥33.3% win rate before any
  costs; EURUSD (34.48%) sits barely above that line before spread/
  commission/EOD-truncation drag it under, and GBPUSD (30.41%) /
  especially USDJPY (25.29%) are well below breakeven on the win rate
  alone, independent of exit-timing effects.

This is the same failure signature already documented for `london_orb`
(discarded 2026-09-17): "breakout predicts continuation" converged on
~32-33% win rate / PF ~0.78-0.81 across three structurally different
entry filters (tick-touch, bar-close+min-range, HTF-trend-aligned) with
no fix found. `london_breakout_retest` adds a materially more selective
entry gate on top of that same continuation thesis — a mandatory
pullback retest plus rejection-candle confirmation (pin bar/engulfing),
which by construction discards many of the immediate-breakout entries
`london_orb` took — and still lands in the *same or worse* win-rate band
(25-34% here vs. 32-33% for `london_orb`; two of three pairs are
strictly worse than every `london_orb` variant). **Entry sophistication
did not fix a thesis-level problem, exactly the pattern this project
already learned from once**: the retest+rejection filter is selecting
*which* breakouts to trade, but breakouts on these pairs still don't
reliably continue afterward regardless of which ones get selected.

## Decision: discarded

Per this project's house rule — refine only with one clearly-motivated
change grounded in what the trade data shows, discard otherwise. The
data here doesn't support a single fixable change:

- The EOD-truncation fix (extend the flat-exit hour, or let winners run
  further) would close at most ~0.15-0.20 PF of the gap on EURUSD alone
  — nowhere near enough to turn any of the three pairs profitable, let
  alone with a real margin over 1.0 after costs.
- The core deficiency (win rate 25-34%, well under 2R breakeven on two
  of three pairs) is a continuation-thesis problem, not a filter,
  stop-placement, or exit-timing problem — and this project already has
  a direct, three-way-replicated precedent (`london_orb`) that tuning
  entry filters on this exact thesis doesn't produce a fix.
- No parameter here (SLBufferPips, TPMultiplier, pin-bar thresholds, H1
  filter design) has a specific, data-grounded reason to expect it would
  push win rate from ~30% up past the ~33-40%+ territory needed for a
  real edge — sweeping any of them now would be exactly the "hoping
  something improves" pattern the house rule exists to prevent.

Moving to `strategies/_graveyard/london_breakout_retest/REASON.md` and
setting registry status to `discarded`.

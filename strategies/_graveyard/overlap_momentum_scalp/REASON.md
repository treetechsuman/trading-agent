# Why overlap_momentum_scalp was retired

Scalping strategy for the London/New York overlap (13:00-16:00 London /
15:00-18:00 server), EURUSD.r, M1. Four distinct variants tested,
2021-2023 in-sample / 2024-2025 out-of-sample:

1. **v1 — momentum continuation.** Bet on continuation of a fast,
   high-conviction M1 bar's body (burst detection relative to a rolling
   average, same technique as `london_range_fade`/`wm_fix_reversal`).
   In-sample PF 0.73, ~49% win rate, drawdown hit the 15% kill-switch.
2. **v2 — momentum fade.** Same burst signal, opposite direction (bet on
   reversion instead of continuation). Worse: PF 0.60, ~45% win rate,
   also hit the 15% kill-switch. Confirmed the single-bar body signal
   carries no real directional information in *either* direction —
   just noise, with costs turning it decisively negative.
3. **v3 (default params) — deviation-from-moving-average fade.** A
   genuinely different, smoother mechanism: fade price's deviation from
   a 20-period M1 SMA instead of a single noisy bar. Real signal this
   time — win rate 55.86%, consistently above 50% both directions — but
   PF still 0.82, because average loss ($17.34) exceeded average win
   ($13.98). A 7-combination SL/TP sweep showed win rate and reward
   trading off in lockstep (PF stuck at 0.82-0.89 across the whole
   range), the signature of geometry/costs dominating rather than a
   miscalibrated ratio.
4. **v3 (tuned, locked) — higher selectivity.** Diagnosed the real
   mechanism directly: gross price P&L (before commission) was actually
   **positive** (+$729.60 over 725 trades), but commission (-$1,784.13)
   was 2.4x the gross edge and wiped it out — a real but tiny edge,
   traded too often at too small a size for this account's fixed
   per-lot commission. Raising the deviation threshold (fewer,
   higher-conviction trades) pushed in-sample PF to 1.02 (221 trades) —
   but 2 of the 3 in-sample years were individually *negative*
   (2021: -$27, 2023: -$42), with the entire net result carried by one
   year (2022: +$110). Out-of-sample (2024-2025) confirmed this was a
   small-sample artifact, not a real edge: **PF 0.80, -$371 net.**

## Conclusion

All four angles — two directions on a fast single-bar signal, and two
tunings of a smoother multi-bar mean-reversion signal — converge on the
same finding: no reliably positive, out-of-sample-validated edge exists
for this thesis on this pair/session/broker cost structure. The closest
attempt (v3 tuned) revealed the actual constraint clearly: there may be
a small genuine directional edge in short-horizon mean reversion here,
but this account's commission structure is large enough relative to
realistic scalp-sized targets that it consumes the edge before it can
compound into a real result. Chasing tighter parameter combinations
further would very likely just be re-discovering the same small-sample
trap already caught once here (see the 4/3/3 → higher-selectivity →
better-in-sample-looking pattern in `v3/sweep/sweep2_results.csv`).

## What would need to be true to revisit scalping here

- A **materially lower-commission execution venue** (this account's
  fixed-per-lot commission is the single biggest identified drag).
- A genuinely different signal source not explored here — true
  order-book/tick-imbalance data (not available via standard MT5 bars),
  which is what most professional scalping edges actually rely on.
- Accepting a **longer holding horizon** (moving away from "scalping" in
  the strict sense toward a quicker intraday trade, closer to this
  project's other day-trading strategies) so each trade's edge is large
  enough relative to the fixed commission cost — effectively conceding
  that pure high-frequency scalping isn't economically viable on this
  account's cost structure for this kind of signal.

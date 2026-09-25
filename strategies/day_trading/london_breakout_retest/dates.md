# london_breakout_retest — date ranges

- **In-sample (optimization):** 2017.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same standard split already established for every other day-trading strategy
this session (gotobi, wm_fix_reversal, month_end_fix_reversal,
yen_fiscal_repatriation) — no strategy-specific reason to deviate. All
parameter sweeps and logic iteration happen only against the in-sample
range. Out-of-sample is used once, unmodified, as a final check.

## Origin

User-specified strategy ("London Breakout & Retest"), given directly with
exact entry/exit mechanics — the same pattern as `gotobi` (user-specified
fixed rules) rather than a Researcher-designed strategy. Researcher's role
here was limited to formalizing the unstated operational parameters (stop
placement, take-profit/exit rule, the H1 "directional context" filter,
position sizing, safety rules, skip conditions) using this project's
established conventions — see `v1/spec.json`'s per-field `reasoning` notes
for exactly which decisions are Researcher's own call versus the user's
exact words.

## Relationship to this account's other Asian-range/London-session strategies

This account has two prior strategies built on the same underlying
Asian-range / London-session structure — worth being explicit about how
this one differs, since superficially all three share "mark a session
range, react to a break of it":

- **`london_orb`** (discarded, see `strategies/_graveyard/london_orb/REASON.md`)
  — traded the pre-London range breakout in the CONTINUATION direction,
  entering on the breakout itself with no retest or confirmation gate.
  Three structurally different entry filters all converged on ~32-33% win
  rate / PF ~0.78-0.81 — no edge in "the breakout alone predicts
  continuation."
- **`london_range_fade`** (parked, see `strategies/day_trading/london_range_fade/STRATEGY.md`)
  — took the opposite thesis: FADES the same kind of range break, betting
  on reversion back into the range rather than continuation. Thin but
  real edge (PF ~1.08-1.14), never discarded, currently parked pending
  further evidence.
- **`london_breakout_retest`** (this strategy) — is neither. It agrees
  with `london_orb` on direction (continuation, not fade), but adds
  exactly the structural element `london_orb` never had: a mandatory
  pullback retest of the broken boundary, plus a rejection-candle
  confirmation (pin bar / engulfing) at that retest, before entering.
  The impulse breakout candle itself is explicitly never traded. This is
  a genuinely different entry mechanism/timing from `london_orb`, not a
  re-test of the same thesis that already failed — worth taking
  seriously on its own evidence rather than assuming `london_orb`'s
  discard already answers the question for this version. Also uses a
  different session window (00:00-06:00 UTC Asian range /
  07:00-11:00 UTC London trading window, vs. `london_orb`'s
  06:00-08:00 server-time pre-London range) and adds an H1 directional
  filter neither prior strategy used.

## Pairs

EUR/USD (EURUSD.r), GBP/USD (GBPUSD.r), USD/JPY (USDJPY, bare — no `.r`
suffix, confirmed from prior strategies) — one EA, backtested
independently per pair since MT5's standard Strategy Tester only trades
the chart's own symbol, same pattern as `gotobi`/`month_end_fix_reversal`.
Each pair's in-sample/out-of-sample runs should live in their own
subfolder inside the version folder (`v1/EURUSD/`, `v1/GBPUSD/`,
`v1/USDJPY/`), each with its own config.ini/report/journal. A combined
3-pair portfolio check (same pattern as `gotobi/v1_portfolio` and
`month_end_fix_reversal/v1_portfolio`) is recommended once individual-pair
results are in, given the position-sizing note in `spec.json` about
possible combined exposure across all three pairs on a shared session
morning.

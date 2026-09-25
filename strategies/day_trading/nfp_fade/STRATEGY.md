# nfp_fade — strategy description

**Status: `discarded` (2026-09-23).** In-sample vs out-of-sample results
sign-flipped on every pair, win rates clustered at chance, and 86% of
out-of-sample trades resolved via an arbitrary 60-minute timer rather
than the strategy's own reversion target. See [VERDICT.md](VERDICT.md)
for the full live-readiness reasoning and
[strategies/_graveyard/nfp_fade/REASON.md](../../_graveyard/nfp_fade/REASON.md)
for the multi-version journey summary.

**Version:** v3 (confirmed no-op vs v2) · **Symbols:** EURUSD.r,
GBPUSD.r, USDJPY · **Timeframe:** M1 · **Compiled EA:**
`v3/strategy.mq5`, deployed identically to all three chart instances

## What it does

Fades the initial overreaction to the monthly US Non-Farm Payrolls (NFP)
release, per Linda Raschke & Larry Connors' "Street Smarts" (1996) "News
Strategy" and corroborating current practitioner sources.

1. **Calendar trigger** — a hardcoded table of the 108 actual historical
   BLS Employment Situation release dates (2017.01-2025.12), not a
   day-of-month approximation and not MT5's `CalendarValueHistory()` API.
2. **Measure the spike** — track price from the release (8:30am ET,
   converted to server time via a combined US+broker DST algorithm) to
   T+10 minutes.
3. **Filter** — skip unless the move clears `MinSpikeSizePipsFloor=15`
   pips and `MinSpikeVsAvgMultiplier=1.2` x a rolling 12-event average.
4. **Fade it** — sell if price rose into T+10, buy if it fell.
5. **Manage the trade** — stop-loss at 1.0x the measured spike,
   take-profit at 1.3x, 60-minute hold-time backstop if neither hits,
   flat by 22:00 server regardless.
6. **Position size** — 0.5% of equity risked per trade.

## Why this approach

Direct structural descendant of `wm_fix_reversal`/`month_end_fix_reversal`'s
"measure a spike, then fade it" pattern, but every numeric parameter was
independently re-derived (not copied) because NFP is a genuinely
different kind of event: a scheduled, surprise-dependent economic data
release rather than a mechanical daily liquidity fixing. See
`dates.md`'s `*_reasoning` fields for the full parameter-by-parameter
justification, and its DST section for the (validated, spot-checked)
combined US-Eastern/broker-server dual-daylight-saving conversion this
strategy required, unlike any prior calendar-triggered strategy in this
project.

## Performance (see [v3/review.md](v3/review.md) / [v3/comparison.md](v3/comparison.md) for full detail)

| | In-sample (2017-2022) | Out-of-sample (2023-2025, used once) |
|---|---|---|
| EURUSD.r PF / trades | 1.46 / 22 | **0.91** / 14 |
| GBPUSD.r PF / trades | 0.73 / 20 | **1.72** / 15 |
| USDJPY PF / trades | 1.31 / 25 | **0.71** / 14 |
| Combined net / trades | +$122.11 / 67 | **+$28.83** / 43 |

**No pair held its in-sample sign or magnitude out-of-sample** — the
opposite of `month_end_fix_reversal`'s "every pair improved, no
exceptions" pattern, and structurally what pure chance looks like split
three ways at n=14-15/pair.

## Known limitations / why this was discarded

- **Sign-flip across all three pairs** — EUR and JPY weakened from
  positive to negative, GBP strengthened from the worst in-sample pair
  to the best out-of-sample one. No coherent direction.
- **Win rates cluster near chance** — 50.00% / 53.33% / 35.71% OOS.
- **Mechanism rarely completes**: 86% of OOS trades (37/43) exit via the
  60-minute hold-time backstop, not the take-profit or stop-loss — only
  1 of 43 trades ever reached the 1.3x reversion target. The strategy is
  effectively a directional bet marked to market after an hour for most
  trades, not a captured reversion, which helps explain the noise-like
  aggregate result.
- **Permanently thin sample** — ~12 qualifying events/year/pair means
  even combining in-sample and out-of-sample windows (110 trades total)
  stays well under this project's 200-trade significance bar, and no
  amount of further iteration removes that ceiling without expanding the
  pair set.
- **Two real bugs were found and fixed along the way** (see below) —
  neither was the reason for discard; the final v3 result is trusted.

## Version history

- **v1**: day-of-month calendar approximation. 59 combined trades, too
  thin to conclude either way (EUR PF 1.46, GBP PF 0.47, JPY PF 1.00
  net-flat). Confirmed a false-negative calendar gap (silently skipped
  real BLS releases falling outside days 1-7, e.g. Jan 2020, Jan 2021) —
  refined to v2.
- **v2**: replaced the day-of-month rule with a hardcoded 108-entry
  actual-BLS-release-date table. Grew the sample to 67 trades (GBP PF
  0.47→0.73, JPY PF 1.00→1.31). A review of the v1→v2 diff initially
  (and, as it turned out, incorrectly) diagnosed a second bug — three
  independently-typed per-symbol tables silently disagreeing with each
  other — and sent v3 back to "fix" it.
- **v3**: EA Coder investigated that premise directly before coding and
  found it didn't match the actual codebase — `nfp_fade` has always been
  one shared `strategy.mq5` file, never three independently-typed
  tables. v3 is a confirmed no-op vs v2 (diff-verified). The false
  diagnosis was corrected in `v3/review.md`; v2's already-verified
  67-trade in-sample result stood unchanged. Proceeded to out-of-sample
  validation on this locked config, which produced the sign-flip result
  documented above — final decision: discard.

## Files

- `v1/`, `v2/`, `v3/` — one spec/strategy/review per version; `v3/` also
  holds each pair's `validation/` out-of-sample subfolder.
- `v3/review.md` — the premise-correction writeup and final in-sample
  decision to proceed to out-of-sample.
- `v3/comparison.md` — full in-sample vs out-of-sample side-by-side.
- `VERDICT.md` — the live-readiness assessment and discard reasoning.
- `dates.md` — date ranges, thesis origin, parameter derivation, and the
  DST-conversion algorithm.

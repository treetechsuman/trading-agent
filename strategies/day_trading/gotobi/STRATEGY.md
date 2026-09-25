# gotobi — strategy description

**Status: v1 fully validated (in-sample + out-of-sample). Verdict: ready for
live at reduced size — see [VERDICT.md](VERDICT.md). Awaiting user decision
on next step (go live reduced-size, run demo/live-monitoring first, or
iterate further).**

**Version:** v1 · **Symbols:** USDJPY, EURJPY.r, GBPJPY.r (one EA, run as
one copy per pair) · **Timeframe:** M1 (tick-driven; timeframe is cosmetic)
· **Compiled EA:** `v1/strategy.mq5` (also compiled at
`MQL5\Experts\EAFactory\gotobi\v1\strategy.ex5` in the terminal)

## What it does

Trades one short-lived setup on specific calendar days: fades the Tokyo
pre-fixing dollar-demand spike caused by Japanese corporate "gotobi"
payment days.

1. **Which days** — 5th, 10th, 15th, 20th, 25th and last-day-of-month
   (30th, except February uses its actual last day). Skips the date
   entirely if it falls on a weekend — no make-up day.
2. **Entry** — one SELL per pair at 00:45 UTC (converted internally to
   this broker's server clock: 03:45 Mar-Oct, 02:45 Nov-Feb — TimeGMT() is
   not simulated in the Strategy Tester, so the conversion is hardcoded by
   month rather than computed at runtime). Enters up to 10 minutes late if
   missed, then skips the day. Skips if spread > 3 pips, margin is
   insufficient, or the computed lot size would be below the broker's
   minimum (never rounds up to the minimum — that would exceed the
   intended risk).
3. **Stop-loss** — 20 pips above entry, set once, never moved. No
   take-profit; the trade is closed by the clock.
4. **Exit** — market close 35 minutes after the nominal entry time
   (01:20 UTC), regardless of the trade's P&L, unless the stop was already
   hit.
5. **Position size** — 0.5% of account balance risked if the stop is hit,
   computed from the stop distance and the symbol's tick value.
6. **Safety ledger (per pair, always on)** — pauses after 6 consecutive
   losses (auto-resumes the following month, or via `InpResetLedgerNow`);
   halts further trades that day after a 5% single-day balance loss; hard
   stops all trading after a 15% drawdown from the balance peak until
   manually reset (`InpResetDrawdownStop`); never scales up after a loss;
   never more than one open position per pair per day; refuses to start on
   a real account unless `InpAllowLiveAccount=true`; closes any stale
   position left open from a previous day at EA startup.

## Why this approach

Unlike the project's other strategies, this one has **no free parameters
to optimize** — entry/exit times, stop distance, risk %, and spread cap
were all specified directly in the source strategy brief, not fit to
historical data. That removes most of the usual curve-fitting risk by
construction; the backtest's job here was purely to confirm the underlying
premise (a real, exploitable, small price move around a known calendar
event) holds up, not to search for a config that works.

## Performance (see [v1/review.md](v1/review.md) / [v1/comparison.md](v1/comparison.md) for full detail)

| | In-sample (2017–2022) | Out-of-sample (2023–2025, used once) |
|---|---|---|
| USDJPY PF / win rate / max DD | 1.48 / 57.4% / 1.69% | 1.86 / 57.5% / 2.29% |
| EURJPY.r PF / win rate / max DD | 1.42 / 60.3% / 1.59% | 1.81 / 58.8% / 2.13% |
| GBPJPY.r PF / win rate / max DD | 1.43 / 57.7% / 2.61% | 1.48 / 56.9% / 2.74% |
| Trades/pair | ~270–300 (6y) | 153 (3y) |

**18 of 18 pair-years in-sample were profitable** (no losing year for any
pair, 2017-2022). Out-of-sample improved on every metric for every pair —
no curve-fit degradation. But **2025 alone carries roughly 65-85% of each
pair's 3-year out-of-sample profit**; a "normal" year (2023/2024) looks
more like 1-3%/yr per pair, not the 9.8%/yr headline figure from the
original spec's own informal testing.

## Known limitations / open questions

- **The edge is thin by design** — expectancy is $4-11/trade on a $10,000
  account (a few pips). The spec itself notes ~3 pips of added cost erases
  it. This is the single biggest live risk and the reason the verdict
  recommends reduced size initially rather than full sizing immediately.
- **Combined-account exposure — tested and closed (2026-09-22).** A
  separate `v1_portfolio/` harness (one EA instance trading all three
  symbols against one shared account, since MT5's standard tester only
  trades one symbol per run) confirmed true combined-account drawdown
  stays at 4.85-8.05% across in-sample and out-of-sample — well below the
  15% kill-switch. Building this harness surfaced a real bug (a shared
  `CTrade` object leaving the wrong magic set when closing non-last-entered
  symbols, causing occasional stuck positions) — fixed, documented in
  `v1_portfolio/strategy.mq5`.
- **EURJPY.r/GBPJPY.r 2017 is partial-year** — this broker's tick history
  for those two symbols only starts 2017.07.25, so that year's stats for
  those pairs are lower-confidence (21 trades vs. ~50 in other years).
- **Live execution quality is unverified** — this is a well-known,
  calendar-published event other participants also trade; whether real
  fills at the exact 00:45 UTC window match the historical tick replay
  closely enough for this thin edge to survive is not something
  backtesting can settle.

## Files

- `v1/` — the only version so far (fixed rules, nothing swept). Each pair's
  in-sample run, out-of-sample validation, and yearly robustness check live
  in `v1/USDJPY/`, `v1/EURJPY/`, `v1/GBPJPY/` (each with its own
  `config.ini`/`report.htm`/`journal.csv`, and a `validation/` subfolder
  for out-of-sample).
- `v1/review.md` — in-sample review and yearly robustness breakdown.
- `v1/comparison.md` — in-sample vs. out-of-sample side by side, per pair.
- `v1/robustness/run_yearly.py` — the script that produced the yearly
  breakdown across all three pairs.
- `v1_portfolio/` — combined-account test harness (one EA instance, all
  three symbols, one shared account) used to measure true concurrent
  3-pair exposure. In-sample: PF 1.36, 898 trades, max drawdown 4.85-6.36%.
  Out-of-sample (`validation/`): PF 1.72, 459 trades, max drawdown
  6.80-8.05%. `strategy.mq5`'s `ManageOpenPosition()` comment documents a
  real bug found and fixed here (shared-`CTrade`-object magic mismatch
  causing stuck positions).
- `VERDICT.md` — the live-readiness assessment and reasoning.
- `dates.md` — the in-sample/out-of-sample date ranges used, and the
  per-pair backtest methodology note.

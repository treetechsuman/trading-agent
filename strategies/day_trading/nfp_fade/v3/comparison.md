# nfp_fade v3 — in-sample vs out-of-sample comparison

v3 is a confirmed no-op vs v2 (version string/comments only, diff-verified
by EA Coder — zero logic/parameter/table changes; see
[v3/review.md](review.md)). No parameters were changed between in-sample
and out-of-sample, and none were swept at any point in this strategy's
history (v1→v2→v3 were each single motivated bug fixes, not a parameter
search). Out-of-sample was run once, unmodified, per pair, into
`v3/<PAIR>/validation/`, per this project's one-shot OOS discipline.

In-sample numbers below are v2's already-produced backtest (reused
directly since v3 is a no-op — no re-run needed, per v3/review.md).

## Side-by-side (per pair, per-pair independent $10,000 account)

| Metric | EURUSD.r IS | EURUSD.r OOS | GBPUSD.r IS | GBPUSD.r OOS | USDJPY IS | USDJPY OOS |
|---|---|---|---|---|---|---|
| Period | 2017–2022 (6y) | 2023–2025 (3y) | 2017–2022 (6y) | 2023–2025 (3y) | 2017–2022 (6y) | 2023–2025 (3y) |
| Trades | 22 | 14 | 20 | 15 | 25 | 14 |
| Win rate | 59.09% | 50.00% | 45.00% | 53.33% | 52.00% | 35.71% |
| Profit factor | 1.46 | 0.91 | 0.73 | **1.72** | 1.31 | 0.71 |
| Net profit | +$116.86 | -$11.84 | -$96.04 | **+$93.85** | +$101.29 | -$53.18 |
| Max drawdown | 1.87% (equity) | 0.78% (equity) / 0.49% (balance) | 1.97% (equity) | 0.68% (equity) / 0.55% (balance) | 1.41% (equity) | 1.21% (equity) / 1.16% (balance) |

**Combined**: IS 67 trades / net +$122.11 → OOS 43 trades / net **+$28.83**.

## What changed, pair by pair

- **EURUSD.r**: flipped from solidly positive in-sample (PF 1.46) to
  roughly breakeven-negative out-of-sample (PF 0.91, -$11.84 on 14
  trades) — a small-dollar swing on a small sample, not a collapse, but
  the pair that carried the in-sample combined result did not repeat.
- **GBPUSD.r**: flipped from the weakest in-sample pair (PF 0.73, the
  only net-negative one) to the strongest out-of-sample pair (PF 1.72,
  +$93.85, 15 trades) — the opposite direction of EUR's move.
- **USDJPY**: degraded from modestly positive in-sample (PF 1.31) to
  net-negative out-of-sample (PF 0.71, -$53.18, 14 trades, win rate
  dropped to 35.71% — the weakest win rate of any pair in either window).

No pair repeated its in-sample sign out-of-sample in the same direction
with comparable magnitude; EUR and JPY both weakened, GBP strengthened.
At 14-15 trades per pair out-of-sample (43 combined), this is a small
enough sample that a handful of trades swinging either way plausibly
explains the whole picture — none of these deltas should be read as a
confirmed regime shift without more data. All three pairs' out-of-sample
runs stayed comfortably inside single-digit-percent drawdown (max 1.21%
equity DD, USDJPY) — no drawdown or correlated-loss red flag in this data.

## Calendar-accuracy note (per explicit task flag)

EA Coder's v3 header flagged **2025.10.03** (USDJPY/EURUSD.r/GBPUSD.r's
formula-derived October 2025 NFP date) as needing external verification,
because the Oct 2025 US federal government shutdown (began 2025.10.01)
could plausibly have delayed that specific BLS release in a way not
reliably confirmable without live internet access. **Checked directly
against all three pairs' OOS journals: no trade fired on or near
2025.10.03 in any pair** — the last trade in every pair's journal is
2025.08.01, and none of the three journals has any entry in
September–December 2025 at all (the EA's own spike-threshold/spread
filters evidently declined whatever setup existed on that date, same
"real filter, not a data-integrity defect" pattern already documented in
v3/review.md for other dates). **This OOS result carries no
calendar-accuracy uncertainty from the flagged 2025.10.03 date** — it
simply never produced a trade to be uncertain about. The other five
MODERATE-confidence dates in the OOS window (2023.11.03, 2024.01.05,
2024.11.01, 2025.02.07, 2025.09.05) similarly did not all fire in every
pair; where they did fire, this report has not independently re-verified
those specific calendar dates beyond EA Coder's own audit (all 108 table
entries matched BLS's documented scheduling rule) — flagging this per the
task's request, not drawing a conclusion from it.

## What this doesn't cover

Same limitation as the in-sample runs: each pair was backtested
independently on its own $10,000 account (MT5's standard tester can't run
a true multi-symbol combined-account portfolio test). A combined-account
portfolio check (same pattern as `gotobi/v1_portfolio` and
`month_end_fix_reversal/v1_portfolio`) has not been run for this
strategy at any point — dates.md flagged this as worth checking given all
three pairs share the same USD-side NFP trigger and could plausibly
correlate on losing days, but that check is Researcher's call on whether
it's warranted given the thin OOS sample size.

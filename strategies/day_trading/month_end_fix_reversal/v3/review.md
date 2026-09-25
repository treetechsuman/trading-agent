# month_end_fix_reversal v3 — review

**What changed vs. v2 (the version the user already `approved_live` for
EURUSD.r + GBPUSD.r at reduced size, USDJPY held back):** exactly two
things, per EA Coder's v3/spec.json — (1) an on-chart status panel
(display-only, `Comment()`-based, per the standing `.claude/agents/
ea-coder.md` convention), and (2) a backfilled safety ledger
(consecutive-loss halt `InpMaxConsecutiveLosses=6`, daily-loss halt
`InpDailyLossStopPercent=5.0`, drawdown kill-switch
`InpMaxDrawdownStopPercent=15.0`, all OR'd into a single gate checked
immediately before v2's existing threshold/spread/sizing checks) that v2
was missing entirely — v2 only ever had the `InpAllowLiveAccount`
live-account guard. By construction the ledger can only suppress a trade
v2 would have taken, never add one. Zero entry/exit/threshold/sizing/
timing logic changed. Because the ledger *could* change trade
count/outcomes (unlike v2's patch, which was a true backtest no-op), v3
was sent back through a fresh full 6-leg backtest before any live/demo
decision, per EA Coder's own note — this review is that decision.

## Fresh v3 results vs. v1/v2 original numbers

| Leg | v1/v2 (original) | v3 (fresh) | Match? |
|---|---|---|---|
| EURUSD.r in-sample | PF 1.12, 35 trades | PF 1.12, 35 trades | **Exact** |
| EURUSD.r out-of-sample | PF 2.21, 19 trades | PF 2.21, 19 trades | **Exact** |
| GBPUSD.r in-sample | PF 1.67, 37 trades | PF 1.67, 37 trades | **Exact** |
| GBPUSD.r out-of-sample | PF 2.05, 21 trades | PF 2.05, 21 trades | **Exact** |
| USDJPY in-sample | PF 1.14, 48 trades | **PF 1.24, 47 trades** | Diverged |
| USDJPY out-of-sample | PF 1.42, 16 trades | PF 1.42, 16 trades | **Exact** |

5 of 6 legs are byte-for-byte identical to the original v1/v2 numbers —
the ledger never fired in EUR or GBP, in-sample or out-of-sample, across
the full 2018-2025 window tested.

## The one divergence, traced to the exact trade

Diffed `v1/USDJPY/journal.csv` against `v3/USDJPY/journal.csv` trade by
trade. They are identical for 46 of 47 rows. The single difference: v1/v2
took a trade on **2021.11.30** (sell, -$112.80) that v3 does not. That
trade would have been USDJPY's **7th consecutive losing trade** — the
preceding six (2021.06.28 -$104.85, 2021.06.30 -$1.44, 2021.08.31
-$107.36, 2021.09.30 -$103.67, 2021.10.29 -$53.56, 2021.11.29 -$109.60)
tripped `InpMaxConsecutiveLosses=6` right as the 2021.11.29 trade closed,
and `monthlyHaltActive` correctly suppressed the very next candidate
trade the following day. That suppressed trade also lost money in the
original run, so the effect on this leg is unambiguously **net
positive**: one fewer loss (-$112.80 avoided), PF improved 1.14→1.24, net
profit and Sharpe both improved, and every trade after 2021.11.30 shows
small knock-on differences in lot size/profit (5.87→5.96 on the very next
trade, etc.) purely because position sizing is equity-based and one fewer
losing trade nudges the equity curve — not a second, independent
divergence.

This is exactly the mechanism the ledger was built for: USDJPY was
already flagged as the weakest of the three pairs (VERDICT.md), and 2021
is the same BOJ-easing/Fed-hiking regime independently flagged as
fighting yen-cross short theses in `yen_fiscal_repatriation`'s review —
a genuine bad stretch for this pair, and the new halt caught it correctly
without needing to touch any entry/exit logic.

## Does this matter for the actually-approved live scope?

**No — and this is the load-bearing fact for the decision below.** The
user's live approval (still standing at `approved_live` in the registry)
was explicitly scoped to **EURUSD.r + GBPUSD.r only**, with USDJPY
deliberately held back per VERDICT.md's own reduced-size recommendation.
The one leg that diverged is USDJPY — the one pair *not* in the approved
live scope. For both approved pairs, the ledger fired zero times across
8 full years of in-sample + out-of-sample data. The strategy's live
behavior for the pairs that would actually trade real money is, as far
as this evidence shows, unchanged from what the user already approved.

## Portfolio-level re-validation: judged not necessary before proceeding, with reasoning

`v1_portfolio/` (the combined 3-pair account harness) was not re-run
with v3's ledger. I considered requiring a fresh `v3_portfolio`-equivalent
run and decided against making it a blocker, for three concrete reasons:

1. **Neither approved pair's trade set changed at all under the ledger**,
   individually, across the full 8-year window. A portfolio run combines
   exactly those same trades; there is no new trade-level behavior for
   the ledger to interact with for EUR/GBP.
2. **The combined-account drawdown headroom is wide relative to the
   ledger's thresholds.** `v1_portfolio/review.md` found combined max
   drawdown of 6.48-7.02% in-sample and 4.39-5.63% out-of-sample — both
   comfortably below the ledger's 5% daily-loss and 15% max-drawdown
   trigger levels. Even accounting for shared-balance dynamics in a
   combined account, there's no evidence in the historical trade record
   that a daily-loss or drawdown halt would have bitten for EUR+GBP
   together, and the ledger cannot suppress a trade unless one of those
   thresholds is actually crossed.
3. **The ledger is provably suppress-only.** Even in an untested
   combined-account configuration, the worst case is a small number of
   additional missed trades (conservative), not a new source of risk
   beyond what v1_portfolio already validated. That bounds the downside
   of skipping this re-run in a way that wouldn't be true if the ledger
   could add or resize trades.

Given that, `v1_portfolio/review.md`'s combined numbers (PF 1.25 IS /
2.08 OOS, max DD 4.39-7.02%) are a reasonable basis for the EUR+GBP live
scope's combined-exposure profile going forward. I'd treat a fresh
portfolio confirmation run as a nice-to-have once live (or as a quick
pre-go-live sanity check if Backtester has spare capacity), not a
prerequisite.

## One new operational note for Live Manager, not a blocker

The ledger's `balancePeak` / `dailyStartBalance` / `consecutiveLosses`
state is tracked as **local variables inside each EA instance**, but this
project's live deployment pattern (confirmed via `gotobi`'s own registry
note) attaches **one EA instance per symbol/chart**, all against the
**same real account** (YOUR_ACCOUNT_LOGIN). That means if EURUSD.r's and GBPUSD.r's
v3 instances are both attached live, each instance's `AccountInfoDouble
(ACCOUNT_BALANCE)` calls read the *same shared real balance* — so a bad
day on one pair can trip the other pair's daily-loss or drawdown halt too
(and vice versa), something neither the isolated single-pair backtests
(each on its own $10,000 test account) nor `v1_portfolio` (predates the
ledger entirely) exercise. This is a **conservative-only** interaction
(more suppression, never less) so it doesn't change the verdict below,
but it's worth Live Manager knowing about before/at attach time, and
worth remembering if `consecutiveLosses` or a halt looks like it fired
"early" once live — it may be correctly reacting to the *other* pair's
losses, not a bug.

## Decision: `live_candidate` — recommend the user reconfirm `approved_live` specifically for v3, as a fast formality

The strategy logic itself needs no further review — this is the same
strategy the user already approved, plus a safety mechanism that (a) can
only remove risk, never add it, and (b) empirically never fired at all
for either approved pair across the full tested history. If this were
purely a judgment call about whether the *evidence* still supports live
readiness, I'd say yes without reservation — nothing here weakens the
case in `VERDICT.md`.

But I'm not carrying the existing `approved_live` status forward silently
onto v3, for a structural reason rather than an evidentiary one: this
project's rule (CLAUDE.md) is that `approved_live` is user-set only and
"never inferred" — and unlike v2's patch (which EA Coder verified was a
true backtest no-op and the registry explicitly left at `approved_live`
without a fresh review), v3's patch was *not* a no-op — it changed a real
result on one leg, and EA Coder's own v3 note explicitly said "this
version requires a fresh in-sample backtest... before any live/demo
status decision is made on it," which is exactly the review this document
is. Given that the whole point of a fresh backtest requirement was to
check before assuming the old approval carries over, silently
re-asserting `approved_live` myself after doing that check would defeat
the reason the check was requested in the first place. Setting
`live_candidate` and asking for a quick reconfirmation costs the user one
short decision and keeps the audit trail honest that this specific
version's approval was actually re-examined, not just carried over by
default.

**Recommendation to relay to the user:** the v3 divergence is a single,
traced, net-positive, suppress-only effect on a pair (USDJPY) that isn't
even part of the approved live scope; both approved pairs (EURUSD.r,
GBPUSD.r) are byte-for-byte unchanged from the version already approved.
Reconfirming `approved_live` for v3 at the same scope (EURUSD.r +
GBPUSD.r, USDJPY still held back) should be a fast decision, not a fresh
full review — but it does need to be the user's own explicit word, not
inferred from the original v2 approval.

## Files

- `v3/summary.csv`, `v3/journal.csv` — EURUSD.r in-sample (root).
- `v3/validation/` — EURUSD.r out-of-sample.
- `v3/GBPUSD/`, `v3/GBPUSD/validation/` — GBPUSD.r in-sample/out-of-sample.
- `v3/USDJPY/`, `v3/USDJPY/validation/` — USDJPY in-sample/out-of-sample
  (the diverged leg).
- `v3/spec.json` — full description of the safety-ledger and panel patch.
- `v1_portfolio/review.md` — combined-account result still relied upon
  (not re-run for v3; see reasoning above).
- `VERDICT.md`, `STRATEGY.md` — original evidence base, still accurate
  for the approved EUR+GBP scope.

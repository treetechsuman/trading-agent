# nfp_fade v3 — review (correction + final in-sample decision)

**Reviewed:** 2026-09-23 | **In-sample data referenced:** 2017.01.01–2022.12.31 (v2's run — v3 is a confirmed no-op, no re-backtest needed) | **Status: proceeding to out-of-sample validation**

## What this review corrects

v2/review.md diagnosed a "table drift" bug: that v2's three per-symbol NFP release-date tables (one independently-typed table per EA instance, per this strategy's `one_ea_per_symbol_chart` design) disagreed with each other, having silently dropped two dates — 2022.02.04 (GBPUSD.r) and 2022.04.01 (USDJPY) — that v1's own research had already confirmed as real BLS releases. That was the basis for sending v3 back to EA Coder rather than proceeding to out-of-sample validation.

**That diagnosis was wrong at the premise level, not just in a detail.** EA Coder checked the actual v1/v2 source tree before coding v3 (per their role: verify a stated premise before either complying with it or silently second-guessing it) and found: `nfp_fade` has always been exactly ONE `strategy.mq5` file, written generically against `_Symbol`, deployed unmodified to all three chart instances (EURUSD.r / GBPUSD.r / USDJPY). There has never been a second, independently-typed copy of the NFP table for anything to drift from — the "three tables" I reasoned about in v2/review.md never existed. Direct inspection confirmed both dates I called "dropped" were present in v2's single table the entire time. EA Coder also ran a full (not sampled) audit of all 108 table entries against BLS's documented scheduling rule: 104/108 match the base rule exactly, the remaining 4 are exactly the already-known exceptions (2020.01.10, 2021.01.08, 2025.01.10, 2025.07.03). Zero anomalies. v3 as built differs from v2 only in version string and comments (confirmed via diff) — it is a functional no-op.

**Root cause of my error**: I inferred "three disagreeing tables" from a symptom (GBP/JPY trade-count differences on specific dates) without first confirming the premise that three independently-maintained tables actually existed in this codebase. They didn't — this project's actual convention for `nfp_fade` (unlike, say, `gotobi/v1_portfolio`, which genuinely does run distinguishable per-symbol logic in some variants) is one shared file. The real, mundane explanation for GBP and JPY not trading on those two specific dates is that this EA's own volatility-threshold/spread filters correctly declined those particular setups on those instruments on those dates — exactly what those filters are designed to do, not a data-integrity defect. Worth a one-line note, not further investigation.

## Verified numbers (re-confirmed directly against summary.csv, not trusted from any prior write-up)

Pulled directly from `v2/EURUSD/summary.csv`, `v2/GBPUSD/summary.csv`, `v2/USDJPY/summary.csv` on 2026-09-23:

| Pair | Trades | Profit Factor | Win rate | Net P&L | Max equity DD |
|---|---|---|---|---|---|
| EURUSD.r | 22 | 1.46 | 59.09% | +$116.86 | 1.87% |
| GBPUSD.r | 20 | 0.73 | 45.00% | -$96.04 | 1.97% |
| USDJPY | 25 | 1.31 | 52.00% | +$101.29 | 1.41% |
| **Combined** | **67** | — | — | **+$122.11** | all <2% |

These match v2/review.md's headline table exactly and match the numbers cited in the task brief that prompted this review. Since v3 is a confirmed no-op (identical table, identical logic, identical parameters), **v2's already-produced backtest is v3's backtest** — no re-run needed. I also re-verified v1's GBP PF while I was at it (v2/review.md had already caught and corrected an earlier brief's mis-citation of 0.79): `v1/GBPUSD/summary.csv` confirms v1's actual GBP PF was **0.47**, not 0.79 — that correction in v2/review.md stands and is accurate.

## Decision: proceed to out-of-sample validation (not discard)

With the false data-integrity concern resolved, the in-sample picture is unchanged from what it was always going to be once the (real) calendar-completeness fix landed in v2: net combined profit (+$122.11), one solidly positive pair (EUR, PF 1.46), one modestly positive pair (JPY, PF 1.31), one still-losing pair (GBP, PF 0.73, though improved from 0.47), all three pairs' max drawdown comfortably under 2%. This is squarely the "genuinely too thin to conclude either way, not decisively negative" bucket this strategy has sat in since v1 — 67 trades combined is well below this project's 200-trade significance bar, and nothing here is either strong enough to skip straight to a live recommendation or bad enough to discard outright.

That's exactly the situation this project's convention is built for: run the one-shot out-of-sample check to see whether the picture holds, degrades, or improves — the same next step already taken for `month_end_fix_reversal` (which itself never cleared 200 trades either, 174-176 combined, and still proceeded through OOS to a `live_candidate` verdict) and `gotobi`. Discarding now, before spending that one free look, would be premature: there is no structural red flag here (no correlated blowup, no drawdown near the kill-switch, no single-year-carries-the-average artifact detected in this data), the sample is thin because the event only happens ~12 times/year/pair, not because of any defect, and v3 is functionally free to run (no rebuild, no new compile risk — same binary logic as v2).

**Next step**: Backtester runs the out-of-sample window (2023.01.01–2025.12.31) once, unmodified, on v3's locked config (functionally identical to v2's — same table, same thresholds, same SL/TP, same sizing, same safety rules), same three pairs, same per-pair independent-account methodology as v1/v2. No further changes regardless of outcome, per this project's out-of-sample discipline — if OOS looks weak, that is reported as a finding, not treated as grounds to re-optimize.

**What would change this call**: if OOS comes back materially worse than in-sample (PF degradation beyond what a thin sample's normal variance would explain, or GBP's already-weak PF collapsing further with no offsetting improvement elsewhere), the next honest conclusion is discard or the same "structurally too low-frequency for this account's cost profile" read flagged since v1 — not another mechanism tweak, per house rule against re-optimizing off an out-of-sample result.

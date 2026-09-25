# nfp_fade v2 — review

**Reviewed:** 2026-09-23 | **In-sample:** 2017.01.01–2022.12.31 | **Status: refining (v3)**

## Headline results (per pair, independent $10k accounts)

| Pair | Trades (v1→v2) | PF (v1→v2) | Win rate | Net P&L | Max equity DD |
|---|---|---|---|---|---|
| EURUSD.r | 22 → 22 (+0) | 1.46 → 1.46 | 59.1% | +$116.86 → +$116.86 (unchanged) | 1.87% |
| GBPUSD.r | 17 → 20 (+3) | 0.47 → 0.73 | 45.0% | -$158.00 → -$96.04 | 1.97% |
| USDJPY | 20 → 25 (+5) | 1.00 → 1.31 | 52.0% | -$0.09 → +$101.29 | 1.41% |
| **Combined** | **59 → 67 (+8)** | — | — | **-$41.23 → +$122.11** | all <2% |

**Correction to the task brief's framing**: the brief states "GBPUSD.r got worse with more data (PF 0.79→0.73)". This does not match the source data — v1's actual GBP PF was **0.47** (v1/review.md line 10, v1/GBPUSD/summary.csv), not 0.79. GBP's PF **improved** from 0.47 to 0.73 with v2, same direction as USDJPY, not the opposite. Noting this explicitly since the review below is built from the primary journal/summary files, not the brief's headline numbers, and the correction changes the shape of the question being asked (both non-EUR pairs moved the same direction, not opposite directions).

67 trades combined is still well below the 200-trade significance bar. Still provisional.

## Part 1: is EUR's persistence actually informative?

**No — and this needs to be said plainly.** EURUSD.r's v2 journal is byte-for-byte identical to v1's (confirmed by diffing both `journal.csv` files: same 22 trades, same dates, same entry/exit prices, same P&L, same running balance). This is not independent replication of a result across two runs — it is the same 22-trade sample counted twice, because zero EUR calendar dates were added or dropped by the v2 table fix. Calling this "persistence across two independent runs" would overstate the evidence. The honest read is: EUR's PF 1.46 / 59.1% win rate is exactly as informative (or uninformative) as it was in v1/review.md — a single 22-trade sample, still well under the significance bar, neither confirmed nor newly supported by v2. Nothing changed for EUR; there's no new EUR evidence to weigh here at all.

## Part 2: GBP vs JPY — trend or noise, and a bug found while checking

Diffed v1 vs v2 journals trade-by-trade for GBP and JPY to see exactly which dates changed and why, since the brief's instruction was not to attribute P&L moves to anything but where recovered trades landed.

**GBPUSD.r (17→20, PF 0.47→0.73):** four dates added (2020.01.10 +$62.19, 2020.05.08 -$9.15, 2021.10.08 +$62.86, 2022.07.08 -$49.72), one date **dropped**: 2022.02.04 (+$4.61 in v1). Net +3 trades, net +$66.18 P&L from the four adds minus the one drop, accounting for the full -$158.00→-$96.04 move.

**USDJPY (20→25, PF 1.00→1.31):** six dates added (2018.10.05 +$62.98, 2019.03.08 +$24.10, 2020.05.08 -$48.80, 2021.06.04 -$49.14, 2021.10.08 +$59.36, 2022.07.08 +$8.28), one date **dropped**: 2022.04.01 (-$46.45 in v1). Net +5 trades, accounting for the full -$0.09→+$101.29 move.

**~~The two dropped dates are the real finding here.~~ SUPERSEDED — see the correction appended at the bottom of this file (2026-09-23).** The paragraphs originally here diagnosed the two dropped dates (2022.02.04 for GBP, 2022.04.01 for JPY) as evidence of a "three independently-typed per-symbol table" drift bug. That diagnosis was investigated by EA Coder before building v3 and found to be **factually wrong at the premise level**: this strategy has only ever had ONE `strategy.mq5` file, deployed unmodified to all three chart instances — there is no second table copy for anything to drift from, and both "dropped" dates were confirmed still present in v2's single table the whole time. The original text is left in place below (struck through in spirit, not literally deleted, per this project's convention of not rewriting history) for the record of what was originally claimed; do not treat the paragraphs immediately following this note as accurate.

**With the two dropped-date confounds isolated, the underlying trend is:** GBP moved from a clearly-losing PF (0.47) to a still-losing-but-less-bad PF (0.73) on 3 net new trades; JPY moved from flat (1.00) to modestly positive (1.31) on 5 net new trades. Both moves are driven by a handful of individual trade outcomes (each new trade is worth several PF points at n=20-25) — this is noise-level movement at this sample size, not a resolvable trend either direction. Neither pair's shift changes the v1 conclusion that the fade thesis is undecided on the available sample. (This paragraph's substance still holds — it was never dependent on the table-drift misdiagnosis, only on the trade-by-trade diff, which is correct.)

## Decision: ~~refining (v3) — targeted bug fix, not proceeding to OOS yet~~ SUPERSEDED

The original decision below (refining v3 to fix a "table drift" bug, deferring OOS) was made in good faith on a false premise. See `v3/review.md` for the corrected understanding and the actual final decision (proceed to out-of-sample validation). Original text preserved for the record:

Per house rule, no parameter sweep on a 67-trade sample, and the calendar-completeness diagnosis from v1 is already fixed — but this review surfaced a second, distinct, concretely-confirmed bug: **the three per-symbol NFP date tables are not consistent with each other or with v1's own already-validated ground truth**, having silently dropped two dates v1 had already confirmed as real BLS releases. This is a data-integrity defect in the current build, not a signal-quality question, and it is squarely the kind of single, causally-diagnosed fix this project's house rules permit outside of the review being over-thin — it's not a hopeful guess or a parameter retune.

**Why this blocks proceeding to out-of-sample now, rather than treating it as a minor footnote:** this project's convention treats out-of-sample validation as a one-shot check against a truly locked, trusted configuration ("used once, unmodified"). Spending that one shot on a build with a demonstrated, only-partially-audited table defect (2 confirmed errors out of the ~24 pair-months I had independent ground truth to check; the other ~84 in-sample and all 108 out-of-sample pair-months per pair are unverified) would risk having to discard and redo the OOS check anyway once the table is fixed, defeating the purpose of using it once.

**Exact change for EA Coder (v3):**
- Reconcile the three per-symbol NFP release-date tables (`EURUSD.r`, `GBPUSD.r`, `USDJPY` EA instances) into one verified, identical source of NFP calendar dates — the underlying event (BLS Employment Situation release) is not pair-specific, so all three tables should be byte-identical. Restore the two confirmed-dropped dates: **2022.02.04** (GBPUSD.r) and **2022.04.01** (USDJPY).
- Produce a full three-way diff across all 108×3 table entries (2017.01–2025.12) before recompiling, and report the diff explicitly (should be empty after the fix) — not just the two known corrections, since the mechanism that produced these two drops (per-symbol independent transcription) could have produced others not yet caught.
- No other change: measurement window, threshold, SL/TP, hold time, sizing, safety rules all stay byte-for-byte locked from v2, consistent with the original single-motivated-change discipline.
- Retest the same in-sample range (2017.01.01–2022.12.31) on the same three pairs. Once that comes back with all three tables confirmed byte-identical and the two errors corrected, **out-of-sample validation (2023.01.01–2025.12.31) on the same locked config is the natural next step** — this review is not a discard, and the underlying fade thesis is still exactly where v1 left it (too thin to conclude, not decisively negative).

**What would change this call**: if v3's reconciled sample is still well under 200 trades combined and the trend remains as mixed/flat as this review found (GBP still net-losing, JPY/EUR still only mildly positive, no resolution of the "is this noise" question), the honest conclusion after OOS is likely the same one flagged in v1/review.md: structurally too low-frequency (~12/year/pair) for this account's cost profile to ever reach statistical confidence on its own — worth deciding then whether a portfolio-combined view (as done for gotobi/month_end_fix_reversal) changes that picture, rather than another mechanism tweak.

---

## CORRECTION (2026-09-23, post-v3 investigation) — see v3/review.md for the full corrected decision

EA Coder investigated the "table drift" diagnosis above before building v3 (per their role: verify premises, don't silently comply with a mistaken one) and found it does not match the actual codebase: `nfp_fade` has always been exactly ONE `strategy.mq5` file, generic against `_Symbol`, deployed unmodified to all three chart instances (EURUSD.r/GBPUSD.r/USDJPY) — there was never a second, independently-typed table for anything to drift from. Both dates flagged above as "dropped" (2022.02.04, 2022.04.01) were confirmed still present in v2's single table the entire time. EA Coder additionally ran a full programmatic audit of all 108 table entries against BLS's documented scheduling rule: 104/108 match the base rule exactly, the other 4 are exactly the 4 already-known exceptions (2020.01.10, 2021.01.08, 2025.01.10, 2025.07.03) — zero anomalies found anywhere in the table. v3 as built is a no-op relative to v2 (version string/comments only, confirmed via diff) — **v2's backtest results above stand as the correct, trustworthy numbers**, independently re-verified directly against `v2/EURUSD/summary.csv`, `v2/GBPUSD/summary.csv`, `v2/USDJPY/summary.csv` on 2026-09-23: EURUSD.r 22 trades/PF 1.46/net +$116.86; GBPUSD.r 20 trades/PF 0.73/net -$96.04; USDJPY 25 trades/PF 1.31/net +$101.29; combined 67 trades/net +$122.11 — matching this review's table exactly.

The real, mundane explanation for GBP/JPY's non-trades on those two specific dates is that this EA's own volatility-threshold/spread filters correctly declined those particular setups on those instruments — not missing data. That's exactly what those filters are for and needs no further investigation.

**Final decision (superseding this review's "refining v3" call above): proceed to out-of-sample validation.** See `v3/review.md`.

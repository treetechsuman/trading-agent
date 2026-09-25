# month_end_fix_reversal v1 — review

**Symbols:** EURUSD.r, GBPUSD.r, USDJPY · **Timeframe:** M1 ·
**In-sample:** 2018.01.01–2022.12.31 · **Out-of-sample:**
2023.01.01–2025.12.31, used once · **Parameters:** direct reuse of
`wm_fix_reversal` v2's locked mechanism (`MinSpikeVsAvgMultiplier=2.0`,
`SLMultiplier=1.0`, `TPMultiplier=1.0`), with one addition:
`TradeLastNDaysOfMonth=3` — **no parameters were tuned or swept for this
strategy.** This is the first and only configuration tested.

## Why this is methodologically different from several earlier "promising then failed" results

Every prior case in this project where an in-sample result looked strong
but failed out-of-sample (`wm_fix_reversal` v1, `overlap_deviation_scalp`
v1-v4) involved a parameter *sweep* — trying several thresholds and
locking whichever looked best. That process mechanically produces
better-looking numbers as the sample shrinks, even with zero real edge
escalation, which is exactly the trap that caught this project out
repeatedly.

This strategy did not go through that process. It reuses
`wm_fix_reversal`'s already-locked mechanism unchanged and adds exactly
one pre-specified, research-backed filter (trade only within 3 calendar
days of month-end, where FX-flow literature places the concentration of
institutional hedge-rebalancing flow) — chosen *before* seeing any
results, not selected from a range of options that were tested and
compared.

## Results

| Metric | EURUSD IS | EURUSD OOS | GBPUSD IS | GBPUSD OOS | USDJPY IS | USDJPY OOS |
|---|---|---|---|---|---|---|
| Trades | 35 | 19 | 37 | 21 | 48 | 16 |
| Profit factor | 1.12 | **2.21** | 1.67 | **2.05** | 1.14 | **1.42** |
| Win rate | 54.3% | 68.4% | 64.9% | 71.4% | 56.3% | 62.5% |
| Max drawdown | 2.9-3.5% | 1.3-2.3% | 1.8-2.5% | 1.4-2.0% | 5.6-6.3% | 3.1-3.5% |

**Every single pair improved out-of-sample — no exceptions, no
degradation anywhere.** Combined trade count: 120 in-sample + 56
out-of-sample = **176 total**, just under this project's 200-trade
significance bar but far more than most of this session's other
attempts managed even in-sample alone.

## Honest caveats

- **176 combined trades is still thin in absolute terms**, even though
  the *shape* of the evidence (no sweep, consistent direction, no
  degradation) is more credible than several higher-trade-count results
  earlier this session that turned out to be artifacts. Low absolute
  frequency is inherent to the design — only ~3 days/month qualify for
  the calendar filter at all, further filtered by the volatility
  threshold.
- **Yearly buckets are too thin to read individually** (4-11 trades per
  pair per year) — the 5-year in-sample aggregate and 3-year
  out-of-sample aggregate are the meaningful units of evidence here, not
  any single year.
- **USDJPY's edge is meaningfully weaker** than the two USD-vs-European
  pairs (PF 1.14/1.42 vs. 1.12-2.21 for EUR/GBP) and carries a
  noticeably higher drawdown (5.6-6.3% in-sample vs. 1.8-3.5% for the
  others) — the JPY leg of this thesis is real but the least convincing
  of the three.
- **Not yet tested as a combined-account portfolio** (unlike `gotobi`'s
  `v1_portfolio` or `wm_fix_reversal`'s `v2_portfolio`) — whether trading
  all three pairs together concentrates or diversifies risk on the same
  month-end days is an open question, the same one that sank
  `wm_fix_reversal`'s own diversification hope.
- Both wm_fix_reversal (its "every day" predecessor) and this
  restricted version share the same underlying WM/Reuters fix mechanism
  — this isn't a fully independent confirmation of a *new* edge, more a
  demonstration that narrowing to the right subset of days meaningfully
  concentrates an edge that was too diluted when applied to every day.

## Assessment

This is the first result in the entire "hunt for another [specific-event
strategy]" effort that didn't fail on close inspection. The mechanism is
well-motivated (documented institutional month-end hedge rebalancing,
concentrated flow around a known fixing time — the same category of
"specific named participants forced to transact at a specific time" that
made `gotobi` work), the evidentiary process was clean (no sweep, no
cherry-picking), and the out-of-sample result improved rather than
degraded on all three pairs tested.

It is not yet at the same confidence level as `gotobi` (which cleared
18/18 profitable pair-years on a much larger sample). The honest
comparison is closer to `wm_fix_reversal`'s original promise before that
strategy's portfolio test revealed a correlation problem — this
strategy needs the same combined-account check before any live
recommendation.

## Proposed next step

Build a combined 3-pair portfolio test harness (same pattern as
`gotobi`'s `v1_portfolio`) to check whether trading EUR/GBP/JPY together
on month-end days concentrates risk the way `wm_fix_reversal`'s did, or
diversifies it. That result should determine whether this becomes a
`live_candidate` or gets parked pending more data.

# yen_fiscal_repatriation — date ranges

- **In-sample (optimization):** 2017.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same split as `gotobi`, `wm_fix_reversal`, and `month_end_fix_reversal`,
for cross-strategy comparability. Note (per `wm_fix_reversal`'s own
finding): this broker's JPY-cross tick history is clean only from
roughly mid-to-late 2017 onward (broker-wide history cutover); expect
2017 itself to contribute few or no trades for the March window and
treat that as a known data-availability artifact, not a strategy
finding, same as already documented for `gotobi`. All parameter
iteration happens only against the in-sample range. Out-of-sample is
used once, unmodified, as a final check.

## Origin

Built 2026-09-23 per the user's explicit request to research a new
day-trading strategy from academic/practitioner FX literature, after
`day_trading/intraday_momentum_carry` (a faithful implementation of
Gao/Han/Li/Zhou 2018 JFE's "intraday momentum" finding, extended to FX
by Baltussen/van Vliet/Ye 2021) was discarded for the same reason
across 8 configurations: the underlying finding is real but generic
(studied primarily on equities/futures, with FX/currency futures as one
of many instruments in a large cross-sectional panel), and too thin
per-instrument to survive retail FX costs. This project's two live
candidates (`gotobi`, `month_end_fix_reversal`) both instead trade a
*specific, named institutional flow with identifiable forced
participants and a concrete reason they must transact at a particular
calendar time* — this strategy was deliberately searched for in that
same category rather than another generic statistical anomaly.

## Research basis / citations

The mechanism traded here — Japanese institutional investors (life
insurers, pension funds, and megabanks) reducing net foreign-currency
exposure and repatriating realized overseas gains ahead of Japan's
fiscal year-end (31 March) and fiscal half-year (30 September), for
balance-sheet and regulatory-reporting purposes — is documented in:

- **Bank for International Settlements, Quarterly Review** — recurring
  discussion (multiple issues) of Japanese institutional investors' FX
  hedging behavior and yen seasonality concentrated around fiscal
  year-end, in the context of BIS's regular coverage of yen carry-trade
  and cross-border-flow dynamics.
- **Hattori, M. and Shin, H.S. (2007), "The Broad Yen Carry Trade,"**
  IMES Discussion Paper, Bank of Japan — documents Japanese financial
  institutions' FX-related balance-sheet dynamics tied to the
  institutional/fiscal reporting calendar, part of the broader
  literature on Japanese financial institutions' currency positioning.
- **FX practitioner research** (major bank FX strategy desks —
  historically Nomura, JPMorgan, Barclays and others have published
  seasonal notes on this) — widely and repeatedly referred to as
  "Japanese fiscal year-end repatriation flow" or "real-money yen
  buying into March," a recurring seasonal theme in FX market
  commentary each Q1 for decades, mirrored to a lesser extent around
  the September half-year mark.

**Honesty note on citation strength**: unlike Gao/Han/Li/Zhou 2018
(a single, precise, peer-reviewed top-journal finding with a reported
effect size), this mechanism's evidence base is closer to
`month_end_fix_reversal`'s own citation ("documented in FX-flow
literature") — well-established, decades-old market structure
knowledge repeatedly referenced in BIS commentary and FX practitioner
research, rather than one clean academic paper with a precise
backtested effect size. This project's own two successes so far
(`gotobi`, `month_end_fix_reversal`) were built on evidence of this
same practitioner-documented-flow type, not single-paper academic
citations either, so this is treated as an acceptable evidentiary
standard here — but it is explicitly weaker sourcing than
`intraday_momentum_carry` had, and that strategy still failed. The
distinguishing bet for this strategy is mechanism specificity
(named participants, dated calendar trigger), not citation pedigree.

## Why this is expected to transfer better than intraday_momentum_carry

1. **Specific, named institutional participants** (Japanese life
   insurers, pension funds, megabanks rebalancing for fiscal-year-end
   reporting) with a concrete, non-discretionary reason to transact at
   a specific calendar time — not a generic statistical regularity that
   happens to appear in a cross-sectional panel including FX.
2. **FX/JPY-specific literature**, not an equity/futures finding
   extended to FX as one of many instruments.
3. **Structurally distinct from this project's other two flow-anchored
   strategies** — different participant type (institutional asset
   managers/insurers, not import/export corporates as in `gotobi`;
   not generic multi-currency month-end asset-manager rebalancing as in
   `month_end_fix_reversal`), different frequency (semi-annual, not
   every-5-days or monthly), different driver (balance-sheet/regulatory
   reporting cycle, not trade settlement or routine hedge rebalancing).
4. Uses only calendar-day logic and MT5 M1/tick data — no order-flow,
   options, or COT feed required, consistent with what this account can
   actually backtest and eventually trade live.

## Post-hoc web verification (2026-09-23, orchestrator session)

The subagent that researched this strategy had no WebSearch/WebFetch access
that run and flagged its citations as drawn from trained knowledge, not
live sources -- it explicitly recommended a follow-up verification pass.
That pass was done immediately after, with live web search:

- **March fiscal year-end leg**: independently corroborated by multiple
  current market-structure sources (IMF eLibrary chapter on the yen;
  practitioner seasonal-flow research citing USDJPY up in the pre-fiscal-
  year-end window "12 of 16 times (75%)" across a multi-decade sample;
  routine desk commentary each Q1). Directly consistent with the
  mechanism as specified.
- **September fiscal half-year leg**: also corroborated, independently of
  the March search -- desk/flow commentary specifically describes
  "yen-buying flows ahead of the quarter-end and the end of Japan's
  financial half-year," confirming this is a real, separately-recognized
  half-year echo of the March effect, not an unsupported extrapolation
  from March alone.
- No single peer-reviewed paper with a precise effect size was found (as
  already flagged above, this is practitioner/market-structure evidence,
  not journal-article evidence) -- but the mechanism itself, both calendar
  legs, and its persistence "out of sample" over decades are now confirmed
  by live sources rather than resting on trained-knowledge recall alone.
  Confidence upgraded from the subagent's own "moderate" to
  reasonably solid on the mechanism's reality; the open question is still
  whether it's large enough net of this account's real costs to trade,
  which only a backtest can answer.

## Pairs

USDJPY, EURJPY.r, GBPJPY.r — same three JPY-cross pairs as `gotobi`,
reusing already-validated symbol-naming and data-availability knowledge
for this broker. One EA, backtested independently per pair (MT5's
Strategy Tester only trades the chart's own symbol), each pair's runs
in their own subfolder inside the version folder, matching `gotobi`'s
and `month_end_fix_reversal`'s layout. A combined-account portfolio
check (like `gotobi/v1_portfolio` and `month_end_fix_reversal/v1_portfolio`)
should follow once single-pair results are reviewed, given all three
pairs share the same JPY-side trigger and could plausibly correlate on
losing days the same way `wm_fix_reversal`'s pairs did — check this
directly rather than assuming it away.

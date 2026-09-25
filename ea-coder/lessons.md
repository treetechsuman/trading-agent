# EA Coder — lessons

Seeded 2026-09-22 from this project's history prior to the multi-agent
restructure. Keep appending after every compile attempt (success or
failure) — this file is the only cross-session memory for coding
mistakes and MQL5/MT5 gotchas.

## Strategy Tester environment gotchas

- **`TimeGMT()`/`TimeLocal()` do not reflect simulated time inside the
  Strategy Tester** — they return the real host clock. Any spec giving
  times in UTC must be implemented against `TimeCurrent()` (broker/server
  time) with the broker's UTC offset hardcoded to match whatever schedule
  the spec provides (e.g. gotobi's entry time was specified as broker-clock
  03:45 Mar-Oct / 02:45 Nov-Feb by the user, precomputed from 00:45 UTC —
  implemented as a plain per-month branch on `MqlDateTime.mon`, not a
  runtime GMT calculation). Found while building `gotobi/v1`.

- **`ACCOUNT_FREEMARGIN` is deprecated** — compiles with a warning, use
  `ACCOUNT_MARGIN_FREE` instead. Caught during `gotobi/v1`'s first compile
  (warning, not an error, but fix it — keep compiles at 0 warnings).

- **`CTrade` is not bound to `_Symbol`** — `trade.Sell(lots, symbol, price,
  sl, tp)` and `trade.PositionClose(symbol)` both take an explicit symbol
  argument, which is what lets one EA instance manage positions on symbols
  other than its own chart. Used in `gotobi/v1_portfolio/strategy.mq5` to
  run three pairs (USDJPY, EURJPY.r, GBPJPY.r) from one instance against
  one shared account, needed because MT5's Strategy Tester only drives
  `OnTick()` for the chart's own symbol (but still evaluates SL/TP for
  other symbols correctly via its own internal engine — only the
  *management* logic, e.g. the scheduled-time exit, is gated by the
  driving chart's tick cadence).

- **CRITICAL when one `CTrade` object trades multiple symbols with
  different magic numbers: `trade.SetExpertMagicNumber(magic)` must be
  called again immediately before EVERY `PositionClose()` call, not just
  before the opening `Sell()`/`Buy()`.** A single shared `CTrade` instance
  only tracks ONE "current" magic number at a time. If you open positions
  for symbols A, B, C in a loop (setting the magic fresh before each
  `Sell()`), the trade object is left holding symbol C's magic when the
  loop ends. Later, when closing A's or B's position, `PositionClose()`
  gets tagged/validated against the *trade object's* current magic (C's),
  not the position's own actual magic — the close request gets silently
  rejected (retcode 10006, "rejected") every single time, forever, with
  no exception thrown and no obvious error unless you check the return
  value and `ResultRetcode()` explicitly. Found in `gotobi/v1_portfolio`:
  a USDJPY position sat open for **4+ years** (only closing when price
  eventually revisited its original stop-loss level) because GBPJPY.r
  happened to be the last symbol entered each day, leaving USDJPY's and
  EURJPY.r's closes permanently mismatched. The backtest's aggregate
  result looked like a real ~78% drawdown catastrophe until traced to this.
  **Fix**: call `trade.SetExpertMagicNumber(magic)` right before every
  `PositionClose()`/`PositionModify()` call too, not just opens — or use a
  separate `CTrade` instance per symbol/magic if managing more than one
  concurrently. Always check `PositionClose()`'s return value and log
  `trade.ResultRetcode()` on failure during development of any multi-
  symbol EA — this bug produced zero errors or warnings at compile time
  and no runtime exception, only silent, permanent rejection.

- **Position sizing: round down, never up.** When a computed lot size
  (from risk % ÷ stop distance ÷ tick value) rounds below the broker's
  minimum lot via `SYMBOL_VOLUME_MIN`, skip the trade entirely rather than
  flooring up to the minimum — flooring up silently exceeds the spec's
  intended risk. (`london_range_fade`'s original `CalculateLotSize`
  *did* floor up to the minimum — fine for that spec, which didn't say
  otherwise, but `gotobi`'s spec explicitly required skip-on-below-minimum,
  so check what the spec actually says rather than copying the pattern by
  default.)

- **`input group "Label"` syntax exists in modern MQL5** but wasn't tested
  against this project's MetaEditor build — avoided it in `gotobi/v1` in
  favor of plain `input` declarations with comments, matching the existing
  `london_range_fade` style, purely to avoid an unverified risk. Worth
  testing directly if grouped inputs would meaningfully help EA readability
  later.

## Process note

`run_backtest.py` auto-extracts every `input` declaration's literal
default straight from the `.mq5` source to build `[TesterInputs]` (see
`backtester/lessons.md` for why). This only works if every tunable value
is a proper `input <type> Name = value;` at file scope — don't bury a
"default" inside `OnInit()` logic where the regex-based extractor can't
see it.

## day_trading/yen_fiscal_repatriation/v1 (2026-09-23)

Compiled clean, 0 errors/0 warnings, first attempt. Straightforward
adaptation of `gotobi/v1`'s single-symbol-chart calendar-window template
(see that file for the base pattern this reuses almost line-for-line:
`ResetDayState`/day-id change detection, `CalculateLotSize` round-down,
`CloseStalePosition` at `OnInit`, `OnTradeTransaction`-driven
consecutive-loss ledger, daily-loss/drawdown halts, `InpAllowLiveAccount`
gate). Two spec-translation judgment calls worth flagging for future specs
in this family:

- **Fixed-clock exit (not entry+hold-minutes) needs its own Summer/Winter
  server-hour inputs, computed independently from the entry's.** gotobi's
  exit was `entryWindowStart + InpHoldMinutes*60` (relative to nominal
  entry); this spec's exit was a separate fixed UTC time (09:00) unrelated
  to the entry's, so it needed its own `InpExitHourSummer/Winter` +
  `InpExitMinuteSummer/Winter` inputs and its own conversion inside
  `ResetDayState`, computed the same way as the entry window but off a
  different `MqlDateTime` copy (`e` vs `w`). Don't reuse gotobi's
  hold-minutes pattern by default — check whether the spec's exit is
  clock-fixed or entry-relative before choosing which pattern to copy.

- **When a spec's halt-resume condition is "next qualifying window" (not
  "next calendar month" like gotobi's), key the resume check off
  `year*12+month` compared against the halt-set window's own month, and
  only evaluate it on days where the window-membership flag is already
  true** (i.e. inside `CheckWindowHaltResume`, gated by `isFiscalWindowDay`
  before the month comparison). This correctly waits through the dead
  months between windows (e.g. April–August) rather than lifting the halt
  on the first day of the next calendar month the way gotobi's
  `CheckMonthlyHaltResume` intentionally does (gotobi trades every month,
  so "next month" and "next qualifying window" are the same thing for it —
  they are NOT the same for a strategy with only 2 windows/year, don't
  copy gotobi's exact resume trigger unmodified for those).

- Also note: this spec's `entry.skip_conditions`/timing block omitted the
  `late_entry_grace_minutes` field that gotobi's own spec had stated
  explicitly. Some non-zero grace window is a coding necessity regardless
  (OnTick ticks won't land on an exact second), so I added
  `InpLateEntryMinutes=10` mirroring gotobi's value as a pure
  implementation detail (not a strategy-logic invention) and flagged it
  back to Researcher/orchestrator in the handoff rather than silently
  assuming it was fine. Worth Researcher adding this field explicitly to
  future specs in this family so it's not left to EA Coder's discretion.

## day_trading/london_breakout_retest/v1 (2026-09-23)

Compiled clean, 0 errors/0 warnings, first attempt. First strategy in this
project needing TWO timeframes from one chart (M15 execution + H1 context
filter) -- straightforward in practice: `iOpen`/`iClose`(`_Symbol`,
`PERIOD_H1`, 1) just works from an M15 chart without attaching a second
chart or `iCustom`; shift 1 (not 0) is the reliable way to mean "most
recently CLOSED H1 candle" regardless of where in the current M15/H1 tick
cycle `OnTick()` fires, since shift 0 may still be forming. Worth
remembering for any future multi-timeframe spec: no special handling
needed, `iOpen`/`iHigh`/`iLow`/`iClose`/`iTime` all accept any
`ENUM_TIMEFRAMES` for the chart's own symbol directly.

- **Multi-step intraday state machines (breakout -> retest -> rejection,
  as opposed to gotobi/yen_fiscal's single fixed-clock trigger) are best
  driven off an explicit "new completed bar" event, not per-tick
  re-evaluation.** Tracked `lastProcessedBarTime` and only called the
  bar-evaluation function when `iTime(_Symbol, PERIOD_M15, 1)` changes --
  avoids re-processing the same closed bar on every tick (which would be
  harmless here since state is idempotent/gated by flags, but would spam
  `Print()` and waste cycles, and would NOT be harmless for a spec where
  the same event should only be allowed to fire once).

- **Computing a finalized range over a past time window (Asian
  high/low) is more robust done as a single backward bar-scan at the
  moment the window closes, than accumulated incrementally tick-by-tick.**
  Implemented `FinalizeAsianRange()` to loop `iTime`/`iHigh`/`iLow` at
  increasing shift until the bar's open time falls before the window
  start, called once (gated by a `asianRangeReady` flag) as soon as
  `TimeCurrent() >= asianWindowEnd`. This also correctly handles EA
  (re)start mid-day after the window already closed -- an incremental
  tick-driven accumulator would silently miss any bars that closed before
  the EA started.

- Reused gotobi's DST-table/day-state-reset/safety-ledger/CTrade
  conventions unmodified (single-symbol-per-chart, not the portfolio
  pattern -- this spec explicitly runs one EA per pair's own chart for
  v1). No new gotchas found in that part.

## day_trading/nfp_fade/v1 (2026-09-23)

Compiled clean, 0 errors/0 warnings, first attempt. First strategy needing a
**per-calendar-year, dual-DST-calendar** clock conversion (US federal DST for
an 8:30am ET release time, combined with the broker's own EU-based server
DST) rather than gotobi's flat month-based "Mar-Oct summer / Nov-Feb winter"
shortcut -- that shortcut is a whole-month simplification that would silently
misfire by a full hour for NFP specifically, since NFP's trigger day is
always in days 1-7 of the month, always on the *wrong side* of gotobi's
March/October transition-week edge case relative to the real EU last-Sunday
cutover (day ~25-31).

- **Computing DST boundaries from first principles (Nth-weekday-of-month
  arithmetic) generalizes cleanly across all twelve months without any
  month-by-month branching**, and is more robust than hand-transcribing a
  derived table: implemented `NthSundayDay(year, mon, n)` (second Sunday of
  March, for US DST start) and `LastSundayDay(year, mon)` (last Sunday of
  March/October, for broker DST) as generic helpers, then simply compared
  the trigger date against the computed start/end dates for that specific
  year (`usDstStart <= triggerDate < usDstEnd`, same pattern for the broker
  side). This one piece of logic correctly handles every month including
  November's year-dependent "still EDT vs already EST" case (majority
  outcome 7/9 years in this project's 2017-2025 window, confirmed against
  dates.md's hand-verified table) with no special-casing at all -- the
  general comparison already produces the right answer for every month
  because a first-Friday day (1-7) can never coincide with a Sunday
  (different weekdays), so date-only (midnight) comparison is always safe,
  no same-day ambiguity to worry about.

- **MQL5 has no standalone "run a function and print the result" harness
  outside attaching an EA/script to a chart or the tester** -- for a
  calendar-math function like this, the safest low-friction verification is
  a line-for-line Python translation of the exact same helper functions
  (same algorithm, same variable names/structure) run standalone, rather
  than trying to rig a throwaway MQL5 script through the chart/tester
  pipeline just to print two numbers. Confirmed both of dates.md's explicit
  spot-check dates (2024.03.08 -> 15:30 server, 2023.11.03 -> 14:30 server)
  plus all 9 hand-verified November years and a full representative-year
  month table -- zero mismatches. This is a validation of the *algorithm's
  logic*, not the MQL5 compiler itself, but for pure calendar arithmetic
  with no MQL5-specific behavior involved, a faithful translation is a
  reliable substitute given the tooling constraint.

- Reused gotobi's day-state-reset/safety-ledger (consecutive-loss pause
  resuming "first day of next month" -- correct here since NFP trades every
  month, same cadence as gotobi, unlike yen_fiscal_repatriation's sparse
  windows)/daily-loss/drawdown-halt/`CloseStalePosition`/`InpAllowLiveAccount`
  gate conventions, and month_end_fix_reversal's spike-measure-then-fade
  window/rolling-history-average/`ACCOUNT_EQUITY`-based risk-percent sizing
  structure, unmodified. No new gotchas in either of those parts.

## day_trading/nfp_fade/v2 (2026-09-23)

Compiled clean, 0 errors/0 warnings, first attempt. Single-motivated-change
refinement (see v1's entry above for the base strategy): replaced the
"first Friday of month, days 1-7" calendar-trigger approximation with a
hardcoded 108-entry table (2017.01-2025.12) of actual historical BLS
Employment Situation (NFP) release dates, per v2/spec.json's exact,
narrowly-scoped instruction. Confirmed via `diff` against v1's source that
the ONLY changes are the version string, the new table/lookup function,
and the single line in `ResetDayState` that selects `isNfpDay` from table
membership instead of `s.day_of_week==5 && s.day<=7` -- every other input,
value, and code path is byte-for-byte identical to v1.

- **Building a "real-world historical fact table" (not a strategy
  parameter) needs its own validation methodology, separate from a
  compile-clean check.** No internet/browse tool was available in this
  coding session, so the table couldn't be fetched fresh from bls.gov as
  the spec asked. Instead: derived BLS's own documented scheduling rule
  algorithmically (release = the Friday 3 calendar weeks after the
  Saturday closing the reference week containing the 12th of the reported
  month), then cross-validated that formula against 10+ independently-
  known real dates already sitting in this project's own `v1/review.md`
  (dates Researcher had separately confirmed against real BLS history
  while investigating v1's 59 trades) -- every single one matched exactly
  before trusting the formula for the full 108-entry table. This is a
  meaningfully different verification posture than the DST-conversion
  logic (`ea-coder/lessons.md`'s nfp_fade/v1 entry above), which was
  validated by translating the *algorithm* faithfully; here the risk is a
  *data* error (BLS's actual historical schedule), not an algorithm error,
  so the validation had to be against independently-known real-world
  dates, not just internal consistency.

- **A "hardcoded calendar-event table" spec should not silently assume
  every entry falls on the same weekday.** While deriving the table, found
  a third case (beyond the spec's two named Jan 2020/Jan 2021 exceptions)
  where BLS's actual schedule isn't even a Friday: 2025.07.03 (Thursday),
  because the formula's computed date landed on July 4th (Independence
  Day). The v1 code's `isNfpDay` check was `s.day_of_week==5 && s.day<=7`
  (Friday-gated) -- if v2 had kept that Friday gate while only swapping in
  a table for *which* Friday, this date would have been silently dropped
  again, reproducing exactly the bug being fixed. Fix: make table
  membership (exact date match) the sole source of truth for
  `isNfpDay`, with no day-of-week precondition at all.

- **When a spec explicitly asks EA Coder to flag confidence level on a
  sourced data table**, do so plainly in the registry note per-tier (e.g.
  "high confidence: X, Y" vs "moderate confidence, not independently
  re-verified against a primary source: Z") rather than a single blanket
  confidence statement -- some parts of a derived table can be far more
  validated than others (here: the general rule + 2 original exceptions =
  high confidence; 2 additional self-discovered exceptions + ~100
  formula-only entries = moderate confidence, explicitly recommended for a
  follow-up spot-check by Backtester/Researcher against a live source).

## day_trading/nfp_fade/v3 (2026-09-23)

Compiled clean, 0 errors/0 warnings, first attempt. Task brief and
v2/review.md both described the bug to fix as "three independently-typed
per-symbol NfpReleaseTable copies that disagree with each other" (one per
EA instance -- EURUSD.r/GBPUSD.r/USDJPY). **Before coding, checked the
actual v1/v2 source tree (per this project's own instruction to check how
prior versions organized multi-symbol EAs before assuming) and found that
premise does not match reality**: `find`-ing the whole `nfp_fade/` tree
for `*.mq5` turned up exactly two files total across v1 and v2 combined
(`v1/strategy.mq5`, `v2/strategy.mq5`) -- ONE file per version, generic
against `_Symbol`, deployed unmodified to all three chart instances. There
has never been a second, independently-typed copy of `NfpReleaseTable` in
this codebase for it to drift from.

- **A journal-level trade-count difference between symbols is not proof of
  a per-symbol calendar-table difference when the EA is actually one
  shared file.** Re-verified directly: both dates v2/review.md called
  "dropped" (2022.02.04, 2022.04.01) were already present in v2's single
  table. The GBP/JPY trade-count deltas the review traced per-pair almost
  certainly came from this EA's own signal filters (spike-vs-threshold,
  spread, price-data availability) legitimately differing per instrument
  on the same calendar date -- not from the calendar table, since only one
  table exists. Flagged this back to Researcher explicitly in the file
  header and registry note rather than fabricating three separate
  per-symbol files just to match a premise the actual codebase doesn't
  have -- per this role's "note discrepancies, don't silently second-guess
  *or* silently comply with a mistaken premise" instruction. Kept the
  existing single-file convention (structurally safer than introducing
  three copies now, since there is no second copy to diverge from).

- **For a "verify every entry against a documented rule" audit
  requirement, brute-force check ALL entries programmatically rather than
  re-spot-checking a sample.** Wrote a throwaway Python script (table
  transcribed from the .mq5 source, not re-derived by hand) implementing
  BLS's documented rule (release = the Friday 20 calendar days after the
  Saturday closing the reference week containing the 12th of the
  **reported** month, i.e. one calendar month before the release month --
  note this is the *reported* month, not the release month itself; using
  the release month directly is an easy off-by-one-month mistake here).
  Checked all 108 entries: 104/108 matched the base rule exactly, and the
  remaining 4 were exactly the 4 already-documented exceptions (2020.01.10,
  2021.01.08, 2025.01.10, 2025.07.03) -- zero new, previously undocumented
  anomalies found anywhere in the table. This is strictly stronger
  evidence than the original 10-date spot-check and is cheap to do
  whenever a spec asks for full-table verification against a stated rule.

- **2023-2025 out-of-sample spot-check (>=10 dates, no internet access)**:
  used recalled real-world market events tied to the specific release date
  (not just formula output) for the HIGH tier -- e.g. 2023.03.10 (SVB
  collapse same day), 2023.04.07 (Good Friday release), 2024.08.02 (weak
  report, "Sahm rule" selloff). MODERATE tier for rule-consistent dates
  without a specific recalled event. Flagged 2025.10.03 specifically as
  needing external verification since the Oct 2025 US federal government
  shutdown (began 2025.10.01) could plausibly have delayed that release in
  a way not reliably in-session-recallable -- worth Researcher/Backtester
  checking before trusting that one month during OOS validation.

## day_trading/month_end_fix_reversal/v2 (2026-09-23) -- retrofit InpAllowLiveAccount gate

**Every strategy coded from now on must include the `InpAllowLiveAccount`
live-safety gate (gotobi/v1's exact pattern) from its very first version --
don't wait for a version to reach `approved_live` before adding it.**

v1 of this strategy compiled clean and passed all the way through
Researcher's verdict, user approval, and into `approved_live` with NO
live-account safeguard at all -- `grep`-ing the full source for
`LiveAccount|TRADE_MODE|REAL` returned zero matches, unlike sibling
`gotobi/v1` which has always had this gate. It was only caught when Live
Manager actually attempted the deployment and hit a hard stop per its own
hard rule 4 (every EA deployed here must already declare an
`InpAllowLiveAccount`-style input). Nothing was ever exposed to real risk
(Live Manager correctly refused to attach), but this was a late,
retrospective catch rather than a built-in default -- three other
strategies coded after gotobi (`yen_fiscal_repatriation`,
`london_breakout_retest`, `nfp_fade`) were checked and do have the gate
(they were built by copying gotobi's template forward), but
`month_end_fix_reversal` and `wm_fix_reversal` (its structural parent) both
apparently branched from an earlier, pre-gate lineage and never picked it
up. Worth an explicit registry-wide audit for any other strategy missing
this gate, not just the one that happened to get caught by a live-deploy
attempt.

**Fix pattern (mirror exactly, from `gotobi/v1/strategy.mq5`):**
```
input bool   InpAllowLiveAccount  = false; // must be explicitly set true to run on a REAL account
...
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   pipSize = ...;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpAllowLiveAccount)
   {
      Alert("<strategy_name> ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      Print("<strategy_name> ", _Symbol, ": refusing to start on a REAL account -- set InpAllowLiveAccount=true to confirm.");
      return INIT_FAILED;
   }
   ...
}
```
Place the check immediately after `trade.SetExpertMagicNumber()`/`pipSize`
setup and before any other `OnInit()` state initialization, same relative
position as gotobi's. This is a no-op during Strategy Tester runs
(`ACCOUNT_TRADE_MODE` is never `ACCOUNT_TRADE_MODE_REAL` there), so adding
it retroactively to an already-backtested version (as done here, v1->v2)
never invalidates existing backtest results -- safe to always retrofit as
a pure version bump rather than a full re-test cycle.

## day_trading/gotobi/v2 (2026-09-23) -- add the chart status panel (display-only)

Compiled clean, 0 errors/0 warnings, first attempt. First EA built under the
new "Chart status panel" standing convention (`.claude/agents/ea-coder.md`,
added 2026-09-23) -- gotobi/v1 was already the reference implementation for
the baseline safety ledger that convention requires, so this version only
needed to add the panel itself, nothing else.

- **MQL5 does not require forward declaration of functions used earlier in
  the same file.** `ResetDayState()` (defined near the top) calls
  `SetLastAction()` (defined much further down, in the new "chart status
  panel" section) with no prototype anywhere -- compiled clean regardless.
  MetaEditor's compiler resolves all global function symbols across the
  whole module before generating code (two-pass, not a single top-to-bottom
  C-style pass), so helper functions can be added anywhere in the file
  without worrying about call-site order. Worth remembering next time a
  patch adds cross-referencing helpers late in a file rather than
  re-ordering the whole file defensively.

- **To guarantee a display refresh fires on every code path (including
  every early `return` inside the original trading logic) without touching
  that logic's structure, move the original function body verbatim into a
  new inner helper (`ProcessTick()`), then call it followed by
  `RenderPanel()` from the real `OnTick()`.** This avoids having to hunt
  down and modify every `return;` in the original logic (which would risk
  an accidental logic edit) while still ensuring the panel is never stale
  after an early exit. `OnTimer()` (1s, `EventSetTimer(1)`/`EventKillTimer()`)
  covers refreshes between ticks during this strategy's long idle stretches
  (gotobi trades ~4-6 days/month).

- **Render the panel via `RenderPanel()` even on the `INIT_FAILED` path**,
  using a dedicated `g_initFailReason` string checked first inside the
  status-line function -- this works even though most other state
  (`isGotobiDay`, `entryWindowStart`, etc.) is still at its zero-value
  default at that point in `OnInit()`, since the display helpers
  (`BuildGotobiBlock()`, `NextGotobiEntryWindow()`) only read `Inp*` inputs
  and `TimeCurrent()`, not the not-yet-initialized trading state -- no
  crash, just a display that correctly reads "NO"/"n/a" for a not-yet-
  determined day until `OnInit()` actually finishes.

- **Symbol-validation matching**: normalize `InpValidatedSymbols` by
  stripping spaces and appending a trailing comma, then substring-match
  `"<symbol>,"` against `"<list>,"` -- avoids `EURUSD` incorrectly matching
  a list entry like `EURUSDX` (a plain `StringFind` on the raw symbol
  without the comma boundary would have this false-positive risk).

- Zero entry/exit/sizing/timing/safety logic changed from v1 -- diff the
  two files if verifying independently: only additions are the
  `InpValidatedSymbols` input, all-new panel helper functions/globals
  (`g_status`, `g_lastAction`, `g_initFailReason`, `SetLastAction`,
  `IsSymbolValidated`, `HaltReason`, `ComputeStatusLine`,
  `FormatCountdown`, `NextGotobiEntryWindow`, `BuildGotobiBlock`,
  `RenderPanel`), the `OnTimer`/`OnDeinit` additions, the `ProcessTick`
  extraction described above, and `SetLastAction(...)` calls inserted
  alongside existing `Print()` calls at each skip/entry/exit point (no
  existing line was removed or reordered).

## day_trading/month_end_fix_reversal/v3 (2026-09-23) -- safety-ledger backfill + chart panel

Compiled clean, 0 errors/0 warnings, first attempt. Two independent additions
requested together, both wired onto v2/strategy.mq5 without touching any
entry/exit/threshold/sizing/timing logic:

1. **Safety-ledger backfill.** v2 (see this file's own `v2` entry above) had
   only ever picked up the `InpAllowLiveAccount` live-account guard -- the
   consecutive-loss halt, daily-loss halt, and drawdown kill-switch
   (`balancePeak` tracking) that `gotobi/v1` has always had were never
   ported over, because `month_end_fix_reversal`/`wm_fix_reversal` branched
   from an earlier pre-ledger lineage. Copied `gotobi/v1/strategy.mq5`'s
   ledger pattern line-for-line: `consecutiveLosses`+`InpMaxConsecutiveLosses`,
   an `OnTradeTransaction()` handler keyed on `MagicNumber`+`_Symbol`+
   `DEAL_ENTRY_OUT`, `monthlyHaltActive`+`haltSetYear`/`haltSetMonth`+
   `CheckMonthlyHaltResume()` (resumes on the first day of next calendar
   month -- correct here since this strategy already evaluates every
   month, unlike `yen_fiscal_repatriation`'s sparse-window case documented
   above), `dailyStartBalance`+`dailyHaltActive`+`InpDailyLossStopPercent`+
   `UpdateDailyLossHalt()` (folded `dailyStartBalance` capture into the
   existing `ResetDayState()`, which already ran once per day -- no new
   day-change detection needed), `balancePeak`+`drawdownHaltActive`+
   `InpMaxDrawdownStopPercent`+`UpdateDrawdownHalt()`, and
   `InpResetLedgerNow`/`InpResetDrawdownStop`. The three halt flags are
   OR'd into a single gate inserted at exactly one point: right after v2's
   existing `if(!isMonthEndWindow || tradeTakenToday) return;` line and
   before its threshold/spread/sizing checks -- same relative position as
   gotobi's own gate. This can only suppress a trade v2 would have taken,
   never add one. **Flagged explicitly in the header comment and spec.json:
   this is NOT a no-op like v2's live-account patch was -- v2's
   review.md/VERDICT.md numbers do not carry over automatically, since the
   new halts can change which trades actually execute. Needs a fresh
   backtest before any live/demo decision.** Registry status set back to
   `coded` (not left at `approved_live`) for exactly this reason, so the
   orchestrator routes it through Backtester again rather than treating it
   as already-validated.

2. **Chart status panel**, per `.claude/agents/ea-coder.md`'s locked spec
   (added 2026-09-23, this was the first EA built after that convention
   landed). Straightforward mechanical translation of the spec's format
   string into `RenderPanel()`, called from `OnTick()` at every early
   return (added one `RenderPanel()` call immediately before each existing
   `return`, without altering which branch is taken) and from a 1-second
   `OnTimer()` (`EventSetTimer(1)` in `OnInit()`, `EventKillTimer()` +
   `Comment("")` in `OnDeinit()`). `IsSymbolValidated()` uses
   `StringSplit(list, ',', parts)` -- MQL5 treats a single-quoted char
   literal as `ushort` (not `char` like C++), so passing `','` directly as
   the separator argument compiles and works with no explicit cast needed.
   Rendered the panel once more right before the `INIT_FAILED` return on
   the live-account guard check (`g_status` set to the specific
   "INIT FAILED: ..." reason first) -- safe to call `RenderPanel()` that
   early because `pipSize` is already assigned by that point in `OnInit()`
   and every other variable it reads either defaults to 0/false (handled,
   e.g. `CurrentDrawdownPercent()` guards `balancePeak<=0`) or is a string
   default. EA-specific block (month-end eligibility day-count, fix
   window start/end/scheduled-exit clock times, spike-history sample
   count/average/adaptive threshold) was pulled directly from variables
   the strategy already tracked (`spikeHistoryCount`, `AverageSpikeHistory()`,
   a new small `CurrentAdaptiveThreshold()` wrapper around the existing
   inline threshold formula) -- no new state needed purely for display
   purposes beyond `g_status`/`g_lastAction` themselves.

**Post-hoc fix (orchestrator, same day):** the task brief told EA Coder to
default `InpValidatedSymbols` from `v2/spec.json`'s `"symbol"` field, which
is only `"EURUSD.r"` -- but `VERDICT.md` documents this strategy was
actually backtested independently on **EURUSD.r, GBPUSD.r, AND USDJPY**
(plus as a true 3-pair portfolio, `v1_portfolio/`), and the user's live
approval explicitly covers EURUSD.r + GBPUSD.r. Left as instructed, the
panel would have shown a false `WARNING: SYMBOL NOT VALIDATED FOR THIS EA`
on a GBPUSD.r chart -- part of the actually-approved live scope. Fixed by
changing the default to `"EURUSD.r,GBPUSD.r,USDJPY"` and recompiling (clean,
0 errors/0 warnings). **Lesson for future specs in a family with a
`_portfolio/` sibling folder: a single-symbol version's own `spec.json`
only ever names *its own* chart's symbol, never the full validated set --
pull `InpValidatedSymbols` from the strategy's `VERDICT.md`/`STRATEGY.md`
(whichever documents the full multi-pair validation) instead of the
version's own `spec.json` when one exists.**

## day_trading/fix_run_momentum/v1 (2026-09-25)

Compiled clean, 0 errors/0 warnings, first attempt. Direct structural cousin
of `wm_fix_reversal`/`month_end_fix_reversal` (same fix-window-timing +
volatility-adaptive-threshold family) but going WITH the pre-fix run
(momentum) instead of fading the post-fix spike, on a much tighter (2-minute)
hold. Single-symbol-per-chart pattern (one EA per pair's own chart), not the
portfolio harness, per spec.json/CLAUDE.md default.

- **A measurement window entirely BEFORE a scheduled event (not straddling
  it like `wm_fix_reversal`'s Pre/PostFixMinutes) is simplest expressed as
  two "minutes-before-fix" offsets for window start/end, plus a separate
  "minutes-after-fix" offset for the exit**, rather than trying to reuse
  `wm_fix_reversal`'s exact `PreFixMinutes`/`PostFixMinutes`/`HoldMinutes`
  input shape unmodified. Here: `windowStart = fixTime -
  MeasureWindowStartMinutesBeforeFix*60`, `windowEnd = fixTime -
  MeasureWindowEndMinutesBeforeFix*60` (this is ALSO the entry instant, since
  the spec's entry fires immediately at measurement-window close),
  `scheduledExitTime = fixTime + ExitDelayMinutesAfterFix*60`. Reusing the
  donor's exact input names/shape when the window's temporal relationship to
  the event is actually different (before-only vs. straddling) would have
  either mis-modeled the window or needed misleading input names.

- **Flipping a fade strategy to a momentum strategy is a one-line change at
  the direction branch** (`if(run > 0) buy` / `if(run < 0) sell`, vs. the
  donor's `if(spike > 0) sell` / `else buy`) plus swapping which side of the
  computed SL/TP distance is "against" vs. "with" the entry direction for
  each branch -- everything else (adaptive-threshold measurement, rolling
  history push-every-day-regardless-of-trade, spread filter, lot sizing) is
  identical and copy-paste safe. Worth remembering this is a cheap, low-risk
  translation whenever a future spec asks for the same fix-window signal in
  the opposite direction.

- **Flagged an unresolved spec-text internal contradiction rather than
  silently picking a side without saying so**: `spec.json`'s
  `entry.entry_time` field literally read `"18:59:00 -> immediately at
  measurement-window close, 17:59:00 server time (15:59:00 London)"` -- the
  leading `18:59:00` value contradicts the very same sentence's own stated
  reasoning, the `measurement_window` field (window closes at `17:59:00`),
  and the `exit.rule` field (fix+1min = `18:01:00`, which is only "exactly 2
  minutes after entry" if entry is `17:59:00`; an `18:59:00` entry would be
  59 minutes AFTER both the fix and the stated exit time, structurally
  impossible for this thesis). Coded against `17:59:00` as the only value
  internally consistent with the rest of the spec, documented prominently in
  the `.mq5` file header (not just a commit-message-style aside) so
  Researcher can correct the spec text if `18:59:00` was actually meant to
  signal something else entirely, rather than treating a header comment
  alone as sufficient visibility for a discrepancy this load-bearing.

- **A spec's own narrative claim about "reusing another version's validated
  value" is not always accurate for every field it lists -- verify against
  the actual donor source, not just the spec's prose.** `spec.json` states
  v1 reuses "wm_fix_reversal v2's already-validated adaptive-threshold
  calibration (MinRunVsAvgMultiplier=2.0, RunHistoryWindow=20,
  MinRunSizePipsFloor=5, MinHistoryToAdapt=20)" -- but checking
  `wm_fix_reversal/v2/strategy.mq5` directly shows its actual coded
  `MinHistoryToAdapt` default is `5`, not `20` (the other three values do
  match exactly). Coded the input default to spec.json's literal stated
  value (`20`) since that is what this spec explicitly specifies for v1
  regardless of the donor mismatch -- not this role's place to silently
  "correct" it back to 5 based on a guess about which one was intended -- but
  flagged the discrepancy explicitly in both the file header and the
  registry note so Researcher can decide whether 20 was a deliberate change
  or a transcription slip.

# Live Manager — lessons

Created 2026-09-22 as part of the multi-agent restructure. No demo or
live deployments have happened yet in this project as of this date —
everything so far has been backtest-only (Strategy Tester, never a real
order). This file starts empty of incidents by design; append after every
operational issue (failed deploy, broker rejection, kill-switch false
trigger, connectivity drop, account/symbol mismatch).

## Standing reminders (not incidents — just don't forget these)

- Account `YOUR_ACCOUNT_LOGIN` / server `FPMarkets-Live` is a **live account**. There
  is currently no demo account configured in this project's `CLAUDE.md` —
  confirm with the user which account to actually point at before any
  `approved_demo` deployment; do not assume one exists.
- Every EA this project has produced so far (`london_range_fade`,
  `gotobi`) refuses to start on `ACCOUNT_TRADE_MODE_REAL` unless
  `InpAllowLiveAccount` (or equivalent) is explicitly set true. Confirm
  this input is set correctly for the account you're actually deploying
  to — true for live, and note that on a real demo account
  `ACCOUNT_TRADE_MODE` would read `ACCOUNT_TRADE_MODE_DEMO`, not `_REAL`,
  so the safeguard wouldn't even engage there; don't rely on it as your
  only check for "am I about to trade live."
- **Not every EA in this project has the safeguard** — see the 2026-09-23
  entry below. Check the actual source (`grep`/read the `.mq5` file
  directly), never assume from the strategy name or category that a
  sibling EA's safeguard pattern was copied.
- Kill-switch is a fixed 15% drawdown from balance peak since the
  strategy started running on that account — see root `CLAUDE.md`
  "Decided operational parameters." Not a judgment call.

## 2026-09-23 — First live-deployment attempt: gotobi (USDJPY) + month_end_fix_reversal (EUR/GBP)

User gave explicit in-session instruction to deploy both to LIVE capital
(account `YOUR_ACCOUNT_LOGIN`/`FPMarkets-Live`), skipping demo, at reduced scope per
each strategy's own `VERDICT.md`. Orchestrator had already set both to
`approved_live` in `strategies/registry.json` with history rows recording
the approval scope before I (Live Manager) was invoked. This is the
project's first real attempt at an actual live/demo attach (everything
before this was Strategy Tester only) — recording the full procedure here
since the user specifically asked for it to be remembered.

### Pre-deployment checklist actually performed (do this every time)

1. Read `live-manager/lessons.md` (this file) first.
2. Read `strategies/registry.json` — confirmed both ids show
   `approved_live` with a history row naming the user's explicit approval
   and exact scope (pair/symbol subset, sizing note).
3. Read `strategies/<category>/<name>/v1/spec.json` for each — confirmed
   the version being deployed (`v1` for both) matches what the registry
   `history` shows reached `live_candidate`/`live_candidate_final`.
4. **Grepped the actual `.mq5` source directly** for the live-account
   safeguard rather than assuming it's there:
   `grep -n "InpAllowLiveAccount\|ACCOUNT_TRADE_MODE\|REAL" strategy.mq5`
   - `gotobi/v1/strategy.mq5`: PRESENT — `input bool InpAllowLiveAccount
     = false;` (line 47), checked at lines 239-243, refuses to start if
     `AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL`
     and the input is still false.
   - `month_end_fix_reversal/v1/strategy.mq5`: **ABSENT** — grep for
     `LiveAccount|TRADE_MODE|REAL` returned zero matches anywhere in the
     file. This EA has no live-account opt-in gate at all; attaching it
     to the live account would start trading real money immediately with
     no safeguard. This is a genuine gap between this EA and its sibling
     `wm_fix_reversal`/`gotobi` — do not assume the pattern was copied
     just because the mechanism (fix-window fade) was reused.
5. Checked the compiled `.ex5` exists in the MT5 data folder's project
   subfolder (source of truth is the repo `.mq5`; `compile_ea.py` copies
   it into the data folder to compile):
   `C:\Users\Suman\AppData\Roaming\MetaQuotes\Terminal\ED480984639B96B48C6EBB5DA707E011\MQL5\Experts\EAFactory\<name>\v1\strategy.ex5`
   - `gotobi`: both `v1/strategy.ex5` (single-symbol build — the one to
     use, since `spec.json` sets `one_ea_per_symbol_chart: true`) and
     `v1_portfolio/strategy.ex5` (multi-symbol build, backtest-only
     harness, NOT what gets attached live) are present.
   - `month_end_fix_reversal`: same pattern, `v1/strategy.ex5` present.
6. Checked whether `terminal64.exe` was even running
   (`tasklist | grep -i terminal64`) — **it was not running at all** at
   the time of this session. No EA was attached to any chart, nothing was
   live, before or after this session's checks.

### Outcome: gotobi — cleared checks, attach NOT performed (manual step remains)

Everything above passed for `gotobi` v1, USDJPY only, at the spec's
default `InpRiskPercent = 0.5` (single-pair deployment is itself the size
reduction the VERDICT called for — not running EURJPY.r/GBPJPY.r
concurrently). This is ready to attach. **I did not perform the actual
attach** — attaching an EA to a live chart in MT5 is a GUI-only action
(Navigator panel drag-and-drop onto an open chart, then an Inputs/Common
dialog to confirm) that this agent cannot drive non-interactively through
Bash. I am not going to fabricate having done this. Registry status was
left at `approved_live`, not advanced to `live`, and a history row records
exactly this state (see `strategies/registry.json`).

**Exact manual steps remaining (for the user, or a future session with
interactive GUI access) to actually go live:**

1. Launch `C:\Program Files\FP Markets MetaTrader 5\terminal64.exe`.
2. Log in to account **`YOUR_ACCOUNT_LOGIN`** on server **`FPMarkets-Live`** (NOT the
   unrelated second MT5 install at `C:\Program Files\MetaTrader 5` — root
   `CLAUDE.md` flags that one explicitly as out of scope). Confirm the
   account number and server shown in the terminal's top-right / title
   bar match before doing anything else.
3. In the Navigator panel (Ctrl+N), find the compiled EA under
   `Expert Advisors → EAFactory → gotobi → v1 → strategy`.
4. Open a **USDJPY** chart (bare symbol, no suffix — confirmed correct
   per root `CLAUDE.md`'s symbol-naming note; USDJPY resolves without
   `.r`, unlike EURJPY/GBPJPY which need it).
5. Drag `strategy` from the Navigator onto the USDJPY chart. In the
   dialog that opens:
   - **Common tab**: check "Allow live trading" (technically implied for
     a real account, but confirm it's checked). Leave "Allow DLL imports"
     unchecked (not needed).
   - **Inputs tab**: set `InpAllowLiveAccount = true` (this is the
     deliberate, approved override for this specific deployment — leave
     it `false` for any future non-approved attach). Leave all other
     inputs at spec defaults: `InpStopLossPips=20`, `InpRiskPercent=0.5`,
     `InpMaxSpreadPips=3.0`, `InpHoldMinutes=35`,
     `InpMaxConsecutiveLosses=6`, `InpDailyLossStopPercent=5.0`,
     `InpMaxDrawdownStopPercent=15.0` — these are already the spec/EA
     defaults, no changes needed for the approved scope.
   - Click OK.
6. Confirm the top-right "Algo Trading" toggle in the terminal toolbar is
   enabled (green) — without it no EA on any chart will trade regardless
   of per-chart settings.
7. Watch the "Experts" log tab for the EA's own startup print — it will
   either start silently (if the `InpAllowLiveAccount` check passes) or
   print the "refusing to start on a REAL account" alert if the input
   wasn't actually set true. Confirm no alert fired.
8. Once confirmed running, THEN update `strategies/registry.json` status
   `approved_live → live` for `day_trading/gotobi` with a history row
   (do not set this before the attach is actually confirmed).
9. Start journaling every trade to `journal/live_trades.csv` as they
   close, tagged `account_mode=live`, `strategy_id=day_trading/gotobi`,
   `version=v1`, `symbol=USDJPY` (header:
   `account_mode,strategy_id,version,symbol,open_time,close_time,side,lots,entry_price,exit_price,commission,swap,profit,balance_after`).
   Source this from the terminal's own trade history / MT5 account
   history export for account YOUR_ACCOUNT_LOGIN, not from re-parsing the Strategy
   Tester's `report.htm` (that's the backtest journal's source, not
   live's).
10. Track `ACCOUNT_BALANCE` peak since this attach for the 15% kill-switch
    check (this needs to happen at every check-in, not just at attach
    time).

### Outcome: month_end_fix_reversal — BLOCKED, not deployed, flagging to user

Did **not** proceed to any attach step for this strategy. Per this
project's hard rule 4 (`root CLAUDE.md` / `.claude/agents/live-manager.md`
"Once deploying is confirmed and authorized" preconditions): every EA
deployed here must already declare an `InpAllowLiveAccount`-style input
that refuses to run on `ACCOUNT_TRADE_MODE_REAL` unless explicitly set
true, and if it's missing, stop and flag rather than deploy anyway.
`month_end_fix_reversal/v1/strategy.mq5` has no such input and no
`ACCOUNT_TRADE_MODE` check anywhere in the file — confirmed by direct grep
of the full source, not inferred from a sibling strategy. This means as
currently coded, attaching this EA to any live chart would start trading
account `YOUR_ACCOUNT_LOGIN`'s real capital immediately with zero opt-in gate.

**This needs to go back to EA Coder** to add the safeguard (same pattern
as `gotobi/v1/strategy.mq5`: an `input bool InpAllowLiveAccount = false;`
declared near the other inputs, checked in `OnInit()` against
`AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL`,
alerting and returning `INIT_FAILED` if true and the input is still
false) before any deployment attempt, live or demo. Once patched
(presumably as a new version, e.g. `v2`, or a same-version patch if the
project's convention allows a safety-only fix without a full version
bump — Researcher/EA Coder's call), Researcher/user should confirm the
existing `approved_live` scope still applies to the patched build before
Live Manager attaches it.

**Reduced-size figure decided now, so it's ready the moment this is
unblocked** (VERDICT.md recommended "reduced size" without pinning an
exact number, per the task instruction to use judgment and document it
here): use **`RiskPercent = 0.5`** (half of the spec's 1.0% default),
applied to **EURUSD.r and GBPUSD.r only** — USDJPY stays held back per
the approval scope until fills are confirmed on the first two. Rationale:
halving risk is the simplest, most legible reduction that directly
addresses the VERDICT's stated concern (unverified live execution quality
at the fix moment), without changing any of the strategy's already-locked
entry/exit/threshold logic (which would reopen the no-re-optimize
discipline this project applies post-out-of-sample). Revisit sizing
upward only after Researcher/user reviews live fills against backtest
assumptions, same as gotobi's own stated next check.

### Net result of this session

**Nothing is live or running.** `terminal64.exe` was not running before
or after this session and no EA was attached to any chart. `gotobi`
(USDJPY, `InpRiskPercent=0.5`) is fully cleared and ready — the only
remaining step is the manual GUI attach above, which needs a human (or a
future session with interactive desktop access) to perform.
`month_end_fix_reversal` is blocked on a missing safety input and was not
attempted. Registry status for both left at `approved_live` (not advanced
to `live`) with history rows recording this exact state. No rows were
added to `journal/live_trades.csv` (empty since nothing traded or was
confirmed attached — adding a placeholder row would misrepresent it to
Researcher as an actual event).

## 2026-09-25 — first actual live attach (gotobi v2, month_end_fix_reversal v3)

**Bare `USDJPY` is NOT tradeable on account `YOUR_ACCOUNT_LOGIN` — use `USDJPY.r`.**
A read-only `SymbolInfoInteger(SYMBOL_TRADE_MODE)` probe (2026-09-23) returned
`DISABLED` for `USDJPY` (path `Forex Majors\USDJPY`, spread ~17 pts) and
`FULL` for `USDJPY.r` (path `Forex Majors Raw\USDJPY.r`, spread ~6 pts). This
is a Raw account; the bare symbols are the Standard-account set, visible
(quotes, history, Strategy Tester) but view-only for trading. The earlier
instruction in this file to attach gotobi to a bare USDJPY chart would have
produced an EA that silently could never place an order. Backtests on bare
USDJPY remain valid evidence (wider spread than live `.r` = conservative,
though they don't include the Raw commission), but **every live chart on
this account must use a `.r` symbol.** Probe trade mode, not just symbol
existence, before any attach.

**Attach without the GUI works via the chart profile.** With the terminal
closed (it rewrites the profile on exit), add an `<expert>` block before
`<window>` in `MQL5\Profiles\Charts\Default\chartNN.chr` (UTF-16LE, CRLF):
`name=strategy`, `path=Experts\EAFactory\<name>\<version>\strategy.ex5`,
`expertmode=33` (this build's value for "algo trading allowed"), and an
`<inputs>` block listing every input (`InpAllowLiveAccount=true` etc.),
then start the terminal. The journal's `expert ... loaded successfully`
with no `initialization failed` / `removed` line confirms the live guard
passed. The terminal loads the `Default` profile regardless of
`ProfileLast` in `config\common.ini`.

**Deployed:** gotobi v2 on USDJPY.r (`InpRiskPercent=0.5`,
`InpValidatedSymbols=USDJPY,USDJPY.r,EURJPY.r,GBPJPY.r`), month_end v3 on
EURUSD.r + GBPUSD.r (`RiskPercent=0.5`). Both `InpAllowLiveAccount=true`,
all other inputs at repo defaults. Registry advanced `approved_live → live`.

**Known gaps in the deployed repo versions** (fixed in a local-only patch
that ran 2026-09-23..25, not yet brought into the repo as new versions):
month-granular DST switch (wrong for the days between 1 Mar and the US DST
date, e.g. the 5 Mar gotobi day enters an hour late); `PositionSelect(_Symbol)`
on a hedging account (month_end's 22:00 close can close ANY position on its
symbol, including manual trades); safety ledger held only in memory, so a
terminal restart clears a loss-streak pause / drawdown stop.

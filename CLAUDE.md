# MT5 Day-Trading EA Factory — Project Plan & Orchestrator

## Goal
Build an autonomous pipeline that designs a day-trading forex strategy,
implements it as an MT5 Expert Advisor (MQL5), backtests and optimizes it,
validates it against unseen data, deploys validated strategies to a demo
account, and — only with explicit manual approval — to live capital.

As of 2026-09-22 this runs as **four specialized subagents coordinated by
an orchestrator** (this file + whatever session is driving it), tracked
through a central `strategies/registry.json`. See "Architecture" below.
Before this restructure, the same pipeline (design → backtest → optimize →
validate → verdict) ran as a single manual, gated loop — that history is
still the working reference for how a good `review.md`/`VERDICT.md` reads;
see `strategies/day_trading/london_range_fade/` and
`strategies/day_trading/gotobi/` as worked examples.

## Scope
- Strategy categories in scope: **day trading**, and **scalping** (added
  2026-09-22, user request — see `strategies/scalping/`). Swing still out
  of scope.
- Researcher designs the strategy itself (indicators, entry/exit rules,
  risk sizing) — no fixed template required.
- This machine has MT5 installed and a broker account already connected.
- **Scalping-specific note**: transaction costs (spread, commission,
  slippage) matter proportionally far more at scalping timescales than
  day-trading ones — a strategy that looks profitable gross can be
  entirely a cost artifact. Model realistic spread/commission (already
  the project default via `Model=4` + `Login=YOUR_ACCOUNT_LOGIN`) and apply a tight
  max-spread filter; treat any scalping strategy's edge as suspect until
  checked against the account's real recorded spread specifically during
  its target session, not just in aggregate.

## Environment
- Broker/terminal in use: **FP Markets MetaTrader 5**, account `YOUR_ACCOUNT_LOGIN` on
  server `FPMarkets-Live`. **This is a live account, not a demo.** Backtests
  run entirely inside the Strategy Tester against historical data and never
  place real orders, so this is safe — but **never invoke terminal64.exe in
  live/chart-trading mode with an EA attached without the specific
  deployment approval Live Manager requires** (see
  `.claude/agents/live-manager.md`). This is the one boundary in the whole
  project that separates "safe to run freely" from "moves real money."
- A second, unrelated installation (`C:\Program Files\MetaTrader 5`, generic
  MetaQuotes build, currently logged out) also exists on this machine.
  Ignore it — all work here uses the FP Markets installation below.
- MT5 terminal path:
  `C:\Program Files\FP Markets MetaTrader 5\terminal64.exe`
- MetaEditor path:
  `C:\Program Files\FP Markets MetaTrader 5\MetaEditor64.exe`
- MT5 data folder:
  `C:\Users\Suman\AppData\Roaming\MetaQuotes\Terminal\ED480984639B96B48C6EBB5DA707E011\`
- Compiled EAs live under this project's own subfolder inside the data
  folder's Experts directory, to avoid colliding with the account's existing
  (unrelated) EAs already there:
  `<data folder>\MQL5\Experts\EAFactory\<strategy_name>\<version>\`
- Source of truth for `.mq5` source stays in this repo
  (`strategies/<category>/<name>/<version>/strategy.mq5`); `compile_ea.py`
  copies it into the data folder to compile (MQL5 include resolution
  requires living under an MQL5 root), then copies the compile log back
  next to the source.
- Tester runs are pointed at account `YOUR_ACCOUNT_LOGIN` (`Login=` in config.ini) so
  the Strategy Tester picks up the account's real contract specs, leverage,
  and commission schedule rather than generic defaults — this is how spread/
  commission realism is achieved (combined with `Model=4`, every tick based
  on real ticks, which replays the broker's actual recorded historical
  bid/ask spread rather than a synthetic constant spread).
- **Symbol naming is inconsistent across instruments on this broker** —
  e.g. bare `USDJPY` resolves but `EURJPY`/`GBPJPY` need a `.r` suffix
  (`EURJPY.r`, `GBPJPY.r`), same pattern as `EURUSD.r`. Probe an unfamiliar
  symbol with a short date range before committing to a long backtest.

## Architecture (subagents + orchestrator)

```
Researcher → spec → EA Coder → EA file → Backtester (Strategy Tester) → structured results
     ↑                                                                        │
     └────────────────────────── (refine or discard) ──────────────────────┘

Researcher flags "live_candidate"
     → 🛑 USER approves manually (approved_demo)
     → Live Manager deploys to DEMO → demo journal → Researcher reviews vs demo_criteria

Researcher flags "live_candidate_final"
     → 🛑 USER approves manually (approved_live)
     → Live Manager deploys to LIVE → live journal → Researcher reviews ongoing
```

Four subagents, defined in `.claude/agents/`:
- **researcher** (`researcher.md`) — generates specs, reviews all results,
  the only agent that makes strategy-logic decisions. Never deploys, never
  writes MQL5.
- **ea-coder** (`ea-coder.md`) — translates a spec into `.mq5` exactly as
  written, self-validates it compiles. Never invents strategy logic.
- **backtester** (`backtester.md`) — runs the existing `scripts/` pipeline
  through the Strategy Tester, produces structured results. Never judges
  whether results are good.
- **live-manager** (`live-manager.md`) — the only agent that can ever touch
  a demo or live account. Deploys only on explicit user instruction plus a
  matching `approved_demo`/`approved_live` registry status. Enforces the
  15% drawdown kill switch.

### Orchestrator loop

When told to "start working" (or similar):

1. Read `strategies/registry.json` for the current status of every
   strategy.
2. For each strategy, dispatch to the subagent that owns its current
   status:
   - `new` → ea-coder
   - `coded` → backtester
   - `backtest_failed` → ea-coder (with the error context)
   - `backtested` → researcher (review)
   - `refining` → ea-coder or researcher, as appropriate to what's being
     changed
   - `demo_failed` → researcher (review)
   - `approved_demo` / `approved_live` → live-manager **— except on this
     machine, see the "Two-machine split" note below**
3. After each subagent finishes and updates the registry, immediately
   check what's next for that strategy and continue — do not wait for the
   user — **until** a strategy reaches a status requiring manual approval
   (`live_candidate`, `live_candidate_final`), at which point stop
   advancing that one and move on to check others.
4. If nothing is in progress, trigger researcher to generate a new
   strategy so the pipeline doesn't idle.
5. Print a clear, visible flag in terminal output whenever a strategy
   reaches `live_candidate` or `live_candidate_final` — this is the only
   notification; the user checks in periodically, no external alerts are
   wired up.
6. **Never advance any strategy past `approved_demo` or `approved_live`
   without that exact status already set by the user** — these two
   statuses are set manually only, never inferred or set by any subagent.

This auto-advance behavior is a deliberate choice (confirmed with the user
2026-09-22): earlier in this project every version increment paused for
manual review. That per-version gate is now delegated to Researcher's own
judgment inside the loop above — the user is no longer asked to approve
each backtest iteration, only the demo/live capital decisions.

### Two-machine split (as of 2026-09-25)

This repo now runs on two machines with different jobs, synced through
this git remote (`github.com/treetechsuman/trading-agent`) — see
`REBUILD.md` for the environment details of each:

- **This machine (dev)**: researcher → ea-coder → backtester loop only.
  Never dispatch live-manager here, never attach/start an EA on a chart,
  never run `terminal64.exe` in live/chart mode — Strategy Tester
  backtests are fine. When a strategy reaches `approved_demo` /
  `approved_live`, **stop there and commit + push** (only when the user
  explicitly asks for the commit/push itself, per the repo conventions
  below) rather than dispatching live-manager locally.
- **The live server (deploy)**: pulls from git, runs live-manager to
  actually attach/monitor/kill-switch EAs against the real account, and
  pushes its own registry/lessons updates back (see `e20b2a2`'s commit
  for a worked example: registry status `approved_live → live`,
  `live-manager/lessons.md` updated, `scripts/common.py`'s `MT5_DATA_DIR`
  pointed at its own data folder).
- **`scripts/common.py`'s `MT5_DATA_DIR`/`TERMINAL_EXE`/`METAEDITOR_EXE`
  are machine-specific on purpose** — each machine keeps its own value
  locally via `git update-index --skip-worktree scripts/common.py` after
  setting it correctly for that machine, so routine pulls don't fight
  over it or accidentally commit the wrong machine's path.
- Registry statuses `live`/`demo` (set by the server's live-manager) are
  terminal from this machine's point of view — don't treat them as
  something to re-dispatch or redeploy locally.

## Status lifecycle (`strategies/registry.json`)

| Status | Set by | Meaning |
|---|---|---|
| `new` | Researcher | Spec created, not yet coded |
| `coded` | EA Coder | MQL5 file exists and compiles, not yet tested |
| `backtest_failed` | Backtester | Pipeline/compile error, needs EA Coder fix |
| `backtested` | Backtester | Results produced, awaiting Researcher review |
| `refining` | Researcher | Sent back for spec adjustment (loops to `new`/`coded`) |
| `discarded` | Researcher | Rejected, won't proceed further |
| `live_candidate` | Researcher | Flagged ready — awaiting user's manual approval for demo |
| `approved_demo` | **User** | Manually approved to run on demo account |
| `demo` | Live Manager | Currently running on demo account |
| `demo_failed` | Researcher | Demo diverged badly from backtest — back to `refining` or `discarded` |
| `live_candidate_final` | Researcher | Demo results met `demo_criteria` — flagged ready for real capital |
| `approved_live` | **User** | Manually approved for live capital (separate approval from demo) |
| `live` | Live Manager | Currently deployed with real capital |
| `paused` | Live Manager | Kill-switch triggered or manually paused |
| `retired` | Live Manager / Researcher | Pulled from live, done |

Registry entry format (id = `<category>/<name>`, matching the folder
path so it's always navigable):
```json
{
  "day_trading/strategy_name": {
    "category": "day_trading",
    "status": "backtested",
    "current_version": "v1",
    "created": "2026-09-20",
    "last_updated": "2026-09-22",
    "history": [
      { "status": "new", "date": "2026-09-20" },
      { "status": "coded", "date": "2026-09-20" },
      { "status": "backtested", "date": "2026-09-21" }
    ]
  }
}
```

Each agent updates the registry status when its own step completes, and
only acts on strategies in the status it owns (e.g. Live Manager only ever
touches `approved_demo` or `approved_live`).

**`"parked": true` / `"parked_date"`** — an optional annotation, not a
lifecycle status. Set only on the user's explicit instruction, when a
strategy shouldn't be discarded (it's not rejected, the evidence is
genuinely mixed/borderline) but also shouldn't keep consuming iteration
effort right now. Leaves `status` at whatever it actually is (usually
`backtested`) so the real technical state stays visible. The orchestrator
loop should skip parked strategies when deciding what to work on next,
same as it would skip `discarded` ones, but Researcher should still
consider them when a new strategy idea might build on or supersede one.
Unset (or the user says to resume) to bring a strategy back into active
iteration.

## Decided operational parameters

These were open questions in the original restructure proposal, resolved
with the user on 2026-09-22:

- **Kill-switch drawdown: 15%** — matches the drawdown hard-stop pattern
  already coded into strategy EAs themselves (see
  `strategies/day_trading/gotobi/v1/strategy.mq5`'s `InpMaxDrawdownStopPercent`),
  for consistency between an EA's own safeguard and Live Manager's
  external one.
- **Backtest statistical-significance bar: 200 trades** — below this,
  Researcher treats profit factor / win rate as provisional, not
  actionable. Separate from (and stricter than) each strategy's own
  `demo_criteria.min_trades`, which governs demo→live promotion instead.
- **No fixed discard floor** — Researcher weighs profit factor, drawdown,
  trade count, and consistency together as a judgment call each time,
  same as every `review.md` decision made manually in this project so far.

## Demo criteria (category-aware, set by Researcher at spec creation)

Added to `spec.json` at creation time — not adjusted later, so the bar
isn't moved after seeing results.

```json
"demo_criteria": {
  "min_trades": 40,
  "min_days": 14,
  "rationale": "scalping strategy, high trade frequency expected on M5"
}
```

Starting anchors (Researcher may adjust per strategy):

| Category | Min trades | Min days |
|---|---|---|
| Scalping | 40–50 | 10–14 |
| Day trading | 25–30 | 14–21 |
| Swing | 10–15 | 30–45 |

Promotion to `live_candidate_final` requires **both** `min_trades` AND
`min_days` satisfied.

## Folder structure
```
mt5-ea-factory/
  CLAUDE.md
  .claude/agents/            <- the four subagent definitions
  strategies/
    registry.json             <- central status tracker for all strategies
    _graveyard/                <- discarded strategies + one-line reason why
    day_trading/
      <strategy_name>/
        dates.md              <- in-sample + out-of-sample ranges for this strategy
        STRATEGY.md            <- single-file summary once a strategy reaches a decision point
        VERDICT.md             <- live-readiness call, once validated
        v1/
          spec.json             <- exact rules EA Coder built this version from
          strategy.mq5
          config.ini            (in-sample dates)
          compile.log
          report.htm / report.xml
          journal.csv
          summary.csv
          review.md            <- stats + proposed next step
          validation/          (only when requested)
            config.ini         (out-of-sample dates)
            report.htm
            journal.csv
            comparison.md      <- in-sample vs out-of-sample side by side
        v2/ (next iteration, only after Researcher decides to refine)
  scripts/
    compile_ea.py       (calls MetaEditor CLI)
    run_backtest.py     (writes config.ini, calls terminal64.exe /config:...)
    parse_report.py     (parses tester report into journal.csv)
    orchestrator.py     (ties the above together per version)
  journal/
    trades.csv           <- aggregate backtest journal across all strategies (Backtester appends)
    live_trades.csv       <- demo/live journal, tagged demo vs live (Live Manager appends)
  researcher/lessons.md      <- strategy-performance memory
  ea-coder/lessons.md        <- compile-error / coding-mistake memory
  backtester/lessons.md      <- pipeline-issue memory
  live-manager/lessons.md    <- deployment/operational memory
  logs/
```

Note: this deviates from a flatter `ea/{id}.mq5` / `backtests/{id}/`
layout in favor of the nested `strategies/<category>/<name>/<version>/`
layout already in use, specifically so `scripts/*.py` (already
battle-tested against real MT5 quirks) keep working unmodified. `id` in
registry/spec terms means `<category>/<name>`.

## Date ranges — in-sample vs out-of-sample
Before the first backtest of a new strategy, Researcher asks the user for:
- **In-sample (optimization) range** — e.g. 2018.01.01–2019.12.31.
  All parameter sweeps and logic iteration happen only against this range.
- **Out-of-sample (validation) range** — e.g. 2023.01.01–2024.12.31.
  Never used for optimization. Used once, unmodified, as a final check.
  If out-of-sample results look weak, report it as a finding — do NOT go
  back and re-optimize in response to it. That breaks the point of the split.

## The loop (one iteration = one version folder)
1. **Generate/modify strategy** (Researcher writes spec.json, EA Coder
   writes `strategy.mq5`).
2. **Compile** — MetaEditor CLI (`/compile:` + `/log:`), via
   `scripts/compile_ea.py`. Stop and fix if there are compile errors —
   never backtest broken code.
3. **Backtest (in-sample)** — Backtester writes `config.ini` with the
   in-sample dates, launches `terminal64.exe /config:...` (use
   `ShutdownTerminal=1` so it closes itself when done).
4. **Parse & journal** — turn the tester report into `journal.csv`, one row
   per trade (open/close time, side, lots, entry, exit, SL, TP, profit,
   pips, duration), and append to the aggregate `journal/trades.csv`.
5. **Optimize** — Researcher decides which fits the problem:
   - **Parameter sweep**: MT5's built-in Optimization mode for tunable
     numeric inputs (MA periods, SL/TP multiples, thresholds, etc.)
   - **Logic change**: EA Coder rewrites entry/exit rules directly if the
     sweep can't fix a structural issue (wrong session, no edge, bad exit
     logic)
6. **Review** — Researcher writes `review.md`:
   - Profit factor, win rate, max drawdown, # trades, expectancy,
     Sharpe/Sortino ratio, max consecutive losses, recovery factor
   - What worked / didn't, referencing specific trades if useful
   - Flag if trade count is below the 200-trade significance bar
   - Proposed next step, with specific reasoning
7. **Registry update** — Researcher sets `refining`, `discarded`, or
   `live_candidate`. Only `live_candidate`/`live_candidate_final` pause
   the orchestrator for the user; everything else continues
   automatically per the Orchestrator loop above.

## Multi-window robustness check
Once a version looks solid on its in-sample range, re-test the same locked
parameters across a few other historical windows (not the one it was tuned
on) to see if the edge holds generally or was a fluke of one period. See
`strategies/day_trading/gotobi/v1/robustness/run_yearly.py` for a worked
pattern (per-pair yearly breakdown, in that case).

## Out-of-sample validation
Re-run the same compiled EA/parameters (no further tweaking) against the
out-of-sample range in a `validation/` subfolder. Report in-sample vs
out-of-sample stats side by side in `comparison.md`. See
`strategies/day_trading/gotobi/v1/comparison.md` for a worked example.

## Realism in backtests
Model spread, commission, and slippage explicitly in `config.ini` rather
than relying on defaults — day-trading edges often disappear once real
transaction costs are applied. Match the tester's execution/tick model to
what the broker actually offers live where possible. In practice here that
means: `Model=4` (every tick based on real ticks) and `Login=YOUR_ACCOUNT_LOGIN` so the
tester uses the account's real historical spread and commission schedule.

## Final verdict (live-readiness)
After in-sample optimization, the multi-window check, and out-of-sample
validation are all done, Researcher writes a `VERDICT.md` with its own
judgment call, then flags `live_candidate`:
- **Ready for live** — if performance is consistent across the different
  years/windows tested (not just one good number). State the specific
  evidence: e.g. "profit factor stayed above 1.4 across all four tested
  years, drawdown never exceeded 12%, out-of-sample results were within
  10% of in-sample — no signs of curve-fitting."
- **Not ready** — same format, explaining what's weak (e.g. out-of-sample
  degradation, too few trades, one good year carrying the average) and
  what would need to change.
- The verdict may also recommend a specific staged/reduced-size rollout
  rather than a flat ready/not-ready — see
  `strategies/day_trading/gotobi/VERDICT.md` for a worked example (thin
  edge, evidence solid, but execution-quality risk unverifiable by
  backtest alone → recommended reduced size before full sizing).
Don't default to always requiring a demo step first, but call it out if
the evidence is genuinely borderline. Either way, `live_candidate` /
`live_candidate_final` only ever *recommends* — the user sets
`approved_demo`/`approved_live` manually.

## Conventions
- Never delete a previous version folder — always increment (v1, v2, ...).
- Every config.ini, spec.json, and strategy.mq5 stays alongside its own
  results, so any run is reproducible and comparable later.
- A backtest with zero trades is a review finding, not a silent failure —
  investigate (session hours, filters, symbol/period) and report it.
- When a strategy reaches a real decision point (validated, verdicted, or
  otherwise worth a consolidated read), write a single-file
  `STRATEGY.md` summary rather than leaving the story scattered across
  version subfolders — see `strategies/day_trading/gotobi/STRATEGY.md` or
  `strategies/day_trading/london_range_fade/STRATEGY.md`.

## Repo / environment conventions (added 2026-09-26, when this project
was first put under version control)

- **This project is a git repo** (`main` branch, remote at
  `github.com/treetechsuman/trading-agent`, **public**). See
  `REBUILD.md` for the full environment/dependency/setup picture — read
  that file, not just this section, before setting this project up on a
  new machine.
- **The real MT5 account login never gets committed.** It lives in
  `scripts/local_settings.py` (gitignored; template at
  `scripts/local_settings.example.py`). Every `config.ini` and every
  mention of the account number in prose (this file included) uses the
  literal placeholder `YOUR_ACCOUNT_LOGIN` instead. If you ever see the
  real number about to go into a new committed file, redact it the same
  way before committing — this was a deliberate, repo-wide pass done on
  2026-09-26, not a one-off.
- **`scripts/common.py`'s `TERMINAL_EXE`/`METAEDITOR_EXE`/`MT5_DATA_DIR`
  constants are machine-specific hardcoded paths, not secrets** — they'll
  need editing on any different install, but there's no need to redact
  them (they contain no account-identifying information, just this
  machine's local folder layout).
- **Only commit when explicitly asked** (standard git-safety practice,
  not specific to this project) — this repo holds real trading strategy
  logic and a live-account-adjacent history; treat every commit as
  something the user should knowingly approve, same as any
  `approved_demo`/`approved_live` registry change.

## Scripts
All four scripts live in `scripts/` and take a version folder path
(e.g. `strategies/day_trading/<name>/v1`) as their main argument.
See each script's `--help` for full options. Typical flow:

```
python scripts/orchestrator.py strategies/day_trading/<name>/v1 ^
    --symbol EURUSD --timeframe H1 ^
    --from 2018.01.01 --to 2019.12.31 --deposit 10000 --currency USD
```

`orchestrator.py` runs compile → backtest → parse in sequence and stops on
compile errors. Each step can also be run standalone. For multi-symbol
strategies, run `run_backtest.py`/`parse_report.py` per symbol into their
own subfolders (`--out-dir`) rather than one combined run — see
`strategies/day_trading/gotobi/v1/`'s per-pair subfolders.

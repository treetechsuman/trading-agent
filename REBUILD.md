# REBUILD.md — recreating this agent from scratch

> **Read this before anything else**: this project's compile/backtest/live
> steps are **Windows-only**, hard-dependent on a real copy of MetaTrader 5
> (a Windows GUI application) being installed and logged into a real,
> funded broker account. A "fresh Linux server" cannot run the actual
> trading pipeline as-is — see **Section 4 and the callout in Section 7**
> for exactly what can and can't be recreated there. Don't skip that part;
> it changes what "rebuild this agent" actually means in your environment.

## 1. Purpose

An autonomous pipeline that designs day-trading and scalping forex
strategies, implements each as an MT5 Expert Advisor (MQL5), backtests and
optimizes it against historical data via MetaTrader 5's Strategy Tester,
validates it on out-of-sample data, and — only with explicit manual
approval at each capital-risk step — deploys it to a demo or live trading
account. The "agent" is four specialized Claude Code subagents (researcher,
EA coder, backtester, live manager) coordinated by an orchestrator session,
with all state tracked in a single JSON registry rather than a database.

## 2. Architecture

There is no server process and no long-running daemon. The "system" is:
a human/orchestrator Claude Code session, four subagent role definitions
it dispatches to, a shared JSON registry both read and write, and a thin
Python scripting layer that shells out to MetaTrader 5's own executables
to do the actual compiling/backtesting.

```
 Orchestrator (a Claude Code session, driven by root CLAUDE.md)
        |
        | reads/updates
        v
 strategies/registry.json  <-- single source of truth for every
        ^                     strategy's lifecycle status
        |
   dispatches to one of four subagents based on status:
        |
        +--> researcher   (.claude/agents/researcher.md)
        |      writes spec.json, reviews results, decides refine/
        |      discard/live_candidate -- the only agent that makes
        |      strategy-logic decisions. Never touches .mq5 or a live
        |      account.
        |
        +--> ea-coder     (.claude/agents/ea-coder.md)
        |      translates spec.json -> strategy.mq5, compiles it via
        |      scripts/compile_ea.py (which shells out to
        |      MetaEditor64.exe). Never invents strategy logic.
        |
        +--> backtester   (.claude/agents/backtester.md)
        |      runs scripts/run_backtest.py (shells out to
        |      terminal64.exe in Strategy Tester mode) then
        |      scripts/parse_report.py (parses the HTML report into
        |      CSV). Never judges whether results are good.
        |
        +--> live-manager (.claude/agents/live-manager.md)
               the only agent that can attach an EA to a demo/live
               chart -- and only on the user's explicit instruction
               plus a matching approved_demo/approved_live registry
               status. Chart-attach itself is a GUI-only action a
               script cannot drive headlessly (see Section 8).
```

Data flow for one strategy version (folder
`strategies/<category>/<name>/<version>/`):

```
spec.json --(ea-coder)--> strategy.mq5 --(compile_ea.py)--> compile.log
    --(run_backtest.py, writes config.ini, drives terminal64.exe)--> report.htm
    --(parse_report.py)--> journal.csv + summary.csv
    --(researcher)--> review.md --> registry.json status update
```

Every subagent also keeps its own flat-file memory
(`{researcher,ea-coder,backtester,live-manager}/lessons.md`) that it reads
before acting and appends to after — this is the only cross-session memory
for role-specific mistakes/gotchas, and is itself part of what needs to be
recreated for the agent to behave the same way over time.

## 3. File tree (important files only — `strategies/` holds ~1650
generated result files following one repeating pattern, described once
below rather than enumerated)

```
CLAUDE.md                     Orchestrator instructions: architecture,
                               status lifecycle, folder conventions, all
                               operational parameters (kill-switch %,
                               significance bar, date-split rules). This
                               is the actual spec for how the agent
                               behaves -- read it in full before anything
                               else if you're rebuilding behavior, not
                               just infrastructure.
REBUILD.md                    This file.
.gitignore                    Excludes local_settings.py (real account
                               login), __pycache__, and Claude Code's
                               local session lock file.

.claude/agents/researcher.md     Researcher subagent system prompt.
.claude/agents/ea-coder.md       EA Coder subagent system prompt
                                  (includes the "chart status panel"
                                  standing convention, added 2026-09-23).
.claude/agents/backtester.md     Backtester subagent system prompt.
.claude/agents/live-manager.md   Live Manager subagent system prompt
                                  (the 15% kill-switch enforcement lives
                                  in strategy logic AND is described
                                  here as an external check too).

scripts/common.py             Shared constants (MT5_DATA_DIR, TERMINAL_EXE,
                               METAEDITOR_EXE -- all machine-specific,
                               hardcoded, must be edited per install) and
                               helpers (run(), wait_for_file(),
                               parse_input_defaults() -- regex-extracts
                               every `input` declaration's literal default
                               straight from a .mq5 file).
scripts/local_settings.py     REAL account login. Gitignored -- never
                               committed. Not present on a fresh checkout;
                               you must create it (see Section 5).
scripts/local_settings.example.py   Template for the above, placeholder
                               value only. This IS committed.
scripts/compile_ea.py         Copies a strategy.mq5 from this repo into
                               the MT5 terminal's own MQL5/Experts tree
                               (required for #include resolution), then
                               runs `MetaEditor64.exe /compile: /log:` and
                               copies compile.log back next to the source.
scripts/run_backtest.py       Writes a Strategy Tester config.ini (dates,
                               symbol, deposit, [TesterInputs] block) and
                               runs `terminal64.exe /config:...`. Also
                               handles the quirk that MT5's Report= field
                               only honors a bare filename -- the actual
                               report always lands at the data-folder
                               root and this script moves it into the
                               real version folder afterward.
scripts/parse_report.py       Parses report.htm (BeautifulSoup + lxml)
                               into journal.csv (one row per trade,
                               FIFO-paired deals) and summary.csv (the
                               tester's own summary metrics).
scripts/orchestrator.py       Runs compile -> backtest -> parse for one
                               version folder in sequence, stopping on a
                               compile error. A convenience wrapper, not
                               required -- each step also runs standalone.

strategies/registry.json      Central status tracker for every strategy
                               (id = "<category>/<name>"). The single
                               most important piece of state in this
                               whole project -- see CLAUDE.md's "Status
                               lifecycle" table for what each value means.
strategies/_graveyard/<name>/REASON.md   One-line-to-one-page reason a
                               discarded strategy was rejected.
strategies/<category>/<name>/dates.md        In-sample / out-of-sample
                               date ranges for that strategy family.
strategies/<category>/<name>/STRATEGY.md     Single-file summary, written
                               once a strategy reaches a real decision
                               point.
strategies/<category>/<name>/VERDICT.md      Live-readiness call, once
                               validated.
strategies/<category>/<name>/<version>/spec.json      Exact rules EA
                               Coder built this version from.
strategies/<category>/<name>/<version>/strategy.mq5   The EA source
                               (source of truth lives here, not in the
                               MT5 data folder -- compile_ea.py copies it
                               out to compile, never the reverse).
strategies/<category>/<name>/<version>/compile.log    MetaEditor's output
                               for this version's most recent compile.
strategies/<category>/<name>/<version>/config.ini     Tester config used
                               for the in-sample run (out-of-sample runs
                               live in a validation/ subfolder with their
                               own config.ini). Login= is redacted to
                               YOUR_ACCOUNT_LOGIN in every committed copy.
strategies/<category>/<name>/<version>/report.htm     Raw Strategy Tester
                               HTML report.
strategies/<category>/<name>/<version>/journal.csv    Parsed per-trade
                               journal for this run.
strategies/<category>/<name>/<version>/summary.csv    Parsed summary
                               metrics for this run.
strategies/<category>/<name>/<version>/review.md      Researcher's
                               findings + proposed next step.
strategies/<category>/<name>/<version>/validation/    Out-of-sample
                               re-run of the same compiled EA, same
                               file set as above.
(Multi-symbol strategies additionally have per-pair subfolders, e.g.
strategies/day_trading/gotobi/v1/GBPJPY/, mirroring the same file set --
see CLAUDE.md's "Scripts" section.)

journal/trades.csv            Aggregate backtest journal across every
                               strategy/version (Backtester appends).
journal/live_trades.csv       Aggregate demo/live journal, tagged
                               demo vs. live (Live Manager appends).

researcher/lessons.md         Strategy-performance memory (93 lines).
ea-coder/lessons.md           Compile-error / MQL5-gotcha memory
                               (582 lines -- the largest, since MQL5/MT5
                               Strategy-Tester quirks are the most
                               numerous class of surprise in this
                               project).
backtester/lessons.md         Pipeline-issue memory (129 lines).
live-manager/lessons.md       Deployment/operational memory (195 lines).

logs/                          Reserved, currently empty.
```

## 4. Exact dependencies with versions

**Confirmed on the machine this was built on:**

| Dependency | Version | Required for |
|---|---|---|
| OS | Windows 11 Home, build 10.0.26200 | Running the MT5 terminal + MetaEditor at all (see callout below) |
| Python | 3.13.14 | All `scripts/*.py` |
| `beautifulsoup4` | 4.15.0 | `parse_report.py`'s HTML parsing |
| `lxml` | 6.1.3 | `parse_report.py`'s BeautifulSoup parser backend (`BeautifulSoup(html, "lxml")`) |
| Git | 2.47.1.windows.1 | Version control (this repo) |
| FP Markets MetaTrader 5 (terminal64.exe + MetaEditor64.exe) | Unpinned — last confirmed-working report format was **build 5830** (see `scripts/parse_report.py`'s own docstring); check Help → About in the terminal for the current build | Compiling `.mq5`, running the Strategy Tester, and any live/demo trading |
| Claude Code (or the Claude Agent SDK, with subagent support) | Whatever this session is running on | The four subagents *are* Claude Code subagent definitions (`.claude/agents/*.md`) — there is no standalone Python implementation of "researcher"/"ea-coder"/etc. |

No other third-party Python packages are used — everything else imported
across `scripts/*.py` is stdlib (`argparse`, `csv`, `re`, `shutil`,
`subprocess`, `sys`, `time`, `pathlib`).

**Critical portability note — MetaTrader 5 is Windows-only for the
functionality this project actually depends on:**
- `terminal64.exe` and `MetaEditor64.exe` are Windows PE executables.
  There is no official Linux or macOS build of the MetaEditor MQL5
  compiler or the Strategy Tester from FP Markets (or most brokers).
- This project's scripts invoke them directly by hardcoded Windows path
  (`scripts/common.py`'s `TERMINAL_EXE`/`METAEDITOR_EXE` constants) and
  parse Windows-style paths out of their log output.
- Running MT5 under Wine on Linux is technically possible in general and
  is how some MT5 users run it on Linux, but **this project has never
  been run or tested that way** — the `/compile:`/`/config:` CLI flags,
  the way `ShutdownTerminal=1` behaves, and the exact report-file-naming
  quirk `run_backtest.py` works around were all reverse-engineered
  against the real Windows build. Treat a Wine-based Linux setup as
  unverified, not equivalent.
- **What genuinely is portable**: the Python scripts' *logic* (argument
  parsing, config.ini templating, report.htm parsing) is plain Python and
  will run on Linux — it just has nothing to compile or execute against
  without a working MT5 install reachable at the paths in `common.py`.
  The `.claude/agents/*.md` subagent prompts and `CLAUDE.md` itself are
  plain text and fully portable. The registry, specs, and past results
  (`strategies/`) are also just data and fully portable.
- **Practical recommendation for a Linux server**: use it to run the
  orchestrator/Claude Code session and the researcher/EA-coder authoring
  steps (spec + `.mq5` writing don't need MT5 at all), but point
  `compile_ea.py`/`run_backtest.py` at a **separate Windows machine**
  reachable over the network (e.g. via a mounted drive or a small RPC
  wrapper) for the actual compile/backtest/deploy steps — or run the
  whole thing on Windows, which is what this repo has only ever actually
  done.

## 5. Environment variables and config

**This project does not use process environment variables or a `.env`
file for its actual configuration** — everything is either a hardcoded
Python constant or a single gitignored settings file:

| Name | Where | What it's for | Real value present in repo? |
|---|---|---|---|
| `ACCOUNT_LOGIN` | `scripts/local_settings.py` (gitignored; template at `scripts/local_settings.example.py`) | The MT5 account login (a username/number, not a password) that `run_backtest.py` passes as `Login=` in every generated `config.ini`, so the Strategy Tester uses that account's real contract specs/spread/commission. | No — redacted to `YOUR_ACCOUNT_LOGIN` everywhere in committed files; the real value only ever exists in the gitignored `local_settings.py` on the machine that runs it. |
| `TERMINAL_EXE` | `scripts/common.py` (plain constant, not secret, but machine-specific) | Absolute path to `terminal64.exe` for this specific broker's MT5 install. | Yes, hardcoded — **must be edited** for any different machine/broker install (currently `C:\Program Files\FP Markets MetaTrader 5\terminal64.exe`). |
| `METAEDITOR_EXE` | `scripts/common.py` | Absolute path to `MetaEditor64.exe`. | Same as above. |
| `MT5_DATA_DIR` | `scripts/common.py` | Absolute path to this MT5 install's per-terminal data folder (where compiled `.mq5`→`.ex5` and generated reports land before being copied out). | Same as above — this path includes a machine-specific terminal ID hash, will be different on every install. |

`.env.example` has been added per your request, but is currently a stub
documenting this — see that file directly. If this project ever grows a
second secret (a broker API token, a notification webhook, etc.), that's
the natural place to put it; there was nothing else to move into it today.

**No MT5 account password is stored anywhere in this repo or in
`local_settings.py`** — the terminal must already be manually logged into
the account (this project assumes an already-connected terminal, per
CLAUDE.md's Environment section), so there's no password to redact in the
first place, only the login/account number.

## 6. External services, APIs, ports, and databases

- **No web server, no listening ports, no database.** All state is flat
  files: one JSON registry, several CSV journals, Markdown reviews. There
  is nothing to stand up beyond the files themselves.
- **FP Markets' MT5 trading server** (`FPMarkets-Live`) — reached only
  through the locally-installed, already-logged-in `terminal64.exe`. The
  Python scripts never make a network call themselves; all broker
  communication happens inside the terminal process they launch.
- **Claude Code / the Anthropic API** — the four subagents are model
  calls made through Claude Code's own auth, not anything stored in this
  repo.
- **GitHub** (`github.com/treetechsuman/trading-agent`) — source control
  remote for this repo only; not part of the pipeline's runtime.

## 7. Step-by-step setup from a clean machine

### Path A — Windows (the only way to get real compile/backtest/deploy functionality)

1. Install a broker's MetaTrader 5 terminal (this project uses FP
   Markets' build; any broker's MT5 terminal exposes the same
   `terminal64.exe`/`MetaEditor64.exe` CLI shape, but paths/behavior may
   differ slightly — re-verify against `ea-coder/lessons.md` and
   `backtester/lessons.md`'s documented quirks).
2. Log the terminal into a real account manually at least once (this
   project does not automate login) — GUI login, then leave it
   logged in.
3. Note this install's data folder path (`%APPDATA%\MetaQuotes\Terminal\<hash>\`)
   and the terminal/MetaEditor `.exe` paths; update `scripts/common.py`'s
   `TERMINAL_EXE`, `METAEDITOR_EXE`, `MT5_DATA_DIR` constants to match.
4. Install Python 3.13+ and the two third-party packages:
   ```
   pip install beautifulsoup4==4.15.0 lxml==6.1.3
   ```
5. Clone this repo.
6. Create your real settings file (never commit it):
   ```
   cp scripts/local_settings.example.py scripts/local_settings.py
   # edit ACCOUNT_LOGIN to your real account number
   ```
7. Sanity-check the scripts can at least import and run `--help`:
   ```
   python scripts/run_backtest.py --help
   python scripts/compile_ea.py --help
   ```
8. Open this repo in Claude Code so the four subagent definitions under
   `.claude/agents/` are available, and so `CLAUDE.md` is loaded as
   project instructions.

### Path B — Linux (orchestration/authoring layer only — see Section 4's callout)

Steps 4–8 above are identical and will work fine (Python + Claude Code +
the repo itself have no OS dependency). Steps 1–3 are the part that
doesn't have a Linux equivalent today — either skip them and accept that
`compile_ea.py`/`run_backtest.py` cannot succeed on this machine, or
point those two scripts' constants at a Windows machine you reach some
other way (network drive, remote execution, etc. — not implemented here).

## 8. How to run it

**There is no background service in the traditional sense** — nothing
listens on a port or runs as a daemon by default.

- **Dev / one-off** — run any pipeline step standalone:
  ```
  python scripts/compile_ea.py strategies/day_trading/gotobi/v1
  python scripts/orchestrator.py strategies/day_trading/gotobi/v1 \
      --symbol USDJPY --timeframe M1 \
      --from 2017.01.01 --to 2022.12.31 --deposit 10000 --currency USD
  ```
- **As the agent** — open this repo in Claude Code and say "start
  working" (or similar). The orchestrator loop described in `CLAUDE.md`
  then reads `strategies/registry.json` and dispatches to whichever
  subagent owns each strategy's current status, looping until every
  strategy is either done or waiting on a manual approval
  (`live_candidate`/`live_candidate_final`). This is a foreground Claude
  Code session, not a background OS process — if you want it re-checked
  periodically without you present, that's a Claude Code scheduling
  concern (e.g. the `/loop` skill or a scheduled cron-style trigger), not
  something this repo implements itself.
- **A deployed EA itself IS a genuine background process** — once
  Live Manager attaches a compiled `.ex5` to a demo/live chart (a
  GUI-only action: Navigator drag-drop → Inputs dialog → enable Algo
  Trading — no script in this repo can do this headlessly), it runs
  continuously inside the MT5 terminal for as long as that chart/terminal
  stays open, independent of whether any Claude Code session is active.

## 9. How to verify it works

```
# 1. Registry is valid JSON and loads
python -m json.tool strategies/registry.json > /dev/null && echo OK

# 2. Scripts import cleanly (this alone catches a missing local_settings.py
#    or a wrong path in common.py, since both are imported at module load)
python scripts/run_backtest.py --help
python scripts/compile_ea.py --help
python scripts/parse_report.py --help
# Expected: each prints its argparse usage/help text with exit code 0.
# A missing scripts/local_settings.py fails loudly here with:
#   ImportError: scripts/local_settings.py is missing -- copy ...

# 3. (Windows + working MT5 install only) recompile an existing, known-good EA
python scripts/compile_ea.py strategies/day_trading/gotobi/v1
# Expected: "Result: 0 errors, 0 warnings, ... elapsed" and a fresh
# strategies/day_trading/gotobi/v1/compile.log

# 4. (Windows + working MT5 install only) run a short backtest end to end
python scripts/orchestrator.py strategies/day_trading/gotobi/v1 \
    --symbol USDJPY --timeframe M1 \
    --from 2022.01.01 --to 2022.03.31 --deposit 10000 --currency USD \
    --out-dir /tmp/rebuild_smoke_test
# Expected: "=== Step 1/3: compile ===" ... "=== Step 2/3: backtest ==="
# (terminal64.exe launches and closes itself, ShutdownTerminal=1) ...
# "=== Step 3/3: parse ===" ... "Done." with journal.csv/summary.csv
# written into the --out-dir path.
```

If step 2 fails with an import error naming `local_settings`, you skipped
Section 7 step 6. If step 3/4 fail with a file-not-found on
`terminal64.exe`/`MetaEditor64.exe`, `scripts/common.py`'s path constants
don't match this machine (or you're on Linux without a Windows target —
see Section 4).

## 10. Known gotchas and decisions, and why

Curated from `ea-coder/lessons.md`, `backtester/lessons.md`, and
`live-manager/lessons.md` (999 lines combined — read those directly for
full detail; this is the "don't rediscover these the hard way" summary):

- **MT5 only allows one `terminal64.exe` instance per data folder.** A
  stray, already-open idle terminal window silently prevents a new
  `/config:` launch from actually running a test — `config.ini` gets
  written, but no `report.htm` is ever produced, and `wait_for_file()`
  just times out. Always check `tasklist` for a lingering instance before
  a backtest run, and never run backtests concurrently.
- **A real multi-year, M1, real-tick (`Model=4`) backtest can legitimately
  take 15–40+ minutes.** Don't set an aggressive timeout and mistake a
  slow-but-healthy run for a hang.
- **`TimeGMT()`/`TimeLocal()` reflect the real host clock inside the
  Strategy Tester, not simulated time.** Any UTC-specified timing must be
  implemented against `TimeCurrent()` (broker/server time) with the
  broker's UTC offset hardcoded per the relevant calendar rule.
- **MT5's tester `Report=` field only honors a bare filename** — any path
  component is silently ignored and no report is written at all.
  `run_backtest.py` works around this by always writing to the data
  folder root, then moving the result into the real version folder.
- **A single shared `CTrade` object only tracks one "current" magic
  number.** For any EA managing multiple symbols, `SetExpertMagicNumber()`
  must be called again immediately before *every* `PositionClose()`, not
  just before opening — otherwise closes for the wrong symbol are
  silently rejected forever (this produced a fake ~78% drawdown in
  `gotobi/v1_portfolio` before being traced).
- **This broker's symbol naming is inconsistent** — bare `USDJPY`
  resolves, but `EURJPY`/`GBPJPY`/`EURUSD`/`GBPUSD` need a `.r` suffix.
  Always probe an unfamiliar symbol with a short date range first.
- **Every strategy now requires (as of 2026-09-23) an `InpAllowLiveAccount`
  live-account guard from its very first version**, and (as of the same
  date) a baseline safety ledger (consecutive-loss halt, daily-loss halt,
  15% drawdown kill-switch) — this was retrofitted after one strategy
  reached `approved_live` with zero live-account protection at all,
  caught only when Live Manager's own pre-deployment check refused to
  proceed.
- **On-chart status panel is mandatory before any `live_candidate` flag**
  (added 2026-09-23, full spec in `ea-coder.md`) — attaching an EA to a
  chart previously showed nothing but the generic MT5 icon, which is
  unworkable for live monitoring of a low-frequency, event-driven
  strategy.
- **Account login is deliberately kept out of every committed file**
  (this repo's own git history) — redacted to `YOUR_ACCOUNT_LOGIN` in all
  `config.ini`/docs, real value only in the gitignored
  `scripts/local_settings.py`. MetaEditor's own compile logs do still
  embed the local Windows username in file paths (e.g.
  `C:\Users\<name>\...`) since that's the compiler's own log output, not
  something this project generates — low-sensitivity (a first name in a
  path, not a credential) but worth knowing if you're auditing for PII.
- **200-trade significance bar (backtest) vs. per-strategy
  `demo_criteria.min_trades` (demo→live promotion) are deliberately
  separate, stricter/looser thresholds** — don't conflate them.
- **Out-of-sample data is used exactly once, never re-optimized against**
  — a weak OOS result is reported as a finding, not a reason to go back
  and retune (this is treated as a hard methodological rule throughout
  the project's history, and violating it is exactly what produced
  several early "looked great, didn't replicate" false positives before
  it was adopted).
- **15% drawdown kill-switch is enforced in two independent places** (the
  EA's own coded safety ledger, and Live Manager's external check) —
  deliberate redundancy, not an oversight.

# Backtester — lessons

Seeded 2026-09-22 from this project's history prior to the multi-agent
restructure. Keep appending after every run where the *pipeline itself*
had an issue (not the strategy performing badly) — this file is the only
cross-session memory for tooling/pipeline problems.

## MT5 Strategy Tester / config.ini gotchas

- **`Report=` only accepts a bare filename** — any directory component
  (absolute or relative) or drive letter is silently ignored and no
  report is written at all, anywhere. `run_backtest.py` works around this
  by always writing the report to the data-folder root under a unique
  tag, then moving `report.htm` (+ companion `.png` files) into the real
  output folder afterward. Don't try to pass a path in `Report=` — it
  will silently fail.

- **Stale `[TesterInputs]` caching is real and dangerous.** When a config
  omits `[TesterInputs]` or leaves it incomplete, MT5 does NOT reliably
  fall back to the compiled EA's own coded defaults — it can silently
  reuse a value left over from testing a *different* EA that happens to
  declare an input with the same name (common in this project since every
  version is copied from the last and input names get reused across
  strategies). `run_backtest.py` fixes this by parsing every `input`
  declaration straight out of the `.mq5` source and writing a complete,
  explicit `[TesterInputs]` section every run. Never write `config.ini` by
  hand without going through this — a first attempt at
  `london_range_fade` v2's volatility filter silently produced
  bit-for-bit-identical results to the no-filter baseline for this exact
  reason, cost real debugging time before being traced to the cache.

- **Two `terminal64.exe` Strategy Tester runs collide if launched
  concurrently** against the same data folder. Always wait for one run's
  report file to appear (or the process to exit) before starting the
  next, even across different symbols/versions.

- **Symbol naming is inconsistent per instrument on this broker (FP
  Markets).** Bare `USDJPY` resolves; `EURJPY`/`GBPJPY` require a `.r`
  suffix (`EURJPY.r`, `GBPJPY.r`) — same pattern as `EURUSD.r`
  (`london_range_fade`). A wrong symbol name doesn't fail fast: the
  tester logs `symbol <NAME> not exist` in
  `Tester/logs/<date>.log` but the calling script can hang up to its full
  timeout waiting for a report that will never appear (found running
  `gotobi/v1`'s EURJPY backtest with a bare "EURJPY" — 1800s timeout, no
  report, `tasklist` showed no terminal64.exe process left running by the
  time it was investigated). **Always probe an unfamiliar symbol with a
  short (~10 day) date range and a short (~120s) timeout first** before
  committing to a multi-year run.

- **`report.htm` is UTF-16** with a nested-table layout — the Orders and
  Deals sub-tables live inside the same outer `<table>` as the summary,
  each introduced by its own `<th colspan=13>` title row rather than a
  separate `<table>` element, which breaks a naive `pandas.read_html()`.
  `parse_report.py` already walks the DOM directly to handle this — don't
  write a new parser.

- **This broker's tick history doesn't go back equally far for every
  symbol.** EURJPY.r/GBPJPY.r tick data only starts 2017.07.25 on this
  installation, while USDJPY's goes back further — a 2017-01-01 start
  date silently produces a partial year (21 trades instead of the normal
  ~50) for those two symbols specifically. Check first-trade dates in a
  new symbol's journal before treating an early year's numbers as a full
  sample.

## Diagnosing "real win rate but still losing" results

If a strategy shows a win rate meaningfully above 50% (or above whatever
its R:R implies it needs) but still has profit factor below 1.0, split
gross price P&L from commission/swap before concluding the signal is
worthless. `parse_report.py`'s `journal.csv`/`summary.csv` already net
everything together, so this needs a small one-off script against the
raw report.htm's Deals table (`extract_deals()`), summing `Profit`,
`Commission`, `Swap` separately across all non-`balance`-type rows (the
first deal row is the initial deposit, not a trade — exclude it, it will
silently add $10,000+ to a naive sum otherwise). Found via
`scalping/overlap_momentum_scalp`: gross was positive, commission alone
flipped it negative — a fundamentally different diagnosis (cost/frequency
mismatch) than "no real edge," worth checking before discarding a
strategy that shows a genuine win-rate signal.

## Multi-symbol strategies

MT5's standard Strategy Tester only trades the chart's own symbol. A spec
calling for "one EA per pair's chart" (e.g. `gotobi`) has to be
backtested either as N independent single-symbol runs (simple, but can't
show combined-account exposure), or as a single EA instance that places
orders on other symbols by name (see
`strategies/day_trading/gotobi/v1_portfolio/strategy.mq5` — the position
management/SL/TP for the non-chart symbols is still evaluated correctly
by the tester's own engine, it's only the *scheduling* logic in `OnTick()`
that's gated by the driving chart's own tick cadence). Default to N
independent runs unless Researcher specifically needs the combined-account
number.

**If a portfolio-style multi-symbol harness produces a wildly
catastrophic first result** (e.g. huge drawdown, trading stopping almost
entirely partway through the range): treat it as a harness bug to
investigate before reporting it as a real finding, not automatically as
"the strategy fails under combined exposure." `gotobi/v1_portfolio`'s
first run showed a fake ~78% drawdown from a `CTrade`-shared-magic bug
(root cause and fix in `ea-coder/lessons.md`) — diagnosed by re-pairing
the raw Deals table's rows **grouped by symbol first** (the standard
`parse_report.py` journal pairs deals in pure chronological FIFO order
across ALL symbols, which silently mismatches entries/exits between
different symbols whenever a multi-symbol EA holds concurrent positions —
this is the documented single-position assumption in that script's
docstring, actually triggered for the first time by a real multi-position
EA). When debugging a multi-symbol run, always regroup by the Deals
table's `Symbol` column before trusting any trade-level pairing.

## Spot-checking entry-timing logic (DST conversions etc.) without touching source

When a spec/EA Coder flags an unverified time-of-day conversion (e.g.
`nfp_fade`'s combined US-DST x broker-DST math) and the EA only trades when
a threshold filter passes, a narrow probe window often produces **zero
trades** even on the right date -- telling you nothing about whether the
timing itself is correct. Don't reach for adding temporary `Print()`
statements to the strategy source for this (that's editing a file that
isn't Backtester's to edit, and risks not being cleanly reverted). Instead,
use `run_backtest.py --set <ThresholdInput>=<near-zero>` on a short,
narrow-date-range, `--out-dir`-scoped probe run only -- this forces a trade
on the very next tick that clears the (now trivial) filter, so the trade's
own `open_time` in the resulting `journal.csv` directly reveals the actual
computed entry timestamp, at zero footprint on the real strategy files or
its real in-sample results. Confirmed working for `nfp_fade` v1: probes
bracketing 2024.03.08 and 2023.11.03 with `InpMinSpikeSizePipsFloor`
dropped to 0.1 produced trades at exactly T+10 after the expected derived
release time on both dates, matching dates.md's table with no off-by-one-
hour error.

## Using the Strategy Tester as a headless harness for non-trading tasks (2026-09-26) -- abandoned, don't retry as-is

Tried to reuse the compile_ea.py/run_backtest.py pipeline to run a
non-trading "EA" (`research/cointegration_check/v1/strategy.mq5`) whose
only job was dumping historical daily closes for ~20 FX pairs via
`CopyRates()` in `OnInit()`, so a real cointegration test could run against
this broker's own data instead of relying on outside literature. The
pattern itself (reusing the existing compile/launch scripts as a pure
execution harness for a non-trading payload) is sound and worked fine for
compiling -- **the failure was at runtime, twice, each a genuine multi-hour
hang with zero log output, not a quick error:**

- **First hang**: turned out to be a false alarm caused by something
  external -- a separate, user-run live terminal instance (a non-repo
  EA, magic `26090902`, tag `[SRBE]`, on `USDJPY.r`) was already running
  on this same machine/data folder when the launch happened. MT5 only
  allows one `terminal64.exe` per data folder, so the new launch likely
  never actually started a fresh process at all -- it just sat waiting
  against the pre-existing instance. No CSV was ever produced. Resolved
  once the user closed their own terminal.
- **Second hang, with that interference confirmed gone**: still hung for
  7.5+ hours, single clean process, zero output -- not even the one log
  line the EA prints per symbol on success OR failure. This means it got
  stuck either before `OnInit()` ever ran, or inside the very *first*
  `CopyRates()` call, for `EURUSD.r` -- the tester's own driving symbol,
  which should be the one case guaranteed to have data already prepared.
  Root cause not established (would need a much smaller isolated probe --
  one symbol, a short date range, a tight timeout -- to even tell whether
  `OnInit()` starts at all). Both attempts were killed via `taskkill`
  rather than resolving on their own.

**Standing lesson**: don't trust a large first attempt at this pattern
(many symbols, an 8-year range) without first proving the mechanism works
at all on a trivial case (one symbol, ~3 months, e.g. `--timeout 60`).
**Before ANY `terminal64.exe` launch on this dev machine, check `tasklist`
first** -- this account apparently also has a separate, manually-run live
setup on this same machine outside the repo/registry, so a collision risk
exists even for supposedly-harmless Tester-only launches, not just between
two of our own backtests. `research/cointegration_check/v1/` (the EA
source + the intended `test_cointegration.py` analysis script) is left in
place, uncommitted, for whoever picks this up next -- the actual
cointegration question itself was never answered; the literature-only
finding in `strategies/_graveyard/liquidity_sweep_reversal/REASON.md`
("FX majors correlated but not reliably cointegrated, even for
AUDUSD/NZDUSD") remains the only evidence on file, not independently
confirmed or refuted against this broker's own data.

## Report file appears before terminal64.exe exits (2026-10-18)

`run_backtest.py` returns as soon as `report.htm` shows up in the data folder.
`terminal64.exe` (with `ShutdownTerminal=1`) can still be alive for a few
seconds after that. A runner that checks `tasklist` before the next launch
right away will see the previous run's own terminal and treat it as a
foreign instance. This happened during month_end_fix_reversal v4: the L2 report
arrived, the next tasklist check saw PID 3048, and the batch aborted. The
process then exited by itself. Fix: after each leg, poll `tasklist` until
terminal64.exe is gone (up to ~120s), and only then run the
"is anything else running?" check for the next launch. A terminal that is
still there after that wait is a real foreign or hung instance.

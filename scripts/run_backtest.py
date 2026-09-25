"""Write a Strategy Tester config.ini and run terminal64.exe against it.

Usage:
    python run_backtest.py strategies/day_trading/<name>/v1 \
        --symbol EURUSD --timeframe H1 \
        --from 2018.01.01 --to 2019.12.31 \
        --deposit 10000 --currency USD [--optimize]

Writes config.ini next to strategy.mq5 (or into validation/ if --validation
is passed), then launches the terminal with ShutdownTerminal=1 so it closes
itself when the run finishes.

IMPORTANT (found by testing against this installation): MT5's `Report=`
tester field only honors a bare filename with no path separators and no
drive letter -- any directory component (absolute or relative) is silently
ignored and no report is written at all. So the report is always generated
at the *data folder root* under a unique name, then this script moves
report.htm and its companion .png files into the actual version folder and
cleans up the data folder root afterward.
"""
from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

from common import ACCOUNT_LOGIN, MT5_DATA_DIR, TERMINAL_EXE, expert_relative_path, parse_input_defaults, run, version_dir_parts, wait_for_file

CONFIG_TEMPLATE = """\
[Tester]
Expert={expert}
Symbol={symbol}
Period={period}
Login={login}
Model=4
ExecutionMode=0
Optimization={optimization}
OptimizationCriterion=0
FromDate={from_date}
ToDate={to_date}
ForwardMode=0
Deposit={deposit}
Currency={currency}
ProfitInPips=0
Leverage={leverage}
UseLocal=1
Visual=0
Report={report}
ReplaceReport=1
ShutdownTerminal=1
"""


def report_basename(strategy_name: str, version: str, validation: bool, tag: str = "") -> str:
    suffix = "_validation" if validation else ""
    tag_part = f"_{tag}" if tag else ""
    # Bare name only -- no path separators (see module docstring).
    return f"EAFactory_{strategy_name}_{version}{suffix}{tag_part}_report"


def write_config(version_dir: Path, args) -> tuple[Path, str]:
    strategy_name, version = version_dir_parts(version_dir)
    if args.out_dir:
        out_dir = Path(args.out_dir)
    else:
        out_dir = version_dir / "validation" if args.validation else version_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    expert = expert_relative_path(strategy_name, version)
    report_name = report_basename(strategy_name, version, args.validation, args.report_tag)

    config_text = CONFIG_TEMPLATE.format(
        expert=expert,
        symbol=args.symbol,
        period=args.timeframe,
        login=ACCOUNT_LOGIN,
        optimization=1 if args.optimize else 0,
        from_date=args.date_from,
        to_date=args.date_to,
        deposit=args.deposit,
        currency=args.currency,
        leverage=args.leverage,
        report=report_name,
    )

    # IMPORTANT: always write every declared input explicitly (see
    # common.parse_input_defaults docstring) -- MT5 does not reliably fall
    # back to the compiled EA's own defaults when [TesterInputs] is omitted
    # or incomplete; it can silently reuse a stale value cached under that
    # parameter name from an earlier run of a *different* EA.
    inputs = parse_input_defaults(version_dir / "strategy.mq5")
    for kv in args.set or []:
        name, value = kv.split("=", 1)
        inputs[name] = value
    lines = ["", "[TesterInputs]"] + [f"{name}={value}" for name, value in inputs.items()]
    config_text += "\n".join(lines) + "\n"

    config_path = out_dir / "config.ini"
    config_path.write_text(config_text, encoding="utf-8")
    print(f"Wrote {config_path}")
    return config_path, report_name


def collect_report(report_name: str, out_dir: Path, timeout: int) -> bool:
    src_htm = MT5_DATA_DIR / f"{report_name}.htm"
    if not wait_for_file(src_htm, timeout=timeout):
        print(f"ERROR: {src_htm} was not produced within {timeout}s")
        return False

    # Give the terminal a moment to finish writing the companion .png files.
    time.sleep(1.0)

    dest_htm = out_dir / "report.htm"
    shutil.move(str(src_htm), str(dest_htm))
    print(f"Moved {src_htm} -> {dest_htm}")

    for suffix in ("", "-hst", "-mfemae", "-holding"):
        src_png = MT5_DATA_DIR / f"{report_name}{suffix}.png"
        if src_png.exists():
            dest_png = out_dir / f"report{suffix}.png"
            shutil.move(str(src_png), str(dest_png))

    return True


def run_backtest(version_dir: Path, args) -> bool:
    config_path, report_name = write_config(version_dir, args)
    out_dir = config_path.parent

    cmd = [str(TERMINAL_EXE), f"/config:{config_path}"]
    print(f"Running: {' '.join(cmd)}")
    print("(terminal will close itself when the test finishes — ShutdownTerminal=1)")
    run(cmd, timeout=args.timeout)

    return collect_report(report_name, out_dir, args.timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version_dir")
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--timeframe", required=True, help="e.g. M15, H1, H4")
    parser.add_argument("--from", dest="date_from", required=True, help="YYYY.MM.DD")
    parser.add_argument("--to", dest="date_to", required=True, help="YYYY.MM.DD")
    parser.add_argument("--deposit", type=int, default=10000)
    parser.add_argument("--currency", default="USD")
    parser.add_argument("--leverage", type=int, default=100)
    parser.add_argument("--optimize", action="store_true", help="Run in optimization mode instead of a single pass")
    parser.add_argument("--validation", action="store_true", help="Write into validation/ subfolder instead of the version root")
    parser.add_argument("--timeout", type=int, default=1800, help="Max seconds to wait for the run to finish")
    parser.add_argument("--set", action="append", metavar="NAME=VALUE", help="Override an EA input for this run (repeatable), e.g. --set BreakoutBufferPips=10")
    parser.add_argument("--out-dir", help="Write config/report here instead of the version folder (e.g. for sweep runs)")
    parser.add_argument("--report-tag", default="", help="Extra tag in the report's bare filename, to keep concurrent/sequential sweep runs from colliding")
    args = parser.parse_args()

    ok = run_backtest(Path(args.version_dir), args)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

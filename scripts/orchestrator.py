"""Run compile -> backtest -> parse for one version folder, stopping on compile errors.

Usage:
    python orchestrator.py strategies/day_trading/<name>/v1 \
        --symbol EURUSD --timeframe H1 \
        --from 2018.01.01 --to 2019.12.31 \
        --deposit 10000 --currency USD [--optimize] [--validation]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from compile_ea import compile_strategy
import parse_report
import run_backtest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version_dir")
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--timeframe", required=True)
    parser.add_argument("--from", dest="date_from", required=True)
    parser.add_argument("--to", dest="date_to", required=True)
    parser.add_argument("--deposit", type=int, default=10000)
    parser.add_argument("--currency", default="USD")
    parser.add_argument("--leverage", type=int, default=100)
    parser.add_argument("--optimize", action="store_true")
    parser.add_argument("--validation", action="store_true")
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--set", action="append", metavar="NAME=VALUE")
    parser.add_argument("--out-dir")
    parser.add_argument("--report-tag", default="")
    args = parser.parse_args()

    version_dir = Path(args.version_dir)

    print("=== Step 1/3: compile ===")
    if not compile_strategy(version_dir):
        print("Compile failed -- stopping before backtest.")
        sys.exit(1)

    print("=== Step 2/3: backtest ===")
    if not run_backtest.run_backtest(version_dir, args):
        print("Backtest did not complete -- stopping before parse.")
        sys.exit(1)

    print("=== Step 3/3: parse ===")
    sys.argv = ["parse_report.py", str(version_dir)]
    if args.validation:
        sys.argv.append("--validation")
    parse_report.main()

    print("Done.")


if __name__ == "__main__":
    main()

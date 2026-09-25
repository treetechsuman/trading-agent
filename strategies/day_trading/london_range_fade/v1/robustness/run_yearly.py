"""Multi-window robustness check for the locked v1 config
(BreakoutBufferPips=10, SL=1, TP=1, MinRangeSizePips=15).

Real tick data for EURUSD.r on this installation doesn't extend before
~2018 (confirmed: 0% real ticks in both a 2015 and a 2017 probe), so there
is no genuinely separate historical window available without eating into
the reserved 2023-2025 out-of-sample range. Instead, this breaks the
already-approved 2018-2022 in-sample period into individual years with the
locked config, to check whether the edge is consistent across years or
carried by one or two good ones -- the out-of-sample range stays untouched.
"""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\london_range_fade\v1")
OUT_ROOT = VERSION_DIR / "robustness"

YEARS = [2018, 2019, 2020, 2021, 2022]

results = []
for year in YEARS:
    tag = f"y{year}"
    out_dir = OUT_ROOT / tag
    print(f"=== {year} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M15",
        "--from", f"{year}.01.01", "--to", f"{year}.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "300",
        "--set", "SLMultiplier=1", "--set", "TPMultiplier=1",
        "--set", "BreakoutBufferPips=10", "--set", "MinRangeSizePips=15",
        "--out-dir", str(out_dir), "--report-tag", tag,
    ], cwd=SCRIPTS)
    if r.returncode != 0:
        print(f"FAILED: {tag}")
        continue
    subprocess.run([sys.executable, str(SCRIPTS / "parse_report.py"), str(out_dir)], cwd=SCRIPTS)

    summary = {}
    with open(out_dir / "summary.csv", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            summary[row["metric"]] = row["value"]
    results.append({
        "year": year,
        "profit_factor": summary.get("Profit Factor"),
        "net_profit": summary.get("Total Net Profit"),
        "max_dd_pct": summary.get("Balance Drawdown Maximal"),
        "total_trades": summary.get("Total Trades"),
        "win_rate": summary.get("Profit Trades (% of total)"),
        "expected_payoff": summary.get("Expected Payoff"),
        "sharpe": summary.get("Sharpe Ratio"),
    })

with open(OUT_ROOT / "yearly_results.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print(f"\nWrote {OUT_ROOT / 'yearly_results.csv'}")

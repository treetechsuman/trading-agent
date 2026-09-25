"""Yearly breakdown for gotobi v1, per pair -- checking whether the edge is
consistent year over year (2017-2022, the in-sample range) or whether one
good year is carrying the aggregate, as the strategy spec itself warned
could happen (it noted 2025 alone carried most of an informal ~9.8%/yr
aggregate result)."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\gotobi\v1")
OUT_ROOT = VERSION_DIR / "robustness"

YEARS = [2017, 2018, 2019, 2020, 2021, 2022]
SYMBOLS = ["USDJPY", "EURJPY.r", "GBPJPY.r"]

results = []
for symbol in SYMBOLS:
    pair_tag = symbol.replace(".", "_")
    for year in YEARS:
        tag = f"{pair_tag}_y{year}"
        out_dir = OUT_ROOT / pair_tag / f"y{year}"
        print(f"=== {symbol} {year} ===")
        r = subprocess.run([
            sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
            "--symbol", symbol, "--timeframe", "M1",
            "--from", f"{year}.01.01", "--to", f"{year}.12.31",
            "--deposit", "10000", "--currency", "USD", "--timeout", "600",
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
            "symbol": symbol,
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

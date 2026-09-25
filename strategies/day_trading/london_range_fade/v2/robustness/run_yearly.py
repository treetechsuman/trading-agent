"""Yearly breakdown for v2 (adds the rolling-average volatility filter on
top of v1's locked buffer=10/minrange=15 config) -- specifically checking
whether 2020 (COVID crash) recovers while 2018 (diffuse, non-event-driven
loss) stays roughly the same, as hypothesized in v1's review."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\london_range_fade\v2")
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

"""Sweep MinSpikeSizePips for wm_fix_reversal v1 -- v1's baseline (15 pips)
produced only 38 trades over 5 years (2018-2022), well below this
project's 200-trade significance bar. Sweeping the threshold down (and up)
to see the trade-count/quality tradeoff before drawing any conclusion."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\wm_fix_reversal\v1")
OUT_ROOT = VERSION_DIR / "sweep"

SPIKE_VALUES = [6, 8, 10, 12, 15, 20]

results = []
for spike in SPIKE_VALUES:
    tag = f"spike{spike}"
    out_dir = OUT_ROOT / tag
    print(f"=== MinSpikeSizePips={spike} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M1",
        "--from", "2018.01.01", "--to", "2022.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "300",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"MinSpikeSizePips={spike}",
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
        "min_spike_pips": spike,
        "total_trades": summary.get("Total Trades"),
        "profit_factor": summary.get("Profit Factor"),
        "net_profit": summary.get("Total Net Profit"),
        "max_dd_pct": summary.get("Balance Drawdown Maximal"),
        "win_rate": summary.get("Profit Trades (% of total)"),
        "expected_payoff": summary.get("Expected Payoff"),
        "sharpe": summary.get("Sharpe Ratio"),
    })

with open(OUT_ROOT / "sweep_results.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print(f"\nWrote {OUT_ROOT / 'sweep_results.csv'}")

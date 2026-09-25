"""Sweep MinSpikeVsAvgMultiplier for wm_fix_reversal v2 -- the 1.5x default
produced 292 trades but diluted the edge to breakeven (PF 1.01, 11.8% max
DD). Sweeping the multiplier up to find where the relative threshold
captures genuine edge without either (a) trading routine noise or (b)
collapsing back to v1's frequency problem."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\wm_fix_reversal\v2")
OUT_ROOT = VERSION_DIR / "sweep"

MULTIPLIER_VALUES = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]

results = []
for mult in MULTIPLIER_VALUES:
    tag = f"mult{str(mult).replace('.', 'p')}"
    out_dir = OUT_ROOT / tag
    print(f"=== MinSpikeVsAvgMultiplier={mult} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M1",
        "--from", "2017.08.01", "--to", "2022.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "300",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"MinSpikeVsAvgMultiplier={mult}",
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
        "multiplier": mult,
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

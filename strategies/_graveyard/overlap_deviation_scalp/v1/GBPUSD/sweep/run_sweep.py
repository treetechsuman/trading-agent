"""Sweep MinDeviationVsAvgMultiplier for overlap_deviation_scalp on
GBPUSD.r -- default (2.0) gave PF 0.88, best of the 4 pairs tested but
still losing. GBPUSD's profile differs from EURUSD's: win rate below 50%
(47.30%) but favorable R:R (avg win $23.60 > avg loss $20.57), unlike
EURUSD's >50% win rate with unfavorable R:R. Testing whether raising
selectivity pushes this over 1.0, same approach that got EURUSD to (a
fragile) PF 1.02 in-sample."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\scalping\overlap_deviation_scalp\v1")
OUT_ROOT = VERSION_DIR / "GBPUSD" / "sweep"

MULTIPLIERS = [2.0, 3.0, 4.0, 5.0, 6.0, 7.0]

results = []
for mult in MULTIPLIERS:
    tag = f"gbp_devmult{str(mult).replace('.', 'p')}"
    out_dir = OUT_ROOT / tag
    print(f"=== GBPUSD MinDeviationVsAvgMultiplier={mult} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "GBPUSD.r", "--timeframe", "M1",
        "--from", "2021.01.01", "--to", "2023.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "600",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"MinDeviationVsAvgMultiplier={mult}",
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
        "dev_mult": mult,
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

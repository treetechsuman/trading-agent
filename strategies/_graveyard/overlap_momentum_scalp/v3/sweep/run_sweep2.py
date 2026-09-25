"""Second sweep for overlap_momentum_scalp v3 -- diagnosed that gross
price P&L is actually positive ($729.60 over 725 trades at SL=1.0/TP=2.0)
but commission (-$1,784.13) more than wipes it out. Testing whether
raising the deviation threshold (fewer, higher-conviction trades) grows
average gross edge per trade faster than it shrinks trade count, which
would make commission a smaller fraction of the edge."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\scalping\overlap_momentum_scalp\v3")
OUT_ROOT = VERSION_DIR / "sweep"

MULTIPLIERS = [2.0, 3.0, 4.0, 5.0, 6.0]

results = []
for mult in MULTIPLIERS:
    tag = f"devmult{str(mult).replace('.', 'p')}"
    out_dir = OUT_ROOT / tag
    print(f"=== MinDeviationVsAvgMultiplier={mult} (SL=1.0, TP=2.0) ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M1",
        "--from", "2021.01.01", "--to", "2023.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "600",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", "SLMultiplier=1.0",
        "--set", "TPMultiplier=2.0",
        "--set", "MinStopPips=5.0",
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

with open(OUT_ROOT / "sweep2_results.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print(f"\nWrote {OUT_ROOT / 'sweep2_results.csv'}")

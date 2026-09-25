"""Sweep MaxHoldMinutes for overlap_deviation_scalp on GBPUSD.r --
diagnosed that 68-73% of trades were hitting the 15-min time exit before
reaching SL or TP, meaning the nominal 1:2 R:R barely applied to actual
outcomes. Testing whether giving trades more room to reach their
deviation-based target naturally improves PF."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\scalping\overlap_deviation_scalp\v1")
OUT_ROOT = VERSION_DIR / "GBPUSD" / "sweep"

HOLD_MINUTES = [15, 30, 45, 60, 90]

results = []
for hold in HOLD_MINUTES:
    tag = f"gbp_hold{hold}"
    out_dir = OUT_ROOT / tag
    print(f"=== GBPUSD MaxHoldMinutes={hold} (dev_mult=4.0) ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "GBPUSD.r", "--timeframe", "M1",
        "--from", "2021.01.01", "--to", "2023.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "600",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"MaxHoldMinutes={hold}",
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
        "max_hold_min": hold,
        "total_trades": summary.get("Total Trades"),
        "profit_factor": summary.get("Profit Factor"),
        "net_profit": summary.get("Total Net Profit"),
        "max_dd_pct": summary.get("Balance Drawdown Maximal"),
        "win_rate": summary.get("Profit Trades (% of total)"),
        "expected_payoff": summary.get("Expected Payoff"),
        "sharpe": summary.get("Sharpe Ratio"),
    })

with open(OUT_ROOT / "sweep_hold_results.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print(f"\nWrote {OUT_ROOT / 'sweep_hold_results.csv'}")

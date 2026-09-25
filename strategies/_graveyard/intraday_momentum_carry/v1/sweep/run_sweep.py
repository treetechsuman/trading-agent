"""Sweep StopLossPips for intraday_momentum_carry v1 -- the pure
literature construction (Gao/Han/Li/Zhou 2018) has no stop-loss at all,
just hold-to-close. This project's own added 20-pip stop is a design
choice, not from the research. Testing whether a much wider stop (or a
near-catastrophic-only stop) changes the picture, since the current
default (PF 0.82) may be an artifact of cutting off trades that would
have recovered by session close."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\intraday_momentum_carry\v1")
OUT_ROOT = VERSION_DIR / "sweep"

STOP_VALUES = [20, 30, 50, 75, 100]

results = []
for stop in STOP_VALUES:
    tag = f"stop{stop}"
    out_dir = OUT_ROOT / tag
    print(f"=== StopLossPips={stop} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M1",
        "--from", "2018.01.01", "--to", "2022.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "600",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"StopLossPips={stop}",
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
        "stop_pips": stop,
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

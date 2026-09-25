"""Sweep MinSweepPips (selectivity) and SwingLookback for
liquidity_sweep_reversal v1 on GBPUSD.r -- default (lookback=12,
sweep=2.0) gave PF 0.90 on 828 trades, close to breakeven with a
favorable win/loss ratio despite sub-50% win rate. Testing whether
requiring a more convincing sweep (bigger clearance past the level)
and/or a longer lookback (more "respected" swing levels) improves
quality without collapsing the sample."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\scalping\liquidity_sweep_reversal\v1")
OUT_ROOT = VERSION_DIR / "sweep"

COMBOS = [
    (12, 2.0),   # default, for reference
    (12, 4.0),
    (12, 6.0),
    (20, 2.0),
    (20, 4.0),
    (20, 6.0),
    (30, 4.0),
    (30, 6.0),
]

results = []
for lookback, sweep in COMBOS:
    tag = f"lb{lookback}_sw{str(sweep).replace('.', 'p')}"
    out_dir = OUT_ROOT / tag
    print(f"=== SwingLookback={lookback} MinSweepPips={sweep} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "GBPUSD.r", "--timeframe", "M5",
        "--from", "2021.01.01", "--to", "2023.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "600",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"SwingLookback={lookback}",
        "--set", f"MinSweepPips={sweep}",
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
        "lookback": lookback,
        "min_sweep_pips": sweep,
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

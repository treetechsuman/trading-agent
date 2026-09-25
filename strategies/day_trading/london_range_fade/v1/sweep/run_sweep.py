"""One-off driver for the v1 sweep -- one-at-a-time sensitivity check around
the baseline (SL=1, TP=1, buffer=3, min_range=15) that produced PF 1.02.
Not part of the reusable scripts/ pipeline -- kept here for reproducibility."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\london_range_fade\v1")
SWEEP_DIR = VERSION_DIR / "sweep"

BASELINE = {"sl": 1, "tp": 1, "buf": 3, "minrange": 15}

# one-at-a-time variations around the baseline (baseline itself already run as v1)
COMBOS = [
    {**BASELINE, "sl": 0.75},
    {**BASELINE, "tp": 0.75},
    {**BASELINE, "sl": 1.5},
    {**BASELINE, "tp": 1.5},
    {**BASELINE, "buf": 5},
    {**BASELINE, "buf": 10},
    {**BASELINE, "minrange": 10},
    {**BASELINE, "minrange": 20},
    {**BASELINE, "minrange": 25},
]

results = []
for c in COMBOS:
    tag = f"sl{c['sl']}_tp{c['tp']}_buf{c['buf']}_mr{c['minrange']}".replace(".", "p")
    out_dir = SWEEP_DIR / tag
    print(f"=== {tag} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M15",
        "--from", "2018.01.01", "--to", "2022.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "300",
        "--set", f"SLMultiplier={c['sl']}",
        "--set", f"TPMultiplier={c['tp']}",
        "--set", f"BreakoutBufferPips={c['buf']}",
        "--set", f"MinRangeSizePips={c['minrange']}",
        "--out-dir", str(out_dir),
        "--report-tag", tag,
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
        "sl_mult": c["sl"], "tp_mult": c["tp"], "buffer_pips": c["buf"], "min_range_pips": c["minrange"],
        "profit_factor": summary.get("Profit Factor"),
        "net_profit": summary.get("Total Net Profit"),
        "max_dd_pct": summary.get("Balance Drawdown Maximal"),
        "total_trades": summary.get("Total Trades"),
        "win_rate_overall": summary.get("Profit Trades (% of total)"),
        "expected_payoff": summary.get("Expected Payoff"),
        "sharpe": summary.get("Sharpe Ratio"),
    })

with open(SWEEP_DIR / "sweep_results.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print(f"\nWrote {SWEEP_DIR / 'sweep_results.csv'}")

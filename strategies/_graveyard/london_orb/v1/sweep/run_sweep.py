"""One-off driver for the v1 parameter sweep (buffer size x SL/TP ratio).
Not part of the reusable scripts/ pipeline -- kept here for reproducibility."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\day_trading\london_orb\v1")
SWEEP_DIR = VERSION_DIR / "sweep"

COMBOS = [
    (buf, sl, tp)
    for buf in (3, 10, 20)
    for (sl, tp) in ((1, 1), (1, 1.5), (1.5, 1), (1, 2))
    if not (buf == 3 and sl == 1 and tp == 2)  # already have this from v1's own run
]

results = []
for buf, sl, tp in COMBOS:
    tag = f"buf{buf}_sl{sl}_tp{tp}".replace(".", "p")
    out_dir = SWEEP_DIR / tag
    print(f"=== {tag} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M15",
        "--from", "2018.01.01", "--to", "2022.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "300",
        "--set", f"BreakoutBufferPips={buf}",
        "--set", f"SLMultiplier={sl}",
        "--set", f"TPMultiplier={tp}",
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
        "buffer_pips": buf, "sl_mult": sl, "tp_mult": tp,
        "profit_factor": summary.get("Profit Factor"),
        "net_profit": summary.get("Total Net Profit"),
        "max_dd_pct": summary.get("Balance Drawdown Maximal"),
        "total_trades": summary.get("Total Trades"),
        "win_rate_long": summary.get("Long Trades (won %)"),
        "win_rate_short": summary.get("Short Trades (won %)"),
        "expected_payoff": summary.get("Expected Payoff"),
        "sharpe": summary.get("Sharpe Ratio"),
    })

with open(SWEEP_DIR / "sweep_results.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print(f"\nWrote {SWEEP_DIR / 'sweep_results.csv'}")

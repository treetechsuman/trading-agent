"""Sweep SL/TP multiplier combinations for overlap_momentum_scalp v3 --
the 55.86% win rate at defaults (SL=1.5, TP=1.0) suggests real signal,
but PF stayed below 1.0 (0.82) because average loss ($17.34) exceeded
average win ($13.98). Testing tighter stops / wider targets to align
the R:R with the win-rate edge, plus the MinStopPips floor which may be
binding often enough to inflate realized losses beyond what the
multiplier alone implies."""
import csv
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(r"D:\ai-projects\trading-agent\scripts")
VERSION_DIR = Path(r"D:\ai-projects\trading-agent\strategies\scalping\overlap_momentum_scalp\v3")
OUT_ROOT = VERSION_DIR / "sweep"

COMBOS = [
    (1.5, 1.0, 5.0),  # current default, for reference
    (1.0, 1.0, 5.0),
    (1.0, 1.5, 5.0),
    (0.75, 1.5, 5.0),
    (1.0, 2.0, 5.0),
    (0.75, 1.0, 3.0),
    (1.0, 1.5, 3.0),
]

results = []
for sl, tp, minstop in COMBOS:
    tag = f"sl{str(sl).replace('.', 'p')}_tp{str(tp).replace('.', 'p')}_min{str(minstop).replace('.', 'p')}"
    out_dir = OUT_ROOT / tag
    print(f"=== SL={sl} TP={tp} MinStopPips={minstop} ===")
    r = subprocess.run([
        sys.executable, str(SCRIPTS / "run_backtest.py"), str(VERSION_DIR),
        "--symbol", "EURUSD.r", "--timeframe", "M1",
        "--from", "2021.01.01", "--to", "2023.12.31",
        "--deposit", "10000", "--currency", "USD", "--timeout", "600",
        "--out-dir", str(out_dir), "--report-tag", tag,
        "--set", f"SLMultiplier={sl}",
        "--set", f"TPMultiplier={tp}",
        "--set", f"MinStopPips={minstop}",
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
        "sl_mult": sl,
        "tp_mult": tp,
        "min_stop_pips": minstop,
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

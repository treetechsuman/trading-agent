"""Parse an MT5 Strategy Tester report.htm into journal.csv + summary.csv.

Usage:
    python parse_report.py strategies/day_trading/<name>/v1 [--validation]

Verified against a real report.htm produced by this installation (FP
Markets MT5 build 5830). Two things about this report format that are easy
to get wrong:

1. The summary section packs up to three label/value pairs per <tr>, so it
   can't be read as a normal key-per-row table -- extract_summary() walks
   each row's <td> cells and matches known metric labels wherever they land.

2. Orders and Deals are two sub-tables stacked as rows inside the SAME
   outer <table> (each introduced by its own <th colspan=13> title row, not
   a new <table>), which breaks a naive pandas.read_html() call. This
   script instead walks the DOM directly: find the <th>Deals</th> marker,
   treat the next row as headers, then read rows until the cell count no
   longer matches.

3. The Deals table has no Position-id column, so entry/exit deals can't be
   paired unambiguously if the EA ever holds multiple concurrent positions.
   pair_deals_into_trades() does simple FIFO pairing of "in"/"out" deals in
   chronological order, which is correct for a strategy that holds at most
   one open position at a time (the common day-trading case) but will
   mis-pair trades for anything that overlaps positions -- if that becomes
   relevant, revisit with the tester's XML report format instead, which
   does carry a position id.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from bs4 import BeautifulSoup


def _num(text: str | None) -> float:
    """Parse an MT5-report number, which uses a space as thousands separator."""
    if not text:
        return 0.0
    try:
        return float(text.replace(" ", "").replace("\xa0", ""))
    except ValueError:
        return 0.0

KNOWN_METRICS = [
    "Total Net Profit", "Balance Drawdown Absolute", "Balance Drawdown Maximal",
    "Balance Drawdown Relative", "Equity Drawdown Absolute", "Equity Drawdown Maximal",
    "Equity Drawdown Relative", "Profit Factor", "Expected Payoff", "Recovery Factor",
    "Sharpe Ratio", "Total Trades", "Total Deals", "Short Trades (won %)", "Long Trades (won %)",
    "Profit Trades (% of total)", "Loss Trades (% of total)", "Largest profit trade",
    "Largest loss trade", "Average profit trade", "Average loss trade",
    "Maximum consecutive wins ($)", "Maximum consecutive losses ($)",
    "Maximal consecutive profit (count)", "Maximal consecutive loss (count)",
    "Average consecutive wins", "Average consecutive losses",
]


def extract_summary(soup: BeautifulSoup) -> dict:
    metrics = {}
    for tr in soup.find_all("tr"):
        cells = [td.get_text(strip=True) for td in tr.find_all("td")]
        i = 0
        while i < len(cells) - 1:
            label = cells[i].rstrip(":").strip()
            if label in KNOWN_METRICS and label not in metrics:
                metrics[label] = cells[i + 1]
                i += 2
                continue
            i += 1
    return metrics


def extract_deals(soup: BeautifulSoup) -> list[dict]:
    """Deals sub-table lives inside a bigger <table>, introduced by a
    <th colspan=13>Deals</th> title row, not its own <table> element."""
    title_cell = None
    for th in soup.find_all("th"):
        if th.get_text(strip=True) == "Deals":
            title_cell = th
            break
    if title_cell is None:
        return []

    title_row = title_cell.find_parent("tr")
    header_row = title_row.find_next_sibling("tr")
    columns = [td.get_text(strip=True) for td in header_row.find_all("td")]
    if not columns:
        return []

    deals = []
    row = header_row.find_next_sibling("tr")
    while row is not None:
        cells = [td.get_text(strip=True) for td in row.find_all("td")]
        if len(cells) != len(columns):
            break  # hit the footer totals row (fewer, merged cells) -- table ends here
        deals.append(dict(zip(columns, cells)))
        row = row.find_next_sibling("tr")
    return deals


def pair_deals_into_trades(deals: list[dict]) -> list[dict]:
    """FIFO-pair 'in' and 'out' deals. Correct only for a strategy that
    holds at most one open position at a time -- see module docstring."""
    trades = []
    open_deals = []
    for d in deals:
        direction = d.get("Direction", "").strip().lower()
        if direction == "in":
            open_deals.append(d)
        elif direction == "out" or direction == "in/out":
            entry = open_deals.pop(0) if open_deals else None
            # MT5 charges commission per leg (often on entry AND exit), and
            # it's a SEPARATE deduction from balance, not folded into the
            # "Profit" field -- true trade P&L is profit + commission + swap
            # summed across both legs, confirmed against the Balance column.
            commission = _num(entry.get("Commission")) + _num(d.get("Commission"))
            swap = _num(entry.get("Swap")) + _num(d.get("Swap"))
            price_pnl = _num(entry.get("Profit")) + _num(d.get("Profit"))
            total_pnl = price_pnl + commission + swap
            trades.append({
                "open_time": entry.get("Time", "") if entry else "",
                "close_time": d.get("Time", ""),
                "side": entry.get("Type", "") if entry else d.get("Type", ""),
                "lots": entry.get("Volume", "") if entry else "",
                "entry_price": entry.get("Price", "") if entry else "",
                "exit_price": d.get("Price", ""),
                "commission": f"{commission:.2f}",
                "swap": f"{swap:.2f}",
                "profit": f"{total_pnl:.2f}",
                "balance_after": d.get("Balance", ""),
            })
        # direction == "" (the initial deposit/balance row) is skipped
    if open_deals:
        print(f"WARNING: {len(open_deals)} 'in' deal(s) never matched with an 'out' -- "
              f"position(s) still open at end of test period.")
    return trades


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version_dir")
    parser.add_argument("--validation", action="store_true")
    args = parser.parse_args()

    base = Path(args.version_dir)
    if args.validation:
        base = base / "validation"
    report_path = base / "report.htm"

    if not report_path.exists():
        print(f"ERROR: {report_path} not found")
        sys.exit(1)

    html = report_path.read_text(encoding="utf-16", errors="ignore")
    if len(html.strip()) == 0:
        html = report_path.read_text(encoding="utf-8", errors="ignore")

    soup = BeautifulSoup(html, "lxml")

    summary = extract_summary(soup)
    print("Summary metrics:")
    for k, v in summary.items():
        print(f"  {k}: {v}")
    if not summary:
        print("WARNING: no known metrics matched -- report layout may have changed.")

    deals = extract_deals(soup)
    trades = pair_deals_into_trades(deals) if deals else []

    journal_path = base / "journal.csv"
    if trades:
        fieldnames = list(trades[0].keys())
        with journal_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(trades)
        print(f"Wrote {len(trades)} trades -> {journal_path}")
    else:
        journal_path.write_text("", encoding="utf-8")
        print(f"No trades parsed. Wrote empty {journal_path} -- treat as a finding, not a silent failure.")

    summary_path = base / "summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["metric", "value"])
        for k, v in summary.items():
            writer.writerow([k, v])
    print(f"Wrote summary -> {summary_path}")


if __name__ == "__main__":
    main()

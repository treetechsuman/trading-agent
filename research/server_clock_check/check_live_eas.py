"""List month_end_fix_reversal and gotobi trading days that fall in US/EU DST
mismatch weeks (US on DST, EU not), and the backtest journal trades on them.

Usage: python check_live_eas.py   (run from repo root)
"""
from __future__ import annotations

import calendar
import csv
from datetime import date, datetime, timedelta
from pathlib import Path

from analyze import is_mismatch, last_sunday, nth_sunday

MEFR = Path("strategies/day_trading/month_end_fix_reversal/v3")
JOURNALS = {
    "EURUSD.r": [MEFR / "journal.csv", MEFR / "validation/journal.csv"],
    "GBPUSD.r": [MEFR / "GBPUSD/journal.csv", MEFR / "GBPUSD/validation/journal.csv"],
    "USDJPY": [MEFR / "USDJPY/journal.csv", MEFR / "USDJPY/validation/journal.csv"],
}


def server_offset_nyplus7(d: date) -> int:
    """UTC offset of a NY+7 server clock (+3 while US DST, else +2)."""
    return 3 if nth_sunday(d.year, 3, 2) <= d < nth_sunday(d.year, 11, 1) else 2


def main():
    print("== month_end_fix_reversal: weekday month-end days (last 3 calendar days) in mismatch weeks ==")
    for y in range(2018, 2028):
        days = []
        for m in (3, 10, 11):
            last = calendar.monthrange(y, m)[1]
            for dd in range(last - 2, last + 1):
                d = date(y, m, dd)
                if d.weekday() < 5 and is_mismatch(d):
                    days.append(d)
        print(f"  {y}: US start {nth_sunday(y,3,2)}, EU start {last_sunday(y,3)}, "
              f"EU end {last_sunday(y,10)}, US end {nth_sunday(y,11,1)} -> {[str(d) for d in days]}")

    print("\n== Backtest journal trades opened on mismatch days ==")
    for sym, files in JOURNALS.items():
        n_all = n_mis = 0
        pnl_mis = 0.0
        for f in files:
            with open(f, newline="") as fh:
                for r in csv.DictReader(fh):
                    t = datetime.strptime(r["open_time"], "%Y.%m.%d %H:%M:%S")
                    n_all += 1
                    if is_mismatch(t.date()):
                        n_mis += 1
                        p = float(r["profit"].replace(" ", ""))
                        pnl_mis += p
                        print(f"  {sym:9s} {r['open_time']}  {r['side']:4s} profit {p:8.2f}  ({f.parent.name}/{f.name})")
        print(f"  {sym}: {n_mis} of {n_all} trades on mismatch days, net {pnl_mis:.2f}")

    print("\n== gotobi: gotobi days where the month rule (03:45 Mar-Oct / 02:45 Nov-Feb) "
          "disagrees with a NY+7 clock (00:45 UTC = 03:45 under US DST, else 02:45) ==")
    for y in range(2017, 2028):
        for m in (3, 10, 11):
            last = calendar.monthrange(y, m)[1]
            for dd in (5, 10, 15, 20, 25, 30):
                if dd > last:
                    continue
                d = date(y, m, dd)
                if d.weekday() >= 5:
                    continue
                coded = 3 if 3 <= m <= 10 else 2
                true_h = server_offset_nyplus7(d)  # 00:45 UTC + offset
                if coded != true_h:
                    print(f"  {d} {d.strftime('%a')}: EA enters {coded:02d}:45 server = "
                          f"{'01:45' if coded > true_h else '23:45 prev-day'} UTC, intended 00:45 UTC")


if __name__ == "__main__":
    main()

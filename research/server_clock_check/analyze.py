"""Analyze server_clock_check probe output (Common\\Files\\server_clock_<year>_<season>.csv).

For each weekday it classifies the date as US/EU DST "mismatch" (US on DST,
EU not) or "normal", then reports per class:
  - where the daily rollover spread spike lands on the server clock
    (hour of the widest per-minute spread between 21:00 and 01:59),
  - the per-minute tick count and bid range around 18:00 vs 19:00 server
    (the London 4pm fix lands at 18:00 under EET, at 19:00 under NY+7
    during mismatch weeks).
Also lists the server time of the first tick after each weekend gap.

Usage: python analyze.py [--files-dir <Common\\Files>]
"""
from __future__ import annotations

import argparse
import csv
import os
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path


def nth_sunday(y, m, n):
    d = date(y, m, 1)
    d += timedelta(days=(6 - d.weekday()) % 7)
    return d + timedelta(weeks=n - 1)


def last_sunday(y, m):
    d = date(y, m + 1, 1) - timedelta(days=1)
    return d - timedelta(days=(d.weekday() - 6) % 7)


def is_mismatch(d: date) -> bool:
    y = d.year
    us_start, eu_start = nth_sunday(y, 3, 2), last_sunday(y, 3)
    eu_end, us_end = last_sunday(y, 10), nth_sunday(y, 11, 1)
    return us_start <= d < eu_start or eu_end <= d < us_end


def load(files_dir: Path):
    rows = []
    for f in sorted(files_dir.glob("server_clock_20*_*.csv")):
        with open(f, newline="") as fh:
            for r in csv.DictReader(fh):
                t = datetime.strptime(r["minute"], "%Y.%m.%d %H:%M")
                rows.append((t, int(r["ticks"]), int(r["spread_max"]),
                             float(r["bid_high"]) - float(r["bid_low"]), r["gap_open"]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files-dir", default=os.path.expandvars(r"%APPDATA%\MetaQuotes\Terminal\Common\Files"))
    args = ap.parse_args()
    rows = load(Path(args.files_dir))

    by_day = defaultdict(dict)
    gaps = []
    for t, ticks, sp, rng, gap in rows:
        by_day[t.date()][(t.hour, t.minute)] = (ticks, sp, rng)
        if gap:
            gaps.append(gap)

    # 1) rollover spike: widest spread in the 21:00-01:59 band, attributed to the
    #    server day it precedes (23:xx belongs to the next day's rollover).
    roll = defaultdict(lambda: defaultdict(int))
    roll_days = {}
    for d, mins in by_day.items():
        cands = []
        for (h, m), (ticks, sp, rng) in mins.items():
            if h >= 21:
                cands.append((sp, h, m, d + timedelta(days=1)))
            elif h <= 1:
                cands.append((sp, h, m, d))
        for sp, h, m, owner in cands:
            prev = roll_days.get(owner)
            if prev is None or sp > prev[0]:
                roll_days[owner] = (sp, h, m)
    for owner, (sp, h, m) in roll_days.items():
        if owner.weekday() >= 5 or owner.weekday() == 0:  # skip Sat/Sun/Mon (weekend open distorts)
            continue
        if owner.month not in (3, 4, 10, 11):
            continue
        roll["mismatch" if is_mismatch(owner) else "normal"][h] += 1

    print("== Rollover spread spike: hour of widest spread (21:00-01:59), Tue-Fri ==")
    for cls in ("normal", "mismatch"):
        print(f"  {cls:9s}", dict(sorted(roll[cls].items())))

    # 2) fix spike: mean ticks / range per minute 17:50-19:10, by class
    acc = defaultdict(lambda: defaultdict(lambda: [0, 0.0, 0]))
    for d, mins in by_day.items():
        if d.weekday() >= 5:
            continue
        cls = "mismatch" if is_mismatch(d) else "normal"
        for (h, m), (ticks, sp, rng) in mins.items():
            if (h == 17 and m >= 50) or h == 18 or (h == 19 and m <= 10):
                a = acc[cls][(h, m)]
                a[0] += ticks
                a[1] += rng
                a[2] += 1

    print("\n== Mean ticks / mean bid range (pips) per server minute ==")
    print("minute   normal(ticks,pips)   mismatch(ticks,pips)")
    keys = sorted(set(acc["normal"]) | set(acc["mismatch"]))
    for k in keys:
        out = []
        for cls in ("normal", "mismatch"):
            a = acc[cls].get(k)
            out.append(f"{a[0]/a[2]:6.1f} {a[1]/a[2]*1e4:5.2f}" if a and a[2] else "   -     -")
        print(f"{k[0]:02d}:{k[1]:02d}    {out[0]}         {out[1]}")

    # 3) per-day: is the 18:00 or 19:00 minute the bigger tick spike?
    print("\n== Per-day: ticks in 17:58-18:02 vs 18:58-19:02, mismatch days only ==")
    wins = defaultdict(lambda: [0, 0])
    for d in sorted(by_day):
        if d.weekday() >= 5:
            continue
        mins = by_day[d]
        a = sum(mins.get((17, m), (0,))[0] for m in (58, 59)) + sum(mins.get((18, m), (0,))[0] for m in (0, 1, 2))
        b = sum(mins.get((18, m), (0,))[0] for m in (58, 59)) + sum(mins.get((19, m), (0,))[0] for m in (0, 1, 2))
        cls = "mismatch" if is_mismatch(d) else "normal"
        wins[cls][0 if a > b else 1] += 1
        if cls == "mismatch":
            print(f"  {d}  18:00 {a:5d}   19:00 {b:5d}   -> {'18' if a > b else '19'}")
    for cls in ("normal", "mismatch"):
        print(f"  {cls}: 18:00 bigger on {wins[cls][0]} days, 19:00 bigger on {wins[cls][1]} days")

    print("\n== First tick after weekend gap (server) ==")
    for g in sorted(set(gaps)):
        print("  ", g, datetime.strptime(g, "%Y.%m.%d %H:%M:%S").strftime("%a"),
              "(mismatch week)" if is_mismatch(datetime.strptime(g[:10], "%Y.%m.%d").date()) else "")


if __name__ == "__main__":
    main()

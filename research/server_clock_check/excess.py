"""Per-year robustness check: fix-spike EXCESS over the local baseline at 18:00 vs 19:00
server (ticks in HH-1:58..HH:02 divided by 5x mean ticks/min over HH-1:40..HH-1:52),
plus rollover-spike hour, for mismatch vs normal weekdays. Run after analyze.py's probes."""
import os
from collections import defaultdict
from pathlib import Path
from analyze import load, is_mismatch

rows = load(Path(os.path.expandvars(r"%APPDATA%\MetaQuotes\Terminal\Common\Files")))
day = defaultdict(dict)
for t, ticks, sp, rng, gap in rows:
    day[t.date()][(t.hour, t.minute)] = (ticks, sp)

def excess(m, h):
    base = [m.get((h - 1, k), (0,))[0] for k in range(40, 53)]
    b = sum(base) / len(base) if base else 0
    spike = sum(m.get((h - 1, k), (0,))[0] for k in (58, 59)) + sum(m.get((h, k), (0,))[0] for k in (0, 1, 2))
    return spike / (5 * b) if b else 0

out = defaultdict(lambda: [0, 0, 0.0, 0.0, 0, 0])
for d, m in sorted(day.items()):
    if d.weekday() >= 5:
        continue
    cls = "mis" if is_mismatch(d) else "nor"
    k = (d.year, "spr" if d.month < 6 else "aut", cls)
    e18, e19 = excess(m, 18), excess(m, 19)
    o = out[k]
    o[0 if e18 > e19 else 1] += 1
    o[2] += e18; o[3] += e19
    # rollover: widest spread among 23:00-23:59 vs 00:00-00:59 of the previous day/this day
    if 1 <= d.weekday() <= 4 and (d - __import__('datetime').timedelta(days=1)) in day:
        p = day[d - __import__('datetime').timedelta(days=1)]
        s23 = max((p.get((23, k), (0, 0))[1] for k in range(60)), default=0)
        s00 = max((m.get((0, k), (0, 0))[1] for k in range(60)), default=0)
        o[4 if s23 > s00 else 5] += 1
print("year season class | fix excess: 18 wins / 19 wins, mean x18, mean x19 | rollover: 23h wins / 00h wins")
for k in sorted(out):
    o = out[k]; n = o[0] + o[1]
    print(f"{k[0]} {k[1]} {k[2]} | {o[0]:2d}/{o[1]:2d}  x18={o[2]/n:4.2f} x19={o[3]/n:4.2f} | {o[4]:2d}/{o[5]:2d}")

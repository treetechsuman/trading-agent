"""Health + trading report for the Linux MT5 server, used by /trading-report.

Runs ON THE SERVER, and needs nothing installed there. From the dev PC the
skill pipes this file in over SSH, so the repo copy is always the one used:

    ssh trader@45.77.236.85 "python3 - --days 7" < server/linux/trading_report.py

Read-only: it reads MT5's log files, the status file written by the
account_reporter EA (chart04), systemd and basic system info. It never
starts, stops or changes anything.

Times are UTC. MT5 deal times (broker server time) are converted using the
offset the account_reporter EA records.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

SERVER_IP = "45.77.236.85"
MT5 = Path.home() / ".mt5/drive_c/Program Files/FP Markets MetaTrader 5"
TERMINAL_LOGS = MT5 / "logs"
EA_LOGS = MT5 / "MQL5/Logs"
STATUS_FILE = MT5 / "MQL5/Files/EAFactory_status.json"
COMMON_INI = MT5 / "Config/common.ini"
MAGICS = {20260030: "gotobi", 20260090: "month_end_fix_reversal"}  # EA magic numbers (same across versions)
STATUS_STALE_SEC = 300
EA_LOG_KEYWORDS = re.compile(
    r"FAILED|fail|error|cut|skip|stop|kill|halt|drawdown|entered|closed|close|limit|retcode|No money",
    re.I,
)

warnings: list[str] = []
WARNINGS_MARK = "@@WARNINGS@@"


def sh(cmd: str, timeout: int = 15) -> str:
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception as e:  # noqa: BLE001 - report must never crash on one probe
        return f"(failed: {e})"


def read_text_any(p: Path) -> str:
    raw = p.read_bytes()
    for enc in ("utf-16", "utf-8", "cp1252"):
        try:
            return raw.decode(enc)
        except UnicodeError:
            continue
    return raw.decode("utf-8", "replace")


def log_lines(folder: Path, since: datetime):
    """Yield (datetime_utc, level, category, message) from MT5 daily logs."""
    if not folder.is_dir():
        return
    for f in sorted(folder.glob("[0-9]" * 8 + ".log")):
        day = datetime.strptime(f.stem, "%Y%m%d").replace(tzinfo=timezone.utc)
        if day.date() < since.date():
            continue
        for line in read_text_any(f).splitlines():
            parts = line.split("\t")
            if len(parts) < 5:
                continue
            _, level, hms, cat, msg = parts[0], parts[1], parts[2], parts[3], "\t".join(parts[4:])
            try:
                h, m, s = hms.split(":")
                ts = day + timedelta(hours=int(h), minutes=int(m), seconds=float(s))
            except ValueError:
                continue
            if ts >= since:
                yield ts, level.strip(), cat.strip(), msg.strip()


def fmt(ts: datetime) -> str:
    return ts.strftime("%a %d %b %H:%M")


def us_dst(d) -> bool:
    """US daylight saving (2nd Sunday of March to 1st Sunday of November), by date.

    FP Markets' server clock is UTC+2, or UTC+3 during US DST (New York close).
    Checked on 2026-11-08: +2.00 h, and month_end's "EU/US DST mismatch" logic relies on this.
    """
    def nth_sunday(year, month, n):
        first = datetime(year, month, 1)
        return first.day + (6 - first.weekday()) % 7 + 7 * (n - 1)
    start = (3, nth_sunday(d.year, 3, 2))
    end = (11, nth_sunday(d.year, 11, 1))
    return start <= (d.month, d.day) < end


def to_utc(server_ts: int, status: dict) -> datetime:
    """Broker server timestamp -> UTC, using the offset in force on THAT date.

    The status file has today's offset only. Older deals from the other DST
    season would otherwise be shown 1 h off.
    """
    now_off = status["server_gmt_offset_sec"]
    base = now_off - (3600 if us_dst(datetime.now(timezone.utc)) else 0)
    day = datetime.fromtimestamp(server_ts, timezone.utc)  # naive server-local date
    return datetime.fromtimestamp(server_ts - base - (3600 if us_dst(day) else 0), timezone.utc)


def section(title: str) -> None:
    print(f"\n== {title} ==")


def ini_value(text: str, section_name: str, key: str) -> str | None:
    m = re.search(rf"(?s)\[{section_name}\]\n(.*?)(?=\n\[|\Z)", text)
    if not m:
        return None
    k = re.search(rf"(?m)^{key}=(.*)$", m.group(1))
    return k.group(1).strip() if k else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7)
    args = ap.parse_args()
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=args.days)
    out_lines: list[str] = []

    # ---------------- MT5 service ----------------
    svc = dict(
        l.split("=", 1)
        for l in sh("systemctl show mt5 -p ActiveState -p SubState -p NRestarts "
                    "-p ActiveEnterTimestamp -p MainPID").splitlines() if "=" in l
    )
    active = svc.get("ActiveState") == "active"
    if not active:
        warnings.append(f"MT5 service is NOT running ({svc.get('ActiveState')}/{svc.get('SubState')})")
    auto_restarts = int(svc.get("NRestarts", "0") or 0)
    if auto_restarts:
        warnings.append(f"systemd auto-restarted MT5 {auto_restarts}x since it was last started by hand (crash recovery)")
    rss = sh("ps -eo rss,args | grep -i 'terminal64' | grep -v grep | awk '{s+=$1} END {print int(s/1024)}'")
    wine_rss = sh("ps -eo rss,args | grep -iE 'wine|\\.exe' | grep -v grep | awk '{s+=$1} END {print int(s/1024)}'")

    common = read_text_any(COMMON_INI).replace("\r\n", "\n") if COMMON_INI.exists() else ""
    algo_ini = ini_value(common, "Experts", "Enabled")

    # ---------------- status file from account_reporter EA ----------------
    status = None
    status_age = None
    if STATUS_FILE.exists():
        try:
            # the EA writes it as ANSI/UTF-8; never try utf-16 here (even-length files "decode" to garbage)
            status = json.loads(STATUS_FILE.read_bytes().decode("utf-8", "replace"))
            status_age = int(time.time() - status["written_gmt"])
        except Exception as e:  # noqa: BLE001
            warnings.append(f"status file unreadable: {e}")
    else:
        warnings.append("no status file yet (account_reporter EA on chart04 not running) - balance/trades unavailable")
    if status_age is not None and status_age > STATUS_STALE_SEC and active:
        warnings.append(f"status file is {status_age // 60} min old - account_reporter EA may have stopped")

    # ---------------- terminal log ----------------
    starts, exits, auths, lost, prev_ips = [], [], [], [], Counter()
    trade_lines, expert_lines, error_lines = [], [], []
    loaded: list[tuple[datetime, str]] = []
    level_counts = Counter()
    for ts, level, cat, msg in log_lines(TERMINAL_LOGS, since):
        if level == "2":
            level_counts[cat] += 1
        if cat == "Terminal" and " started for " in msg:
            starts.append(ts)
        elif cat == "Terminal" and msg.startswith("exit with code"):
            exits.append((ts, msg))
        elif cat == "Network":
            if "authorized on" in msg:
                auths.append((ts, msg))
            if re.search(r"connection to .* lost|disconnect", msg, re.I):
                lost.append(ts)
            m = re.search(r"previous successful authorization performed from (\S+) on", msg)
            if m:
                prev_ips[m.group(1)] += 1
        elif cat == "Trades" and "VPS Hosting" not in msg:
            trade_lines.append((ts, msg))
        elif cat == "Experts":
            m = re.search(r"expert (\S+) \((\S+)\) loaded successfully", msg)
            if m:
                loaded.append((ts, m.group(2)))
            else:
                expert_lines.append((ts, msg))
        if level == "2" and cat not in ("CommunityDispatcher",):
            error_lines.append((ts, cat, msg))

    reboots = [l for l in sh("last -x reboot --time-format iso 2>/dev/null | head -20").splitlines() if l.startswith("reboot")]
    reboots_in_period = []
    for l in reboots:
        m = re.search(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})", l)
        if m and datetime.fromisoformat(m.group(1)).replace(tzinfo=timezone.utc) >= since:
            reboots_in_period.append(m.group(1).replace("T", " "))

    other_ips = {ip: n for ip, n in prev_ips.items() if ip != SERVER_IP}
    # a drop right before an MT5 start is just the restart, not a network problem
    lost = [t for t in lost if not any(timedelta(0) <= s - t <= timedelta(minutes=3) for s in starts)]
    if lost:
        warnings.append(f"{len(lost)} broker connection drop(s) in the last {args.days} days")
    failed_trades = [t for t in trade_lines if re.search(r"failed|reject|no money|invalid", t[1], re.I)]
    if failed_trades:
        warnings.append(f"{len(failed_trades)} failed/rejected trade request(s) - see Trades section")

    # ---------------- EA (MQL5) logs ----------------
    ea_events = [(ts, cat, msg) for ts, _l, cat, msg in log_lines(EA_LOGS, since) if EA_LOG_KEYWORDS.search(msg)]

    # =================== PRINT ===================
    print(f"TRADING REPORT  Linux MT5 server {SERVER_IP}  |  {now:%a %d %b %Y %H:%M} UTC  |  last {args.days} days")

    # Algo state
    algo_live = status.get("algo_trading_button") if status else None
    algo_txt = {True: "ON", False: "OFF", None: "unknown"}[algo_live]
    if algo_live is None and algo_ini is not None:
        algo_txt = "ON" if algo_ini == "1" else "OFF"
    if algo_txt == "OFF":
        warnings.append("Algo Trading is OFF - the EAs will not trade")

    section("WARNINGS")
    print(WARNINGS_MARK)  # filled in at the end, so warnings found later still show at the top

    section("MT5 STATUS")
    print(f"Service: {svc.get('ActiveState')}/{svc.get('SubState')}, running since {svc.get('ActiveEnterTimestamp', '?')}")
    print(f"Algo Trading button: {algo_txt}   (common.ini Enabled={algo_ini})")
    if status:
        print(f"Broker connection: {'connected' if status['terminal_connected'] else 'NOT CONNECTED'}, "
              f"ping {status['ping_ms']} ms, build {status['terminal_build']}")
        a = status["account"]
        print(f"Account {a['login']} on {a['server']}: trading allowed={a['trade_allowed']}, EA trading allowed={a['trade_expert']}")
        print(f"Status file written {status_age}s ago")
    print(f"MT5 memory: terminal {rss} MB, all Wine processes {wine_rss} MB")
    last_start = starts[-1] if starts else since
    now_loaded = [c for ts, c in loaded if ts >= last_start]
    print(f"EAs loaded at the last MT5 start ({fmt(last_start)}): {len(now_loaded)} - {', '.join(now_loaded) or 'none'}"
          "  (expected 4: USDJPY.r gotobi, EURUSD.r + GBPUSD.r month_end, EURUSD.r account_reporter)")
    if active and starts and len(now_loaded) < 4:
        warnings.append(f"only {len(now_loaded)} of 4 EAs loaded at the last MT5 start")

    section("RESTARTS AND UPTIME")
    print(f"MT5 starts in period: {len(starts)}" + (f"  ({', '.join(fmt(s) for s in starts[-12:])})" if starts else ""))
    print(f"systemd crash auto-restarts (since last manual start): {auto_restarts}")
    print(f"Server reboots in period: {len(reboots_in_period)}" + (f"  ({', '.join(reboots_in_period)})" if reboots_in_period else ""))
    print(f"Server up since: {sh('uptime -s')} UTC  ({sh('uptime -p')})")
    print(f"Clean MT5 exits in period: {len(exits)} (starts minus clean exits = crashes/kills/reboots)")

    section("BROKER CONNECTION")
    print(f"Logins: {len(auths)}, connection drops: {len(lost)}" + (f" (last {fmt(lost[-1])})" if lost else ""))
    if auths:
        print(f"Last login: {fmt(auths[-1][0])}  {auths[-1][1][:110]}")
    if other_ips:
        print("Same account also logged in from other IPs (old server / dev PC): "
              + ", ".join(f"{ip} x{n}" for ip, n in other_ips.items()))

    section("ACCOUNT")
    if status:
        a = status["account"]
        print(f"Balance {a['balance']:.2f} {a['currency']} | Equity {a['equity']:.2f} | Margin {a['margin']:.2f} "
              f"| Free margin {a['free_margin']:.2f} | Leverage 1:{a['leverage']}")
    else:
        print("(no status file)")

    section("OPEN POSITIONS")
    if status and status["positions"]:
        for p in status["positions"]:
            opened = to_utc(p["time"], status)
            print(f"  {p['symbol']:9} {p['type']:4} {p['volume']:.2f} @ {p['open_price']}  SL {p['sl']} TP {p['tp']}  "
                  f"P/L {p['profit'] + p['swap']:+.2f}  {MAGICS.get(p['magic'], 'magic ' + str(p['magic']))}  opened {fmt(opened)}")
    else:
        print("  none" if status else "  (no status file)")

    section("TRADES")
    if status:
        st = status
        positions = defaultdict(list)
        cash = []
        for d in status["deals"]:
            if d["type"] in ("buy", "sell"):
                positions[d["position"]].append(d)
            else:
                cash.append(d)
        closed = []
        for pid, deals in positions.items():
            outs = [d for d in deals if d["entry"] in ("out", "inout", "out_by")]
            if not outs:
                continue
            ins = [d for d in deals if d["entry"] == "in"]
            magic = (ins or deals)[0]["magic"]
            net = sum(d["profit"] + d["commission"] + d["swap"] for d in deals)
            close_t = to_utc(max(d["time"] for d in outs), st)
            open_t = to_utc(min(d["time"] for d in deals), st)
            closed.append({"magic": magic, "net": net, "close": close_t, "open": open_t,
                           "symbol": deals[0]["symbol"], "side": (ins or deals)[0]["type"],
                           "volume": (ins or deals)[0]["volume"]})
        closed.sort(key=lambda c: c["close"])

        def summary(rows, label):
            by = defaultdict(list)
            for r in rows:
                by[MAGICS.get(r["magic"], f"magic {r['magic']}" if r["magic"] else "manual")].append(r)
            print(f"{label}: {len(rows)} closed trade(s), net {sum(r['net'] for r in rows):+.2f}")
            for name, rs in sorted(by.items()):
                wins = sum(1 for r in rs if r["net"] > 0)
                print(f"  {name:28} {len(rs):3} trades  {wins} won / {len(rs) - wins} lost  net {sum(r['net'] for r in rs):+.2f}")

        summary([c for c in closed if c["close"] >= since], f"Last {args.days} days")
        summary(closed, "All account history")
        print("Last 10 closed trades:")
        for c in closed[-10:]:
            name = MAGICS.get(c["magic"], f"magic {c['magic']}" if c["magic"] else "manual")
            print(f"  {fmt(c['close'])}  {c['symbol']:9} {c['side']:4} {c['volume']:.2f}  {c['net']:+8.2f}  {name}")
        if not closed:
            print("  none")
        dep = [d for d in cash if d["type"] == "balance"]
        if dep:
            print(f"Deposits/withdrawals: {len(dep)}, total {sum(d['profit'] for d in dep):+.2f} "
                  f"(last {fmt(to_utc(dep[-1]['time'], st))})")
        # Kill-switch reference: equity vs the highest balance since the first EA trade.
        # Walk balance backwards from today's balance so old manual history is ignored.
        deals_sorted = sorted(status["deals"], key=lambda d: d["time"])
        ea_times = [d["time"] for d in deals_sorted if d["magic"] in MAGICS]
        if ea_times:
            bal = status["account"]["balance"]
            peak = bal
            for d in reversed(deals_sorted):
                if d["time"] < ea_times[0]:
                    break
                bal -= d["profit"] + d["commission"] + d["swap"]
                peak = max(peak, bal)
            dd = (peak - status["account"]["equity"]) / peak * 100 if peak > 0 else 0.0
            first = to_utc(ea_times[0], st)
            print(f"Equity vs highest balance since EAs started ({first:%d %b %Y}): {dd:.1f}% below peak {peak:.2f} "
                  "(EA safety stop at 15%)")
            if dd >= 10:
                warnings.append(f"equity {dd:.1f}% below peak balance - near the 15% stop")
    else:
        print("(no status file - trade history unavailable)")
    print(f"Trade requests in MT5 log (last {args.days} days): {len(trade_lines)}, failed/rejected: {len(failed_trades)}")
    for ts, msg in (failed_trades or trade_lines)[-10:]:
        print(f"  {fmt(ts)}  {msg[:140]}")

    section("EA MESSAGES (entries, closes, cuts, stops, errors)")
    for ts, cat, msg in ea_events[-20:]:
        print(f"  {fmt(ts)}  {cat[:28]:28} {msg[:120]}")
    if not ea_events:
        print("  none")
    for ts, msg in expert_lines[-8:]:
        print(f"  {fmt(ts)}  Experts: {msg[:130]}")

    section("MT5 ERRORS (level 2 log lines)")
    for ts, cat, msg in error_lines[-10:]:
        print(f"  {fmt(ts)}  {cat}: {msg[:130]}")
    if not error_lines:
        print("  none")

    section("SERVER HEALTH")
    print(f"Load: {sh('cat /proc/loadavg')}")
    print(sh("free -m | awk 'NR==2{printf \"Memory: %d of %d MB used\", $3, $2} NR==3{printf \", swap %d of %d MB\", $3, $2}'"))
    print(sh("df -h / | awk 'NR==2{print \"Disk: \" $3 \" of \" $2 \" used (\" $5 \")\"}'"))
    print(f"Clock synced: {sh('timedatectl show -p NTPSynchronized --value')}")
    print(f"Remote desktop (VNC): {sh('systemctl is-active tigervncserver@:1')}, fail2ban: {sh('systemctl is-active fail2ban')}")
    rr = Path("/var/run/reboot-required").exists()
    print(f"Reboot needed for updates: {'yes (weekend-reboot timer will do it Sat 06:00 UTC)' if rr else 'no'}")
    print(f"Next weekend reboot check: {sh('systemctl show weekend-reboot.timer -p NextElapseUSecRealtime --value')}")


if __name__ == "__main__":
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        main()
    summary_text = "\n".join(f"- {w}" for w in warnings) if warnings else "- none"
    print(buf.getvalue().replace(WARNINGS_MARK, summary_text), end="")

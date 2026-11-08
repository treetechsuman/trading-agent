"""Write the live chart profile for the Linux MT5 server (run with MT5 CLOSED).

Creates 3 M15 charts in MQL5/Profiles/Charts/Default, each with its EA
attached, and forces the terminal-wide Algo Trading button OFF
([Experts] Enabled=0 in Config/common.ini). The EAs load, show their panels
and wait; nothing trades until someone presses Algo Trading in MT5.

Every input declared in each .mq5 is written explicitly (repo defaults plus
the overrides below), per live-manager/lessons.md: MT5 does not reliably
fall back to compiled defaults.

Usage (on the server, MT5 stopped):
    python3 setup_charts.py ~/trading-agent                  # all charts, Algo OFF
    python3 setup_charts.py ~/trading-agent --reporter-only  # only add/refresh chart04
                                                             # (account_reporter); leaves
                                                             # charts 01-03 and Algo alone
"""
from __future__ import annotations

import re
import shutil
import sys
import time
from pathlib import Path

MT5 = Path.home() / ".mt5/drive_c/Program Files/FP Markets MetaTrader 5"
PROFILE = MT5 / "MQL5/Profiles/Charts/Default"
COMMON_INI = MT5 / "Config/common.ini"

CHARTS = [
    {
        "symbol": "USDJPY.r",
        "src": "strategies/day_trading/gotobi/v2/strategy.mq5",
        "ex5": r"Experts\EAFactory\gotobi\v2\strategy.ex5",
        "overrides": {
            "InpRiskPercent": "2.0",
            "MagicNumber": "20260030",
            "InpAllowLiveAccount": "true",
            "InpValidatedSymbols": "USDJPY,USDJPY.r,EURJPY.r,GBPJPY.r",
        },
    },
    {
        "symbol": "EURUSD.r",
        "src": "strategies/day_trading/month_end_fix_reversal/v5/strategy.mq5",
        "ex5": r"Experts\EAFactory\month_end_fix_reversal\v5\strategy.ex5",
        "overrides": {
            "RiskPercent": "1.0",
            "MagicNumber": "20260090",
            "InpAllowLiveAccount": "true",
            "InpDstMismatchShift": "true",
            "InpValidatedSymbols": "EURUSD.r,GBPUSD.r,USDJPY",
        },
    },
    {
        "symbol": "GBPUSD.r",
        "src": "strategies/day_trading/month_end_fix_reversal/v5/strategy.mq5",
        "ex5": r"Experts\EAFactory\month_end_fix_reversal\v5\strategy.ex5",
        "overrides": {
            "RiskPercent": "1.0",
            "MagicNumber": "20260090",
            "InpAllowLiveAccount": "true",
            "InpDstMismatchShift": "true",
            "InpValidatedSymbols": "EURUSD.r,GBPUSD.r,USDJPY",
        },
    },
]

# Read-only status writer for /trading-report (never trades). Kept last so the
# trading charts keep their chart01-03 numbers.
REPORTER = {
    "symbol": "EURUSD.r",
    "src": "server/linux/account_reporter/v1/strategy.mq5",
    "ex5": r"Experts\EAFactory\account_reporter\v1\strategy.ex5",
    "overrides": {},
}

INPUT_RE = re.compile(
    r"^\s*input\s+[A-Za-z_][A-Za-z0-9_]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+?)\s*;",
    re.MULTILINE,
)


def inputs_for(src: Path, overrides: dict[str, str]) -> list[tuple[str, str]]:
    out = []
    for name, value in INPUT_RE.findall(src.read_text(encoding="utf-8", errors="replace")):
        value = value.strip().strip('"')
        out.append((name, overrides.get(name, value)))
    missing = set(overrides) - {n for n, _ in out}
    if missing:
        raise SystemExit(f"{src}: overrides for unknown inputs {missing}")
    return out


def read_utf16(p: Path) -> str:
    return p.read_bytes().decode("utf-16")  # handles the BOM


def write_utf16(p: Path, text: str) -> None:
    text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    p.write_bytes(b"\xff\xfe" + text.encode("utf-16-le"))


def build_chart(template: str, idx: int, chart: dict, repo: Path) -> str:
    t = template.replace("\r\n", "\n")
    t = re.sub(r"(?s)<expert>.*?</expert>\n", "", t)  # drop any old EA
    t = re.sub(r"(?m)^id=\d+$", f"id={int(time.time() * 1000) * 10 + idx}", t, count=1)
    t = re.sub(r"(?m)^symbol=.*$", f"symbol={chart['symbol']}", t, count=1)
    t = re.sub(r"(?m)^description=.*$", "description=", t, count=1)
    t = re.sub(r"(?m)^period_type=.*$", "period_type=0", t, count=1)  # minutes
    t = re.sub(r"(?m)^period_size=.*$", "period_size=15", t, count=1)  # M15
    lines = ["<expert>", "name=strategy", f"path={chart['ex5']}", "expertmode=33", "<inputs>"]
    lines += [f"{n}={v}" for n, v in inputs_for(repo / chart["src"], chart["overrides"])]
    lines += ["</inputs>", "</expert>", ""]
    pos = t.index("<window>")
    return t[:pos] + "\n".join(lines) + t[pos:]


def force_algo_trading_off() -> None:
    text = read_utf16(COMMON_INI).replace("\r\n", "\n")
    block = "[Experts]\nAllowDllImport=0\nEnabled=0\nAccount=0\nProfile=0\nChart=0\nApi=0\nWebRequest=0\n"
    if "[Experts]" in text:
        text = re.sub(r"(?s)\[Experts\]\n.*?(?=\n\[|\Z)", block.rstrip("\n"), text)
    else:
        text = text.rstrip("\n") + "\n" + block
    write_utf16(COMMON_INI, text)


def find_template() -> str:
    """First intact chart file (has a <window> block) in Default, then in backups.

    A chart file can be left 0 bytes if MT5 is killed while saving its profile
    (seen 2026-11-08), so never trust chart01.chr blindly.
    """
    dirs = [PROFILE] + sorted(PROFILE.parent.glob("Default-backup-*"), reverse=True)
    for d in dirs:
        for f in sorted(d.glob("chart*.chr")):
            try:
                text = read_utf16(f)
            except (UnicodeError, OSError):
                continue
            if "<window>" in text:
                return text
    raise SystemExit("no intact chart*.chr found to use as a template")


def main() -> None:
    repo = Path(sys.argv[1]).expanduser()
    stamp = time.strftime("%Y%m%d-%H%M%S")
    shutil.copytree(PROFILE, PROFILE.parent / f"Default-backup-{stamp}")
    shutil.copy2(COMMON_INI, COMMON_INI.with_name(f"common.ini.bak-{stamp}"))
    template = find_template()
    n = len(CHARTS) + 1
    if "--reporter-only" in sys.argv:
        write_utf16(PROFILE / f"chart{n:02d}.chr", build_chart(template, n, REPORTER, repo))
        print(f"chart{n:02d}.chr  {REPORTER['symbol']} M15  {REPORTER['ex5']} (charts 01-03 and Algo untouched)")
        return
    for old in PROFILE.glob("chart*.chr"):
        old.unlink()
    for i, chart in enumerate(CHARTS, start=1):
        write_utf16(PROFILE / f"chart{i:02d}.chr", build_chart(template, i, chart, repo))
        print(f"chart{i:02d}.chr  {chart['symbol']} M15  {chart['ex5']}")
    write_utf16(PROFILE / f"chart{n:02d}.chr", build_chart(template, n, REPORTER, repo))
    print(f"chart{n:02d}.chr  {REPORTER['symbol']} M15  {REPORTER['ex5']} (read-only reporter)")
    force_algo_trading_off()
    print("Algo Trading forced OFF ([Experts] Enabled=0). Backup:", f"Default-backup-{stamp}")


if __name__ == "__main__":
    main()

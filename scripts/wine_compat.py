"""Run the MT5 Windows executables on Linux under Wine (no-op on Windows).

On the Linux live server MT5 runs under Wine (see LINUX_SERVER.md), so
`MetaEditor64.exe` / `terminal64.exe` must be started as `wine <exe>` and
every path handed to them on the command line must be a Windows path
(`C:\\...` or `Z:\\...`). On Windows both helpers return their input
unchanged, so the scripts behave exactly as before.

Environment (Linux only, with defaults):
    WINEPREFIX  ~/.mt5   (where MetaQuotes' mt5linux.sh puts MT5)
    DISPLAY     :1       (the VNC desktop MT5 runs on)
    WINEDEBUG   -all     (silence Wine's debug spam)
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

IS_WINE = os.name != "nt"

if IS_WINE:
    os.environ.setdefault("WINEPREFIX", str(Path.home() / ".mt5"))
    os.environ.setdefault("DISPLAY", ":1")
    os.environ.setdefault("WINEDEBUG", "-all")


def windows_path(path: Path | str) -> str:
    """Return `path` as MT5 should see it (Windows form under Wine)."""
    if not IS_WINE:
        return str(path)
    out = subprocess.run(
        ["winepath", "-w", str(path)], capture_output=True, text=True, timeout=60
    )
    converted = out.stdout.strip()
    if out.returncode != 0 or not converted:
        raise RuntimeError(f"winepath failed for {path}: {out.stderr.strip()}")
    return converted


def wrap_cmd(cmd: list[str]) -> list[str]:
    """Prefix a Windows-executable command with `wine` on Linux."""
    return ["wine", *cmd] if IS_WINE else cmd

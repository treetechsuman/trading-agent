"""Compile strategy.mq5 for a given version folder using MetaEditor CLI.

Usage:
    python compile_ea.py strategies/day_trading/<name>/v1

Copies strategy.mq5 into the terminal's own MQL5\\Experts\\EAFactory tree
(required for #include resolution), compiles it there with MetaEditor64.exe,
then copies the resulting compile.log (and, on success, notes the .ex5
location) back next to the source file.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

from common import METAEDITOR_EXE, data_expert_dir, run, version_dir_parts


def compile_strategy(version_dir: Path) -> bool:
    version_dir = version_dir.resolve()
    source = version_dir / "strategy.mq5"
    if not source.exists():
        print(f"ERROR: {source} does not exist")
        return False

    strategy_name, version = version_dir_parts(version_dir)
    dest_dir = data_expert_dir(strategy_name, version)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_source = dest_dir / "strategy.mq5"
    shutil.copy2(source, dest_source)

    log_path = dest_dir / "compile.log"
    if log_path.exists():
        log_path.unlink()

    cmd = [
        str(METAEDITOR_EXE),
        f"/compile:{dest_source}",
        f"/log:{log_path}",
    ]
    print(f"Running: {' '.join(cmd)}")
    proc = run(cmd, timeout=180)

    # MetaEditor writes the log file itself; stdout/stderr are usually empty.
    log_text = ""
    if log_path.exists():
        # MetaEditor logs are typically UTF-16LE with a BOM.
        for enc in ("utf-16", "utf-8", "utf-8-sig", "cp1252"):
            try:
                log_text = log_path.read_text(encoding=enc)
                break
            except (UnicodeError, UnicodeDecodeError):
                continue

    dest_log_copy = version_dir / "compile.log"
    dest_log_copy.write_text(log_text, encoding="utf-8")

    print(log_text)
    if proc.stdout:
        print("stdout:", proc.stdout)
    if proc.stderr:
        print("stderr:", proc.stderr)

    ex5 = dest_dir / "strategy.ex5"
    # MetaEditor's summary line looks like: "Result: 0 errors, 2 warnings, ..."
    success = ex5.exists()
    for line in log_text.splitlines():
        low = line.lower()
        if "result:" in low:
            print(f"Compile summary: {line.strip()}")
            if "0 error" not in low:
                success = False

    if success and ex5.exists():
        print(f"Compiled OK -> {ex5}")
        return True

    print("Compile FAILED. See compile.log above.")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version_dir", help="Path to the version folder, e.g. strategies/day_trading/foo/v1")
    args = parser.parse_args()

    ok = compile_strategy(Path(args.version_dir))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

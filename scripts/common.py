"""Shared paths/helpers for the EA factory scripts."""
from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path

TERMINAL_EXE = Path(r"C:\Program Files\FP Markets MetaTrader 5\terminal64.exe")
METAEDITOR_EXE = Path(r"C:\Program Files\FP Markets MetaTrader 5\MetaEditor64.exe")
MT5_DATA_DIR = Path(
    r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\ED480984639B96B48C6EBB5DA707E011"
)

try:
    from local_settings import ACCOUNT_LOGIN
except ImportError as exc:
    raise ImportError(
        "scripts/local_settings.py is missing -- copy scripts/local_settings.example.py "
        "to scripts/local_settings.py and fill in your real MT5 account login. "
        "This file is gitignored so the real account number never ends up in the repo."
    ) from exc

# Root under the terminal's own MQL5 tree where this project's EAs are compiled.
# Kept separate from the account's other (unrelated) EAs already in Experts/.
FACTORY_ROOT_NAME = "EAFactory"


def version_dir_parts(version_dir: Path) -> tuple[str, str]:
    """Given .../strategies/day_trading/<name>/v1, return (name, version)."""
    version_dir = version_dir.resolve()
    version = version_dir.name
    strategy_name = version_dir.parent.name
    return strategy_name, version


def data_expert_dir(strategy_name: str, version: str) -> Path:
    return MT5_DATA_DIR / "MQL5" / "Experts" / FACTORY_ROOT_NAME / strategy_name / version


def expert_relative_path(strategy_name: str, version: str) -> str:
    """Path to pass as Expert= in tester config (relative to MQL5\\Experts, no extension)."""
    return f"{FACTORY_ROOT_NAME}\\{strategy_name}\\{version}\\strategy"


def run(cmd: list[str], timeout: int = 600) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def wait_for_file(path: Path, timeout: int = 300, poll: float = 1.0) -> bool:
    start = time.time()
    while time.time() - start < timeout:
        if path.exists():
            return True
        time.sleep(poll)
    return path.exists()


_INPUT_RE = re.compile(
    r"^\s*input\s+[A-Za-z_][A-Za-z0-9_]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+?)\s*;",
    re.MULTILINE,
)


def parse_input_defaults(mq5_path: Path) -> dict[str, str]:
    """Extract every `input <type> Name = value;` declaration's coded default.

    IMPORTANT: found by testing on this installation -- when a tester config
    has no [TesterInputs] section at all, MT5 does NOT reliably fall back to
    the compiled EA's own default values. It silently reuses whatever value
    was last used *for a parameter of that name*, cached across different
    EAs/versions that happen to share input names (which all of ours do,
    since they're copied from one version to the next). Two EAs compiled to
    the same "strategy.ex5" filename in different folders are NOT isolated
    from each other's cached inputs.

    The only reliable fix is to never omit [TesterInputs]: always write
    every declared input explicitly, sourced from the .mq5 file itself so
    it can't drift from what's actually coded.
    """
    text = mq5_path.read_text(encoding="utf-8", errors="ignore")
    return {name: value.strip() for name, value in _INPUT_RE.findall(text)}

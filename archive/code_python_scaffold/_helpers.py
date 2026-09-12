"""Shared paths & helpers for the Python port (code/python/).

Mirrors the R pipeline's root-relative paths under the new data/code/results layout.
"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # repo root
DATA_OLD = ROOT / "data" / "old"                    # Stefan's raw data
DATA_NEW = ROOT / "data" / "new"                    # new per-year raw data
OUTPUTS = ROOT / "results" / "outputs"              # per-step, per-year products
INTERMEDIATE = ROOT / "results" / "intermediate"    # FABIO MRIO products
RESULTS = ROOT / "results"                          # final figures/tables


def parse_year(default: int = 2013) -> int:
    """YEAR from argv[1] (default 2013); enforce the 2000-2022 range."""
    try:
        y = int(sys.argv[1])
    except (IndexError, ValueError):
        y = default
    if not (2000 <= y <= 2022):
        raise SystemExit(f"YEAR {y} out of range 2000-2022")
    return y


def out_dir(step: str, year: int) -> Path:
    """results/outputs/<step>_<year>/, created if needed."""
    d = OUTPUTS / f"{step}_{year}"
    d.mkdir(parents=True, exist_ok=True)
    return d

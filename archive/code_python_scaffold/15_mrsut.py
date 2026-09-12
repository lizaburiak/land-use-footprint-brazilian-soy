"""Step 15 — Multi-regional supply/use tables   [PYTHON PORT]

R reference : code/new/15_mrsut.R
Purpose     : Assemble the multi-regional supply/use tables.

Inputs      : results/intermediate/FABIO/*
Outputs     : results/intermediate/FABIO/mr_*
Port status : BLOCKED — needs FABIO data.

Usage       : python code/python/15_mrsut.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/15_mrsut.R
    raise NotImplementedError(
        "Step 15 (Multi-regional supply/use tables) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/15_mrsut.R\n"
        "  Status: BLOCKED — needs FABIO data."
    )


if __name__ == "__main__":
    main(H.parse_year())

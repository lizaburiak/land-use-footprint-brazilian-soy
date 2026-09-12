"""Step 14 — FABIO use table   [PYTHON PORT]

R reference : code/new/14_use.R
Purpose     : Build the FABIO use table.

Inputs      : FABIO inst/tidy data
Outputs     : results/intermediate/FABIO/use*
Port status : BLOCKED — needs FABIO data.

Usage       : python code/python/14_use.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/14_use.R
    raise NotImplementedError(
        "Step 14 (FABIO use table) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/14_use.R\n"
        "  Status: BLOCKED — needs FABIO data."
    )


if __name__ == "__main__":
    main(H.parse_year())

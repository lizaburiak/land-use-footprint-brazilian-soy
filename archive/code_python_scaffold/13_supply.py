"""Step 13 — FABIO supply table   [PYTHON PORT]

R reference : code/new/13_supply.R
Purpose     : Build the FABIO supply table (nest subnational flows into FABIO).

Inputs      : FABIO inst/tidy data (data/old/FABIO/*)
Outputs     : results/intermediate/FABIO/sup*
Port status : BLOCKED — needs WU/fineprint FABIO data (absent, see WHAT_IS_MISSING.md §4).

Usage       : python code/python/13_supply.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/13_supply.R
    raise NotImplementedError(
        "Step 13 (FABIO supply table) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/13_supply.R\n"
        "  Status: BLOCKED — needs WU/fineprint FABIO data (absent, see WHAT_IS_MISSING.md §4)."
    )


if __name__ == "__main__":
    main(H.parse_year())

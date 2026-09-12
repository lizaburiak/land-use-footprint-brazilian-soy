"""Step 16 — Multi-regional input-output table   [PYTHON PORT]

R reference : code/new/16_mrio.R
Purpose     : Build the MRIO (Z, Y) from the MR-SUT.

Inputs      : results/intermediate/FABIO/mr_*
Outputs     : results/intermediate/FABIO/{Z,Y}_*
Port status : BLOCKED — needs FABIO + EXIOBASE data.

Usage       : python code/python/16_mrio.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/16_mrio.R
    raise NotImplementedError(
        "Step 16 (Multi-regional input-output table) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/16_mrio.R\n"
        "  Status: BLOCKED — needs FABIO + EXIOBASE data."
    )


if __name__ == "__main__":
    main(H.parse_year())

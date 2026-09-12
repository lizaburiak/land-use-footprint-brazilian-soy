"""Step 19 — Invert the hybridized B   [PYTHON PORT]

R reference : code/new/19_invert_B.R
Purpose     : Invert the hybridized B matrix.

Inputs      : results/intermediate/FABIO/*; /mnt/nfs_fineprint/exiobase
Outputs     : results/intermediate/FABIO/{Y}_B_inv_*
Port status : BLOCKED — needs FABIO + EXIOBASE.

Usage       : python code/python/19_invert_B.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/19_invert_B.R
    raise NotImplementedError(
        "Step 19 (Invert the hybridized B) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/19_invert_B.R\n"
        "  Status: BLOCKED — needs FABIO + EXIOBASE."
    )


if __name__ == "__main__":
    main(H.parse_year())

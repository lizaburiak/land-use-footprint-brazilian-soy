"""Step 17 — Leontief inverse   [PYTHON PORT]

R reference : code/new/17_leontief_inverse.R
Purpose     : Compute the Leontief inverse L = (I-A)^-1.

Inputs      : results/intermediate/FABIO/*
Outputs     : results/intermediate/FABIO/{Y}_L_*
Port status : BLOCKED — needs FABIO data (numpy/scipy sparse once available).

Usage       : python code/python/17_leontief_inverse.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/17_leontief_inverse.R
    raise NotImplementedError(
        "Step 17 (Leontief inverse) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/17_leontief_inverse.R\n"
        "  Status: BLOCKED — needs FABIO data (numpy/scipy sparse once available)."
    )


if __name__ == "__main__":
    main(H.parse_year())

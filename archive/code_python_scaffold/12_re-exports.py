"""Step 12 — Re-exports adjustment   [PYTHON PORT]

R reference : code/new/12_re-exports.R
Purpose     : Adjust importer flows for re-exports using FABIO bilateral trade.

Inputs      : results/outputs/*; data/new/04/FABIO/FABIO_exp
Outputs     : results/outputs/12_{Y}/ (reex, btd_final, cbs_full)
Port status : TODO — medium. Empty for YEAR>=2014 (FABIO_exp ends 2013).

Usage       : python code/python/12_re-exports.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/12_re-exports.R
    raise NotImplementedError(
        "Step 12 (Re-exports adjustment) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/12_re-exports.R\n"
        "  Status: TODO — medium. Empty for YEAR>=2014 (FABIO_exp ends 2013)."
    )


if __name__ == "__main__":
    main(H.parse_year())

"""Step 18 — Hybridize the B quadrant (FABIO-EXIOBASE)   [PYTHON PORT]

R reference : code/new/18_hybridize_B_quadrant.R
Purpose     : Hybridize FABIO with EXIOBASE in the B quadrant.

Inputs      : data/old/FABIO/FABIO_hybrid/*; /mnt/nfs_fineprint/exiobase
Outputs     : results/intermediate/FABIO/*hybrid*
Port status : BLOCKED — needs FABIO_hybrid + EXIOBASE (NFS).

Usage       : python code/python/18_hybridize_B_quadrant.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/18_hybridize_B_quadrant.R
    raise NotImplementedError(
        "Step 18 (Hybridize the B quadrant (FABIO-EXIOBASE)) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/18_hybridize_B_quadrant.R\n"
        "  Status: BLOCKED — needs FABIO_hybrid + EXIOBASE (NFS)."
    )


if __name__ == "__main__":
    main(H.parse_year())

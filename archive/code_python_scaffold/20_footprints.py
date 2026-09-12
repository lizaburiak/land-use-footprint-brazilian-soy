"""Step 20 — Land-use footprints   [PYTHON PORT]

R reference : code/new/20_footrpints.R
Purpose     : Compute municipal land-use footprints from the MRIO + FABIO extensions.

Inputs      : results/intermediate/FABIO/{Y}_{L,B_inv}_*; /mnt/nfs_fineprint/fabio
Outputs     : results/footprints/*
Port status : BLOCKED — needs FABIO MRIO + EXIOBASE (NFS).

Usage       : python code/python/20_footprints.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/20_footrpints.R
    raise NotImplementedError(
        "Step 20 (Land-use footprints) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/20_footrpints.R\n"
        "  Status: BLOCKED — needs FABIO MRIO + EXIOBASE (NFS)."
    )


if __name__ == "__main__":
    main(H.parse_year())

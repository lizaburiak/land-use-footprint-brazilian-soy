"""Step 09 — Sensitivity analysis   [PYTHON PORT]

R reference : code/new/09_sensitivity.R
Purpose     : Assess sensitivity of origin→importer flows to bootstrap cost parameters.

Inputs      : results/outputs/08_{Y}/*
Outputs     : results/figures/* sensitivity plots
Port status : TODO — medium (pandas + matplotlib).

Usage       : python code/python/09_sensitivity.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/09_sensitivity.R
    raise NotImplementedError(
        "Step 09 (Sensitivity analysis) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/09_sensitivity.R\n"
        "  Status: TODO — medium (pandas + matplotlib)."
    )


if __name__ == "__main__":
    main(H.parse_year())

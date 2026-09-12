"""Step 11 — Analyse benchmarks (correlations + maps)   [PYTHON PORT]

R reference : code/new/11_analyse_benchmarks.R
Purpose     : Compute model-vs-Trase correlations and render benchmark maps/figures/tables.

Inputs      : results/outputs/10_{Y}; data/old/geo/GADM_boundaries
Outputs     : results/{maps,figures,tables}/{Y}/*
Port status : TODO — spatial/medium (geopandas + matplotlib). Mirror the 9300000 placeholder drop.

Usage       : python code/python/11_analyse_benchmarks.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/11_analyse_benchmarks.R
    raise NotImplementedError(
        "Step 11 (Analyse benchmarks (correlations + maps)) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/11_analyse_benchmarks.R\n"
        "  Status: TODO — spatial/medium (geopandas + matplotlib). Mirror the 9300000 placeholder drop."
    )


if __name__ == "__main__":
    main(H.parse_year())

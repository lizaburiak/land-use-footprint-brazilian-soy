"""Step 10 — Create Trase benchmarks   [PYTHON PORT]

R reference : code/new/10_create_benchmarks.R
Purpose     : Build the model-vs-Trase comparison table (v2.6.1 composite).

Inputs      : results/outputs/08_{Y}; data/old/brazil_soy_v2_6_1_composite.csv
Outputs     : results/outputs/10_{Y}/comp_list
Port status : TODO — medium. Mirror the no-Trase-data skip for <2004.

Usage       : python code/python/10_create_benchmarks.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/10_create_benchmarks.R
    raise NotImplementedError(
        "Step 10 (Create Trase benchmarks) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/10_create_benchmarks.R\n"
        "  Status: TODO — medium. Mirror the no-Trase-data skip for <2004."
    )


if __name__ == "__main__":
    main(H.parse_year())

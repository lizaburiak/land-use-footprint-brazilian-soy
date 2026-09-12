"""Step 21 — Probability maps (grid refinement)   [PYTHON PORT]

R reference : code/new/21_probability_maps.R
Purpose     : Refine municipal footprints to the 30m grid using MapBiomas soy tiles.

Inputs      : results/footprints/*; MapBiomas tiles
Outputs     : results/footprints/prob_map_*
Port status : BLOCKED — needs FABIO footprints (step 20) + MapBiomas tiles.

Usage       : python code/python/21_probability_maps.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/21_probability_maps.R
    raise NotImplementedError(
        "Step 21 (Probability maps (grid refinement)) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/21_probability_maps.R\n"
        "  Status: BLOCKED — needs FABIO footprints (step 20) + MapBiomas tiles."
    )


if __name__ == "__main__":
    main(H.parse_year())

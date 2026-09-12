"""Step 00 — Data preparation — build the municipal soy dataset   [PYTHON PORT]

R reference : code/new/00_data_preparation/00_data_preparation.R
Purpose     : Combine ~15 raw sources into one municipality-level dataset (production, trade, processing, livestock, population, food, biodiesel) + spatial layers and distance matrices.

Inputs      : data/new/00/new/* (IBGE, COMEX, ABIOVE, FAO CBS, ANP); data/old/geo/*
Outputs     : results/outputs/00_{Y}/ (SOY_MUN_00, GEO_MUN_SOY_00, CBS_SOY, MUN_capital_dist, MUN_capitals, ...)
Port status : TODO — hardest step. Spatial-heavy: port with geopandas (sf), pandas, rasterio. Sheet-era ABIOVE logic + per-year dispatch.

Usage       : python code/python/00_data_preparation.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/00_data_preparation/00_data_preparation.R
    raise NotImplementedError(
        "Step 00 (Data preparation — build the municipal soy dataset) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/00_data_preparation/00_data_preparation.R\n"
        "  Status: TODO — hardest step. Spatial-heavy: port with geopandas (sf), pandas, rasterio. Sheet-era ABIOVE logic + per-year dispatch."
    )


if __name__ == "__main__":
    main(H.parse_year())

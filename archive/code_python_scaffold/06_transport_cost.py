"""Step 06 — Transport-cost network (road/rail/water)   [PYTHON PORT]

R reference : code/new/06_transport_cost.R
Purpose     : Build the multimodal transport network — road/rail/water distance matrices, hub locations, route capacities.

Inputs      : data/old/geo/* (OSM, DNIT, ANTAQ, ANTT); data/new/00/new/IBGE_storage
Outputs     : results/outputs/06_{Y}/ (stations, ports, cargo_long, dist_matrices)
Port status : TODO — SPATIAL-HEAVY + BLOCKED: also needs the missing geo files (ip_add.gpkg, RailCargo, train_stations_soy.gpkg — see WHAT_IS_MISSING.md). Port with geopandas + networkx/scikit-image cost-distance.

Usage       : python code/python/06_transport_cost.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/06_transport_cost.R
    raise NotImplementedError(
        "Step 06 (Transport-cost network (road/rail/water)) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/06_transport_cost.R\n"
        "  Status: TODO — SPATIAL-HEAVY + BLOCKED: also needs the missing geo files (ip_add.gpkg, RailCargo, train_stations_soy.gpkg — see WHAT_IS_MISSING.md). Port with geopandas + networkx/scikit-image cost-distance."
    )


if __name__ == "__main__":
    main(H.parse_year())

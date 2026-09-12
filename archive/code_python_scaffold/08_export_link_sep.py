"""Step 08 — Link flows to importers (separate)   [PYTHON PORT]

R reference : code/new/08_export_link_sep.R
Purpose     : Per-iteration origin→importer linking (separate bootstrap version).

Inputs      : results/outputs/{07,05}_{Y}
Outputs     : results/outputs/08_{Y}/source_to_export_list
Port status : TODO — tabular/medium.

Usage       : python code/python/08_export_link_sep.py [YEAR]   (default 2013, range 2000-2022)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    # TODO: port the logic from code/new/08_export_link_sep.R
    raise NotImplementedError(
        "Step 08 (Link flows to importers (separate)) is scaffolded but not yet ported to Python.\n"
        "  Reference R: code/new/08_export_link_sep.R\n"
        "  Status: TODO — tabular/medium."
    )


if __name__ == "__main__":
    main(H.parse_year())

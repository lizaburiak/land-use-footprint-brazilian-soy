#!/usr/bin/env python3
"""SOYPRINT results database - entity-relationship diagram (ERD).

Introspects data/db/soyprint.duckdb (table and column lists, types, row
counts) and renders a crow's-foot ERD with Graphviz, in the style of
pgModeler figures in Scientific Data papers: one box per table with
columns (name | type | constraint), colored by pipeline stage, edges
from foreign-key columns to the referenced primary key.

Key relationships are declared in FKS below (the .duckdb is built with
CREATE TABLE AS, so no FK constraints exist in the catalog itself).

Usage:
    .venv/bin/python code/db/make_erd.py
    -> paper/main/figures/fig_db_schema.pdf (+ .dot source alongside)

    .venv/bin/python code/db/make_erd.py --simple
    -> paper/main/figures/fig_db_schema_simple.pdf - compact version:
       column names only (primary keys in bold), one connector per table
       pair, no type/constraint columns and no metadata tables.
"""

import subprocess
import sys
from pathlib import Path

import duckdb

SIMPLE = "--simple" in sys.argv

INPUTS_MODE = "--inputs" in sys.argv

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "data/db/soyprint.duckdb"
STEM = ("fig_db_inputs_schema" if INPUTS_MODE else
        "fig_db_schema_simple" if SIMPLE else "fig_db_schema")
OUT_DOT = ROOT / f"paper/main/figures/{STEM}.dot"
OUT_PDF = ROOT / f"paper/main/figures/{STEM}.pdf"

TYPEMAP = {"BIGINT": "int", "INTEGER": "int", "DOUBLE": "double",
           "VARCHAR": "text", "BOOLEAN": "bool"}

# primary-key columns per table (composite keys: every listed column is a part)
PKS = {
    "dim_municipality": ["co_mun"],
    "dim_country": ["iso3c"],
    "dim_commodity": ["comm_code"],
    "dim_soy_product": ["product"],
    "production": ["year", "co_mun"],
    "domestic_use": ["year", "co_mun", "product", "use_category"],
    "trade": ["year", "co_mun", "product", "flow", "partner_iso3", "hs4"],
    "export_attribution": ["year", "method", "product", "co_mun", "dest_iso3"],
    "transport_flows": ["year", "method", "product", "co_mun_orig", "co_mun_dest"],
    "footprint_country": ["year", "co_mun", "consumer_code", "demand"],
    "footprint_product": ["year", "co_mun", "product_family", "product_code"],
    "footprint_animal_country": ["year", "co_mun", "consumer_iso3", "item"],
    "input_municipality": ["year", "co_mun"],
    "input_trade": ["year", "co_mun", "product", "flow", "partner_iso3", "hs4"],
    "input_cbs_national": ["year", "product"],
    "input_livestock_systems": ["year", "co_mun", "animal"],
    "input_feed": ["year", "co_mun", "animal"],
    "input_faostat_trade": ["year", "product", "flow", "partner_iso3"],
}

# (table, column) -> referenced (table, column)
FKS = {
    ("production", "co_mun"): ("dim_municipality", "co_mun"),
    ("domestic_use", "co_mun"): ("dim_municipality", "co_mun"),
    ("domestic_use", "product"): ("dim_soy_product", "product"),
    ("trade", "co_mun"): ("dim_municipality", "co_mun"),
    ("trade", "product"): ("dim_soy_product", "product"),
    ("trade", "partner_iso3"): ("dim_country", "iso3c"),
    ("export_attribution", "co_mun"): ("dim_municipality", "co_mun"),
    ("export_attribution", "product"): ("dim_soy_product", "product"),
    ("export_attribution", "dest_iso3"): ("dim_country", "iso3c"),
    ("transport_flows", "co_mun_orig"): ("dim_municipality", "co_mun"),
    ("transport_flows", "co_mun_dest"): ("dim_municipality", "co_mun"),
    ("transport_flows", "product"): ("dim_soy_product", "product"),
    ("footprint_country", "co_mun"): ("dim_municipality", "co_mun"),
    ("footprint_country", "consumer_code"): ("dim_country", "iso3c"),
    ("footprint_product", "co_mun"): ("dim_municipality", "co_mun"),
    ("footprint_product", "product_code"): ("dim_commodity", "comm_code"),
    ("footprint_animal_country", "co_mun"): ("dim_municipality", "co_mun"),
    ("footprint_animal_country", "consumer_iso3"): ("dim_country", "iso3c"),
    ("input_municipality", "co_mun"): ("dim_municipality", "co_mun"),
    ("input_trade", "co_mun"): ("dim_municipality", "co_mun"),
    ("input_trade", "product"): ("dim_soy_product", "product"),
    ("input_trade", "partner_iso3"): ("dim_country", "iso3c"),
    ("input_cbs_national", "product"): ("dim_soy_product", "product"),
    ("input_livestock_systems", "co_mun"): ("dim_municipality", "co_mun"),
    ("input_feed", "co_mun"): ("dim_municipality", "co_mun"),
    ("input_faostat_trade", "product"): ("dim_soy_product", "product"),
    ("input_faostat_trade", "partner_iso3"): ("dim_country", "iso3c"),
}

# stage groups: cluster label + (header fill, border) per table
GROUPS_RESULTS = [
    ("Dimensions", "#dbe6f4", "#31538f",
     ["dim_municipality", "dim_soy_product", "dim_commodity", "dim_country"]),
    ("Supply, use & trade (pipeline step 05)", "#dcebd7", "#3d7337",
     ["production", "domestic_use", "trade"]),
    ("Transport & export attribution (step 08)", "#fbe5c9", "#b26a12",
     ["export_attribution", "transport_flows"]),
    ("Consumption footprints (step 20)", "#f4d7d7", "#a03232",
     ["footprint_country", "footprint_product", "footprint_animal_country"]),
    ("Metadata", "#e6e6e6", "#666666",
     ["meta_provenance", "meta_build"]),
]

GROUPS_INPUTS = [
    ("Dimensions", "#dbe6f4", "#31538f",
     ["dim_municipality", "dim_soy_product", "dim_country"]),
    ("Grand municipal input (step 00)", "#dcebd7", "#3d7337",
     ["input_municipality"]),
    ("Trade & commodity balance (steps 00, 04)", "#fbe5c9", "#b26a12",
     ["input_trade", "input_cbs_national", "input_faostat_trade"]),
    ("Livestock & feed (steps 02–03)", "#f4d7d7", "#a03232",
     ["input_livestock_systems", "input_feed"]),
]

GROUPS = GROUPS_INPUTS if INPUTS_MODE else GROUPS_RESULTS


def table_html(name, cols, nrows, fill, border):
    pks, fk_cols = PKS.get(name, []), {c for (t, c) in FKS if t == name}
    span = 1 if SIMPLE else 3
    rows = [f'<TR><TD COLSPAN="{span}" BGCOLOR="{fill}" ALIGN="LEFT">'
            f'<B>{name}</B>  <FONT POINT-SIZE="8" COLOR="#555555">'
            f'{nrows:,} row{"s" if nrows != 1 else ""}</FONT></TD></TR>']
    if SIMPLE:
        # one cell per column: just the name, primary-key parts in bold
        for col, _ in cols:
            nm = f"<B>{col}</B>" if col in pks else col
            rows.append(f'<TR><TD ALIGN="LEFT">{nm}</TD></TR>')
        return (f'  {name} [color="{border}", label=<\n'
                '    <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0"'
                ' CELLPADDING="3">\n'
                + "\n".join("    " + r for r in rows) + "\n    </TABLE>>];")
    # two ports per row, on the table's outer borders, so connectors attach at
    # the left edge (name cell, :w) or the right edge (constraint cell, :e)
    for col, typ in cols:
        keys = [k for k, ok in (("pk", col in pks), ("fk", col in fk_cols)) if ok]
        key = f'<FONT COLOR="#777777">{" ".join(keys)}</FONT>' if keys else " "
        rows.append(
            f'<TR><TD ALIGN="LEFT" PORT="{col}">{col}</TD>'
            f'<TD ALIGN="LEFT"><FONT COLOR="#333333">{TYPEMAP.get(typ, typ.lower())}'
            f"</FONT></TD>"
            f'<TD ALIGN="LEFT" PORT="{col}_e">{key}</TD></TR>')
    return (f'  {name} [color="{border}", label=<\n'
            '    <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="3">\n'
            + "\n".join("    " + r for r in rows) + "\n    </TABLE>>];")


def main():
    con = duckdb.connect(str(DB), read_only=True)
    cols = {}  # table -> [(col, type)]
    for t, c, d in con.execute("""
            SELECT table_name, column_name, data_type
            FROM information_schema.columns WHERE table_name NOT LIKE 'v\\_%' ESCAPE '\\'
            ORDER BY table_name, ordinal_position""").fetchall():
        cols.setdefault(t, []).append((c, d))
    nrows = {t: con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0]
             for t in cols}
    con.close()

    sep = "nodesep=0.35, ranksep=0.9" if SIMPLE else "nodesep=0.45, ranksep=1.1"
    title = ("SOYPRINT input database (soyprint.duckdb, input_* tables)."
             " Cleaned inputs of pipeline steps 00–03, 2000–2023,"
             " hive-partitioned by year in the Parquet layer."
             if INPUTS_MODE else
             "SOYPRINT database (soyprint.duckdb). Fact tables cover"
             " 2000–2022 and are hive-partitioned by year in the Parquet layer.")
    lines = [
        "digraph soyprint_db {",
        f"  graph [rankdir=LR, splines=spline, {sep},"
        " newrank=true, compound=true,"
        ' fontname="Helvetica", fontsize=11, labelloc=t,'
        f' label="{title}"];',
        '  node [shape=plain, fontname="Helvetica", fontsize=9];',
        '  edge [color="#31538f", penwidth=0.9,'
        " dir=both, arrowtail=crowodot, arrowhead=teetee, arrowsize=0.7];",
    ]
    for i, (label, fill, border, tables) in enumerate(GROUPS):
        if SIMPLE and label == "Metadata":
            continue
        present = [t for t in tables if t in cols]
        if not present:
            continue
        lines.append(f"  subgraph cluster_{i} {{")
        lines.append(f'    label="{label}"; fontsize=11; fontcolor="{border}";'
                     f' color="{border}"; style=dashed; margin=10;')
        for t in present:
            lines.append(table_html(t, cols[t], nrows[t], fill, border))
        lines.append("  }")
    # column order: step 05 | step 08 + meta | dimensions | footprints.
    # Footprint FK edges are declared dim -> fact (cardinality marks swapped)
    # so the footprint tables land to the RIGHT of the dimensions; invisible
    # edges pin the step-08 and metadata clusters to the middle column.
    right_of_dims = {"footprint_country", "footprint_product",
                     "footprint_animal_country"}
    # only draw relationships between tables that are in the current figure
    drawn = {t for _, _, _, tables in GROUPS for t in tables}
    fks = {k: v for k, v in FKS.items() if k[0] in drawn and v[0] in drawn}
    if SIMPLE:
        # one connector per table pair, attached to the box border
        for t, rt in dict.fromkeys((t, rt) for (t, _), (rt, _) in fks.items()):
            if t in right_of_dims:
                lines.append(f"  {rt} -> {t}"
                             " [arrowtail=teetee, arrowhead=crowodot];")
            else:
                lines.append(f"  {t} -> {rt};")
    else:
        for (t, c), (rt, rc) in fks.items():
            if t in right_of_dims:
                lines.append(f"  {rt}:{rc}_e:e -> {t}:{c}:w"
                             " [arrowtail=teetee, arrowhead=crowodot];")
            else:
                lines.append(f"  {t}:{c}_e:e -> {rt}:{rc}:w;")
    if INPUTS_MODE:
        # columns: grand input | other input clusters | dimensions
        lines.append("  input_municipality -> input_trade [style=invis];")
        lines.append("  input_municipality -> input_livestock_systems"
                     " [style=invis];")
    elif SIMPLE:
        # push step 08 to a middle column for a squarer, wider layout
        lines.append("  production -> transport_flows [style=invis];")
    else:
        # the full version stacks all fact tables in one left column so the
        # figure stays narrow enough for a portrait page; metadata moves to
        # the middle column, under the dimensions, to balance column heights
        lines.append("  trade -> meta_provenance [style=invis];")
    lines.append("}")

    OUT_DOT.write_text("\n".join(lines))
    subprocess.run(["dot", "-Tpdf", str(OUT_DOT), "-o", str(OUT_PDF)], check=True)
    print(f"wrote {OUT_PDF.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""SoyPrint release schema (Figure 5), drawn from the release's data dictionary.

Reads data_dictionary.csv (tables, fields, types, row counts and pk/fk flags as
introspected from the released SQLite) and renders a crow's-foot ERD with
Graphviz, in the style of code/db/make_erd.py. Foreign keys are drawn where the
dictionary marks a column fk; the target follows from the column name.

Layout, three columns left to right:
  1. transport & export attribution, above supply, use & trade
  2. dimensions, with the metadata tables side by side below them
  3. consumption footprints and land balance
Each column is one Graphviz node built from nested HTML tables, so the order
inside a column is fixed. The columns are padded to the same height and tied by
heavy invisible edges, so their tops line up.

Usage (from the repo root):
    python3 code/db/make_erd_release.py [results/reference/data_dictionary.csv]
    ->  results/figures/fig_db_schema.{dot,pdf,png}
Needs Graphviz (`dot`) on the PATH.
"""
import csv, re, subprocess, sys
from pathlib import Path

DICT = Path(sys.argv[1] if len(sys.argv) > 1 else "results/reference/data_dictionary.csv")
OUTDIR = Path("results/figures")
STEM = str(OUTDIR / "fig_db_schema")
TYPEMAP = {"INTEGER": "int", "REAL": "real", "TEXT": "text"}
FK_TARGET = {
    "co_mun": ("dim_municipality", "co_mun"),
    "co_mun_orig": ("dim_municipality", "co_mun"),
    "co_mun_dest": ("dim_municipality", "co_mun"),
    "product": ("dim_soy_product", "product"),
    "partner_iso3": ("dim_country", "iso3c"),
    "dest_iso3": ("dim_country", "iso3c"),
    "consumer_iso3": ("dim_country", "iso3c"),
}
DISCR = {("footprint_product", "product_family")}  # says which vocabulary product_code uses
STYLE = {  # cluster: (title, header fill, border colour)
    "transport": ("Transport &amp; export attribution (step 08)", "#fbe5c9", "#b26a12"),
    "supply": ("Supply, use &amp; trade (step 05)", "#dcebd7", "#3d7337"),
    "dims": ("Dimensions", "#dbe6f4", "#31538f"),
    "meta": ("Metadata", "#e6e6e6", "#666666"),
    "footprints": ("Consumption footprints and land balance (step 20)", "#f4d7d7", "#a03232"),
}
# column -> list of (cluster, tables, arrangement)
COLUMNS = {
    "col_left": [("transport", ["transport_flows", "export_attribution"], "v"),
                 ("supply", ["production", "domestic_use", "trade"], "v")],
    "col_mid": [("dims", ["dim_municipality", "dim_soy_product", "dim_commodity",
                          "dim_country"], "v"),
                ("meta", ["meta_provenance", "meta_build"], "h")],
    "col_right": [("footprints", ["footprint_country", "footprint_product",
                                  "land_balance", "footprint_animal_country"], "v")],
}

rows = [r for r in csv.DictReader(l for l in DICT.open() if not l.startswith("#"))]
cols, nrows, keys = {}, {}, {}
for r in sorted(rows, key=lambda r: (r["table_name"], int(r["ordinal"]))):
    t = r["table_name"]
    cols.setdefault(t, []).append((r["field"], r["data_type"]))
    nrows[t] = int(r["row_count"])
    keys[(t, r["field"])] = set(filter(None, r["key"].split(",")))
placed = {t for col in COLUMNS.values() for _, ts, _ in col for t in ts}
if placed != set(cols):
    sys.exit(f"tables not placed: {set(cols) - placed}; unknown: {placed - set(cols)}")
home = {t: c for c, col in COLUMNS.items() for _, ts, _ in col for t in ts}

fks = {}
for (t, c), k in keys.items():
    if "fk" in k:
        if c not in FK_TARGET:
            sys.exit(f"fk {t}.{c} has no known target")
        fks[(t, c)] = FK_TARGET[c]


def table_html(name, fill, border):
    out = [f'<TR><TD COLSPAN="3" BGCOLOR="{fill}" ALIGN="LEFT"><B>{name}</B>  '
           f'<FONT POINT-SIZE="8" COLOR="#555555">{nrows[name]:,} '
           f'row{"s" if nrows[name] != 1 else ""}</FONT></TD></TR>']
    for col, typ in cols[name]:
        k = [x for x in ("pk", "fk") if x in keys[(name, col)]]
        if (name, col) in DISCR:
            k.append("discr")
        key = f'<FONT COLOR="#777777">{" ".join(k)}</FONT>' if k else " "
        out.append(f'<TR><TD ALIGN="LEFT" PORT="{name}__{col}">{col}</TD>'
                   f'<TD ALIGN="LEFT"><FONT COLOR="#333333">'
                   f'{TYPEMAP.get(typ, typ.lower())}</FONT></TD>'
                   f'<TD ALIGN="LEFT" PORT="{name}__{col}_e">{key}</TD></TR>')
    return (f'<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="3" '
            f'COLOR="{border}">' + "".join(out) + "</TABLE>")


def cluster_html(cluster, tables, arrangement):
    title, fill, border = STYLE[cluster]
    inner = [table_html(t, fill, border) for t in tables]
    if arrangement == "v":
        body = "".join(f'<TR><TD ALIGN="CENTER">{x}</TD></TR>' for x in inner)
        span = 1
    else:
        body = "<TR>" + "".join(f'<TD VALIGN="TOP">{x}</TD>' for x in inner) + "</TR>"
        span = len(inner)
    return (f'<TABLE BORDER="1" STYLE="dashed" COLOR="{border}" CELLBORDER="0" '
            f'CELLSPACING="14" CELLPADDING="0">'
            f'<TR><TD COLSPAN="{span}"><FONT POINT-SIZE="11" COLOR="{border}">'
            f'{title}</FONT></TD></TR>{body}</TABLE>')


def build(pad):
    lines = ["digraph soyprint_db {",
             '  graph [rankdir=LR, splines=spline, nodesep=0.3, ranksep=1.0,'
             ' fontname="Helvetica"];',
             '  node [shape=plain, fontname="Helvetica", fontsize=9];',
             '  edge [color="#31538f", penwidth=0.9, dir=both, arrowtail=crowodot,'
             ' arrowhead=teetee, arrowsize=0.7];']
    for c, col in COLUMNS.items():
        parts = "".join(f'<TR><TD>{cluster_html(*x)}</TD></TR>' for x in col)
        filler = f'<TR><TD HEIGHT="{pad[c]}"> </TD></TR>' if pad.get(c) else ""
        lines.append(f'  {c} [label=<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="10" '
                     f'CELLPADDING="0">{parts}{filler}</TABLE>>];')
    for (t, c), (rt, rc) in sorted(fks.items()):
        a, b = home[t], home[rt]
        if a == "col_right":   # footprints sit right of the dimensions
            lines.append(f'  {b}:"{rt}__{rc}_e":e -> {a}:"{t}__{c}":w'
                         ' [arrowtail=teetee, arrowhead=crowodot];')
        else:
            lines.append(f'  {a}:"{t}__{c}_e":e -> {b}:"{rt}__{rc}":w;')
    lines.append("  col_left -> col_mid -> col_right [style=invis, weight=100];")
    lines.append("}")
    return "\n".join(lines) + "\n"


def heights(dot_src):
    plain = subprocess.run(["dot", "-Tplain"], input=dot_src, text=True,
                           capture_output=True, check=True).stdout
    return {f[1]: float(f[5]) * 72 for f in (l.split() for l in plain.splitlines())
            if f[0] == "node"}


# pad the shorter columns until all three are equally tall (the filler row
# also adds cell spacing, so a few rounds are needed)
pad = {}
for _ in range(6):
    src = build(pad)
    h2 = heights(src)
    top = max(h2.values())
    if top - min(h2.values()) <= 1:
        break
    for c, v in h2.items():
        if top - v > 1:
            pad[c] = max(1, round(pad.get(c, 0) + top - v))
if max(h2.values()) - min(h2.values()) > 2:
    sys.exit(f"columns not equal in height: {h2}")
OUTDIR.mkdir(parents=True, exist_ok=True)
Path(f"{STEM}.dot").write_text(src)
for fmt in ("pdf", "png"):
    subprocess.run(["dot", f"-T{fmt}", f"{STEM}.dot", "-o", f"{STEM}.{fmt}"]
                   + (["-Gdpi=150"] if fmt == "png" else []), check=True)
print(f"{len(cols)} tables, {sum(nrows.values()):,} rows, {len(fks)} foreign keys;"
      f" column heights {', '.join(f'{k} {v:.0f}pt' for k, v in h2.items())}")

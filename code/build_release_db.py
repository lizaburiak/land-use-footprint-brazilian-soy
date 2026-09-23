#!/usr/bin/env python3
"""
build_release_db.py -- load the release Parquet layer into SQLite (Stage 5, part 2 of 2).

Run code/build_release_parquet.R first; this reads what it wrote and produces a single
portable soyprint.sqlite with typed columns, primary keys, foreign keys and indexes.

    Rscript code/build_release_parquet.R 2000 2020
    python3 code/build_release_db.py

Usage:
    python3 code/build_release_db.py [--parquet DIR] [--out FILE] [--force]

Exit codes: 0 clean; 1 usage/IO error; 2 built but with integrity warnings
(orphan foreign keys, or tables from Figure 5 that could not be built).

Requires pyarrow (present) and the sqlite3 stdlib module. No DuckDB.
"""

from __future__ import annotations

import argparse
import csv
import os
import sqlite3
import sys
from pathlib import Path

# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR.
DATA_DIR = Path(os.environ.get("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint"))

try:
    import pyarrow.parquet as pq
    import pyarrow.dataset as ds
    HAVE_PYARROW = True
except ImportError:
    # The VM's system Python has no pyarrow and is externally managed (no pip install).
    # --csv DIR then loads the same tables from a CSV dump written by R (arrow can read
    # the Parquet layer and write CSV); see build_csv_from_parquet.R.
    HAVE_PYARROW = False

# `group` is a reserved SQL keyword; it is quoted everywhere it appears.
SCHEMA: dict[str, dict] = {
    "dim_municipality": {
        "cols": [("co_mun", "INTEGER"), ("nm_mun", "TEXT"), ("co_state", "INTEGER"),
                 ("nm_state", "TEXT"), ("lon", "REAL"), ("lat", "REAL")],
        "pk": ["co_mun"], "fk": [], "partitioned": False,
    },
    "dim_soy_product": {
        "cols": [("product", "TEXT"), ("hs4", "INTEGER"),
                 ("fabio_item_code", "INTEGER"), ("description", "TEXT")],
        "pk": ["product"], "fk": [], "partitioned": False,
    },
    "dim_country": {
        "cols": [("iso3c", "TEXT"), ("name", "TEXT"), ("continent", "TEXT"),
                 ("region", "TEXT"), ("eu27", "INTEGER")],
        "pk": ["iso3c"], "fk": [], "partitioned": False,
    },
    "dim_commodity": {
        "cols": [("comm_code", "TEXT"), ("item_code", "INTEGER"), ("item", "TEXT"),
                 ("comm_group", "TEXT"), ("group", "TEXT")],
        "pk": ["comm_code"], "fk": [], "partitioned": False,
    },
    "production": {
        "cols": [("co_mun", "INTEGER"), ("area_planted_ha", "REAL"),
                 ("area_harvested_ha", "REAL"), ("production_bean_t", "REAL"),
                 ("processed_bean_t", "REAL"), ("production_oil_t", "REAL"),
                 ("production_cake_t", "REAL"), ("year", "INTEGER")],
        "pk": ["co_mun", "year"],
        "fk": [(["co_mun"], "dim_municipality", ["co_mun"])], "partitioned": True,
    },
    "domestic_use": {
        "cols": [("co_mun", "INTEGER"), ("product", "TEXT"), ("use_category", "TEXT"),
                 ("tonnes", "REAL"), ("year", "INTEGER")],
        "pk": ["co_mun", "product", "use_category", "year"],
        "fk": [(["co_mun"], "dim_municipality", ["co_mun"]),
               (["product"], "dim_soy_product", ["product"])], "partitioned": True,
    },
    "trade": {
        "cols": [("co_mun", "INTEGER"), ("product", "TEXT"), ("flow", "TEXT"),
                 ("partner_iso3", "TEXT"), ("hs4", "INTEGER"), ("tonnes", "REAL"),
                 ("value_usd", "REAL"), ("year", "INTEGER")],
        "pk": ["co_mun", "product", "flow", "partner_iso3", "hs4", "year"],
        "fk": [(["co_mun"], "dim_municipality", ["co_mun"]),
               (["product"], "dim_soy_product", ["product"]),
               (["partner_iso3"], "dim_country", ["iso3c"])], "partitioned": True,
    },
    "transport_flows": {
        "cols": [("method", "TEXT"), ("product", "TEXT"), ("co_mun_orig", "INTEGER"),
                 ("co_mun_dest", "INTEGER"), ("tonnes", "REAL"), ("year", "INTEGER")],
        "pk": ["method", "product", "co_mun_orig", "co_mun_dest", "year"],
        "fk": [(["product"], "dim_soy_product", ["product"]),
               (["co_mun_orig"], "dim_municipality", ["co_mun"]),
               (["co_mun_dest"], "dim_municipality", ["co_mun"])], "partitioned": True,
    },
    "export_attribution": {
        "cols": [("method", "TEXT"), ("product", "TEXT"), ("co_mun", "INTEGER"),
                 ("dest_iso3", "TEXT"), ("tonnes", "REAL"), ("year", "INTEGER")],
        "pk": ["method", "product", "co_mun", "dest_iso3", "year"],
        "fk": [(["product"], "dim_soy_product", ["product"]),
               (["co_mun"], "dim_municipality", ["co_mun"]),
               (["dest_iso3"], "dim_country", ["iso3c"])], "partitioned": True,
    },
    # -- footprints (pipeline step 20, F_mass, hectares of municipal soy land) ----
    # consumer_code is ISO3 *plus* FABIO's five rest-of-world regions (ROW_WA/WE/WF/
    # WL/WM), which are not countries and are absent from dim_country, so this column
    # carries no FK. footprint_animal_country.consumer_iso3 has no such aggregates
    # (verified: 0 values outside dim_country) and is keyed normally.
    "footprint_country": {
        "cols": [("co_mun", "INTEGER"), ("consumer_code", "TEXT"), ("demand", "TEXT"),
                 ("hectares", "REAL"), ("year", "INTEGER")],
        "pk": ["co_mun", "consumer_code", "demand", "year"],
        "fk": [(["co_mun"], "dim_municipality", ["co_mun"])], "partitioned": True,
    },
    # Figure 5 gives product_code an FK to dim_commodity; it cannot hold, because the
    # nonfood half of this table is keyed by EXIOBASE product, not FABIO item.
    # product_family ("fabio" / "exiobase") says which vocabulary a row uses instead.
    "footprint_product": {
        "cols": [("co_mun", "INTEGER"), ("product_family", "TEXT"),
                 ("product_code", "TEXT"), ("hectares", "REAL"), ("year", "INTEGER")],
        "pk": ["co_mun", "product_family", "product_code", "year"],
        "fk": [(["co_mun"], "dim_municipality", ["co_mun"])], "partitioned": True,
    },
    "footprint_animal_country": {
        "cols": [("co_mun", "INTEGER"), ("consumer_iso3", "TEXT"), ("item", "TEXT"),
                 ("hectares", "REAL"), ("year", "INTEGER")],
        "pk": ["co_mun", "consumer_iso3", "item", "year"],
        "fk": [(["co_mun"], "dim_municipality", ["co_mun"]),
               (["consumer_iso3"], "dim_country", ["iso3c"])], "partitioned": True,
    },
    "meta_build": {
        "cols": [("built_at", "TEXT"), ("git_commit", "TEXT"),
                 ("git_branch", "TEXT"), ("sqlite_version", "TEXT")],
        "pk": [], "fk": [], "partitioned": False,
    },
    "meta_provenance": {
        "cols": [("tbl", "TEXT"), ("year", "INTEGER"), ("source_file", "TEXT"),
                 ("source_mtime", "TEXT"), ("exported_at", "TEXT")],
        "pk": [], "fk": [], "partitioned": False,
    },
}

# Figure 5 tables that come from pipeline step 20. They are built whenever the Parquet
# layer carries them; a year without a step-20 footprint simply has no partition. This is
# resolved per run (see main) rather than hard-coded, so the DB never claims a table is
# unbuildable when the data is in fact present.
FOOTPRINT_TABLES = ["footprint_animal_country", "footprint_country", "footprint_product"]

BATCH = 50_000


def q(name: str) -> str:
    """Quote an identifier (handles reserved words such as `group`)."""
    return '"' + name.replace('"', '""') + '"'


def ddl(table: str, spec: dict) -> str:
    lines = [f"  {q(c)} {t}" for c, t in spec["cols"]]
    if spec["pk"]:
        lines.append("  PRIMARY KEY (" + ", ".join(q(c) for c in spec["pk"]) + ")")
    for cols, ref_tbl, ref_cols in spec["fk"]:
        lines.append(
            f"  FOREIGN KEY ({', '.join(q(c) for c in cols)}) "
            f"REFERENCES {q(ref_tbl)} ({', '.join(q(c) for c in ref_cols)})")
    return f"CREATE TABLE {q(table)} (\n" + ",\n".join(lines) + "\n)"


def read_csv_table(csvdir: Path, table: str, spec: dict):
    """Yield row tuples for a table from <csvdir>/<table>.csv, or None if absent.

    The CSV carries every column the schema names (year included, already unpacked
    from the hive partition). Values are cast per the schema's SQLite type so the
    stored types match a pyarrow load exactly; "" and "NA" become NULL.
    """
    f = csvdir / f"{table}.csv"
    if not f.exists():
        return None
    names = [c for c, _ in spec["cols"]]
    types = dict(spec["cols"])

    def cast(v, t):
        if v is None or v == "" or v == "NA":
            return None
        if t == "INTEGER":
            return int(float(v)) if v not in ("TRUE", "FALSE") else int(v == "TRUE")
        if t == "REAL":
            return float(v)
        return v

    rows = []
    with open(f, newline="", encoding="utf-8") as fh:
        rdr = csv.DictReader(fh)
        present = [n for n in names if n in (rdr.fieldnames or [])]
        for rec in rdr:
            rows.append(tuple(cast(rec.get(n), types[n]) if n in present else None
                              for n in names))
    return rows, present, names


def read_table(pqdir: Path, table: str, spec: dict):
    """Yield pyarrow RecordBatches for a table, or None if its Parquet is absent."""
    root = pqdir / table
    if not root.exists():
        return None
    if spec["partitioned"]:
        dataset = ds.dataset(root, format="parquet", partitioning="hive")
    else:
        f = root / "part-0.parquet"
        if not f.exists():
            return None
        dataset = ds.dataset(f, format="parquet")
    names = [c for c, _ in spec["cols"]]
    present = [n for n in names if n in dataset.schema.names]
    return dataset, present, names


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--parquet", default=str(DATA_DIR / "generated/parquet"))
    ap.add_argument("--out", default=str(DATA_DIR / "generated/soyprint.sqlite"))
    ap.add_argument("--force", action="store_true",
                    help="overwrite an existing database file")
    ap.add_argument("--csv", default=None,
                    help="load from a CSV dump of the Parquet layer instead of Parquet "
                         "(for hosts without pyarrow); see build_csv_from_parquet.R")
    a = ap.parse_args()

    csvdir = Path(a.csv) if a.csv else None
    if csvdir is not None:
        if not csvdir.is_dir():
            sys.exit(f"no CSV layer at {csvdir}")
    elif not HAVE_PYARROW:
        sys.exit("pyarrow is not installed and --csv was not given. Either install pyarrow "
                 "or dump the Parquet layer to CSV (code/build_csv_from_parquet.R) and pass --csv DIR.")

    pqdir = Path(a.parquet)
    if csvdir is None and not pqdir.is_dir():
        sys.exit(f"no Parquet layer at {pqdir} -- run code/build_release_parquet.R first")

    out = Path(a.out)
    if out.exists():
        if not a.force:
            sys.exit(f"{out} exists; pass --force to overwrite")
        out.unlink()
    out.parent.mkdir(parents=True, exist_ok=True)

    con = sqlite3.connect(out)
    con.execute("PRAGMA journal_mode=OFF")
    con.execute("PRAGMA synchronous=OFF")
    con.execute("PRAGMA foreign_keys=ON")

    warnings: list[str] = []
    counts: dict[str, int] = {}

    # dimensions first so the fact tables' foreign keys resolve
    order = ([t for t in SCHEMA if not SCHEMA[t]["partitioned"] and not t.startswith("meta_")]
             + [t for t in SCHEMA if SCHEMA[t]["partitioned"]]
             + [t for t in SCHEMA if t.startswith("meta_")])

    for table in order:
        spec = SCHEMA[table]
        con.execute(ddl(table, spec))
        got = read_csv_table(csvdir, table, spec) if csvdir is not None else read_table(pqdir, table, spec)
        if got is None:
            warnings.append(f"{table}: no Parquet found -- created empty")
            counts[table] = 0
            continue
        src, present, names = got
        missing = [n for n in names if n not in present]
        if missing:
            warnings.append(f"{table}: columns absent from Parquet, stored NULL: {missing}")

        placeholders = ", ".join("?" for _ in names)
        insert = (f"INSERT INTO {q(table)} ({', '.join(q(n) for n in names)}) "
                  f"VALUES ({placeholders})")
        total = 0
        if csvdir is not None:
            for i in range(0, len(src), BATCH):
                chunk = src[i:i + BATCH]
                con.executemany(insert, chunk)
                total += len(chunk)
            counts[table] = total
            con.commit()
            print(f"  {table:<26} {total:>10,} rows")
            continue
        dataset = src
        for batch in dataset.to_batches(columns=present, batch_size=BATCH):
            cols = {n: batch.column(present.index(n)).to_pylist() if n in present
                    else [None] * batch.num_rows for n in names}
            rows = list(zip(*(cols[n] for n in names)))
            # booleans -> 0/1 so SQLite stores INTEGER, not 'True'
            rows = [tuple(int(v) if isinstance(v, bool) else v for v in r) for r in rows]
            con.executemany(insert, rows)
            total += len(rows)
        counts[table] = total
        con.commit()
        print(f"  {table:<26} {total:>10,} rows")

    # record the engine version now that we know it
    con.execute("UPDATE meta_build SET sqlite_version = ?", (sqlite3.sqlite_version,))

    # a footprint table that received no rows is genuinely absent -> say so in provenance
    not_built = [t for t in FOOTPRINT_TABLES if not counts.get(t)]
    for t in not_built:
        cur = con.execute("SELECT COUNT(*) FROM meta_provenance WHERE tbl = ?", (t,))
        if cur.fetchone()[0] == 0:
            con.execute(
                "INSERT INTO meta_provenance (tbl, year, source_file, source_mtime, exported_at) "
                "VALUES (?, NULL, ?, NULL, datetime('now'))",
                (t, "NOT BUILT -- no step 20 footprint output in the Parquet layer"))
    con.commit()

    print("\nIndexes...")
    for table, spec in SCHEMA.items():
        if spec["partitioned"]:
            con.execute(f"CREATE INDEX {q('ix_' + table + '_year')} ON {q(table)} (year)")
        for cols, ref_tbl, _ in spec["fk"]:
            name = f"ix_{table}_{'_'.join(cols)}"
            con.execute(f"CREATE INDEX {q(name)} ON {q(table)} "
                        f"({', '.join(q(c) for c in cols)})")
    con.commit()

    print("Integrity checks...")
    ic = con.execute("PRAGMA integrity_check").fetchone()[0]
    if ic != "ok":
        warnings.append(f"integrity_check: {ic}")
    orphans = con.execute("PRAGMA foreign_key_check").fetchall()
    if orphans:
        by_tbl: dict[str, int] = {}
        for row in orphans:
            by_tbl[row[0]] = by_tbl.get(row[0], 0) + 1
        for t, n in sorted(by_tbl.items()):
            warnings.append(f"{t}: {n:,} rows with unresolved foreign keys")

    con.execute("ANALYZE")
    con.commit()
    con.close()

    size = out.stat().st_size / 1e6
    print(f"\nWrote {out} ({size:,.1f} MB), {sum(counts.values()):,} rows across "
          f"{len(SCHEMA)} tables.")
    if not_built:
        print(f"Not built (Figure 5 specifies, step 20 required): {', '.join(not_built)}")
    else:
        print("All 12 Figure 5 tables built, footprints included.")

    if warnings:
        print("\nWARNINGS:")
        for w in warnings:
            print(f"  - {w}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

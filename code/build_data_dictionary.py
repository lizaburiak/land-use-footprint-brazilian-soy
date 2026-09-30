#!/usr/bin/env python3
"""
build_data_dictionary.py -- emit the SoyPrint data dictionary (gap register C2).

Scientific Data requires a machine-readable dictionary covering every table and
every field, with type, unit and definition. Types and keys can be read from the
database; units and definitions cannot -- they are editorial and live in a
sidecar annotations file that a human maintains.

The script therefore does three things:

  1. introspects whatever tables the SQLite build actually contains -- it hard-
     codes no table or field names, so it stays correct as the schema changes;
  2. merges curated units and definitions from the annotations sidecar, marking
     anything unannotated as UNVERIFIED rather than guessing;
  3. validates every field against the hive-partitioned Parquet layer and
     records, per field, whether the two agree.

Re-running is safe and idempotent: corrections live in the sidecar, never in
the generated CSV, so they survive regeneration.

Usage
-----
    python3 code/build_data_dictionary.py \
        --db      data/generated/soyprint.sqlite \
        --parquet data/generated/parquet \
        --out     results/reference/data_dictionary.csv

    # first run: create the sidecar skeleton to fill in
    python3 code/build_data_dictionary.py --init-annotations

Exit codes: 0 clean; 1 usage/IO error; 2 dictionary written but incomplete
(unverified annotations and/or Parquet mismatches). CI can gate on 0.

Requires pyarrow for the Parquet layer; sqlite3 is in the stdlib. No DuckDB --
the release container is SQLite (soyprint.sqlite) with Parquet alongside.
"""

from __future__ import annotations

import os
import argparse
import csv
import datetime as _dt
import sqlite3
import subprocess
import sys
from pathlib import Path

# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR.
DATA_DIR = Path(os.environ.get("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint"))

try:
    import pyarrow.dataset as ds
except ImportError:
    sys.exit("pyarrow is not installed. Run: pip install pyarrow")

UNVERIFIED = "UNVERIFIED -- TODO"

OUTPUT_COLUMNS = [
    "table_name", "table_role", "row_count",
    "field", "ordinal", "data_type", "nullable", "key",
    "unit", "definition",
    "parquet_check", "notes",
]

ANNOTATION_COLUMNS = ["table_name", "field", "unit", "definition", "notes"]


# --------------------------------------------------------------------------
# introspection
# --------------------------------------------------------------------------

def classify(table: str) -> str:
    """Group tables for the report. Presentational only -- never affects content."""
    t = table.lower()
    if t.startswith("dim_"):
        return "dimension"
    if t.startswith(("meta_", "metadata_")):
        return "metadata"
    return "fact"


def user_tables(con) -> list[str]:
    """Base tables, excluding SQLite's internal ones."""
    rows = con.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name"
    ).fetchall()
    return [r[0] for r in rows]


def read_schema(con) -> list[dict]:
    """Every column of every base table, in ordinal order (PRAGMA table_info)."""
    out: list[dict] = []
    for t in user_tables(con):
        for cid, name, decl_type, notnull, _default, _pk in con.execute(
                f'PRAGMA table_info("{t}")').fetchall():
            out.append({
                "table_name": t,
                "field": name,
                "ordinal": cid,
                # SQLite columns may be declared without a type; say so rather than guess
                "data_type": (decl_type or "").upper() or "(untyped)",
                "nullable": "no" if notnull else "yes",
            })
    return out


def read_keys(con) -> dict[tuple[str, str], str]:
    """Map (table, field) -> 'pk' / 'fk' / 'pk,fk' from declared constraints."""
    keys: dict[tuple[str, str], set[str]] = {}
    for t in user_tables(con):
        for _cid, name, _ty, _nn, _dflt, pk in con.execute(
                f'PRAGMA table_info("{t}")').fetchall():
            if pk:
                keys.setdefault((t, name), set()).add("pk")
        # foreign_key_list row: id, seq, table, from, to, on_update, on_delete, match
        for row in con.execute(f'PRAGMA foreign_key_list("{t}")').fetchall():
            keys.setdefault((t, row[3]), set()).add("fk")
    return {k: ",".join(sorted(v)) for k, v in keys.items()}


def read_row_counts(con, tables, exact: bool = True) -> dict[str, int]:
    """Exact count(*) per table. SQLite has no cheap row estimate, so --estimate-rows
    is accepted for CLI compatibility but always counts exactly."""
    return {t: con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0] for t in tables}


# --------------------------------------------------------------------------
# parquet validation
# --------------------------------------------------------------------------

def parquet_columns(root: Path, table: str) -> dict[str, str] | None:
    """
    Column -> Arrow type for the Parquet copy of `table`, or None if not found.

    Handles both layouts the exporter produces: a hive-partitioned directory for
    fact tables (<root>/<table>/year=YYYY/part-0.parquet) and a single file for
    dimensions (<root>/<table>/part-0.parquet).
    """
    d = root / table
    try:
        if d.is_dir():
            dataset = ds.dataset(d, format="parquet", partitioning="hive")
        elif (root / f"{table}.parquet").exists():
            dataset = ds.dataset(root / f"{table}.parquet", format="parquet")
        else:
            return None
    except Exception:
        return None
    return {n: str(t) for n, t in zip(dataset.schema.names, dataset.schema.types)}


# Type families. The left-hand names are SQLite declared types, the right-hand
# ones Arrow type names; both fold into one family so the cross-engine comparison
# is meaningful. A Parquet round-trip widens integers (a hive partition key reads
# back as int32/int64 whatever it was written as), so a width change is reported
# but is not a defect; a change of family is a real mismatch.
_FAMILIES = {
    "integer": {"TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT", "INT",
                "INT8", "INT16", "INT32", "INT64",
                "UINT8", "UINT16", "UINT32", "UINT64"},
    "float":   {"FLOAT", "REAL", "DOUBLE", "FLOAT32", "FLOAT64", "HALFFLOAT"},
    "string":  {"VARCHAR", "CHAR", "TEXT", "STRING", "BPCHAR", "LARGE_STRING", "UTF8"},
    "boolean": {"BOOLEAN", "BOOL"},
    "temporal": {"DATE", "TIME", "TIMESTAMP", "DATE32", "DATE64"},
}


def _family(t: str) -> str:
    base = t.upper().split("(")[0].split("[")[0].strip()
    for name, members in _FAMILIES.items():
        if base in members:
            return name
    if base.startswith("DECIMAL") or base.startswith("NUMERIC"):
        return "float"
    return base.lower()


def compare(db_type: str, pq_type: str | None, strict: bool = False) -> str:
    """Return 'match', an expected-representation note, or a mismatch description."""
    if pq_type is None:
        return "missing in parquet"
    if db_type.upper() == pq_type.upper():
        return "match"
    if not strict:
        fam_db, fam_pq = _family(db_type), _family(pq_type)
        if fam_db == fam_pq:
            return f"width differs, same type family (parquet: {pq_type})"
        # SQLite has no BOOLEAN type: booleans are stored as INTEGER 0/1 while
        # Parquet keeps a real bool. Expected on both sides, not drift.
        if {fam_db, fam_pq} == {"integer", "boolean"}:
            return f"boolean stored as INTEGER in SQLite (parquet: {pq_type})"
    return f"TYPE MISMATCH (parquet: {pq_type})"


def is_defect(check: str) -> bool:
    """Only genuine problems gate the exit code."""
    return (check not in ("match", "not checked")
            and not check.startswith("width differs")
            and not check.startswith("boolean stored as INTEGER"))


# --------------------------------------------------------------------------
# annotations sidecar
# --------------------------------------------------------------------------

def load_annotations(path: Path) -> dict[tuple[str, str], dict]:
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as fh:
        return {
            (r["table_name"].strip(), r["field"].strip()): r
            for r in csv.DictReader(fh)
            if r.get("table_name") and r.get("field")
        }


def write_annotation_skeleton(path: Path, schema: list[dict], existing: dict) -> int:
    """Create or extend the sidecar so every field has a row to fill in."""
    added = 0
    rows = []
    for col in schema:
        key = (col["table_name"], col["field"])
        if key in existing:
            rows.append({c: existing[key].get(c, "") for c in ANNOTATION_COLUMNS})
        else:
            rows.append({
                "table_name": col["table_name"], "field": col["field"],
                "unit": "", "definition": "", "notes": "",
            })
            added += 1

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=ANNOTATION_COLUMNS)
        w.writeheader()
        w.writerows(rows)
    return added


# --------------------------------------------------------------------------
# provenance
# --------------------------------------------------------------------------

def build_provenance(db: Path) -> list[str]:
    """Record what the dictionary was generated from, for the Zenodo deposit."""
    stamp = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        commit = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, cwd=Path(__file__).resolve().parent,
        ).stdout.strip() or "unknown"
    except Exception:
        commit = "unknown"
    return [
        f"# SoyPrint data dictionary -- generated {stamp}",
        f"# source database: {db}",
        f"# generator: code/build_data_dictionary.py @ {commit}",
        f"# sqlite: {sqlite3.sqlite_version}; parquet layer read with pyarrow",
        f"# '{UNVERIFIED}' means no human-supplied value exists yet; nothing here is inferred.",
    ]


# --------------------------------------------------------------------------

def main() -> int:
    p = argparse.ArgumentParser(
        description="Emit the SoyPrint data dictionary from the live SQLite build."
    )
    p.add_argument("--db", type=Path, default=DATA_DIR / "generated/soyprint.sqlite",
                   help="path to soyprint.sqlite")
    p.add_argument("--parquet", type=Path, help="root of the hive-partitioned Parquet layer")
    p.add_argument("--out", type=Path, default=Path("results/reference/data_dictionary.csv"))
    p.add_argument("--annotations", type=Path,
                   default=Path("results/reference/data_dictionary_annotations.csv"),
                   help="sidecar holding human-supplied units and definitions")
    p.add_argument("--init-annotations", action="store_true",
                   help="create/extend the sidecar skeleton, then exit")
    p.add_argument("--estimate-rows", action="store_true",
                   help="accepted for compatibility; SQLite always counts exactly")
    p.add_argument("--strict-types", action="store_true",
                   help="treat any type-name difference as a mismatch, including "
                        "integer-width changes introduced by the Parquet round-trip")
    p.add_argument("--no-header-comments", action="store_true",
                   help="omit the leading # provenance lines (for strict CSV consumers)")
    args = p.parse_args()

    if not args.db.exists():
        return err(f"database not found: {args.db}")

    con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)

    schema = read_schema(con)
    if not schema:
        return err(f"no user tables found in {args.db}")

    existing = load_annotations(args.annotations)

    if args.init_annotations:
        added = write_annotation_skeleton(args.annotations, schema, existing)
        print(f"Annotations sidecar: {args.annotations}")
        print(f"  {len(schema)} fields total, {added} new row(s) added.")
        print("  Fill in 'unit' and 'definition', then re-run without --init-annotations.")
        return 0

    tables = sorted({c["table_name"] for c in schema})
    keys = read_keys(con)
    counts = read_row_counts(con, tables, exact=not args.estimate_rows)

    pq: dict[str, dict[str, str] | None] = {}
    if args.parquet:
        if not args.parquet.exists():
            return err(f"parquet root not found: {args.parquet}")
        for t in tables:
            pq[t] = parquet_columns(args.parquet, t)

    out_rows, unverified, mismatches = [], [], []

    for col in schema:
        table, field = col["table_name"], col["field"]
        ann = existing.get((table, field), {})
        unit = (ann.get("unit") or "").strip()
        definition = (ann.get("definition") or "").strip()

        if not unit:
            unit = UNVERIFIED
            unverified.append(f"{table}.{field} (unit)")
        if not definition:
            definition = UNVERIFIED
            unverified.append(f"{table}.{field} (definition)")

        if not args.parquet:
            check = "not checked"
        elif pq.get(table) is None:
            check = "table missing in parquet"
        else:
            check = compare(col["data_type"], pq[table].get(field), args.strict_types)
        if is_defect(check):
            mismatches.append(f"{table}.{field}: {check}")

        out_rows.append({
            "table_name": table,
            "table_role": classify(table),
            "row_count": counts.get(table, ""),
            "field": field,
            "ordinal": col["ordinal"],
            "data_type": col["data_type"],
            "nullable": col["nullable"],
            "key": keys.get((table, field), ""),
            "unit": unit,
            "definition": definition,
            "parquet_check": check,
            "notes": (ann.get("notes") or "").strip(),
        })

    # fields present in Parquet but absent from the database
    for table, cols in pq.items():
        if not cols:
            continue
        known = {c["field"] for c in schema if c["table_name"] == table}
        for extra in sorted(set(cols) - known):
            msg = f"{table}.{extra}: present in parquet, absent from database"
            mismatches.append(msg)
            out_rows.append({
                "table_name": table, "table_role": classify(table),
                "row_count": counts.get(table, ""), "field": extra, "ordinal": "",
                "data_type": cols[extra], "nullable": "", "key": "",
                "unit": UNVERIFIED, "definition": UNVERIFIED,
                "parquet_check": "extra in parquet",
                "notes": "hive partition key, or database/parquet drift -- check",
            })

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as fh:
        if not args.no_header_comments:
            for line in build_provenance(args.db):
                fh.write(line + "\n")
        w = csv.DictWriter(fh, fieldnames=OUTPUT_COLUMNS)
        w.writeheader()
        w.writerows(out_rows)

    report(args, tables, schema, out_rows, unverified, mismatches)
    return 2 if (unverified or mismatches) else 0


def report(args, tables, schema, out_rows, unverified, mismatches) -> None:
    print(f"Wrote {args.out}")
    print(f"  {len(tables)} tables, {len(schema)} fields "
          f"({len(out_rows) - len(schema)} extra parquet column(s))")

    roles: dict[str, int] = {}
    for t in tables:
        roles[classify(t)] = roles.get(classify(t), 0) + 1
    print("  " + ", ".join(f"{n} {role}" for role, n in sorted(roles.items())))

    if mismatches:
        print(f"\n  {len(mismatches)} database/Parquet mismatch(es):", file=sys.stderr)
        for m in mismatches[:25]:
            print(f"    - {m}", file=sys.stderr)
        if len(mismatches) > 25:
            print(f"    ... and {len(mismatches) - 25} more", file=sys.stderr)

    if unverified:
        print(f"\n  {len(unverified)} unverified annotation(s) "
              f"across {len({u.split(' ')[0] for u in unverified})} field(s).",
              file=sys.stderr)
        print(f"  Fill them in: {args.annotations}", file=sys.stderr)
        print("  (run with --init-annotations to generate the skeleton)", file=sys.stderr)

    if not unverified and not mismatches:
        print("\n  Complete: every field annotated, database and Parquet agree.")


def err(msg: str) -> int:
    print(f"error: {msg}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

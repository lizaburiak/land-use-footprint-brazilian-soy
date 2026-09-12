#!/usr/bin/env python3
"""SOYPRINT results database - optional stage 3: dump everything to CSV.

Reads data/db/soyprint.duckdb and writes plain CSV files under data/db/csv/:

  csv/
    <table>.csv                    all small/medium tables, one file each
    <big_table>/<big_table>_YYYY.csv.gz
                                   the 3 municipality-level footprint tables,
                                   split per year and gzipped (millions of
                                   rows -- too big for Excel either way; R and
                                   pandas read .csv.gz directly)
    summaries/*.csv                small aggregated tables (country x year,
                                   biome x year, end-use x year, national
                                   balance) -- open these in Excel/Numbers

Usage:
    .venv/bin/python code/db/export_csv.py            # everything
    .venv/bin/python code/db/export_csv.py --skip-big # skip the per-year dumps
"""

import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "data/db/soyprint.duckdb"
OUT = ROOT / "data/db/csv"

# municipality-level footprint triplets: 9-47M rows -> per-year gzip
BIG = ["footprint_country", "footprint_product", "footprint_animal_country"]

SUMMARIES = {
    # consumer country totals (join gives readable names/regions)
    "footprint_by_country_year": """
        SELECT year, iso3, country, region, continent, demand,
               round(sum(hectares)) AS hectares
        FROM v_footprint_by_country GROUP BY ALL ORDER BY year, hectares DESC
    """,
    "footprint_by_enduse_year": """
        SELECT year, enduse_bucket, round(sum(hectares)) AS hectares
        FROM v_footprint_by_enduse GROUP BY ALL ORDER BY year, hectares DESC
    """,
    "footprint_by_biome_year": """
        SELECT year, biome, matopiba, demand, round(sum(hectares)) AS hectares
        FROM v_footprint_by_biome GROUP BY ALL ORDER BY year, hectares DESC
    """,
    "footprint_by_state_year": """
        SELECT f.year, m.nm_state, f.demand, round(sum(f.hectares)) AS hectares
        FROM footprint_country f JOIN dim_municipality m USING (co_mun)
        GROUP BY ALL ORDER BY year, hectares DESC
    """,
    "national_soy_balance_year": """
        SELECT year,
               round(sum(area_harvested_ha))    AS area_harvested_ha,
               round(sum(production_bean_t))    AS production_bean_t,
               round(sum(processed_bean_t))     AS processed_bean_t,
               round(sum(export_bean_t))        AS export_bean_t,
               round(sum(domestic_use_bean_t))  AS domestic_use_bean_t
        FROM v_soy_balance GROUP BY year ORDER BY year
    """,
    "top_municipalities_footprint": """
        SELECT year, co_mun, nm_mun, nm_state, biome, hectares FROM (
          SELECT f.year, f.co_mun, m.nm_mun, m.nm_state, m.biome,
                 round(sum(f.hectares)) AS hectares
          FROM footprint_country f JOIN dim_municipality m USING (co_mun)
          GROUP BY ALL
        ) QUALIFY row_number()
            OVER (PARTITION BY year ORDER BY hectares DESC) <= 100
        ORDER BY year, hectares DESC
    """,
}


def copy(con, select_sql: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    compress = ", COMPRESSION gzip" if path.suffix == ".gz" else ""
    p = str(path).replace("'", "''")
    con.execute(f"COPY ({select_sql}) TO '{p}' (HEADER{compress})")
    print(f"  [ok] {path.relative_to(ROOT)} ({path.stat().st_size / 1e6:.1f} MB)")


def main() -> None:
    skip_big = "--skip-big" in sys.argv
    con = duckdb.connect(str(DB), read_only=True)

    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM duckdb_tables() ORDER BY estimated_size"
    ).fetchall()]

    print("== tables ==")
    for t in tables:
        if t in BIG:
            continue
        copy(con, f"SELECT * FROM {t}", OUT / f"{t}.csv")

    print("== summaries ==")
    for name, sql in SUMMARIES.items():
        copy(con, sql, OUT / "summaries" / f"{name}.csv")

    if not skip_big:
        print("== big tables (per year, gzipped) ==")
        for t in BIG:
            years = [r[0] for r in con.execute(
                f"SELECT DISTINCT year FROM {t} ORDER BY year").fetchall()]
            for y in years:
                copy(con, f"SELECT * FROM {t} WHERE year = {y}",
                     OUT / t / f"{t}_{y}.csv.gz")

    con.close()
    total = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file())
    print(f"\ncsv layer: {OUT} ({total / 1e6:.0f} MB)")


if __name__ == "__main__":
    main()

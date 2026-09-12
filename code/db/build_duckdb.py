#!/usr/bin/env python3
"""SOYPRINT results database - stage 2: assemble data/db/soyprint.duckdb.

Reads the hive-partitioned Parquet written by code/db/export_parquet.R plus the
FABIO code lists, materialises everything into a single self-contained DuckDB
file (fact tables + dimensions + analysis views), and runs QA checks.

Usage:
    .venv/bin/python code/db/build_duckdb.py            # build + QA
    .venv/bin/python code/db/build_duckdb.py --qa-only  # QA on existing db
"""

import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "data/db/soyprint.duckdb"

# SQL-escaped path literals (the repo path contains an apostrophe)
PQ = str(ROOT / "data/db/parquet").replace("'", "''")
FABIO_INST = str(ROOT / "data/fabio/v2/inst").replace("'", "''")

FACTS = [
    "production", "domestic_use", "trade", "export_attribution",
    "transport_flows", "footprint_country", "footprint_product",
    "footprint_animal_country",
]

# cleaned pipeline inputs (steps 00-03), exported by export_inputs_parquet.R;
# hive-partitioned by year like the facts
INPUTS = [
    "input_municipality", "input_trade", "input_cbs_national",
    "input_livestock_systems", "input_feed",
]
# once-only input tables (year column, no partition)
INPUTS_FLAT = ["input_faostat_trade"]

# EXIOBASE rest-of-world aggregates that appear as nonfood consumer codes
ROW_REGIONS = {
    "WA": "RoW Asia and Pacific", "WE": "RoW Europe", "WF": "RoW Africa",
    "WL": "RoW America", "WM": "RoW Middle East",
}

ENDUSE_SQL = """
    CASE
      WHEN "group" IN ('Meat','Milk','Eggs','Live animals','Animal fats',
                       'Hides, skins, wool','Honey')
           OR comm_group IN ('Meat','Milk','Eggs','Live animals','Animal fats',
                       'Hides, skins, wool','Honey')
        THEN 'Animal products (meat/dairy/eggs)'
      WHEN comm_group IN ('Oil crops','Vegetable oils','Oil cakes')
        THEN 'Soybeans, meal & oil (commodity)'
      ELSE 'Other food'
    END
"""


def build(con: duckdb.DuckDBPyConnection) -> None:
    # ---- dimensions --------------------------------------------------------
    con.execute(f"""
        CREATE OR REPLACE TABLE dim_municipality AS
        SELECT * FROM read_parquet('{PQ}/dims/dim_municipality/data.parquet')
    """)

    # FABIO maps some historical splits (China/Taiwan, Sudan/South Sudan,
    # Ethiopia/PDR) to one current iso3c - keep one row per code (the `current`
    # one) so country joins don't fan out.
    con.execute(f"""
        CREATE OR REPLACE TABLE dim_country AS
        SELECT iso3c, name, continent, region, eu27 FROM (
          SELECT iso3c, name, continent, region, EU27 AS eu27,
                 row_number() OVER (PARTITION BY iso3c
                   ORDER BY "current" DESC, code) AS rn
          FROM read_csv_auto('{FABIO_INST}/regions_full.csv', header=true)
        ) WHERE rn = 1
        UNION ALL
        SELECT code, name, NULL, 'Rest of World', false
        FROM (VALUES {", ".join(f"('{k}', '{v}')" for k, v in ROW_REGIONS.items())})
             AS t(code, name)
    """)

    con.execute(f"""
        CREATE OR REPLACE TABLE dim_commodity AS
        SELECT comm_code, item_code, item, comm_group, "group",
               {ENDUSE_SQL} AS enduse_bucket
        FROM read_csv_auto('{FABIO_INST}/items_full.csv', header=true)
    """)

    con.execute("""
        CREATE OR REPLACE TABLE dim_soy_product AS
        SELECT * FROM (VALUES
          ('bean', 1201, 2555, 'Soybeans (raw beans)'),
          ('oil',  1507, 2571, 'Soybean oil'),
          ('cake', 2304, 2590, 'Soybean cake/meal')
        ) AS t(product, hs4, fabio_item_code, description)
    """)

    # ---- facts + inputs (materialised so the .duckdb is self-contained) ----
    # union_by_name: some input years have extra/missing columns (e.g. the
    # CBS dom_supply_side/dom_use_side diagnostics absent in 2023)
    for tbl in FACTS + INPUTS:
        con.execute(f"""
            CREATE OR REPLACE TABLE {tbl} AS
            SELECT * FROM read_parquet(
                '{PQ}/{tbl}/year=*/data.parquet', hive_partitioning = true,
                union_by_name = true)
        """)
        n = con.execute(f"SELECT count(*) FROM {tbl}").fetchone()[0]
        print(f"  [ok] {tbl}: {n:,} rows")

    for tbl in INPUTS_FLAT:
        con.execute(f"""
            CREATE OR REPLACE TABLE {tbl} AS
            SELECT * FROM read_parquet('{PQ}/{tbl}/data.parquet')
        """)
        n = con.execute(f"SELECT count(*) FROM {tbl}").fetchone()[0]
        print(f"  [ok] {tbl}: {n:,} rows")

    # ---- meta ---------------------------------------------------------------
    con.execute(f"""
        CREATE OR REPLACE TABLE meta_provenance AS
        SELECT * FROM read_parquet('{PQ}/meta/provenance.parquet')
    """)
    git = lambda *a: subprocess.run(("git", "-C", str(ROOT)) + a,
        capture_output=True, text=True).stdout.strip()
    con.execute("""
        CREATE OR REPLACE TABLE meta_build AS
        SELECT ? AS built_at, ? AS git_commit, ? AS git_branch, ? AS duckdb_version
    """, [datetime.now(timezone.utc).isoformat(timespec="seconds"),
          git("rev-parse", "--short", "HEAD"), git("branch", "--show-current"),
          duckdb.__version__])

    # ---- analysis views -----------------------------------------------------
    con.execute("""
        CREATE OR REPLACE VIEW v_footprint_by_country AS
        SELECT f.year, f.co_mun, f.consumer_code AS iso3, c.name AS country,
               c.region, c.continent, f.demand, f.hectares
        FROM footprint_country f
        LEFT JOIN dim_country c ON f.consumer_code = c.iso3c
    """)

    con.execute("""
        CREATE OR REPLACE VIEW v_footprint_by_enduse AS
        SELECT f.year, f.co_mun,
               CASE WHEN f.product_family = 'exiobase'
                    THEN 'Non-food / industrial' ELSE d.enduse_bucket
               END AS enduse_bucket,
               f.product_family, f.product_code, d.item, f.hectares
        FROM footprint_product f
        LEFT JOIN dim_commodity d
          ON f.product_family = 'fabio' AND f.product_code = d.comm_code
    """)

    con.execute("""
        CREATE OR REPLACE VIEW v_footprint_by_biome AS
        SELECT f.year, m.biome, m.matopiba, f.demand,
               sum(f.hectares) AS hectares
        FROM footprint_country f
        JOIN dim_municipality m USING (co_mun)
        GROUP BY ALL
    """)

    con.execute("""
        CREATE OR REPLACE VIEW v_soy_balance AS
        SELECT p.year, p.co_mun, m.nm_mun, m.nm_state, m.biome,
               p.area_harvested_ha, p.production_bean_t, p.processed_bean_t,
               coalesce(e.export_t, 0)  AS export_bean_t,
               coalesce(u.domestic_use_t, 0) AS domestic_use_bean_t
        FROM production p
        JOIN dim_municipality m USING (co_mun)
        LEFT JOIN (SELECT year, co_mun, sum(tonnes) AS export_t
                   FROM trade WHERE flow = 'export' AND product = 'bean'
                   GROUP BY ALL) e USING (year, co_mun)
        LEFT JOIN (SELECT year, co_mun, sum(tonnes) AS domestic_use_t
                   FROM domestic_use WHERE product = 'bean'
                   GROUP BY ALL) u USING (year, co_mun)
    """)


def qa(con: duckdb.DuckDBPyConnection) -> None:
    print("\n== QA ==")
    rows = con.execute("""
        SELECT year,
               round(sum(hectares) FILTER (demand = 'food')    / 1e6, 2) AS food_mha,
               round(sum(hectares) FILTER (demand = 'nonfood') / 1e6, 2) AS nonfood_mha
        FROM footprint_country GROUP BY year ORDER BY year
    """).fetchall()
    print("footprint (Mha) by year [food / nonfood]:")
    for y, f, nf in rows:
        print(f"  {y}: {f} / {nf}")

    checks = {
        "footprint_country vs footprint_product total ha mismatch (years)": """
            SELECT count(*) FROM (
              SELECT c.year FROM
                (SELECT year, sum(hectares) h FROM footprint_country GROUP BY year) c
              JOIN (SELECT year, sum(hectares) h FROM footprint_product GROUP BY year) p
              USING (year) WHERE abs(c.h - p.h) / c.h > 1e-6)
        """,
        "footprint consumer codes not in dim_country": """
            SELECT count(DISTINCT consumer_code) FROM footprint_country
            WHERE consumer_code NOT IN (SELECT iso3c FROM dim_country)
        """,
        "trade partners not in dim_country": """
            SELECT count(DISTINCT partner_iso3) FROM trade
            WHERE partner_iso3 NOT IN (SELECT iso3c FROM dim_country)
        """,
        "fact municipalities missing from dim_municipality": """
            SELECT count(DISTINCT co_mun) FROM footprint_country
            WHERE co_mun NOT IN (SELECT co_mun FROM dim_municipality)
        """,
        "municipalities without biome (excl. undeclared placeholders)": """
            SELECT count(*) FROM dim_municipality
            WHERE biome IS NULL AND co_mun < 9000000
        """,
        "duplicate iso3c in dim_country (fans out country joins)": """
            SELECT count(*) FROM (SELECT iso3c FROM dim_country
              GROUP BY iso3c HAVING count(*) > 1)
        """,
        "duplicate co_mun in dim_municipality": """
            SELECT count(*) FROM (SELECT co_mun FROM dim_municipality
              GROUP BY co_mun HAVING count(*) > 1)
        """,
        "input_municipality co_mun missing from dim_municipality": """
            SELECT count(DISTINCT co_mun) FROM input_municipality
            WHERE co_mun NOT IN (SELECT co_mun FROM dim_municipality)
        """,
        "input_trade partners not in dim_country": """
            SELECT count(DISTINCT partner_iso3) FROM input_trade
            WHERE partner_iso3 NOT IN (SELECT iso3c FROM dim_country)
        """,
        "input products not in dim_soy_product": """
            SELECT count(*) FROM (
              SELECT product FROM input_trade
              UNION SELECT product FROM input_cbs_national
              UNION SELECT product FROM input_faostat_trade)
            WHERE product NOT IN (SELECT product FROM dim_soy_product)
        """,
    }
    for label, sql in checks.items():
        n = con.execute(sql).fetchone()[0]
        print(f"  {'[ok]' if n == 0 else '[!!]'} {label}: {n}")

    print("\nyears per table:")
    for tbl in FACTS + INPUTS:
        lo, hi, n = con.execute(
            f"SELECT min(year), max(year), count(DISTINCT year) FROM {tbl}"
        ).fetchone()
        print(f"  {tbl}: {lo}-{hi} ({n} years)")


if __name__ == "__main__":
    DB.parent.mkdir(parents=True, exist_ok=True)
    if "--qa-only" not in sys.argv:
        DB.unlink(missing_ok=True)  # rebuild from scratch: duckdb files never shrink
    con = duckdb.connect(str(DB))
    if "--qa-only" not in sys.argv:
        build(con)
    qa(con)
    con.close()
    print(f"\ndatabase: {DB} ({DB.stat().st_size / 1e6:.1f} MB)")

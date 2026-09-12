"""Step 01 — Consumption & processing allocation   [PYTHON PORT — WORKING, validated vs R]

R reference : code/new/01_consumption_and_processing.R
Purpose     : Allocate national processing, food, other (biodiesel), seed and stock use to
              municipalities using municipal proxies (crush capacity, oil acquisition,
              biodiesel capacity, storage capacity), and derive municipal oil/cake production.

Inputs      : results/outputs/00_{Y}/parquet/SOY_MUN_00.parquet, CBS_SOY.parquet
              -> from:  Rscript code/python/export_for_py.R {Y}
Outputs     : results/outputs/01_{Y}/parquet/SOY_MUN_01_py.parquet
Port status : WORKING — the 8 allocated columns validated against the R SOY_MUN_01.
Not ported  : the GEO_MUN_SOY_01 spatial merge (needs geopandas).

Usage       : Rscript code/python/export_for_py.R 2013
              python  code/python/01_consumption_and_processing.py 2013
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pandas as pd
import _helpers as H

NEW_COLS = ["proc_bean", "prod_oil", "prod_cake", "food_bean", "food_oil",
            "other_oil", "seed_bean", "stock_bean"]


def main(year: int) -> None:
    p00 = H.OUTPUTS / f"00_{year}" / "parquet" / "SOY_MUN_00.parquet"
    pcbs = H.OUTPUTS / f"00_{year}" / "parquet" / "CBS_SOY.parquet"
    if not (p00.exists() and pcbs.exists()):
        raise SystemExit(f"Missing inputs. Run: Rscript code/python/export_for_py.R {year}")

    soy = pd.read_parquet(p00).copy()
    cbs = pd.read_parquet(pcbs).set_index(".rowname")

    # ── processing ────────────────────────────────────────────────────────────
    proc_days = cbs.loc["bean", "processing"] / soy["proc_cap"].sum()          # na.rm
    cake_conv = cbs.loc["cake", "production"] / cbs.loc["bean", "processing"]
    oil_conv = cbs.loc["oil", "production"] / cbs.loc["bean", "processing"]
    soy["proc_bean"] = soy["proc_cap"] * proc_days
    soy["prod_oil"] = soy["proc_bean"] * oil_conv
    soy["prod_cake"] = soy["proc_bean"] * cake_conv

    # ── food use (proxy: per-capita oil acquisition × population) ─────────────
    oil_acq = soy["oil_acq_pc"] * soy["population"]
    tot = oil_acq.sum(skipna=False)                                            # R: no na.rm
    soy["food_bean"] = oil_acq / tot * cbs.loc["bean", "food"]
    soy["food_oil"] = oil_acq / tot * cbs.loc["oil", "food"]

    # ── other use (proxy: soy-biodiesel capacity) ─────────────────────────────
    soy["other_oil"] = soy["diesel_cap_soy"] / soy["diesel_cap_soy"].sum(skipna=False) * cbs.loc["oil", "other"]

    # ── seed use (proxy: soybean production) ──────────────────────────────────
    seed_share = cbs.loc["bean", "seed"] / soy["prod_bean"].sum()              # na.rm
    soy["seed_bean"] = soy["prod_bean"] * seed_share

    # ── stock addition (proxy: storage capacity) ──────────────────────────────
    soy["stock_bean"] = soy["storage_cap"] / soy["storage_cap"].sum() * cbs.loc["bean", "stock_addition"]

    out = H.out_dir("01", year) / "parquet"
    out.mkdir(parents=True, exist_ok=True)
    soy.to_parquet(out / "SOY_MUN_01_py.parquet", index=False)
    print(f"[01] wrote SOY_MUN_01_py ({len(soy)} muns) → {out}")
    print(f"[01] proc_bean total={soy['proc_bean'].sum():,.0f} "
          f"(CBS processing={cbs.loc['bean','processing']:,.0f})")

    # ── validate against the R SOY_MUN_01 ─────────────────────────────────────
    rref = out / "SOY_MUN_01.parquet"
    if rref.exists():
        r = pd.read_parquet(rref)
        m = soy[["co_mun"] + NEW_COLS].merge(r[["co_mun"] + NEW_COLS], on="co_mun", suffixes=("_py", "_r"))
        worst = max((m[f"{c}_py"] - m[f"{c}_r"]).abs().max() for c in NEW_COLS)
        print(f"[01] validate {len(NEW_COLS)} allocated columns vs R: max |Δ| = {worst:.3e}")
        print("[01] ✓ matches R" if worst < 1e-2 else "[01] ✗ differs from R")
    else:
        print(f"[01] (no R reference at {rref} — run export_for_py.R for validation)")


if __name__ == "__main__":
    main(H.parse_year())

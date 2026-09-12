"""Step 05 — Supply/demand balancing   [PYTHON PORT — WORKING, validated vs R]

R reference : code/new/05_balancing.R
Purpose     : Balance the national CBS, harmonize municipal supply/use to the national FAO
              totals, and compute per-product total/excess supply & demand and domestic use.
              (The key output, SOY_MUN_fin, feeds the transport step.)

Inputs      : results/outputs/03_{Y}/parquet/SOY_MUN_03.parquet   (or SOY_MUN_03_R.parquet)
              results/outputs/00_{Y}/parquet/CBS_SOY.parquet
              -> from:  Rscript code/python/export_for_py.R {Y}   (+ step 03 python output)
Outputs     : results/outputs/05_{Y}/parquet/SOY_MUN_fin_py.parquet
Port status : WORKING — total/excess/domestic columns validated against the R SOY_MUN_fin.
Not ported  : the EXP/IMP_MUN_SOY rescaling and the GEO_MUN_SOY_fin spatial merge (secondary
              outputs; the spatial join needs geopandas). Core balancing is complete.

Usage       : Rscript code/python/export_for_py.R 2013
              python  code/python/03_feed_use.py 2013
              python  code/python/05_balancing.py 2013
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import pandas as pd
import _helpers as H

# columns rescaled to the national totals (order matters — must align with FAO targets)
CBS_COLS = ["prod_bean", "prod_oil", "prod_cake",
            "imp_bean", "imp_oil", "imp_cake",
            "exp_bean", "exp_oil", "exp_cake",
            "food_bean", "food_oil", "feed_bean", "feed_cake", "seed_bean",
            "other_oil", "proc_bean", "stock_bean", "stock_oil", "stock_cake"]


def main(year: int) -> None:
    p03 = H.OUTPUTS / f"03_{year}" / "parquet" / "SOY_MUN_03.parquet"
    if not p03.exists():
        p03 = H.OUTPUTS / f"03_{year}" / "parquet" / "SOY_MUN_03_R.parquet"
    p00 = H.OUTPUTS / f"00_{year}" / "parquet" / "CBS_SOY.parquet"
    if not (p03.exists() and p00.exists()):
        raise SystemExit(f"Missing inputs. Run: Rscript code/python/export_for_py.R {year} "
                         f"and python code/python/03_feed_use.py {year}")

    soy = pd.read_parquet(p03).copy()
    cbs = pd.read_parquet(p00).set_index(".rowname")

    # ── balance the national CBS ──────────────────────────────────────────────
    use_cols = ["export", "food", "feed", "seed", "processing", "other", "stock_addition"]
    cbs["total_supply"] = cbs["production"] + cbs["import"]
    cbs["total_use"] = cbs[use_cols].sum(axis=1)
    cbs["stock_addition"] = cbs["stock_addition"] + (cbs["total_supply"] - cbs["total_use"])
    cbs["stock_withdrawal"] = -cbs["stock_addition"]
    cbs = cbs.loc[["bean", "oil", "cake"]]
    # FAO 2014+: roll oil "processing" into "other", cake "processing" into "feed"
    if pd.notna(cbs.loc["oil", "processing"]) and cbs.loc["oil", "processing"] != 0:
        cbs.loc["oil", "other"] += cbs.loc["oil", "processing"]; cbs.loc["oil", "processing"] = 0
    if pd.notna(cbs.loc["cake", "processing"]) and cbs.loc["cake", "processing"] != 0:
        cbs.loc["cake", "feed"] += cbs.loc["cake", "processing"]; cbs.loc["cake", "processing"] = 0

    # ── allocate oil/cake stock to municipalities by production share ─────────
    soy["stock_oil"] = cbs.loc["oil", "stock_addition"] * soy["prod_oil"] / soy["prod_oil"].sum()
    soy["stock_cake"] = cbs.loc["cake", "stock_addition"] * soy["prod_cake"] / soy["prod_cake"].sum()

    # ── harmonize municipal values to national FAO totals ─────────────────────
    fao = np.array([
        cbs.loc["bean", "production"], cbs.loc["oil", "production"], cbs.loc["cake", "production"],
        cbs.loc["bean", "import"], cbs.loc["oil", "import"], cbs.loc["cake", "import"],
        cbs.loc["bean", "export"], cbs.loc["oil", "export"], cbs.loc["cake", "export"],
        cbs.loc["bean", "food"], cbs.loc["oil", "food"],
        cbs.loc["bean", "feed"], cbs.loc["cake", "feed"],
        cbs.loc["bean", "seed"],
        cbs.loc["oil", "other"],
        cbs.loc["bean", "processing"],
        cbs.loc["bean", "stock_addition"], cbs.loc["oil", "stock_addition"], cbs.loc["cake", "stock_addition"],
    ], dtype=float)
    mun = soy[CBS_COLS].to_numpy(dtype=float).sum(axis=0)
    with np.errstate(divide="ignore", invalid="ignore"):
        ratio = fao / mun
    ratio[~np.isfinite(ratio)] = 1.0   # 0/0 → 1 (Stefan-bug fix)
    soy[CBS_COLS] = soy[CBS_COLS].to_numpy(dtype=float) * ratio   # column-wise rescale

    bal = max(abs(soy[CBS_COLS].sum().to_numpy() - fao))
    print(f"[05] harmonized — max |MUN_total - FAO| after rescale = {bal:.3e}")

    # ── totals, excess supply/demand, domestic use ───────────────────────────
    soy["total_supply_bean"] = soy["prod_bean"] + soy["imp_bean"]
    soy["total_supply_oil"] = soy["prod_oil"] + soy["imp_oil"]
    soy["total_supply_cake"] = soy["prod_cake"] + soy["imp_cake"]
    soy["total_use_bean"] = soy[["exp_bean", "food_bean", "feed_bean", "seed_bean", "proc_bean", "stock_bean"]].sum(axis=1)
    soy["total_use_oil"] = soy[["exp_oil", "food_oil", "other_oil", "stock_oil"]].sum(axis=1)
    soy["total_use_cake"] = soy[["exp_cake", "feed_cake", "stock_cake"]].sum(axis=1)
    for prod in ("bean", "oil", "cake"):
        diff = soy[f"total_supply_{prod}"] - soy[f"total_use_{prod}"]
        soy[f"excess_supply_{prod}"] = diff.clip(lower=0)
        soy[f"excess_use_{prod}"] = (-diff).clip(lower=0)
        soy[f"domestic_use_{prod}"] = soy[f"total_use_{prod}"] - soy[f"exp_{prod}"]

    out = H.out_dir("05", year) / "parquet"
    out.mkdir(parents=True, exist_ok=True)
    soy.to_parquet(out / "SOY_MUN_fin_py.parquet", index=False)
    print(f"[05] wrote SOY_MUN_fin_py ({len(soy)} muns) → {out}")

    # ── validate against the R SOY_MUN_fin ────────────────────────────────────
    rref = out / "SOY_MUN_fin.parquet"
    if rref.exists():
        r = pd.read_parquet(rref)
        cols = [c for c in soy.columns if c.startswith(("total_supply_", "total_use_",
                                                        "excess_supply_", "excess_use_", "domestic_use_"))]
        m = soy[["co_mun"] + cols].merge(r[["co_mun"] + cols], on="co_mun", suffixes=("_py", "_r"))
        worst = 0.0
        for c in cols:
            d = (m[f"{c}_py"] - m[f"{c}_r"]).abs().max()
            worst = max(worst, d)
        print(f"[05] validate {len(cols)} balancing columns vs R: max |Δ| = {worst:.3e}")
        print("[05] ✓ matches R" if worst < 1e-2 else "[05] ✗ differs from R")
    else:
        print(f"[05] (no R reference at {rref} — run export_for_py.R for validation)")


if __name__ == "__main__":
    main(H.parse_year())

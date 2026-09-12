"""Step 03 — Feed-use estimation   [PYTHON PORT — WORKING, validated vs R]

R reference : code/new/03_feed_use.R
Purpose     : Estimate soybean & cake feed use per municipality from per-system animal
              numbers (step 02) × FAO feed ratios, then rescale to the national CBS feed total.

Inputs      : results/outputs/02_{Y}/parquet/SOY_MUN_02.parquet   (per-system animal numbers)
              results/outputs/00_{Y}/parquet/CBS_SOY.parquet      (national CBS, feed column)
              data/new/03/Feed_ratios_FAO.xlsx  (sheet 2)
              -> the two parquet inputs come from:  Rscript code/python/export_for_py.R {Y}
Outputs     : results/outputs/03_{Y}/parquet/{SOY_MUN_03,bean_feed_t,cake_feed_t}.parquet
Port status : WORKING — feed_bean/feed_cake validated against the R output (max abs diff ~0).

Notes       : faithful port of the R logic incl. the na.rm feed-scaling fix (a single NA
              placeholder municipality can't poison the totals). If the R reference
              (SOY_MUN_03_R.parquet, from export_for_py.R) is present, it self-validates.

Usage       : Rscript code/python/export_for_py.R 2013        # one-time: parquet inputs + R ref
              python  code/python/03_feed_use.py 2013
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import pandas as pd
import _helpers as H

DM_CONTENT = 0.88  # dry-matter content (EMBRAPA), same for bean and cake


def main(year: int) -> None:
    p02 = H.OUTPUTS / f"02_{year}" / "parquet" / "SOY_MUN_02.parquet"
    p00 = H.OUTPUTS / f"00_{year}" / "parquet" / "CBS_SOY.parquet"
    if not (p02.exists() and p00.exists()):
        raise SystemExit(
            f"Missing parquet inputs. First run:  Rscript code/python/export_for_py.R {year}\n"
            f"  expected: {p02}\n            {p00}")

    soy = pd.read_parquet(p02)
    cbs = pd.read_parquet(p00).set_index(".rowname")
    fr = pd.read_excel(H.DATA_NEW / "03" / "Feed_ratios_FAO.xlsx", sheet_name=1)  # sheet 2

    # feed ratios → wet-matter intake per animal per year, in tonnes (mirror R)
    fr["bean_t"] = (fr["DM"] * fr["bean"] / 100.0 / DM_CONTENT) / 1000.0
    fr["cake_t"] = (fr["DM"] * fr["cake"] / 100.0 / DM_CONTENT) / 1000.0
    systems = fr["system_name"].tolist()

    # feed per municipality per system = animals[mu, sys] * intake[sys] (column-wise)
    A = soy[systems].to_numpy(dtype=float)                      # (n_mu, n_sys)
    bean_t = fr.set_index("system_name").loc[systems, "bean_t"].to_numpy()
    cake_t = fr.set_index("system_name").loc[systems, "cake_t"].to_numpy()
    bean_feed = A * bean_t                                      # broadcast over columns
    cake_feed = A * cake_t

    # rescale to national CBS feed (na.rm)
    bean_feed_fin = bean_feed * (float(cbs.loc["bean", "feed"]) / np.nansum(bean_feed))
    cake_feed_fin = cake_feed * (float(cbs.loc["cake", "feed"]) / np.nansum(cake_feed))

    soy = soy.copy()
    soy["feed_bean"] = np.nansum(bean_feed_fin, axis=1)
    soy["feed_cake"] = np.nansum(cake_feed_fin, axis=1)

    out = H.out_dir("03", year) / "parquet"
    out.mkdir(parents=True, exist_ok=True)
    soy.to_parquet(out / "SOY_MUN_03.parquet", index=False)
    pd.DataFrame(bean_feed_fin, columns=systems).assign(co_mun=soy["co_mun"].to_numpy()) \
        .to_parquet(out / "bean_feed_t.parquet", index=False)
    pd.DataFrame(cake_feed_fin, columns=systems).assign(co_mun=soy["co_mun"].to_numpy()) \
        .to_parquet(out / "cake_feed_t.parquet", index=False)
    print(f"[03] wrote SOY_MUN_03 ({len(soy)} muns) → {out}")
    print(f"[03] feed_bean total = {soy['feed_bean'].sum():,.2f}  "
          f"feed_cake total = {soy['feed_cake'].sum():,.2f}")

    # ── validate against the R output if present ──────────────────────────────
    rref = out / "SOY_MUN_03_R.parquet"
    if rref.exists():
        r = pd.read_parquet(rref)[["co_mun", "feed_bean", "feed_cake"]]
        m = soy[["co_mun", "feed_bean", "feed_cake"]].merge(r, on="co_mun", suffixes=("_py", "_r"))
        for col in ("feed_bean", "feed_cake"):
            d = (m[f"{col}_py"] - m[f"{col}_r"]).abs()
            denom = m[f"{col}_r"].abs().max() or 1.0
            print(f"[03] validate {col}: max|Δ| = {d.max():.3e}  "
                  f"(rel {d.max()/denom:.2e})  corr = {m[f'{col}_py'].corr(m[f'{col}_r']):.6f}")
        print("[03] ✓ matches R" if max(
            (m["feed_bean_py"] - m["feed_bean_r"]).abs().max(),
            (m["feed_cake_py"] - m["feed_cake_r"]).abs().max()) < 1e-3 else "[03] ✗ differs from R")
    else:
        print(f"[03] (no R reference at {rref} — run export_for_py.R to enable validation)")


if __name__ == "__main__":
    main(H.parse_year())

"""Step 00_FAO — FAO CBS consistency checks   [PYTHON PORT — WORKING, validated vs R]

R reference : code/new/00_FAO_consitency_checks.R
Purpose     : Format the raw FAOSTAT commodity-balance sheet into the national CBS_SOY table
              (the structural reference for steps 01 & 05) and build a MU-vs-FAO consistency table.

Inputs      : data/new/00/new/FAO_CBS/CBS_SOY_{Y}_FAO.xlsx   (raw FAOSTAT export)
              results/outputs/00_{Y}/parquet/SOY_MUN_00.parquet  (from export_for_py.R)
Outputs     : results/outputs/00_{Y}/parquet/{CBS_SOY_py,FAO_consistency_py}.parquet
Port status : WORKING — CBS_SOY + consistency table validated against R.

Usage : Rscript code/python/export_for_py.R 2013 ; python code/python/00_FAO_consitency_checks.py 2013
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import pandas as pd
import _helpers as H

ITEMS = ["domestic_supply", "production", "export", "import", "food",
         "feed", "seed", "other", "processing", "stock_withdrawal"]


def main(year: int) -> None:
    xlsx = H.DATA_NEW / "00" / "new" / "FAO_CBS" / f"CBS_SOY_{year}_FAO.xlsx"
    p00 = H.OUTPUTS / f"00_{year}" / "parquet" / "SOY_MUN_00.parquet"
    if not xlsx.exists():
        raise SystemExit(f"Missing raw FAO CBS: {xlsx}")

    # ── format the raw FAOSTAT CBS ────────────────────────────────────────────
    # header row = the year row; 13 data rows: [0]=product names, [1]=units,
    # [2:12]=the 10 Brazil items, [12]=FAO-url footer. Columns 5/4/3 = bean/oil/cake.
    raw = pd.read_excel(xlsx, header=0)
    body = raw.iloc[2:12]
    vals = body.iloc[:, [4, 3, 2]].apply(pd.to_numeric, errors="coerce")
    vals.columns = ["bean", "oil", "cake"]
    vals.index = ITEMS
    cbs = vals.T.fillna(0.0)                       # rows bean/oil/cake, cols = items
    cbs["stock_addition"] = -cbs["stock_withdrawal"]
    cbs["dom_supply_side"] = cbs["production"] - cbs["export"] + cbs["import"] + cbs["stock_withdrawal"]
    cbs["dom_use_side"] = cbs["food"] + cbs["feed"] + cbs["other"] + cbs["processing"] + cbs["seed"]

    out = H.out_dir("00", year) / "parquet"
    out.mkdir(parents=True, exist_ok=True)
    cbs.reset_index(names=".rowname").to_parquet(out / "CBS_SOY_py.parquet", index=False)
    print(f"[00_FAO] CBS_SOY: bean prod={cbs.loc['bean','production']:,.0f} "
          f"bean feed={cbs.loc['bean','feed']:,.0f} cake feed={cbs.loc['cake','feed']:,.0f}")

    # ── MU-vs-FAO consistency table ───────────────────────────────────────────
    if p00.exists():
        soy = pd.read_parquet(p00)
        s = lambda c: float(soy[c].sum()) if c in soy else np.nan
        cons = pd.DataFrame({
            # R's SOY_MUN$prod partial-matches the only prod* column, prod_bean
            "prod":     [s("prod_bean"), cbs.loc["bean", "production"]],
            "exp_bean": [s("exp_bean"), cbs.loc["bean", "export"]],
            "exp_oil":  [s("exp_oil"),  cbs.loc["oil", "export"]],
            "exp_cake": [s("exp_cake"), cbs.loc["cake", "export"]],
            "imp_bean": [s("imp_bean"), cbs.loc["bean", "import"]],
            "imp_oil":  [s("imp_oil"),  cbs.loc["oil", "import"]],
            "imp_cake": [s("imp_cake"), cbs.loc["cake", "import"]],
            "proc_cap": [s("proc_cap") * 5 * 52, cbs.loc["bean", "processing"]],
            "ref_cap":  [s("ref_cap") * 5 * 52,  cbs.loc["oil", "production"]],
        }, index=["MU_data", "FAO"])
        cons.reset_index(names=".rowname").to_parquet(out / "FAO_consistency_py.parquet", index=False)
    else:
        cons = None
        print(f"[00_FAO] (no SOY_MUN_00 parquet — skipping consistency table)")

    # ── validate against R ────────────────────────────────────────────────────
    rcbs = out / "CBS_SOY.parquet"
    if rcbs.exists():
        r = pd.read_parquet(rcbs).set_index(".rowname")
        common = [c for c in cbs.columns if c in r.columns]
        worst = (cbs[common] - r.loc[cbs.index, common]).abs().to_numpy().max()
        print(f"[00_FAO] validate CBS_SOY ({len(common)} cols) vs R: max |Δ| = {worst:.3e}  "
              f"{'✓' if worst < 1e-3 else '✗'}")
    rcons = out / "FAO_consistency_R.parquet"
    if cons is not None and rcons.exists():
        rc = pd.read_parquet(rcons).set_index(".rowname")
        w = (cons.reset_index(drop=True) - rc.reset_index(drop=True)).abs().to_numpy().max()
        print(f"[00_FAO] validate FAO_consistency vs R: max |Δ| = {w:.3e}  {'✓' if w < 1e-3 else '✗'}")


if __name__ == "__main__":
    main(H.parse_year())

"""Step 04 — Trade harmonization   [PYTHON PORT — WORKING, validated vs R]

R reference : code/new/04_trade_harmonization.R
Purpose     : Harmonize municipal COMEX exports/imports with the FAO/FABIO country sample and
              bilateral trade (BTD), and attach the FAOSTAT trade-matrix reference.

Inputs (parquet via `Rscript code/python/export_for_py.R {Y}`):
  results/outputs/00_{Y}/parquet/{EXP,IMP}_MUN_SOY_00.parquet
  results/outputs/04_{Y}/parquet/{btd_imp_soy,btd_exp_soy,btd_exp_pure_soy}.parquet
  + read directly: data/new/04/PAIS_COMEX.csv, FABIO/FAO_regions_full.csv,
                   FABIO/FABIO_regions.xlsx, FAOSTAT_tradematrix_BRAsoy[_{Y}].csv
Outputs     : results/outputs/04_{Y}/parquet/{EXP_MUN_SOY,IMP_MUN_SOY,EXP_NAT_SOY,IMP_NAT_SOY,regions}_py.parquet
Port status : WORKING — EXP/IMP MU + national tables validated against the R references.

Usage : Rscript code/python/export_for_py.R 2013 ; python code/python/04_trade_harmonization.py 2013
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import pandas as pd
import _helpers as H

SOY = [2555, 2571, 2590]
ITEM = {"soybean": 2555, "soy_oil": 2571, "soy_cake": 2590}
ITEM_INV = {2555: "soybean", 2571: "soy_oil", 2590: "soy_cake"}


def main(year: int) -> None:
    o4 = H.OUTPUTS / f"04_{year}" / "parquet"
    o0 = H.OUTPUTS / f"00_{year}" / "parquet"
    exp = pd.read_parquet(o0 / "EXP_MUN_SOY_00.parquet")
    imp = pd.read_parquet(o0 / "IMP_MUN_SOY_00.parquet")
    btd_imp = pd.read_parquet(o4 / "btd_imp_soy.parquet")
    btd_exp = pd.read_parquet(o4 / "btd_exp_soy.parquet")
    btd_exp_pure = pd.read_parquet(o4 / "btd_exp_pure_soy.parquet")

    d4 = H.DATA_NEW / "04"
    comex = pd.read_csv(d4 / "PAIS_COMEX.csv", sep=";", encoding="ISO-8859-1")
    fao = pd.read_csv(d4 / "FABIO" / "FAO_regions_full.csv")
    fabio = pd.read_excel(d4 / "FABIO" / "FABIO_regions.xlsx")
    tm_year = d4 / f"FAOSTAT_tradematrix_BRAsoy_{year}.csv"
    tm_path = tm_year if tm_year.exists() else d4 / "FABIO" / "FAOSTAT_tradematrix_BRAsoy.csv"
    trade_mat = pd.read_csv(tm_path)

    # ── country harmonization: COMEX ↔ FAO ↔ FABIO/BTD ────────────────────────
    comex["CO_PAIS_ISOA3"] = comex["CO_PAIS_ISOA3"].replace("ZZZ", "ROW")
    comex["CO_PAIS_ISON3"] = comex["CO_PAIS_ISON3"].replace(898, 999)
    fao = fao[~fao["code"].isin([351, 62, 206])]
    regions = comex.merge(fao, how="outer", left_on="CO_PAIS_ISOA3", right_on="iso3c")
    regions["code"] = regions["code"].fillna(999)
    regions = regions.rename(columns={"code": "CO_FAO", "CO_PAIS": "CO_COMEX"})
    regions["CO_FAO"] = regions["CO_FAO"].astype("int64")

    btd_regions = pd.unique(btd_exp["from_code"])
    if len(btd_regions) == 0:
        btd_regions = fabio["FAO.Code"].to_numpy()
    btd_regions = set(int(x) for x in btd_regions)
    regions["CO_BTD"] = np.where(regions["CO_FAO"].isin(btd_regions), regions["CO_FAO"], 999).astype("int64")
    regions["ISO_BTD"] = np.where(regions["CO_BTD"] == 999, "ROW", regions["CO_PAIS_ISOA3"])
    fr = regions["CO_PAIS_ISOA3"].isin(["GLP", "GUF", "MTQ", "REU"])
    regions.loc[fr, "ISO_BTD"] = "FRA"
    regions.loc[fr, "CO_BTD"] = 68

    reg_sel = regions[["CO_COMEX", "CO_BTD", "ISO_BTD"]]

    # ── attach BTD codes, aggregate MU trade to FABIO regions ─────────────────
    exp = exp.merge(reg_sel, how="left", left_on="co_destin", right_on="CO_COMEX") \
             .rename(columns={"CO_BTD": "to_code", "ISO_BTD": "to_name"}).drop(columns=["CO_COMEX"])
    gcols = ["co_mun", "nm_mun", "co_state", "nm_state", "HS4", "product", "to_code", "to_name"]
    exp = exp.groupby(gcols, dropna=False, as_index=False).agg(
        export=("export", "sum"), export_dol=("export_dol", "sum"))

    imp = imp.merge(reg_sel, how="left", left_on="co_origin", right_on="CO_COMEX") \
             .rename(columns={"CO_BTD": "from_code", "ISO_BTD": "from_name"}).drop(columns=["CO_COMEX"])
    gcols_i = ["co_mun", "nm_mun", "co_state", "nm_state", "HS4", "product", "from_code", "from_name"]
    imp = imp.groupby(gcols_i, dropna=False, as_index=False).agg(
        import_=("import", "sum"), import_dol=("import_dol", "sum")).rename(columns={"import_": "import"})

    # item codes
    exp["item_code"] = exp["product"].map(ITEM)
    imp["item_code"] = imp["product"].map(ITEM)

    # ── Brazil soy BTD slices (Brazil FAO code = 21) ──────────────────────────
    def bra(df, side):  # side 'from' (exports) or 'to' (imports)
        return df[(df[f"{side}_code"] == 21) & (df["item_code"].isin(SOY))]
    e_exp = bra(btd_exp, "from"); e_pure = bra(btd_exp_pure, "from"); e_imp = bra(btd_imp, "from")
    i_exp = bra(btd_exp, "to");   i_pure = bra(btd_exp_pure, "to");   i_imp = bra(btd_imp, "to")

    # ── aggregate MU trade to national, merge with BTD ────────────────────────
    exp_nat = exp.groupby(["product", "item_code", "to_code", "to_name"], as_index=False).agg(
        export=("export", "sum"), export_dol=("export_dol", "sum"))
    imp_nat = imp.groupby(["product", "item_code", "from_code", "from_name"], as_index=False).agg(
        import_=("import", "sum"), import_dol=("import_dol", "sum")).rename(columns={"import_": "import"})

    def jexp(nat, b, name):
        return nat.merge(b[["item_code", "to_code", "value"]], how="outer",
                         on=["item_code", "to_code"]).rename(columns={"value": name})
    exp_nat = jexp(exp_nat, e_exp, "export_btd_exp")
    exp_nat = jexp(exp_nat, e_pure, "export_btd_exp_pure")
    exp_nat = jexp(exp_nat, e_imp, "export_btd_imp")

    def jimp(nat, b, name):
        return nat.merge(b[["item_code", "from_code", "value"]], how="outer",
                         on=["item_code", "from_code"]).rename(columns={"value": name})
    imp_nat = jimp(imp_nat, i_exp, "import_btd_exp")
    imp_nat = jimp(imp_nat, i_pure, "import_btd_ex_pure")
    imp_nat = jimp(imp_nat, i_imp, "import_btd_imp")

    # product names + country names for BTD-only rows
    exp_nat["product"] = exp_nat["item_code"].map(ITEM_INV)
    imp_nat["product"] = imp_nat["item_code"].map(ITEM_INV)
    fmap = fabio.set_index("FAO.Code")["ISO"]
    exp_nat["to_name"] = exp_nat["to_code"].map(fmap)
    imp_nat["from_name"] = imp_nat["from_code"].map(fmap)

    # ── FAOSTAT trade matrix → EXP_NAT ────────────────────────────────────────
    tm = trade_mat.copy()
    # pandas keeps the CSV's original headers (spaces/parens), unlike R's read.csv dot-munging
    item_map = {236: "soybean", 237: "soy_oil", 238: "soy_cake"}
    tm["product"] = tm["Item Code"].map(item_map)
    tm = tm[tm["product"].notna()]
    tm = tm.rename(columns={"Partner Country Code (ISO3)": "to_name", "Value": "FAO_trade_mat"})
    tm = tm[["to_name", "product", "FAO_trade_mat"]].copy()
    tm["to_name"] = tm["to_name"].replace("41", "CHN")
    iso_map = regions[["ISO_BTD", "CO_PAIS_ISOA3"]].rename(columns={"CO_PAIS_ISOA3": "to_name"}).drop_duplicates()
    tm = tm.merge(iso_map, how="left", on="to_name")
    tm_agg = tm.groupby(["ISO_BTD", "product"], as_index=False).agg(
        FAO_trade_mat=("FAO_trade_mat", "sum")).rename(columns={"ISO_BTD": "to_name"})
    exp_nat = exp_nat.merge(tm_agg, how="outer", on=["product", "to_name"])

    # replace NA in numeric columns with 0
    for df in (exp_nat, imp_nat):
        num = df.select_dtypes(include="number").columns
        df[num] = df[num].fillna(0)
    exp_nat["comex_fao_diff"] = exp_nat["export"] - exp_nat["FAO_trade_mat"]

    out = H.out_dir("04", year) / "parquet"
    for nm, df in [("EXP_MUN_SOY", exp), ("IMP_MUN_SOY", imp),
                   ("EXP_NAT_SOY", exp_nat), ("IMP_NAT_SOY", imp_nat), ("regions", regions)]:
        df.to_parquet(out / f"{nm}_py.parquet", index=False)
    print(f"[04] wrote EXP/IMP MU + national tables → {out}")

    # ── validate against R references ─────────────────────────────────────────
    _validate(out, exp, imp, exp_nat, imp_nat)


def _validate(out, exp, imp, exp_nat, imp_nat):
    def cmp(py, name, keys, valcols):
        rp = out / f"{name}_R.parquet"
        if not rp.exists():
            print(f"[04] {name}: no R ref"); return
        r = pd.read_parquet(rp)
        # compare per-product totals of each value column (robust to row order/NaN-keys)
        worst = 0.0
        for v in valcols:
            if v not in py or v not in r:
                continue
            a = py.groupby("product")[v].sum().round(3)
            b = r.groupby("product")[v].sum().round(3)
            d = (a - b).abs().reindex(set(a.index) | set(b.index)).fillna(0).max()
            worst = max(worst, float(d))
        print(f"[04] {name}: per-product totals max |Δ| = {worst:.3e}  "
              f"({'✓' if worst < 1.0 else '✗'})  [py {len(py)} rows / R {len(r)}]")

    cmp(exp, "EXP_MUN_SOY", None, ["export", "export_dol"])
    cmp(imp, "IMP_MUN_SOY", None, ["import", "import_dol"])
    cmp(exp_nat, "EXP_NAT_SOY", None, ["export", "export_btd_exp", "export_btd_imp", "FAO_trade_mat"])
    cmp(imp_nat, "IMP_NAT_SOY", None, ["import", "import_btd_exp", "import_btd_imp"])


if __name__ == "__main__":
    main(H.parse_year())

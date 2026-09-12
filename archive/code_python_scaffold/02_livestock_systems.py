"""Step 02 — Livestock systems   [PYTHON PORT — WORKING, validated vs R]

R reference : code/new/02_livestock_systems.R
Purpose     : Split municipal animal numbers (cattle/buffalo/pig/chicken) into FAO production
              systems, using FAO gridded-livestock rasters (coverage-weighted zonal sums) +
              the ruminant-systems raster + the 2006 feedlot census.

Inputs      : results/outputs/01_{Y}/GEO_MUN_SOY_01.gpkg   (polygons + IBGE animal numbers)
              data/new/02/geo/FAO_gridded_livestock/*.tif  (8 rasters)
              data/new/02/FeedlotCattle_2006_tabela919_IBGE.xlsx
              -> run:  Rscript code/python/export_for_py.R {Y}   (writes the gpkg)
Outputs     : results/outputs/02_{Y}/parquet/SOY_MUN_02_systems_py.parquet (co_mun + 15 systems)
Port status : WORKING — the 15 system columns validated against the R SOY_MUN_02.

Deps        : geopandas, rasterio, exactextract (coverage-weighted zonal stats, == R exactextractr).
Usage       : Rscript code/python/export_for_py.R 2013 ; python code/python/02_livestock_systems.py 2013
"""
from __future__ import annotations
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import pandas as pd
import geopandas as gpd
import rasterio
from exactextract import exact_extract
import _helpers as H

RAST = H.DATA_NEW / "02" / "geo" / "FAO_gridded_livestock"
TIF = {"ChExt": "06_ChExt_2010_Da.tif", "ChInt": "07_ChInt_2010_Da.tif",
       "PgExt": "8_PgExt_2010_Da.tif", "PgInt": "9_PgInt_2010_Da.tif", "PgInd": "10_PgInd_2010_Da.tif",
       "Cattle": "5_Ct_2010_Da.tif", "Buffalo": "5_Bf_2010_Da.tif", "RumSys": "glps_gleam_61113_10km.tif"}


def _zsum(tif_path, gdf):
    """coverage-weighted zonal sum per polygon (== R exactextractr 'sum')."""
    return exact_extract(str(tif_path), gdf, ["sum"], output="pandas")["sum"].to_numpy()


def _masked_tif(value_tif, classes, keep_in: bool):
    """Write a temp GeoTIFF = value raster, zeroed where RumSys class NOT in `classes`
    (or IN, if keep_in=False). Mirrors R's `X[!RumSys %in% classes] <- 0`."""
    with rasterio.open(value_tif) as vsrc, rasterio.open(RAST / TIF["RumSys"]) as rsrc:
        v = vsrc.read(1).astype("float64")
        rs = rsrc.read(1)
        prof = vsrc.profile.copy()
        ndv = vsrc.nodata
    mask = np.isin(rs, classes)
    if not keep_in:
        mask = ~mask
    v[~mask] = 0.0                      # zero out non-selected classes (sum-neutral)
    prof.update(dtype="float64", nodata=ndv)
    fd, path = tempfile.mkstemp(suffix=".tif"); os.close(fd)
    with rasterio.open(path, "w", **prof) as dst:
        dst.write(v, 1)
    return path


def _state_fill(df, cols):
    """replace NA shares by state (co_state) mean — R's group_by(co_state) if_else(is.na, mean)."""
    for c in cols:
        df[c] = df.groupby("co_state")[c].transform(lambda s: s.fillna(s.mean()))
    return df


def main(year: int) -> None:
    gpkg = H.OUTPUTS / f"01_{year}" / "GEO_MUN_SOY_01.gpkg"
    if not gpkg.exists():
        raise SystemExit(f"Missing {gpkg}. Run: Rscript code/python/export_for_py.R {year}")
    g = gpd.read_file(gpkg)

    # ── chicken & pig: direct zonal sums ──────────────────────────────────────
    for k in ("ChExt", "ChInt", "PgExt", "PgInt", "PgInd"):
        g[k] = _zsum(RAST / TIF[k], g)

    g["PgExtShare"] = g["PgExt"] / (g["PgExt"] + g["PgInt"] + g["PgInd"])
    g["PgIntShare"] = g["PgInt"] / (g["PgExt"] + g["PgInt"] + g["PgInd"])
    g["PgIndShare"] = g["PgInd"] / (g["PgExt"] + g["PgInt"] + g["PgInd"])
    g["ChExtShare"] = g["ChExt"] / (g["ChExt"] + g["ChInt"])
    g["ChIntShare"] = g["ChInt"] / (g["ChExt"] + g["ChInt"])
    g = _state_fill(g, ["PgExtShare", "PgIntShare", "PgIndShare", "ChExtShare", "ChIntShare"])

    g["pig_byd"] = g["pig"] * g["PgExtShare"]
    g["pig_int"] = g["pig"] * g["PgIntShare"]
    g["pig_ind"] = g["pig"] * g["PgIndShare"]
    g["chicken_byd"] = g["chicken"] * g["ChExtShare"]
    g["chicken_bro"] = np.where(g["chicken_layer"].isna(),
                                g["chicken"] * g["ChIntShare"],
                                (g["chicken"] - g["chicken_layer"]) * g["ChIntShare"])
    g["chicken_lay"] = g["chicken_layer"] * g["ChIntShare"]

    # ── cattle: combine number grid with ruminant-system classes ──────────────
    cg = _masked_tif(RAST / TIF["Cattle"], [1, 2, 3, 4, 14, 15], keep_in=True)   # grass + other + unsuit
    cm = _masked_tif(RAST / TIF["Cattle"], list(range(5, 14)), keep_in=True)      # mixed + urban (5-13)
    g["CattGrass"] = _zsum(cg, g); g["CattMix"] = _zsum(cm, g)
    os.remove(cg); os.remove(cm)
    g["CattGrassShare"] = g["CattGrass"] / (g["CattGrass"] + g["CattMix"])
    g["CattMixShare"] = g["CattMix"] / (g["CattGrass"] + g["CattMix"])
    g = _state_fill(g, ["CattGrassShare", "CattMixShare"])

    # feedlot (2006 census → extrapolate to 2013)
    fl = pd.read_excel(H.DATA_NEW / "02" / "FeedlotCattle_2006_tabela919_IBGE.xlsx",
                       skiprows=5, na_values=["X", "-"])
    fl = fl.iloc[:, [0, 1, 3, 6]].copy()
    fl.columns = ["co_mun", "nm_mun", "cattle_tot", "cattle_flot"]
    fl["co_mun"] = pd.to_numeric(fl["co_mun"], errors="coerce")
    fl["cattle_flot"] = pd.to_numeric(fl["cattle_flot"], errors="coerce")
    fl["cattle_flot"] = (fl["cattle_flot"] * (4.38 / 3.46)).round()
    g = g.merge(fl[["co_mun", "cattle_flot"]], on="co_mun", how="left")
    g["cattle_flot"] = g["cattle_flot"].fillna(0)

    g["cattle_gra_dair"] = g["cattle_milked"] * g["CattGrassShare"]
    g["cattle_mix_dair"] = g["cattle_milked"] * g["CattMixShare"]
    g["cattle_gra_meat"] = (g["cattle"] - g["cattle_milked"] - g["cattle_flot"]) * g["CattGrassShare"]
    g["cattle_mix_meat"] = (g["cattle"] - g["cattle_milked"] - g["cattle_flot"]) * g["CattMixShare"]

    # ── buffalo ───────────────────────────────────────────────────────────────
    bg = _masked_tif(RAST / TIF["Buffalo"], [1, 2, 3, 4, 14, 15], keep_in=True)
    bm = _masked_tif(RAST / TIF["Buffalo"], list(range(5, 14)), keep_in=True)
    g["BuffGrass"] = _zsum(bg, g); g["BuffMix"] = _zsum(bm, g)
    os.remove(bg); os.remove(bm)
    g["BuffGrassShare"] = g["BuffGrass"] / (g["BuffGrass"] + g["BuffMix"])
    g["BuffMixShare"] = g["BuffMix"] / (g["BuffGrass"] + g["BuffMix"])
    g = _state_fill(g, ["BuffGrassShare", "BuffMixShare"])

    g["MilkShare"] = g["cattle_milked"] / g["cattle"]
    g = _state_fill(g, ["MilkShare"])
    g["buffalo_gra_dair"] = g["buffalo"] * g["MilkShare"] * g["BuffGrassShare"]
    g["buffalo_mix_dair"] = g["buffalo"] * g["MilkShare"] * g["BuffMixShare"]
    g["buffalo_gra_meat"] = g["buffalo"] * (1 - g["MilkShare"]) * g["BuffGrassShare"]
    g["buffalo_mix_meat"] = g["buffalo"] * (1 - g["MilkShare"]) * g["BuffMixShare"]

    systems = ["cattle_gra_dair", "cattle_mix_dair", "cattle_gra_meat", "cattle_mix_meat", "cattle_flot",
               "buffalo_gra_dair", "buffalo_mix_dair", "buffalo_gra_meat", "buffalo_mix_meat",
               "pig_byd", "pig_int", "pig_ind", "chicken_byd", "chicken_lay", "chicken_bro"]
    res = g[["co_mun"]].copy()
    for c in systems:
        res[c] = g[c].round(0)   # R rounds livestock numbers to whole heads

    out = H.out_dir("02", year) / "parquet"
    out.mkdir(parents=True, exist_ok=True)
    res.to_parquet(out / "SOY_MUN_02_systems_py.parquet", index=False)
    print(f"[02] wrote {len(systems)} system columns ({len(res)} muns) → {out}")

    # ── validate against R SOY_MUN_02 ─────────────────────────────────────────
    rref = out / "SOY_MUN_02.parquet"
    if rref.exists():
        r = pd.read_parquet(rref)
        m = res.merge(r[["co_mun"] + systems], on="co_mun", suffixes=("_py", "_r"))
        worst, worstcol = 0.0, ""
        for c in systems:
            d = (m[f"{c}_py"] - m[f"{c}_r"]).abs().max()
            if d > worst:
                worst, worstcol = d, c
        print(f"[02] validate {len(systems)} system columns vs R: max |Δ| = {worst:.3e} ({worstcol})")
        print("[02] ✓ matches R" if worst < 1.0 else "[02] ~ close (rounding/edge); see worst column")
    else:
        print(f"[02] (no R reference at {rref})")


if __name__ == "__main__":
    main(H.parse_year())

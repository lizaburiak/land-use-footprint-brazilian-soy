"""Load step-05 + step-06 outputs into Python dicts for the Pyomo model.

Loading priority (per source file):
    1. .parquet  — fastest, no R-binding deps. Generate via
       `Rscript code/pipeline/transport_lp/export_to_parquet.R YEAR`.
    2. .rds / .Rdata via pyreadr — fallback when parquet not present.

The .parquet layout (under data/generated/outputs/05_YYYY/parquet/ and data/generated/outputs/06_YYYY/parquet/):
    SOY_MUN_fin.parquet              ← all SOY_MUN columns + co_mun as str
    stations_orig.parquet, stations_dest.parquet
    ports_orig.parquet,    ports_dest.parquet
    cargo_rail_long.parquet, cargo_water_long.parquet
        cols: orig, dest, product, volume
    {road_dist_MUN,road_dist_MUN_stat,road_dist_MUN_port,
     road_dist_stat_MUN,road_dist_port_MUN,
     rail_dist,water_dist}_long.parquet
        cols: from, to, distance  (NA / negative entries already dropped)
"""
from __future__ import annotations
from pathlib import Path
from typing import Dict, Tuple

import numpy as np
import pandas as pd

try:
    import pyreadr
    HAVE_PYREADR = True
except ImportError:
    HAVE_PYREADR = False


PRODUCTS = ["bean", "oil", "cake"]


# ── Low-level readers ───────────────────────────────────────────────────────
def _read_parquet(path: Path) -> pd.DataFrame:
    return pd.read_parquet(path)


def _read_rds(path: Path) -> pd.DataFrame:
    if not HAVE_PYREADR:
        raise ImportError(
            "pyreadr not installed and no parquet fallback found at the expected path. "
            "Either run `Rscript code/pipeline/transport_lp/export_to_parquet.R YEAR` to produce "
            "parquet files, or install pyreadr."
        )
    res = pyreadr.read_r(str(path))
    if not res:
        raise ValueError(f"{path} contained no R objects")
    return next(iter(res.values()))


def _read_rdata(path: Path) -> Dict[str, pd.DataFrame]:
    if not HAVE_PYREADR:
        raise ImportError(f"pyreadr required to read {path} (or convert via export_to_parquet.R)")
    return dict(pyreadr.read_r(str(path)))


# ── High-level loaders ──────────────────────────────────────────────────────
def load_soy_mun(year: int) -> pd.DataFrame:
    """Load SOY_MUN_fin — per-município supply/demand. Prefers parquet."""
    pq = Path(f"data/generated/outputs/05_{year}/parquet/SOY_MUN_fin.parquet")
    rds = Path(f"data/generated/outputs/05_{year}/SOY_MUN_fin.rds")
    if pq.exists():
        df = _read_parquet(pq)
    elif rds.exists():
        df = _read_rds(rds)
    else:
        raise FileNotFoundError(
            f"Neither {pq} nor {rds} found — run code/new step 05 (and optionally export_to_parquet.R) for {year}"
        )
    df["co_mun"] = df["co_mun"].astype(str)
    return df


def load_step06_artifacts(year: int) -> dict:
    """Load all step-06 outputs. Prefers parquet for everything.

    Returns dict with keys:
        stations_orig, stations_dest, ports_orig, ports_dest,
        cargo_rail_long, cargo_water_long,
        road_dist_MUN, road_dist_MUN_stat, road_dist_MUN_port,
        road_dist_stat_MUN, road_dist_port_MUN,
        rail_dist, water_dist

    Distance matrices come back as 2D pandas DataFrames indexed by node id.
    """
    base = Path(f"data/generated/outputs/06_{year}")
    if not base.exists():
        raise FileNotFoundError(
            f"{base} does not exist — step 06 has not been run for {year}.\n"
            f"For testing without real geometry, use `make_fixture.py` to build a "
            f"synthetic step-06 fixture from SOY_MUN."
        )

    pq_dir = base / "parquet"
    artifacts: dict = {}

    # Try parquet first
    if pq_dir.exists():
        for name in ("stations_orig", "stations_dest", "ports_orig", "ports_dest",
                     "cargo_rail_long", "cargo_water_long"):
            p = pq_dir / f"{name}.parquet"
            if p.exists():
                artifacts[name] = _read_parquet(p)
        for name in ("road_dist_MUN", "road_dist_MUN_stat", "road_dist_MUN_port",
                     "road_dist_stat_MUN", "road_dist_port_MUN",
                     "rail_dist", "water_dist"):
            p = pq_dir / f"{name}_long.parquet"
            if p.exists():
                long_df = _read_parquet(p)
                artifacts[name] = _long_to_dist_matrix(long_df)

    # Fill any gaps from .Rdata via pyreadr
    if not all(k in artifacts for k in ("stations_orig", "stations_dest")):
        artifacts.update(_read_rdata(base / "stations.Rdata"))
    if not all(k in artifacts for k in ("ports_orig", "ports_dest")):
        artifacts.update(_read_rdata(base / "ports.Rdata"))
    if not all(k in artifacts for k in ("cargo_rail_long", "cargo_water_long")):
        artifacts.update(_read_rdata(base / "cargo_long.Rdata"))
    needed_dist = ("road_dist_MUN", "road_dist_MUN_stat", "road_dist_MUN_port",
                   "road_dist_stat_MUN", "road_dist_port_MUN", "rail_dist", "water_dist")
    if not all(k in artifacts for k in needed_dist):
        artifacts.update(_read_rdata(base / "dist_matrices.Rdata"))

    return artifacts


def _long_to_dist_matrix(df: pd.DataFrame) -> pd.DataFrame:
    """Pivot a long-format (from, to, distance) frame to a 2D DataFrame."""
    return (
        df.pivot_table(index="from", columns="to", values="distance", fill_value=np.inf)
        .astype(float)
    )


# ── Assemble Pyomo-ready inputs ─────────────────────────────────────────────
def build_structural_inputs(soy_mun: pd.DataFrame, step06: dict) -> dict:
    """Cost-independent inputs for `model.build_structure`.

    `a` is restricted to municipalities that have positive supply OR demand of
    some product — municipalities with neither carry no flow and only inflate
    the LP. (Per-product supply/demand filtering happens inside build_structure.)
    """
    stations_orig = step06["stations_orig"]
    stations_dest = step06["stations_dest"]
    ports_orig = step06["ports_orig"]
    ports_dest = step06["ports_dest"]

    r1 = stations_orig["CodigoTres"].astype(str).tolist()
    r2 = stations_dest["CodigoTres"].astype(str).tolist()
    w1 = ports_orig["cdi_tuaria"].astype(str).tolist()
    w2 = ports_dest["cdi_tuaria"].astype(str).tolist()

    supply, demand, exp_proc = {}, {}, {}
    relevant = set()  # MUs with any positive supply or demand
    for _, row in soy_mun.iterrows():
        m = str(row["co_mun"])
        sup = {
            "bean": float(row.get("excess_supply_bean", 0) or 0),
            "oil":  float(row.get("excess_supply_oil",  0) or 0),
            "cake": float(row.get("excess_supply_cake", 0) or 0),
        }
        dem = {
            "bean": float(row.get("excess_use_bean", 0) or 0),
            "oil":  float(row.get("excess_use_oil",  0) or 0),
            "cake": float(row.get("excess_use_cake", 0) or 0),
        }
        # Stefan's exp_proc: export + processing for bean; export only for oil/cake
        ep = {
            "bean": float(row.get("exp_bean", 0) or 0) + float(row.get("proc_bean", 0) or 0),
            "oil":  float(row.get("exp_oil",  0) or 0),
            "cake": float(row.get("exp_cake", 0) or 0),
        }
        for p in PRODUCTS:
            if sup[p] > 0:
                supply[(m, p)] = sup[p]
            if dem[p] > 0:
                demand[(m, p)] = dem[p]
            if ep[p] > 0:
                exp_proc[(m, p)] = ep[p]
        if any(v > 0 for v in sup.values()) or any(v > 0 for v in dem.values()):
            relevant.add(m)

    a = sorted(relevant)

    cap_r = _cargo_to_dict(step06["cargo_rail_long"])
    cap_w = _cargo_to_dict(step06["cargo_water_long"])

    return dict(
        products=PRODUCTS,
        a=a, r1=r1, r2=r2, w1=w1, w2=w2,
        supply=supply, demand=demand, exp_proc=exp_proc,
        cap_r=cap_r, cap_w=cap_w,
    )


def build_cost_matrices(step06: dict, cost_params: dict, a_keep=None) -> dict:
    """Build the 7 cost dicts for `model.set_costs` from step-06 distances.

    Mirrors Stefan's R cost construction (07_transport_GAMS_parallel.R:142-156):
    road $/t-km × dist/1000, +m_switch on intermodal road legs, rail short/long
    split at 1000 km, water $/t-km × dist/1000.

    cost_params: dict with c_road, c_rail_short, c_rail_long, c_water, m_switch.
    a_keep: optional set of municipality ids — when given, the dense MU×MU road
        cost (C_a_b) is restricted to that sub-block (the rest carry no flow).
    """
    cp = cost_params
    road_dist_MUN      = _dist_to_dict(step06["road_dist_MUN"], keep_rows=a_keep, keep_cols=a_keep)
    road_dist_MUN_stat = _dist_to_dict(step06["road_dist_MUN_stat"], keep_rows=a_keep)
    road_dist_MUN_port = _dist_to_dict(step06["road_dist_MUN_port"], keep_rows=a_keep)
    road_dist_stat_MUN = _dist_to_dict(step06["road_dist_stat_MUN"], keep_cols=a_keep)
    road_dist_port_MUN = _dist_to_dict(step06["road_dist_port_MUN"], keep_cols=a_keep)
    rail_dist          = _dist_to_dict(step06["rail_dist"])
    water_dist         = _dist_to_dict(step06["water_dist"])

    C_a_b = {k: cp["c_road"] * v / 1000.0 for k, v in road_dist_MUN.items()}
    C_a_r1 = {k: cp["c_road"] * v / 1000.0 + cp["m_switch"] for k, v in road_dist_MUN_stat.items()}
    C_a_w1 = {k: cp["c_road"] * v / 1000.0 + cp["m_switch"] for k, v in road_dist_MUN_port.items()}
    C_r2_b = {k: cp["c_road"] * v / 1000.0 + cp["m_switch"] for k, v in road_dist_stat_MUN.items()}
    C_w2_b = {k: cp["c_road"] * v / 1000.0 + cp["m_switch"] for k, v in road_dist_port_MUN.items()}
    C_r1_r2: Dict[Tuple[str, str], float] = {}
    for k, dist in rail_dist.items():
        rate = cp["c_rail_short"] if dist < 1_000_000 else cp["c_rail_long"]
        C_r1_r2[k] = rate * dist / 1000.0
    C_w1_w2 = {k: cp["c_water"] * v / 1000.0 for k, v in water_dist.items()}

    return dict(
        C_a_b=C_a_b, C_a_r1=C_a_r1, C_a_w1=C_a_w1,
        C_r2_b=C_r2_b, C_w2_b=C_w2_b, C_r1_r2=C_r1_r2, C_w1_w2=C_w1_w2,
    )


def build_model_inputs(soy_mun: pd.DataFrame, step06: dict, cost_params: dict) -> dict:
    """Assemble all params for `model.build_model` (structure + costs).

    Convenience wrapper for one-shot solves. The bootstrap calls
    build_structural_inputs once and build_cost_matrices per iteration instead.

    cost_params: dict with c_road, c_rail_short, c_rail_long, c_water, m_switch
        (units: $/t-km for road/rail/water; $/tonne for m_switch).
    """
    s = build_structural_inputs(soy_mun, step06)
    c = build_cost_matrices(step06, cost_params, a_keep=set(s["a"]))
    return {**s, **c}


def _cargo_to_dict(df: pd.DataFrame) -> Dict[Tuple[str, str, str], float]:
    """Long-format cargo df → {(orig, dest, product) -> volume}."""
    out = {}
    for _, row in df.iterrows():
        key = (str(row["orig"]), str(row["dest"]), str(row["product"]))
        out[key] = float(row["volume"])
    return out


def _dist_to_dict(mat, keep_rows=None, keep_cols=None) -> Dict[Tuple[str, str], float]:
    """2D DataFrame → {(i, j) -> dist} (skips inf / NA / negative).

    keep_rows / keep_cols: optional sets of node ids — when given, the matrix is
    restricted to that sub-block first (cheap reindex) so we never materialise
    cost cells for routes that carry no flow (e.g. the full MU×MU road matrix).
    """
    if not isinstance(mat, pd.DataFrame):
        raise TypeError(
            "Distance matrix must be a pandas DataFrame with row/col index = node ids"
        )
    mat = mat.copy()
    mat.index = mat.index.astype(str)
    mat.columns = mat.columns.astype(str)
    if keep_rows is not None:
        mat = mat.loc[[r for r in mat.index if r in keep_rows]]
    if keep_cols is not None:
        mat = mat.loc[:, [c for c in mat.columns if c in keep_cols]]
    rows = mat.index.tolist()
    cols = mat.columns.tolist()
    arr = mat.to_numpy()
    out = {}
    for i, r in enumerate(rows):
        for j, c in enumerate(cols):
            v = arr[i, j]
            if np.isfinite(v) and v >= 0:
                out[(r, c)] = float(v)
    return out

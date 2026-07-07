"""Write LP solution to .rds / .csv matching the GAMS pipeline output format.

code/pipeline/08_export_link_mean.R lists files in `./data/generated/outputs/gams/bs_res_{YEAR}/` and reads
each .rds via readr::read_rds. Each .rds must be a 4-column data.frame with
columns:
    co_orig  numeric
    co_dest  numeric
    product  character
    value    numeric  (total tonnes routed orig→dest via all mode combinations)
"""
from __future__ import annotations
from pathlib import Path
from typing import Dict

import numpy as np
import pandas as pd

try:
    import pyreadr
    HAVE_PYREADR = True
except ImportError:
    HAVE_PYREADR = False


def consolidate_flows(flows: Dict[str, pd.DataFrame]) -> pd.DataFrame:
    """Sum direct, rail, and water mode-flows into a single (orig, dest, product, value) frame.

    Stefan's R post-processing (after the GAMS solve) computes:
        X_a_b_via_rail = (X_a_r1 / colsum(X_a_r1)) @ (X_r1_r2 / colsum(X_r1_r2)) @ X_r2_b
        X_a_b_via_water = analogous with w1, w2
        X_a_b_total = X_a_b_direct + X_a_b_via_rail + X_a_b_via_water
    """
    # Direct truck
    direct = flows["X_a_b"].rename(columns={"a": "co_orig", "b": "co_dest"})

    # Rail leg attribution (a → b via R1 → R2)
    rail = _attribute_intermodal(
        flows["X_a_r1"], flows["X_r1_r2"], flows["X_r2_b"],
        hub_orig_col="r1", hub_dest_col="r2",
    )

    # Water leg attribution (a → b via W1 → W2)
    water = _attribute_intermodal(
        flows["X_a_w1"], flows["X_w1_w2"], flows["X_w2_b"],
        hub_orig_col="w1", hub_dest_col="w2",
    )

    # drop empty legs before concat (e.g. road-only runs have no rail/water) to
    # avoid pandas' all-NA-column FutureWarning
    _parts = [df for df in (direct, rail, water) if not df.empty]
    combined = (pd.concat(_parts, ignore_index=True) if _parts
                else pd.DataFrame(columns=["co_orig", "co_dest", "product", "value"]))
    combined = (
        combined.groupby(["co_orig", "co_dest", "product"], as_index=False)["value"]
        .sum()
    )
    combined = combined[combined["value"] > 0].reset_index(drop=True)

    # Convert co_orig / co_dest to numeric to match R script's downstream expectations
    combined["co_orig"] = pd.to_numeric(combined["co_orig"], errors="coerce")
    combined["co_dest"] = pd.to_numeric(combined["co_dest"], errors="coerce")
    combined = combined.dropna(subset=["co_orig", "co_dest"]).reset_index(drop=True)
    combined["co_orig"] = combined["co_orig"].astype(int)
    combined["co_dest"] = combined["co_dest"].astype(int)
    return combined[["co_orig", "co_dest", "product", "value"]]


def _attribute_intermodal(
    leg_in: pd.DataFrame,   # X_a_h1  (a, h1, product, value)  truck into origin hub
    leg_mid: pd.DataFrame,  # X_h1_h2 (h1, h2, product, value) intermodal between hubs
    leg_out: pd.DataFrame,  # X_h2_b  (h2, b, product, value)  truck out of destination hub
    hub_orig_col: str,
    hub_dest_col: str,
) -> pd.DataFrame:
    """Approximate the a→b flow through an intermodal pair (h1, h2).

    Implementation matches Stefan's R post-processing:
        For each product:
            P_a_h1 = X_a_h1 / colSums(X_a_h1)    (column-normalised: prob over a given h1)
            P_h1_h2 = X_h1_h2 / colSums(X_h1_h2) (column-normalised over h1 given h2)
            X_a_b_attrib = P_a_h1 @ P_h1_h2 @ X_h2_b
    """
    if leg_in.empty or leg_mid.empty or leg_out.empty:
        return pd.DataFrame(columns=["co_orig", "co_dest", "product", "value"])

    results = []
    for product in leg_mid["product"].unique():
        li = leg_in[leg_in["product"] == product]
        lm = leg_mid[leg_mid["product"] == product]
        lo = leg_out[leg_out["product"] == product]
        if li.empty or lm.empty or lo.empty:
            continue

        # Build the three matrices as 2D arrays with row/col index alignment.
        a_idx = sorted(li["a"].unique())
        h1_idx = sorted(set(li[hub_orig_col]).union(lm[hub_orig_col]))
        h2_idx = sorted(set(lm[hub_dest_col]).union(lo[hub_orig_col if False else hub_dest_col]))
        b_idx = sorted(lo["b"].unique())

        A_h1 = _pivot(li, "a", hub_orig_col, "value", a_idx, h1_idx)  # (|a|, |h1|)
        H_h2 = _pivot(lm, hub_orig_col, hub_dest_col, "value", h1_idx, h2_idx)  # (|h1|, |h2|)
        H_b  = _pivot(lo, hub_dest_col, "b", "value", h2_idx, b_idx)  # (|h2|, |b|)

        # Column-normalize the first two legs (Stefan's t(t(x)/colSums(x)))
        col_sums_A = A_h1.sum(axis=0, keepdims=True)
        col_sums_H = H_h2.sum(axis=0, keepdims=True)
        with np.errstate(divide="ignore", invalid="ignore"):
            P_A = np.where(col_sums_A > 0, A_h1 / col_sums_A, 0.0)
            P_H = np.where(col_sums_H > 0, H_h2 / col_sums_H, 0.0)

        X_attrib = P_A @ P_H @ H_b  # (|a|, |b|)

        # Materialise non-zero entries
        nz = np.argwhere(X_attrib > 0)
        for ii, jj in nz:
            results.append({
                "co_orig": a_idx[ii],
                "co_dest": b_idx[jj],
                "product": product,
                "value": X_attrib[ii, jj],
            })

    if not results:
        return pd.DataFrame(columns=["co_orig", "co_dest", "product", "value"])
    return pd.DataFrame(results)


def _pivot(df: pd.DataFrame, row_col: str, col_col: str, val_col: str,
           row_idx: list, col_idx: list) -> np.ndarray:
    """Build dense |row_idx| × |col_idx| matrix from long-format df."""
    p = df.pivot_table(index=row_col, columns=col_col, values=val_col, aggfunc="sum", fill_value=0.0)
    return p.reindex(index=row_idx, columns=col_idx, fill_value=0.0).to_numpy()


def write_iteration_rds(
    flows_total: pd.DataFrame,
    year: int,
    iteration: int,
    bs_res_dir: Path | str | None = None,
) -> Path:
    """Write a single bootstrap iteration's flow frame to .rds, matching R format."""
    if not HAVE_PYREADR:
        raise ImportError("pyreadr required to write .rds (pip install pyreadr)")
    if bs_res_dir is None:
        bs_res_dir = Path(f"data/generated/outputs/gams/bs_res_{year}")
    bs_res_dir = Path(bs_res_dir)
    bs_res_dir.mkdir(parents=True, exist_ok=True)

    path = bs_res_dir / f"{iteration:05d}.rds"
    pyreadr.write_rds(str(path), flows_total)
    return path


def append_bs_par(
    bs_par_csv: Path | str,
    iteration: int,
    cost_params,
    objval: float,
) -> None:
    """Append one row to the bootstrap parameter log CSV."""
    bs_par_csv = Path(bs_par_csv)
    new_file = not bs_par_csv.exists()
    row = pd.DataFrame([{
        "id": iteration,
        "c_road":       cost_params.c_road,
        "c_rail_short": cost_params.c_rail_short,
        "c_rail_long":  cost_params.c_rail_long,
        "c_water":      cost_params.c_water,
        "m_switch":     cost_params.m_switch,
        "objval":       objval,
    }])
    row.to_csv(bs_par_csv, mode="a", index=False, header=new_file)

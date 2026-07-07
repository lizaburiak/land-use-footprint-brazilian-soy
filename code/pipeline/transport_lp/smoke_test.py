"""End-to-end smoke test on a downsampled real-data fixture.

Runs: load_soy_mun + load_step06_artifacts + build_model + solve + extract_flows
+ consolidate_flows on the fixture produced by `make_fixture.py`. Verifies:
  - LP terminates optimal
  - All supply ≥ shipped (no overshipment)
  - All demand met (within feasibility)
  - No negative flows

Usage:
  python code/pipeline/transport_lp/make_fixture.py 2013      # produce fixture
  python code/pipeline/transport_lp/smoke_test.py 2013        # run smoke test
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import numpy as np
import pandas as pd

from transport_lp.cost_perturbation import central
from transport_lp.model import build_model, solve_model, extract_flows
from transport_lp.write_output import consolidate_flows


def load_fixture(year: int, suffix: str) -> tuple[pd.DataFrame, dict]:
    """Read the parquet fixture produced by make_fixture.py."""
    soy_pq = Path(f"data/generated/outputs/05_{year}_{suffix}/parquet/SOY_MUN_fin.parquet")
    if not soy_pq.exists():
        sys.exit(f"Fixture not found at {soy_pq}. "
                 f"Run: python code/pipeline/transport_lp/make_fixture.py {year}")
    soy = pd.read_parquet(soy_pq)
    soy["co_mun"] = soy["co_mun"].astype(str)

    pq_dir = Path(f"data/generated/outputs/06_{year}_{suffix}/parquet")
    if not pq_dir.exists():
        sys.exit(f"Step-06 fixture not found at {pq_dir}. Run make_fixture.py.")

    s06: dict = {}
    for name in ("stations_orig", "stations_dest", "ports_orig", "ports_dest",
                 "cargo_rail_long", "cargo_water_long"):
        s06[name] = pd.read_parquet(pq_dir / f"{name}.parquet")
    for name in ("road_dist_MUN", "road_dist_MUN_stat", "road_dist_MUN_port",
                 "road_dist_stat_MUN", "road_dist_port_MUN",
                 "rail_dist", "water_dist"):
        long = pd.read_parquet(pq_dir / f"{name}_long.parquet")
        # Pivot to 2D
        wide = long.pivot_table(index="from", columns="to", values="distance",
                                 fill_value=np.inf)
        s06[name] = wide.astype(float)
    return soy, s06


def main():
    p = argparse.ArgumentParser()
    p.add_argument("year", type=int)
    p.add_argument("--suffix", default="smoke", help="fixture suffix (matches make_fixture.py)")
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args()

    from transport_lp.data_loader import build_model_inputs

    print(f"[smoke] Loading fixture {args.year}_{args.suffix}…")
    soy, s06 = load_fixture(args.year, args.suffix)
    print(f"[smoke] |a|={len(soy)} municípios, "
          f"|r1|={len(s06['stations_orig'])}, |w1|={len(s06['ports_orig'])}")

    cp = central()
    print(f"[smoke] Cost params (central): {cp.to_dict()}")

    inputs = build_model_inputs(soy, s06, cp.to_dict())

    print("[smoke] Building Pyomo model…")
    m = build_model(**inputs)

    print("[smoke] Solving with HiGHS…")
    res = solve_model(m, threads=1, tee=args.verbose)
    print(f"[smoke] {res}")
    if res["termination_condition"] != "optimal":
        sys.exit(2)

    # ── Sanity checks ────────────────────────────────────────────────────────
    flows = extract_flows(m)
    total = consolidate_flows(flows)
    print(f"[smoke] {len(total):,} non-zero (orig, dest, product) flows after consolidation")

    # Per-municipality supply audit: shipped_out ≤ excess_supply
    sup_dict = {(row["co_mun"], p): float(row[f"excess_supply_{p}"])
                for _, row in soy.iterrows() for p in ("bean", "oil", "cake")}
    shipped_out = (
        total.groupby(["co_orig", "product"])["value"].sum()
        .rename("shipped").reset_index()
    )
    shipped_out["co_orig"] = shipped_out["co_orig"].astype(str)
    fails = []
    for _, row in shipped_out.iterrows():
        key = (row["co_orig"], row["product"])
        sup = sup_dict.get(key, 0.0)
        if row["shipped"] > sup + 1e-3:
            fails.append((key, row["shipped"], sup))
    if fails:
        print(f"[smoke] FAIL: {len(fails)} (mu, product) shipments exceed supply:")
        for (k, s, sup) in fails[:5]:
            print(f"  {k}: shipped={s:.2f}, supply={sup:.2f}")
        sys.exit(3)
    print("[smoke] ✓ supply audit OK")

    # Demand audit: shipped_in ≥ excess_use
    dem_dict = {(row["co_mun"], p): float(row[f"excess_use_{p}"])
                for _, row in soy.iterrows() for p in ("bean", "oil", "cake")}
    shipped_in = (
        total.groupby(["co_dest", "product"])["value"].sum()
        .rename("received").reset_index()
    )
    shipped_in["co_dest"] = shipped_in["co_dest"].astype(str)
    demand_fails = []
    for (mu, p), dem in dem_dict.items():
        rec_row = shipped_in[(shipped_in["co_dest"] == mu) & (shipped_in["product"] == p)]
        rec = float(rec_row["received"].sum()) if len(rec_row) else 0.0
        if rec < dem - 1e-3:
            demand_fails.append(((mu, p), rec, dem))
    if demand_fails:
        print(f"[smoke] FAIL: {len(demand_fails)} (mu, product) demands not met:")
        for (k, r, dem) in demand_fails[:5]:
            print(f"  {k}: received={r:.2f}, demand={dem:.2f}")
        sys.exit(3)
    print("[smoke] ✓ demand audit OK")

    # All flows non-negative
    if (total["value"] < -1e-6).any():
        print("[smoke] FAIL: negative flows detected")
        sys.exit(3)
    print("[smoke] ✓ non-negativity OK")

    print(f"\n[smoke] PASS — objective: {res['objective']:.4e}, wall: {res['wall_time']:.3f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())

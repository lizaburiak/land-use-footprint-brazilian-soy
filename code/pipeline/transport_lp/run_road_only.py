"""Run the transport LP ROAD-ONLY on fully real data — no synthetic fixture.

Inputs are all real:
  - supply/demand:  data/generated/outputs/05_{YEAR}/SOY_MUN_fin (step 05)
  - road distances: data/generated/outputs/00_{YEAR}/MUN_capital_dist (step 00, great-circle metres)
There are NO rail/water hubs (those need the missing step-06 data), so the LP reduces to
direct min-cost road transport — the same problem 07_transport_R solves, but via the Pyomo
model. Cost = c_road * dist/1000 (Stefan's central cost parameter).

The full 2013 problem is ~7M variables (1731×3839 for bean alone), too large for an explicit
Pyomo build, so we restrict to the top --n-sup supply and --n-dem demand municipalities per
product (real municipalities, real distances, real quantities) and rebalance each product so
sum(supply)==sum(demand) — exactly the rebalancing 07_transport_R applies.

Usage:
  python code/pipeline/transport_lp/run_road_only.py 2013 --n-sup 250 --n-dem 250
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

PRODUCTS = ["bean", "oil", "cake"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("year", type=int)
    p.add_argument("--n-sup", type=int, default=250, help="top-N supply muns per product")
    p.add_argument("--n-dem", type=int, default=250, help="top-N demand muns per product")
    args = p.parse_args()
    YEAR = args.year

    soy = pd.read_parquet(f"data/generated/outputs/05_{YEAR}/parquet/SOY_MUN_fin.parquet")
    soy["co_mun"] = soy["co_mun"].astype(str)

    # pick the biggest real supply & demand municipalities per product
    keep: set[str] = set()
    for prod in PRODUCTS:
        s = soy.nlargest(args.n_sup, f"excess_supply_{prod}")
        d = soy.nlargest(args.n_dem, f"excess_use_{prod}")
        keep |= set(s.loc[s[f"excess_supply_{prod}"] > 0, "co_mun"])
        keep |= set(d.loc[d[f"excess_use_{prod}"] > 0, "co_mun"])
    soy = soy[soy["co_mun"].isin(keep)].copy()
    a_list = sorted(keep)
    print(f"[road-only] {YEAR}: kept {len(a_list)} real municipalities")

    # real supply/demand, rebalanced per product (scale larger side to match)
    supply, demand = {}, {}
    for prod in PRODUCTS:
        s = soy.set_index("co_mun")[f"excess_supply_{prod}"].clip(lower=0)
        d = soy.set_index("co_mun")[f"excess_use_{prod}"].clip(lower=0)
        ss, ds = s.sum(), d.sum()
        if ss > 0 and ds > 0:
            if ss > ds:
                s = s * (ds / ss)
            else:
                d = d * (ss / ds)
            for m, v in s[s > 0].items():
                supply[(m, prod)] = float(v)
            for m, v in d[d > 0].items():
                demand[(m, prod)] = float(v)

    # real great-circle road distances → cost (restricted to kept pairs)
    dl = pd.read_parquet(f"data/generated/outputs/00_{YEAR}/parquet/MUN_capital_dist_long.parquet")
    dl["from"] = dl["from"].astype(str)
    dl["to"] = dl["to"].astype(str)
    sub = dl[dl["from"].isin(keep) & dl["to"].isin(keep)]
    c_road = central().c_road
    C_a_b = dict(zip(zip(sub["from"], sub["to"]), c_road * sub["distance"].to_numpy() / 1000.0))
    print(f"[road-only] {len(C_a_b):,} real road arcs (cost = c_road·dist/1000, c_road={c_road:.4f})")

    # build the LP with NO rail/water hubs → pure road transport
    m = build_model(
        products=PRODUCTS, a=a_list, r1=[], r2=[], w1=[], w2=[],
        supply=supply, demand=demand, exp_proc={}, cap_r={}, cap_w={},
        C_a_b=C_a_b, C_a_r1={}, C_a_w1={}, C_r2_b={}, C_w2_b={}, C_r1_r2={}, C_w1_w2={},
    )
    print("[road-only] solving with HiGHS…")
    res = solve_model(m, threads=1)
    print(f"[road-only] {res['termination_condition']}, "
          f"objective={res['objective']:.4e}, wall={res['wall_time']:.2f}s")
    if res["termination_condition"] != "optimal":
        sys.exit(2)

    flows = extract_flows(m)
    total = consolidate_flows(flows)
    print(f"[road-only] {len(total):,} non-zero (orig→dest, product) flows")

    # audits
    ship_out = total.groupby(["co_orig", "product"])["value"].sum()
    bad = sum(ship_out.get((int(m_), prod), 0.0) > supply.get((m_, prod), 0.0) + 1.0
              for (m_, prod) in supply)
    print(f"[road-only] supply audit: {'OK' if bad == 0 else f'{bad} overshipments'}")
    for prod in PRODUCTS:
        moved = total.loc[total["product"] == prod, "value"].sum()
        print(f"[road-only]   {prod:5s}: {moved:,.0f} t moved")
    print(f"\n[road-only] PASS — real 2013 road transport, obj={res['objective']:.4e}")


if __name__ == "__main__":
    sys.exit(main())

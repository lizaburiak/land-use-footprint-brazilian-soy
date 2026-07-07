"""Single deterministic solve of the multimode LP for a given year.

Use this as a smoke test / for 'central' (mean cost params) results.
For bootstrap × N iterations, use bootstrap.py.

    python code/pipeline/transport_lp/solve_one.py 2013
    python code/pipeline/transport_lp/solve_one.py 2014 --threads 4 --tee
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from transport_lp.data_loader import build_model_inputs, load_soy_mun, load_step06_artifacts
from transport_lp.cost_perturbation import central
from transport_lp.model import build_model, solve_model, extract_flows
from transport_lp.write_output import consolidate_flows, write_iteration_rds, append_bs_par


def main():
    p = argparse.ArgumentParser(description="Single LP solve for given year")
    p.add_argument("year", type=int)
    p.add_argument("--threads", type=int, default=1)
    p.add_argument("--tee", action="store_true", help="stream HiGHS solver log to stdout")
    p.add_argument("--time-limit", type=float, default=None, help="seconds")
    p.add_argument("--out-id", type=int, default=0, help="iteration id (0 = central run)")
    p.add_argument("--cost-fallback-year", type=int, default=None,
                   help="use step-06 artifacts from a different year (when cargo missing)")
    args = p.parse_args()

    print(f"[solve_one] Loading data for YEAR={args.year} …")
    soy_mun = load_soy_mun(args.year)
    step06_year = args.cost_fallback_year or args.year
    step06 = load_step06_artifacts(step06_year)
    if step06_year != args.year:
        print(f"[solve_one] (using step-06 artifacts from {step06_year} as fallback)")

    cp = central()
    print(f"[solve_one] Central cost params: {cp.to_dict()}")

    inputs = build_model_inputs(soy_mun, step06, cp.to_dict())
    print(f"[solve_one] |a|={len(inputs['a'])}  |r1|={len(inputs['r1'])}  "
          f"|r2|={len(inputs['r2'])}  |w1|={len(inputs['w1'])}  |w2|={len(inputs['w2'])}")

    print("[solve_one] Building Pyomo model …")
    m = build_model(**inputs)

    print(f"[solve_one] Solving with HiGHS (threads={args.threads}) …")
    res = solve_model(m, threads=args.threads, tee=args.tee, time_limit=args.time_limit)
    print(f"[solve_one] {res}")

    if res["termination_condition"] != "optimal":
        sys.exit(2)

    flows = extract_flows(m)
    total = consolidate_flows(flows)
    print(f"[solve_one] {len(total):,} non-zero (orig, dest, product) flows")

    rds_path = write_iteration_rds(total, args.year, args.out_id)
    bs_par_csv = Path(f"data/generated/outputs/gams/bs_res_{args.year}/bs_par.csv")
    append_bs_par(bs_par_csv, args.out_id, cp, res["objective"])
    print(f"[solve_one] Wrote {rds_path}")
    print(f"[solve_one] Appended bootstrap row to {bs_par_csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Parallel bootstrap × N iterations — replaces Stefan's foreach %dorng% loop.

Each worker:
  1. Draws cost parameters from Stefan's uniform ranges
  2. Builds + solves the LP with those costs
  3. Writes ./data/generated/outputs/gams/bs_res_{YEAR}/{i:05d}.rds and appends to bs_par.csv

Output format matches the GAMS pipeline 1:1, so code/pipeline/08_export_link_mean.R
and 08_export_link_sep.R consume it unchanged.

    python code/pipeline/transport_lp/bootstrap.py 2013 --n-iters 1000 --workers 8
"""
from __future__ import annotations
import argparse
import multiprocessing as mp
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import numpy as np

from transport_lp.data_loader import (
    build_structural_inputs, build_cost_matrices, load_soy_mun, load_step06_artifacts,
)
from transport_lp.cost_perturbation import draw
from transport_lp.model import build_structure, set_costs, solve_model, extract_flows
from transport_lp.write_output import consolidate_flows, write_iteration_rds, append_bs_par


# Module-level workers (so they're picklable across processes).
# Heavy invariants (model structure, step06) are built once per worker process
# via the initializer; each iteration only swaps the cost coefficients and
# re-solves — mirroring Stefan's GAMS "compile once, swap cost gdx" loop.

_WORKER_STATE = {}


def _worker_init(year: int, step06_year: int):
    """Initialise per-worker invariants once: load data and build the LP structure."""
    soy_mun = load_soy_mun(year)
    step06 = load_step06_artifacts(step06_year)
    struct = build_structural_inputs(soy_mun, step06)
    _WORKER_STATE["year"] = year
    _WORKER_STATE["step06"] = step06
    _WORKER_STATE["a_keep"] = set(struct["a"])
    # Variables + constraints are cost-independent: build them exactly once.
    _WORKER_STATE["model"] = build_structure(**struct)


def _solve_iter(iter_seed_tuple):
    """One bootstrap iteration: returns (iteration_id, costs, objval, total_flows, term)."""
    iteration, seed = iter_seed_tuple
    state = _WORKER_STATE
    rng = np.random.default_rng(seed)
    cp = draw(rng)
    # Only the objective changes between iterations — swap costs, reuse structure.
    costs = build_cost_matrices(state["step06"], cp.to_dict(), a_keep=state["a_keep"])
    m = state["model"]
    set_costs(m, **costs)
    res = solve_model(m, threads=1, tee=False)
    if "optimal" not in res["termination_condition"].lower():
        return (iteration, cp, np.nan, None, res["termination_condition"])
    flows = extract_flows(m)
    total = consolidate_flows(flows)
    return (iteration, cp, res["objective"], total, res["termination_condition"])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("year", type=int)
    p.add_argument("--n-iters", type=int, default=1000)
    p.add_argument("--workers", type=int, default=max(1, mp.cpu_count() - 1))
    p.add_argument("--seed", type=int, default=42, help="base seed for reproducibility")
    p.add_argument("--start-id", type=int, default=1, help="resume from iteration N")
    p.add_argument("--cost-fallback-year", type=int, default=None,
                   help="use step-06 artifacts from a different year (when cargo missing)")
    args = p.parse_args()

    step06_year = args.cost_fallback_year or args.year
    bs_res_dir = Path(f"data/generated/outputs/gams/bs_res_{args.year}")
    bs_par_csv = bs_res_dir / "bs_par.csv"
    bs_res_dir.mkdir(parents=True, exist_ok=True)

    print(f"[bootstrap] YEAR={args.year}  n_iters={args.n_iters}  workers={args.workers}")
    print(f"[bootstrap] output dir: {bs_res_dir}")

    seeds = np.random.SeedSequence(args.seed).generate_state(args.n_iters)
    work_items = [
        (i + args.start_id, int(seeds[i])) for i in range(args.n_iters)
    ]

    t0 = time.time()
    n_done = 0
    n_fail = 0
    with mp.Pool(
        processes=args.workers,
        initializer=_worker_init,
        initargs=(args.year, step06_year),
    ) as pool:
        for iteration, cp, objval, total, term in pool.imap_unordered(_solve_iter, work_items):
            if total is None:
                n_fail += 1
                print(f"[bootstrap] iter {iteration:5d}  FAILED ({term})")
                continue
            write_iteration_rds(total, args.year, iteration, bs_res_dir=bs_res_dir)
            append_bs_par(bs_par_csv, iteration, cp, objval)
            n_done += 1
            elapsed = time.time() - t0
            rate = n_done / elapsed if elapsed > 0 else 0
            print(f"[bootstrap] iter {iteration:5d}  obj={objval:.4e}  "
                  f"({n_done}/{args.n_iters} ok, {n_fail} fail, {rate:.2f}/s)")

    print(f"[bootstrap] Done. {n_done} ok, {n_fail} failed. Total {time.time() - t0:.1f}s.")
    return 0 if n_fail == 0 else 3


if __name__ == "__main__":
    sys.exit(main())

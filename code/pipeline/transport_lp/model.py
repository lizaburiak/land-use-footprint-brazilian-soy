"""Pyomo port of archive/code_old_stefan/gams/transport_model_Brazil_intermod.gms.

The objective, constraints, and variables mirror Stefan's GAMS file 1:1.

Sparsity is implemented the same way GAMS does it via the `$()` filter — only
variables that can carry flow are created:

    X_a_b(a,b,p)    only where supply(a,p) > 0 AND demand(b,p) > 0
    X_a_r1(a,r1,p)  only where supply(a,p) > 0 (and r1 is on a capacity route)
    X_a_w1(a,w1,p)  only where supply(a,p) > 0 (and w1 is on a capacity route)
    X_r1_r2(r1,r2,p) only where cap_r(r1,r2,p) > 0
    X_w1_w2(w1,w2,p) only where cap_w(w1,w2,p) > 0
    X_r2_b(r2,b,p)  only where demand(b,p) > 0 AND exp_proc(b,p) > 0
    X_w2_b(w2,b,p)  only where demand(b,p) > 0 AND exp_proc(b,p) > 0

This produces an LP of the same size as Stefan's GAMS model (a few hundred
supplying × demanding municipalities per product) rather than the full dense
cartesian product (~5,570² × 3 ≈ 90M variables), which is intractable.

Build/solve split for the bootstrap:
    build_structure(...)  → vars + constraints (cost-independent; build ONCE)
    set_costs(m, ...)     → (re)build the objective from cost dicts (swap per
                            bootstrap iteration, like GAMS swapping the cost gdx)
    build_model(...)      → convenience wrapper (structure + costs) used by the
                            standalone solvers and tests.
"""
from __future__ import annotations

from collections import defaultdict
from typing import Iterable, Mapping, Tuple

from pyomo.environ import (
    ConcreteModel,
    Constraint,
    NonNegativeReals,
    Objective,
    Set,
    SolverFactory,
    Var,
    minimize,
    value,
)

# Penalty for a cost cell with no entry — keeps the solver off uninitialised
# routes. The data loader provides dense road costs, so this rarely binds.
BIG_COST = 1e9


def build_structure(
    products: Iterable[str],
    a: Iterable[str],
    r1: Iterable[str],
    r2: Iterable[str],
    w1: Iterable[str],
    w2: Iterable[str],
    supply: Mapping[Tuple[str, str], float],
    demand: Mapping[Tuple[str, str], float],
    exp_proc: Mapping[Tuple[str, str], float],
    cap_r: Mapping[Tuple[str, str, str], float],
    cap_w: Mapping[Tuple[str, str, str], float],
) -> ConcreteModel:
    """Build the sparse variable + constraint structure (no objective).

    The objective is cost-dependent; add it with `set_costs(m, ...)`. Splitting
    the two lets the bootstrap build this once and only swap costs per iteration.
    """
    products = list(products)
    a = list(a)
    r1, r2, w1, w2 = list(r1), list(r2), list(w1), list(w2)
    supply, demand, exp_proc = dict(supply), dict(demand), dict(exp_proc)
    cap_r, cap_w = dict(cap_r), dict(cap_w)

    # ── Per-product positive index sets (the GAMS $() filter) ────────────────
    sup = {p: [m_ for m_ in a if supply.get((m_, p), 0) > 0] for p in products}
    dem = {p: [m_ for m_ in a if demand.get((m_, p), 0) > 0] for p in products}
    # destinations that may receive intermodal flow (demand AND export+processing)
    epd = {p: [m_ for m_ in a if demand.get((m_, p), 0) > 0 and exp_proc.get((m_, p), 0) > 0]
           for p in products}
    # capacity routes that actually exist, per product
    capr_keys = {p: [(i, j) for (i, j, pp), v in cap_r.items() if pp == p and v > 0]
                 for p in products}
    capw_keys = {p: [(i, j) for (i, j, pp), v in cap_w.items() if pp == p and v > 0]
                 for p in products}
    # only hubs that sit on a capacity route can carry flow (others are forced to
    # 0 by hub conservation, so excluding them is exact and much smaller)
    r1_act = {p: sorted({i for (i, j) in capr_keys[p]}) for p in products}
    r2_act = {p: sorted({j for (i, j) in capr_keys[p]}) for p in products}
    w1_act = {p: sorted({i for (i, j) in capw_keys[p]}) for p in products}
    w2_act = {p: sorted({j for (i, j) in capw_keys[p]}) for p in products}

    # ── Variable index lists + adjacency for constraint assembly ─────────────
    idx_ab, idx_ar1, idx_aw1 = [], [], []
    idx_r1r2, idx_w1w2, idx_r2b, idx_w2b = [], [], [], []
    ab_b, ab_a = defaultdict(list), defaultdict(list)
    ar1_h, ar1_a = defaultdict(list), defaultdict(list)
    aw1_h, aw1_a = defaultdict(list), defaultdict(list)
    r1r2_to, r1r2_from = defaultdict(list), defaultdict(list)
    w1w2_to, w1w2_from = defaultdict(list), defaultdict(list)
    r2b_b, r2b_h = defaultdict(list), defaultdict(list)
    w2b_b, w2b_h = defaultdict(list), defaultdict(list)

    for p in products:
        for ai in sup[p]:
            for bi in dem[p]:
                idx_ab.append((ai, bi, p)); ab_b[(ai, p)].append(bi); ab_a[(bi, p)].append(ai)
            for hi in r1_act[p]:
                idx_ar1.append((ai, hi, p)); ar1_h[(ai, p)].append(hi); ar1_a[(hi, p)].append(ai)
            for hi in w1_act[p]:
                idx_aw1.append((ai, hi, p)); aw1_h[(ai, p)].append(hi); aw1_a[(hi, p)].append(ai)
        for (hi, hj) in capr_keys[p]:
            idx_r1r2.append((hi, hj, p)); r1r2_to[(hi, p)].append(hj); r1r2_from[(hj, p)].append(hi)
        for (hi, hj) in capw_keys[p]:
            idx_w1w2.append((hi, hj, p)); w1w2_to[(hi, p)].append(hj); w1w2_from[(hj, p)].append(hi)
        for hj in r2_act[p]:
            for bi in epd[p]:
                idx_r2b.append((hj, bi, p)); r2b_b[(hj, p)].append(bi); r2b_h[(bi, p)].append(hj)
        for hj in w2_act[p]:
            for bi in epd[p]:
                idx_w2b.append((hj, bi, p)); w2b_b[(hj, p)].append(bi); w2b_h[(bi, p)].append(hj)

    m = ConcreteModel(name="soyprint_multimode_transport")

    # ── Sparse variables (all ≥ 0) ───────────────────────────────────────────
    m.IDX_a_b   = Set(dimen=3, initialize=idx_ab)
    m.IDX_a_r1  = Set(dimen=3, initialize=idx_ar1)
    m.IDX_a_w1  = Set(dimen=3, initialize=idx_aw1)
    m.IDX_r1_r2 = Set(dimen=3, initialize=idx_r1r2)
    m.IDX_w1_w2 = Set(dimen=3, initialize=idx_w1w2)
    m.IDX_r2_b  = Set(dimen=3, initialize=idx_r2b)
    m.IDX_w2_b  = Set(dimen=3, initialize=idx_w2b)

    m.X_a_b   = Var(m.IDX_a_b,   within=NonNegativeReals)
    m.X_a_r1  = Var(m.IDX_a_r1,  within=NonNegativeReals)
    m.X_a_w1  = Var(m.IDX_a_w1,  within=NonNegativeReals)
    m.X_r1_r2 = Var(m.IDX_r1_r2, within=NonNegativeReals)
    m.X_w1_w2 = Var(m.IDX_w1_w2, within=NonNegativeReals)
    m.X_r2_b  = Var(m.IDX_r2_b,  within=NonNegativeReals)
    m.X_w2_b  = Var(m.IDX_w2_b,  within=NonNegativeReals)

    # ── Constraint domains (only where the RHS can bind) ─────────────────────
    m.SUP   = Set(dimen=2, initialize=[(ai, p) for p in products for ai in sup[p]])
    m.DEM   = Set(dimen=2, initialize=[(bi, p) for p in products for bi in dem[p]])
    m.EPD   = Set(dimen=2, initialize=[(bi, p) for p in products for bi in epd[p]])
    m.R1ACT = Set(dimen=2, initialize=[(hi, p) for p in products for hi in r1_act[p]])
    m.R2ACT = Set(dimen=2, initialize=[(hj, p) for p in products for hj in r2_act[p]])
    m.W1ACT = Set(dimen=2, initialize=[(hi, p) for p in products for hi in w1_act[p]])
    m.W2ACT = Set(dimen=2, initialize=[(hj, p) for p in products for hj in w2_act[p]])

    # supply_const: outflow from a ≤ supply(a,p)
    def supply_rule(m, ai, p):
        terms = ([m.X_a_b[ai, bi, p] for bi in ab_b[(ai, p)]]
                 + [m.X_a_r1[ai, hi, p] for hi in ar1_h[(ai, p)]]
                 + [m.X_a_w1[ai, hi, p] for hi in aw1_h[(ai, p)]])
        if not terms:
            return Constraint.Skip
        return sum(terms) <= supply[(ai, p)]
    m.supply_const = Constraint(m.SUP, rule=supply_rule)

    # demand_const: inflow to b ≥ demand(b,p)
    def demand_rule(m, bi, p):
        terms = ([m.X_a_b[ai, bi, p] for ai in ab_a[(bi, p)]]
                 + [m.X_r2_b[hj, bi, p] for hj in r2b_h[(bi, p)]]
                 + [m.X_w2_b[hj, bi, p] for hj in w2b_h[(bi, p)]])
        if not terms:
            # demand with no possible delivery — infeasible data (GAMS would be
            # infeasible too); skip to avoid a constant constraint error.
            return Constraint.Skip
        return sum(terms) >= demand[(bi, p)]
    m.demand_const = Constraint(m.DEM, rule=demand_rule)

    # hub flow conservation: rail origin (everything trucked in leaves by rail)
    def hub_r1_rule(m, hi, p):
        return (sum(m.X_r1_r2[hi, hj, p] for hj in r1r2_to[(hi, p)])
                - sum(m.X_a_r1[ai, hi, p] for ai in ar1_a[(hi, p)]) == 0)
    m.hub_const_r1 = Constraint(m.R1ACT, rule=hub_r1_rule)

    def hub_w1_rule(m, hi, p):
        return (sum(m.X_w1_w2[hi, hj, p] for hj in w1w2_to[(hi, p)])
                - sum(m.X_a_w1[ai, hi, p] for ai in aw1_a[(hi, p)]) == 0)
    m.hub_const_w1 = Constraint(m.W1ACT, rule=hub_w1_rule)

    # hub flow conservation: rail destination (everything railed in leaves by truck)
    def hub_r2_rule(m, hj, p):
        return (sum(m.X_r1_r2[hi, hj, p] for hi in r1r2_from[(hj, p)])
                - sum(m.X_r2_b[hj, bi, p] for bi in r2b_b[(hj, p)]) == 0)
    m.hub_const_r2 = Constraint(m.R2ACT, rule=hub_r2_rule)

    def hub_w2_rule(m, hj, p):
        return (sum(m.X_w1_w2[hi, hj, p] for hi in w1w2_from[(hj, p)])
                - sum(m.X_w2_b[hj, bi, p] for bi in w2b_b[(hj, p)]) == 0)
    m.hub_const_w2 = Constraint(m.W2ACT, rule=hub_w2_rule)

    # capacity caps on inter-hub flows
    def cap_r_rule(m, hi, hj, p):
        return m.X_r1_r2[hi, hj, p] <= cap_r[(hi, hj, p)]
    m.cap_const_r = Constraint(m.IDX_r1_r2, rule=cap_r_rule)

    def cap_w_rule(m, hi, hj, p):
        return m.X_w1_w2[hi, hj, p] <= cap_w[(hi, hj, p)]
    m.cap_const_w = Constraint(m.IDX_w1_w2, rule=cap_w_rule)

    # intermodal inflow to b ≤ export+processing demand
    def intermod_rule(m, bi, p):
        terms = ([m.X_r2_b[hj, bi, p] for hj in r2b_h[(bi, p)]]
                 + [m.X_w2_b[hj, bi, p] for hj in w2b_h[(bi, p)]])
        if not terms:
            return Constraint.Skip
        return sum(terms) <= exp_proc[(bi, p)]
    m.intermod_const = Constraint(m.EPD, rule=intermod_rule)

    return m


def set_costs(
    m: ConcreteModel,
    C_a_b: Mapping[Tuple[str, str], float],
    C_a_r1: Mapping[Tuple[str, str], float],
    C_a_w1: Mapping[Tuple[str, str], float],
    C_r2_b: Mapping[Tuple[str, str], float],
    C_w2_b: Mapping[Tuple[str, str], float],
    C_r1_r2: Mapping[Tuple[str, str], float],
    C_w1_w2: Mapping[Tuple[str, str], float],
    big_cost: float = BIG_COST,
) -> None:
    """(Re)build the minimize-total-cost objective over the existing variables.

    Swapping costs between bootstrap iterations only rebuilds this objective —
    the variables and constraints (which don't depend on cost) are untouched.
    """
    if m.component("cost") is not None:
        m.del_component("cost")

    def cost_rule(m):
        return (
            sum(C_a_b.get((i, j), big_cost)   * m.X_a_b[i, j, p]   for (i, j, p) in m.IDX_a_b)
            + sum(C_a_r1.get((i, j), big_cost)  * m.X_a_r1[i, j, p]  for (i, j, p) in m.IDX_a_r1)
            + sum(C_a_w1.get((i, j), big_cost)  * m.X_a_w1[i, j, p]  for (i, j, p) in m.IDX_a_w1)
            + sum(C_r1_r2.get((i, j), big_cost) * m.X_r1_r2[i, j, p] for (i, j, p) in m.IDX_r1_r2)
            + sum(C_w1_w2.get((i, j), big_cost) * m.X_w1_w2[i, j, p] for (i, j, p) in m.IDX_w1_w2)
            + sum(C_r2_b.get((i, j), big_cost)  * m.X_r2_b[i, j, p]  for (i, j, p) in m.IDX_r2_b)
            + sum(C_w2_b.get((i, j), big_cost)  * m.X_w2_b[i, j, p]  for (i, j, p) in m.IDX_w2_b)
        )
    m.cost = Objective(rule=cost_rule, sense=minimize)


def build_model(
    products: Iterable[str],
    a: Iterable[str],
    r1: Iterable[str],
    r2: Iterable[str],
    w1: Iterable[str],
    w2: Iterable[str],
    supply: Mapping[Tuple[str, str], float],
    demand: Mapping[Tuple[str, str], float],
    exp_proc: Mapping[Tuple[str, str], float],
    cap_r: Mapping[Tuple[str, str, str], float],
    cap_w: Mapping[Tuple[str, str, str], float],
    C_a_b: Mapping[Tuple[str, str], float],
    C_a_r1: Mapping[Tuple[str, str], float],
    C_a_w1: Mapping[Tuple[str, str], float],
    C_r2_b: Mapping[Tuple[str, str], float],
    C_w2_b: Mapping[Tuple[str, str], float],
    C_r1_r2: Mapping[Tuple[str, str], float],
    C_w1_w2: Mapping[Tuple[str, str], float],
) -> ConcreteModel:
    """Build the full multimode transport LP (structure + objective).

    Convenience wrapper around `build_structure` + `set_costs` for one-shot
    solves and tests. The bootstrap calls the two halves separately.
    """
    m = build_structure(products, a, r1, r2, w1, w2,
                         supply, demand, exp_proc, cap_r, cap_w)
    set_costs(m, C_a_b, C_a_r1, C_a_w1, C_r2_b, C_w2_b, C_r1_r2, C_w1_w2)
    return m


def solve_model(
    m: ConcreteModel,
    solver_name: str = "appsi_highs",
    tee: bool = False,
    time_limit: float | None = None,
    threads: int = 1,
) -> dict:
    """Solve the model with HiGHS (default) and return solver summary.

    Returns
    -------
    {"status": str, "termination_condition": str, "objective": float,
     "wall_time": float}
    """
    solver = SolverFactory(solver_name)
    if not solver.available(exception_flag=False):
        # Try alternative names; pyomo registers HiGHS under multiple aliases.
        for alt in ("highs", "appsi_highs"):
            solver = SolverFactory(alt)
            if solver.available(exception_flag=False):
                break
        else:
            raise RuntimeError(
                "No HiGHS solver available. Install highspy: pip install highspy"
            )

    if time_limit is not None:
        solver.options["time_limit"] = time_limit
    if threads:
        solver.options["threads"] = threads

    import time
    t0 = time.time()
    result = solver.solve(m, tee=tee)
    wall = time.time() - t0

    return {
        "status": str(result.solver.status),
        "termination_condition": str(result.solver.termination_condition),
        "objective": value(m.cost),
        "wall_time": wall,
    }


def extract_flows(m: ConcreteModel, tol: float = 1e-6) -> dict:
    """Pull non-zero variable values from a solved model into pandas frames.

    Returns
    -------
    dict[str, pandas.DataFrame] keyed by the seven X_* variable names.
    Each frame has columns:
      X_a_b  : a, b, product, value
      X_a_r1 : a, r1, product, value
      ... etc.
    """
    import pandas as pd

    def _df(var, idx_names):
        rows = []
        for idx in var:
            v = value(var[idx])
            if v is not None and abs(v) > tol:
                rows.append((*idx, v))
        return pd.DataFrame(rows, columns=[*idx_names, "value"])

    return {
        "X_a_b":   _df(m.X_a_b,   ["a", "b", "product"]),
        "X_a_r1":  _df(m.X_a_r1,  ["a", "r1", "product"]),
        "X_a_w1":  _df(m.X_a_w1,  ["a", "w1", "product"]),
        "X_r1_r2": _df(m.X_r1_r2, ["r1", "r2", "product"]),
        "X_w1_w2": _df(m.X_w1_w2, ["w1", "w2", "product"]),
        "X_r2_b":  _df(m.X_r2_b,  ["r2", "b", "product"]),
        "X_w2_b":  _df(m.X_w2_b,  ["w2", "b", "product"]),
    }

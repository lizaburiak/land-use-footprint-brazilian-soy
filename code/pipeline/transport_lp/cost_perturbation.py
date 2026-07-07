"""Cost-parameter perturbation matching Stefan's GAMS bootstrap.

Stefan draws 5 parameters independently from uniform distributions per
iteration. See code/pipeline/07_transport_GAMS_parallel.R lines ~140–150.

Ranges (from Stefan's 2022 thesis appendix A.2.2 & 2 / Brazilian freight
literature):

    c_road       ~ U(0.0129, 0.1738)   [$ per t-km, truck]
    c_rail_short ~ U(0.0055, 0.0645)   [$ per t-km, rail < 1000 km]
    c_rail_long  = c_rail_short        (per Stefan's setup)
    c_water      ~ U(0.0044, 0.0316)   [$ per t-km, ship]
    m_switch     ~ U(0.7358, 2.5734)   [$ per tonne, intermodal switching]

The means are sometimes used for a deterministic "central" run.
"""
from __future__ import annotations
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class CostParams:
    c_road: float
    c_rail_short: float
    c_rail_long: float
    c_water: float
    m_switch: float

    def to_dict(self) -> dict:
        return dict(
            c_road=self.c_road,
            c_rail_short=self.c_rail_short,
            c_rail_long=self.c_rail_long,
            c_water=self.c_water,
            m_switch=self.m_switch,
        )


# Stefan's bootstrap intervals
RANGES = dict(
    c_road=(0.0129, 0.1738),
    c_rail_short=(0.0055, 0.0645),
    c_water=(0.0044, 0.0316),
    m_switch=(0.7358, 2.5734),
)


def draw(rng: np.random.Generator | None = None) -> CostParams:
    """Draw one bootstrap iteration's cost parameters."""
    if rng is None:
        rng = np.random.default_rng()
    c_road = rng.uniform(*RANGES["c_road"])
    c_rail_short = rng.uniform(*RANGES["c_rail_short"])
    c_rail_long = c_rail_short  # Stefan's setup: rail_long = rail_short
    c_water = rng.uniform(*RANGES["c_water"])
    m_switch = rng.uniform(*RANGES["m_switch"])
    return CostParams(c_road, c_rail_short, c_rail_long, c_water, m_switch)


def central() -> CostParams:
    """Return the midpoint of each range — for a single deterministic 'mean' run."""
    mid = lambda lo, hi: (lo + hi) / 2
    return CostParams(
        c_road=mid(*RANGES["c_road"]),
        c_rail_short=mid(*RANGES["c_rail_short"]),
        c_rail_long=mid(*RANGES["c_rail_short"]),  # same as short by convention
        c_water=mid(*RANGES["c_water"]),
        m_switch=mid(*RANGES["m_switch"]),
    )

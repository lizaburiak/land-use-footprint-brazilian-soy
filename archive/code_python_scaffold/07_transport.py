"""Step 07 — Transport optimization   [PYTHON PORT — WORKING (road) via transport_lp]

R reference : code/new/07_transport_R.R (Euclidean) + 07_transport_GAMS_parallel.R (multimode)
The Python transport model lives in code/new/transport_lp/ and is validated to match
Stefan's R `transport` solver exactly. This step delegates to it.

Modes (see code/new/transport_lp/README.md):
  road-only, fully real :  python code/new/transport_lp/run_road_only.py YEAR
  multimode demo        :  make_fixture.py YEAR --n-mun 40 ; smoke_test.py YEAR --suffix smoke
  multimode production  :  solve_one.py / bootstrap.py YEAR   (needs step-06 geo data)

Usage : python code/python/07_transport.py [YEAR]
"""
from __future__ import annotations
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _helpers as H


def main(year: int) -> None:
    tl = H.ROOT / "code" / "new" / "transport_lp" / "run_road_only.py"
    print(f"[07] delegating to transport_lp (road-only) for {year}")
    subprocess.run([sys.executable, str(tl), str(year)], check=True)


if __name__ == "__main__":
    main(H.parse_year())

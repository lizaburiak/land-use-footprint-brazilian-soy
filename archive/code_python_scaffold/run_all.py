"""Run the Python-port pipeline (steps 00-21) for one year — mirrors code/run_year_full.sh.

Steps not yet ported raise NotImplementedError and are reported as TODO (the run continues).
Usage: python code/python/run_all.py [YEAR]
"""
from __future__ import annotations
import argparse, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
STEPS = [
    "00_data_preparation", "00_FAO_consitency_checks", "01_consumption_and_processing",
    "02_livestock_systems", "03_feed_use", "04_trade_harmonization", "05_balancing",
    "06_transport_cost", "07_transport", "08_export_link_mean", "08_export_link_sep",
    "09_sensitivity", "10_create_benchmarks", "11_analyse_benchmarks", "12_re-exports",
    "13_supply", "14_use", "15_mrsut", "16_mrio", "17_leontief_inverse",
    "18_hybridize_B_quadrant", "19_invert_B", "20_footprints", "21_probability_maps",
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("year", nargs="?", type=int, default=2013)
    year = ap.parse_args().year
    ok = todo = 0
    for s in STEPS:
        print(f"==== {s} ====")
        r = subprocess.run([sys.executable, str(HERE / f"{s}.py"), str(year)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            ok += 1; print(f"  OK")
        elif "NotImplementedError" in r.stderr:
            todo += 1; print(f"  TODO (not yet ported)")
        else:
            print(f"  FAILED:\n{r.stderr.strip()[-400:]}")
    print(f"\n[run_all] {ok} ran, {todo} TODO, of {len(STEPS)} steps")


if __name__ == "__main__":
    main()

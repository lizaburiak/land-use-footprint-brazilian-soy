# Python port of the pipeline (steps 00-21)

Python reimplementation of the R reproduction (`code/new/`), under the same `data/code/results`
layout. **Status: scaffold** — every step exists as an importable module with an accurate
header (R source, inputs, outputs); the actual logic is ported incrementally. Step **07**
already works (delegates to the validated `code/new/transport_lp/`).

Run one step:   `python code/python/01_consumption_and_processing.py 2013`
Run all steps:  `python code/python/run_all.py 2013`   (ported steps run; others report TODO)

## Port status

| File | Step | Status |
|---|---|---|
| `00_data_preparation.py` | Data preparation — build the municipal soy dataset | ⬜ TODO |
| `00_FAO_consitency_checks.py` | FAO CBS consistency checks | ✅ working (CBS_SOY Δ=0; consistency Δ~1e-8) |
| `01_consumption_and_processing.py` | Consumption & processing allocation | ✅ working (validated vs R, Δ~1e-10) |
| `02_livestock_systems.py` | Livestock systems | ✅ working (12/15 cols Δ=0; chicken Δ≤10 heads in 6/5570 muns, from zonal-stat float precision) |
| `03_feed_use.py` | Feed-use estimation | ✅ working (validated vs R, Δ~1e-15) |
| `04_trade_harmonization.py` | Trade harmonization | ✅ working (validated vs R, Δ=0) |
| `05_balancing.py` | Supply/demand balancing | ✅ working (core validated vs R, Δ~1e-9) |
| `06_transport_cost.py` | Transport-cost network (road/rail/water) | ⬜ TODO |
| `07_transport.py` | Transport optimization (multimode LP) | ✅ working |
| `08_export_link_mean.py` | Link flows to importers (mean) | ⬜ TODO |
| `08_export_link_sep.py` | Link flows to importers (separate) | ⬜ TODO |
| `09_sensitivity.py` | Sensitivity analysis | ⬜ TODO |
| `10_create_benchmarks.py` | Create Trase benchmarks | ⬜ TODO |
| `11_analyse_benchmarks.py` | Analyse benchmarks (correlations + maps) | ⬜ TODO |
| `12_re-exports.py` | Re-exports adjustment | ⬜ TODO |
| `13_supply.py` | FABIO supply table | 🚫 blocked |
| `14_use.py` | FABIO use table | 🚫 blocked |
| `15_mrsut.py` | Multi-regional supply/use tables | 🚫 blocked |
| `16_mrio.py` | Multi-regional input-output table | 🚫 blocked |
| `17_leontief_inverse.py` | Leontief inverse | 🚫 blocked |
| `18_hybridize_B_quadrant.py` | Hybridize the B quadrant (FABIO-EXIOBASE) | 🚫 blocked |
| `19_invert_B.py` | Invert the hybridized B | 🚫 blocked |
| `20_footprints.py` | Land-use footprints | 🚫 blocked |
| `21_probability_maps.py` | Probability maps (grid refinement) | 🚫 blocked |

✅ working · ⬜ TODO (scaffolded, not yet ported) · 🚫 blocked on missing data (FABIO/EXIOBASE
or the step-06 geo files — see `WHAT_IS_MISSING.md`).

## Porting order (suggested)

1. **Tabular, easy** (pandas): 00_FAO, 01, 03, 05 — then 04, 08, 10, 12.
2. **Raster/spatial** (geopandas + rasterio): 02, 11, then 00 (hardest) and 06.
3. **FABIO MRIO** (13-21): blocked until the FABIO/EXIOBASE data is available.

Each port is validated against the R output in `results/outputs/<step>_<year>/`.
Shared paths/helpers are in `_helpers.py`.

## Reading R data (the parquet bridge)

`pyreadr` won't build on this machine, so Python can't read `.rds` directly. Instead, a small
R helper dumps the R intermediate tables to parquet for the Python steps to read:

```bash
Rscript code/python/export_for_py.R 2013   # CBS_SOY, SOY_MUN_00/01/02/04/fin → parquet
                                           # + R reference outputs (e.g. SOY_MUN_03_R) for validation
```
Run it once per year before the ported Python steps. As more steps are ported to Python they
will read each other's parquet directly, shrinking the need for this bridge. (Long term, swap to
`pyreadr`/`feather` once a build is available, or have the R steps emit parquet natively.)

**Example — step 03:**
```bash
Rscript code/python/export_for_py.R 2013
python  code/python/03_feed_use.py 2013     # prints "✓ matches R"
```

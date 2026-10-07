# Runbook

How to run the pipeline on your machine. Everything runs **from the repo root** with
relative paths. For where the input data comes from and where to put it, see
[`DATA.md`](DATA.md); for the folder map see [`STRUCTURE.md`](STRUCTURE.md).

## Quick start

```bash
bash code/run_all.sh              # all years 2000–2020, steps 00–21
bash code/run_all.sh 2004 2020    # a custom year range
bash code/run_all.sh 2013 2013    # a single year
```

`run_all.sh` calls `run_year_full.sh` per year: steps **00–12** (the core model), then
**13–21** (FABIO MRIO + footprints). It continues past a failing year and writes a pass/fail
roll-up to `logs/run_all_summary.txt`.

- **Results:** `data/generated/outputs/<NN>_<YEAR>/` (e.g. `05_2013/SOY_MUN_fin.rds`), plus
  `results/{figures,maps,tables}/` from step 11.
- **Logs:** `logs/year_<YEAR>/<step>.log`.

Transport between municipalities uses straight-line (Euclidean) distances (`07_transport_R`).
Steps **13–21 self-skip** (non-fatal) until the FABIO/EXIOBASE data is present; the rest runs
for 2000–2020 with no extra files.

## Setup (one-time)

Install **R (≥ 4.2)** and the CRAN packages the pipeline uses:

```r
install.packages(c(
  "dplyr","tidyr","data.table","readr","readxl","openxlsx","janitor","stringr","purrr",
  "tibble","reshape2","Matrix","Metrics","transport","abind","gtools","MASS","gmodels",
  "foreach","doParallel","sf","raster","terra","gdistance","exactextractr","fasterize",
  "ggplot2","ggpubr","ggsci","ggpointdensity","patchwork","viridis","xtable"))
```

The geospatial packages need system libs GDAL/GEOS/PROJ (`brew install gdal geos proj` on macOS).

## Year-by-year notes

- **2000–2013** — import trade from Stefan's `btd_bal.rds`; FAOSTAT trade matrix from his 2013
  file (no per-year matrices before 2013). Step 12 (re-exports) works.
- **2014–2020** — import trade from the new multi-year `btd_bal.RData`; own per-year trade matrix.
  Step 12 comes out empty (FABIO export snapshot stops at 2013) — non-fatal.
- Periodic inputs (boundaries, POF, biodiesel) use the nearest available year ≤ target.

## Building the release (procedure of the `e35c056` build, October 2026)

Each year was run from raw inputs in its own worker, so that nothing is shared between years:

```bash
FRESH=1 bash code/setup_worker.sh 2013          # creates <data root>/generated/workers/fp2013
cd <data root>/generated/workers/fp2013
bash code/run_core.sh 2013                      # steps 00-11
bash code/run_fp.sh 2013                        # steps 12-20 and the footprint validation
Rscript code/prep/land_balance_mun.R 2013       # the per-municipality land balance (see below)
```

Then the worker's `outputs/`, `footprints/` and benchmark tables are copied to the data root and
the release is built with `code/build_release_parquet.R`, `code/build_release_db.py` and
`code/build_data_dictionary.py`.

**`land_balance`.** The release table `land_balance` is built from
`footprints/<Y>_land_balance_mun.csv`. In the `e35c056` build these files were written by
`code/prep/land_balance_mun.R <Y>`, run after step 20. Step 20 writes a file of the same name
itself (same function, `code/shared/land_balance.R`); its numbers agree with the standalone
script to within 1e-14 relative but are not bit-identical, because the footprint rows are summed
in a different order. To reproduce the release's `land_balance` byte for byte, run the
standalone script after step 20, as above. Every other release table is reproduced byte for
byte by the steps alone (checked on 2013, 7 October 2026).

## Troubleshooting

- **`cannot open file … .rds`** → an earlier step didn't finish; check that step's log in
  `logs/year_<YEAR>/`.
- **A package fails to load** → install it (above).
- Re-running a year overwrites that year's `data/generated/outputs/<NN>_<YEAR>/` in place.

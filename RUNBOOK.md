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

## Troubleshooting

- **`cannot open file … .rds`** → an earlier step didn't finish; check that step's log in
  `logs/year_<YEAR>/`.
- **A package fails to load** → install it (above).
- Re-running a year overwrites that year's `data/generated/outputs/<NN>_<YEAR>/` in place.

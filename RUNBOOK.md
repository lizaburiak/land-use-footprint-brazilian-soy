# Runbook

How the pipeline is run, and how the `e35c056` release (years 2000-2022) was built. Everything
runs **from the repo root** with relative paths. For where the input data comes from and where
to put it, see [`DATA.md`](DATA.md); for the folder map see [`STRUCTURE.md`](STRUCTURE.md).

## Quick start

The scripts read the data root from `SOYPRINT_DATA_DIR` (default `/mnt/bigdata/projects/soyprint`).
One year, from raw inputs, in its own worker directory:

```bash
FRESH=1 bash code/setup_worker.sh 2013          # <data root>/generated/workers/fp2013
cd <data root>/generated/workers/fp2013
bash code/run_core.sh 2013                      # steps 00-11
bash code/run_fp.sh 2013                        # steps 12-20 and the footprint validation
```

This is the procedure of the release; the full sequence, including the land balance and the
build scripts, is in [Building the release](#building-the-release-procedure-of-the-e35c056-build-october-2026).

- **Years:** 2000-2022, one worker per year. Steps 13-17 write files without a year in their
  name into `generated/fabio/`, so two years must never share a directory.
- **Results:** in the worker, `data/generated/outputs/<NN>_<YEAR>/` (steps 00-12),
  `data/generated/footprints/<YEAR>_*` (step 20) and `results/tables/benchmarks/<YEAR>/`.
- **Logs:** in the worker, `run_logs/<step>.log`, with `core_steps.tsv` and `steps.tsv`
  (exit code, seconds and peak memory per step).
- `code/run_all.sh` and `code/run_year_full.sh` run the same steps in one shared tree. They were
  **not** used for the release, and `run_all.sh` still defaults to 2000-2020.

## Steps

| steps | what | run by |
|---|---|---|
| 00, 00_FAO | municipal inputs; national soy balance | `run_core.sh` |
| 01-05 | consumption and processing, livestock systems, feed, trade, balancing | `run_core.sh` |
| 05b | splits the stock change of step 05 into stock variation, losses and residual (labels for the release; no step reads it) | `run_core.sh` |
| 07, 08 | transport between municipalities (straight-line distances) and the link to export destinations | `run_core.sh` |
| 10, 11 | Trase benchmarks | `run_core.sh` |
| 12 | re-exports | `run_fp.sh` |
| 13-19 | supply and use tables, multi-regional table, Leontief inverse, link to EXIOBASE | `run_fp.sh` |
| 20 | land-use footprints, then `logs/fabio_probe/scripts/validate_footprints.R` | `run_fp.sh` |
| 21 | probability maps (30 m) | by hand: `Rscript code/pipeline/21_probability_maps.R <YEAR>` |

Step 06 (transport cost surface over roads, rail and waterways) is not part of the release,
which uses straight-line distances only. Step 21 is not in `run_fp.sh`; for the release it was
run for 2022 only and produced the maps for China and EU-27 before running out of memory.

**Guards.** These stop the run instead of letting a faulty input through:

- **Step 00:** the IBGE production file must have planted area, harvested area and production
  in columns 5-7, planted area at most 1.5 x harvested, and 1-5 t per harvested hectare. The
  herd file must carry the ten expected herd types, no national herd may be zero (sows before
  2013 excepted), and none may change by more than 30% against the previous year's file.
- **Step 00_FAO:** the balance workbook must have the expected rows and items. The soybean
  cake row is rebuilt (exports from COMEX heading 2304, production 0.75 x beans processed,
  feed = production - exports); the municipal cake exports must match heading 2304 within
  0.5%, and feed cannot be negative.
- **Step 12:** region codes must be sorted and unique, and every soy flow must have both ends
  inside the matrix. Municipal flows with Brazil itself as partner are dropped and logged; more
  than 100 t of them in a year stops the run.
- **Step 17:** no general cap on column sums. Only a column that uses 1 unit or more of its own
  item per unit of output is scaled down (the same-item rule), and each one is logged to
  `footprints/<YEAR>_scaled_columns.csv`.
- **Step 20:** harvested area must equal kept final demand + stock additions dropped +
  balancing dropped + land lost to the columns scaled in step 17, within 0.01%; that last term
  may not exceed 0.5%; no soy-land multiplier, consumer total or product total may be negative.

**Year notes.**

- Import trade (step 04) comes from the 1986-2013 FABIO trade file for years up to 2013 and from
  the 2010-2023 file after that. The FAOSTAT trade matrix is per year from 2014; 2000-2013 share
  one 2013 file.
- Steps 12, 13, 14 and 20 use the FABIO v1.1 files before 2010 and FABIO v2 from 2010.
  Step 12 produces re-exports in every year 2000-2022.
- EXIOBASE is version 3.10.1 for 2000-2020 and 3.9.5 for 2021-2022.
- Steps 10 and 11 skip themselves in years without Trase data (before 2004).
- Periodic inputs (boundaries, POF, biodiesel) use the nearest available year at or before the target.

## Setup

The release was built in a Docker image (`my-r-env`, Ubuntu 24.04) with:

| | version |
|---|---|
| R | 4.6.1 (2026-06-24) |
| Python | 3.12.3, with pyarrow 25.0.1 |
| SQLite | 3.45.1 |
| GDAL / GEOS / PROJ | 3.8.4 / 3.12.1 / 9.4.0 |
| main R packages | Matrix 1.7-5, data.table 1.18.6.1, dplyr 1.2.1, tidyr 1.3.2, sf 1.1-2, raster 3.6-32, terra 1.9-50, arrow 25.0.1, openxlsx 4.2.9 |

The full list (every package the steps load, `sessionInfo()`, the Python packages of the
builders and of `download_data.py`, and the separate Python environment of the multimodal
comparison) is in [`docs/environment_e35c056.txt`](docs/environment_e35c056.txt).

To set up elsewhere, install R and the packages listed there; `sf`, `raster` and `terra` need
the system libraries GDAL, GEOS and PROJ. The schema figure
(`code/db/make_erd_release.py`) also needs Graphviz.

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
the release is built, in this order:

```bash
Rscript code/build_release_parquet.R 2000 2022 <release dir>/parquet
python3 code/build_release_db.py --parquet <release dir>/parquet --out <release dir>/soyprint.sqlite --force
python3 code/build_data_dictionary.py --db <release dir>/soyprint.sqlite --parquet <release dir>/parquet
```

`run_fp.sh` ends with `logs/fabio_probe/scripts/validate_footprints.R`, which `setup_worker.sh`
copies into the worker from the repository's `logs/` folder; that script is not tracked in git.

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
  the worker's `run_logs/`.
- **A package fails to load** → install it (see Setup).
- Re-running a year overwrites that year's `data/generated/outputs/<NN>_<YEAR>/` in place.

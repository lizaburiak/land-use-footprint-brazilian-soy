# Runbook — running the reproduction on your computer

## ⭐ Quick start — run everything

From the **repo root**, one command runs the full pipeline (steps 00–21) for every year:

```bash
bash code/run_all.sh            # all years 2000–2020
bash code/run_all.sh 2004 2020  # a custom year range
bash code/run_all.sh 2013 2013  # a single year
```

What happens:
- For each year it runs `code/run_year_full.sh YYYY` → steps **00–12** (the core model,
  "Path B" Euclidean transport), then steps **13–21** (FABIO MRIO + footprints).
- Steps **13–21 self-skip** with a clear message until the FABIO/EXIOBASE data is present
  (see `WHAT_IS_MISSING.md`); the run does NOT fail because of them.
- It continues past any year that fails, so one bad year doesn't stop the rest.

Where things land:
- **Results:** `data/generated/outputs/<NN>_<YEAR>/` (e.g. `data/generated/outputs/05_2013/SOY_MUN_fin.rds`,
  `data/generated/outputs/12_2013/`), plus `results/{figures,maps,tables}/<YEAR>/` from step 11.
- **Logs:** `logs/year_<YEAR>/<step>.log` (one per step) + a pass/fail roll-up in
  `logs/run_all_summary.txt`.

Run a single year, all steps: `bash code/run_year_full.sh 2013`
Run a single year, core 00–12 only: `bash code/run_year_full.sh 2013`

> First time on a new machine? Do the one-time setup in §1 first (R + packages). The
> rest of this runbook explains data prerequisites, the optional Python transport path,
> per-year caveats, and troubleshooting.

---

## Detail: what runs, and the two transport options

`code/run_all.sh` uses **Path B (Euclidean)** transport — runnable today for 2000–2020 with
no extra files. The alternative multimode transport (Stefan's GAMS model, re-implemented as the
Python `transport_lp`) needs step 06 + extra input files; see §0 and §3. Everything runs **from
the repo root** with relative paths. Examples below use `YEAR=2010`.

---

## 0. What you need to obtain (checklist)

### Path B — nothing missing ✅
You can run Path B right now. Skip to §2.

### Multimode / Python path — these are missing ❌
To run step 06 (and therefore the Python transport), you must add:

The Python (`transport_lp`) itself only reads **`data/generated/outputs/06_YYYY/`** — which is *generated*
by running step 06. Step 06 is what's actually missing input data. Always-missing (any year):

| File | Put it at | Used for |
|---|---|---|
| `RailCargo_2006-21_ANTT.xls` | `data/geo/` | step 06 rail cargo (read by sheet = year) |
| `ip_add.gpkg` | `data/geo/ANTAQ/` | step 06 supplementary ports |
| `train_stations_soy.gpkg` | `data/geo/ANTT/` | step 06 hand-curated soy rail stations |
| `pyreadr` (Python pkg) | `pip install pyreadr` | Python reads/writes `.rds` |

Additionally, ANTAQ waterway cargo for the **target year**:

| Year | ANTAQ cargo files |
|---|---|
| 2017–2020 | ✅ already present (`{YEAR}Carga.txt` + `_Conteinerizada.txt`) |
| ≤ 2016 (e.g. 2010, 2013) | ❌ need `2013Carga.txt` + `2013Carga_Conteinerizada.txt` in `data/geo/ANTAQ/` (Stefan's fallback) |

Source: ANTT (rail) and ANTAQ (waterway) Brazilian open-data portals, plus Stefan's
original 2013 ANTAQ download. They are large and were always git-ignored.

> Note: step 12 (re-exports) is empty for **YEAR ≥ 2014** because Stefan's FABIO export
> snapshot only covers 1986–2013. This is a non-fatal warning, not a failure, and is
> independent of the transport choice.

---

## 1. One-time environment setup

### R (needed for all steps)
Install R (≥ 4.2) and the CRAN packages the pipeline uses. Path B needs only CRAN
packages — **not** the GAMS packages (`gdxrrw`/`gdxdt`), which only `07_transport_GAMS`
uses. In an R console:

```r
install.packages(c(
  "dplyr","tidyr","data.table","readr","readxl","openxlsx","janitor","stringr",
  "purrr","tibble","reshape2","Matrix","Metrics","transport","abind","gtools",
  "MASS","gmodels","foreach","doParallel",
  "sf","raster","terra","gdistance","exactextractr","fasterize",
  "ggplot2","ggpubr","ggsci","ggpointdensity","patchwork","viridis","xtable"
))
```
(The geospatial ones — `sf`, `raster`, `terra`, `gdistance`, `exactextractr`,
`fasterize` — may need system libraries GDAL/GEOS/PROJ. On macOS: `brew install gdal geos proj`.)

### Python (only for the multimode `transport_lp` path)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r code/pipeline/transport_lp/requirements.txt   # pyomo, highspy, pyreadr, pandas, numpy, scipy
```

---

## 2. Run Path B (00 → 12) — the achievable real result

From the repo root:

```bash
bash code/run_year_full.sh 2010
```

What it does: runs `00 → 00_FAO → 01 → 02 → 03 → 04 → 05 → 07_transport_R →
08_mean → 08_sep → 10 → 11 → 12`, logging each step to `logs/year_2010/<step>.log`.
It stops on the first hard failure and prints the log tail.

**Where results land:** `data/generated/outputs/<NN>_2010/` — e.g.:
- `data/generated/outputs/00_2010/SOY_MUN_00.rds` … the municipal supply-chain dataset
- `data/generated/outputs/05_2010/SOY_MUN_fin.rds` … balanced municipal supply/demand
- `data/generated/outputs/08_2010/source_to_export_mean.rds` … origin→importer flows
- `data/generated/outputs/10_2010/comp_list.rds`, `data/generated/outputs/11_*` … Trase benchmarks/correlations
- `data/generated/outputs/12_2010/*` … re-exports (empty for ≥2014; populated for 2010)

**Run EVERYTHING (all years, steps 00–21):**
```bash
bash code/run_all.sh              # every year 2000–2020, full pipeline
bash code/run_all.sh 2004 2020    # custom range
```
`run_all.sh` calls `code/run_year_full.sh YYYY` per year (core steps 00–12, then the
FABIO/footprint steps 13–21 which self-skip when their data is absent), continues past any
failing year, and writes a pass/fail summary to `logs/run_all_summary.txt`.

**Check it worked:**
```bash
ls data/generated/outputs/12_2010/                 # final step produced files?
tail -5 logs/year_2010/12_re-exports.log
```
In step 04's log you'll see which fallback data it used, e.g.
`[04] btd_imp: Stefan's btd_bal.rds (1986-2013) for YEAR=2010` and
`[04] trade matrix: …FAOSTAT_tradematrix_BRAsoy.csv (no 2010-specific file; using Stefan's 2013 fallback)`.

---

## 3. Run the multimode Python transport path

Do this **after** §0's missing files are in place. It replaces the single
`07_transport_R` step with: step 06 → `transport_lp` → step 08.

```bash
# (a) Build the spatial transport-cost layer (rail/port/road distances + capacities)
Rscript code/pipeline/06_transport_cost.R 2010
#   -> data/generated/outputs/06_2010/{stations,ports,cargo_long,dist_matrices}.Rdata

# (b) Export step-05 + step-06 tables to Parquet (lets Python read without pyreadr)
Rscript code/pipeline/transport_lp/export_to_parquet.R 2010

# (c) Run the LP WITHOUT the missing step-06 geo data: build a synthetic step-06
#     fixture from the real year's supply/demand, then solve + audit it (~1s).
source .venv/bin/activate   # only needed if you made a venv
python code/pipeline/transport_lp/make_fixture.py 2010 --n-mun 40
python code/pipeline/transport_lp/smoke_test.py  2010 --suffix smoke   # expect "PASS"

# (d) One deterministic solve with Stefan's mean cost parameters
python code/pipeline/transport_lp/solve_one.py 2010
#   -> data/generated/outputs/gams/bs_res_2010/00000.rds  (needs pyreadr to write the .rds)

# (e) Bootstrap × N iterations (Stefan used 1000; start small to test)
python code/pipeline/transport_lp/bootstrap.py 2010 --n-iters 20 --workers 4
#   -> data/generated/outputs/gams/bs_res_2010/00001.rds … and bs_par.csv

# (f) Hand the Python flows back to the R pipeline (same files GAMS would have written)
Rscript code/pipeline/08_export_link_mean.R 2010
Rscript code/pipeline/08_export_link_sep.R  2010
Rscript code/pipeline/10_create_benchmarks.R 2010
Rscript code/pipeline/11_analyse_benchmarks.R 2010
Rscript code/pipeline/12_re-exports.R 2010
```

`transport_lp` writes `.rds` flow matrices into `data/generated/outputs/gams/bs_res_2010/` in **exactly the
format Stefan's GAMS path produced**, so step 08 consumes them unchanged.

> Without the §0 files you can still run (c) the synthetic test — it proves the LP
> works, but uses a 3-municipality toy network, not real geography.

---

## 4. Year-by-year notes (2000–2020, Path B)

- **2000–2013** — import trade from Stefan's `btd_bal.rds`; FAOSTAT trade matrix from
  Stefan's 2013 file (no per-year matrices before 2013 exist). Step 12 works.
- **2014–2020** — import trade from the new `btd_bal.RData`; own per-year trade matrix.
  Step 12 (re-exports) comes out empty (FABIO export snapshot stops at 2013) — non-fatal.
- Periodic inputs (municipal boundaries, POF, biodiesel) use the nearest available
  year ≤ target when an exact-year file is absent.

## 5. Troubleshooting

- **`cannot open file ... .rds` in a step** → an earlier step didn't finish; check that
  step's log in `logs/year_<YEAR>/`.
- **A package fails to load** → install it (see §1). If it's `gdxrrw`/`gdxdt`, you're
  accidentally running the GAMS step `07_transport_GAMS` — Path B does not need it.
- **`ModuleNotFoundError: pyreadr`** → `pip install pyreadr` inside the venv.
- **step 06 `stop(... ANTAQ ...)`** → add the §0 ANTAQ files (or use 2017–2020 which
  already have theirs).
- **Re-running a year overwrites** that year's `data/generated/outputs/<NN>_<YEAR>/` in place.

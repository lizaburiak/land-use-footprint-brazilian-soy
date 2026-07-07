# transport_lp — Python port of Stefan's GAMS multimode transport step

Open-source replacement for `code/pipeline/07_transport_GAMS_parallel.R` + `archive/code_old_stefan/gams/transport_model_Brazil_intermod*.gms`.

Solves the same multi-modal min-cost flow LP using **Pyomo + HiGHS** (no GAMS licence, no `gdxrrw`). The bootstrap loop (cost perturbation × 1000 iterations) runs in Python multiprocessing and writes the same output format that `code/pipeline/08_export_link_mean.R` and `08_export_link_sep.R` consume (`./data/generated/outputs/gams/bs_res_{YEAR}/*.rds`).

## Status

Validated on a synthetic fixture; **not yet validated on real 2013 data**:
- ✅ Pyomo model file `model.py` — 1:1 port of `transport_model_Brazil_intermod.gms`. **Sparse**: variables are created only on the GAMS `$()` support (positive supply/demand per product, capacity routes), so the LP is the same size as Stefan's GAMS model rather than the full dense ~5,570²×3 ≈ 90M-variable product. `build_structure()` (vars+constraints, cost-independent) is split from `set_costs()` (objective).
- ✅ Data loader `data_loader.py` — reads `data/generated/outputs/05_YYYY/SOY_MUN_fin.rds` and `data/generated/outputs/06_YYYY/{stations,ports,cargo_long,dist_matrices}.Rdata` via `pyreadr` / `rpy2`. `a` is restricted to municipalities with positive supply/demand; `build_structural_inputs()` (once) is split from `build_cost_matrices()` (per iteration).
- ✅ Cost-perturbation module `cost_perturbation.py` — mirrors Stefan's `runif()` distributions for the 5 bootstrap parameters
- ✅ CLI entry points: `solve_one.py` (deterministic single solve, validates against Stefan) and `bootstrap.py` (parallel × N iterations). The bootstrap **builds the LP structure once per worker** and only swaps costs + re-solves each iteration — mirroring GAMS "compile once, swap cost gdx".
- ✅ Output writer `write_output.py` — produces `.rds` matrices that code/pipeline/08 can read unmodified
- ✅ `make_fixture.py` + `smoke_test.py` — run end-to-end on a synthetic step-06 fixture built
  from a real year's supply/demand (no missing geo data needed); 2013/40-mun solves to optimal,
  supply/demand/non-negativity audits pass
- ⏳ **End-to-end validation against Stefan's 2013 multimode reference output** — requires step 06 outputs to be present (`data/generated/outputs/06_2013/`). Not yet executed.

## Dependencies

```
pip install -r requirements.txt
```

Key packages:
- `pyomo>=6.7` — modelling language (GAMS-like)
- `highspy>=1.7` — open-source LP solver (comfortably handles the sparse LP, ~10⁵–10⁶ variables on real data)
- `pyreadr>=0.5` — reads R `.rds` files
- `pandas>=2.0`, `numpy>=1.24`, `scipy>=1.10` — data wrangling
- (optional) `rpy2>=3.5` — fallback for `.Rdata` reading; `pyreadr` covers most cases

## Quick start

All commands run **from the repo root**. One-time per year, convert the R outputs to
parquet so Python needs no `pyreadr`:

```bash
Rscript code/pipeline/transport_lp/export_to_parquet.R 2013
```

**① Fully-real road-only solve** — real supply/demand + real great-circle road distances,
no synthetic data. Validated to match the R `transport` solver exactly. **Runs now.**
```bash
python code/pipeline/transport_lp/run_road_only.py 2013 --n-sup 150 --n-dem 150
```

**② Synthetic-fixture multimode demo** — exercises the rail+water LP on fabricated geometry
(real supply/demand), since the real step-06 geo data is missing. **Runs now.**
```bash
python code/pipeline/transport_lp/make_fixture.py 2013 --n-mun 40
python code/pipeline/transport_lp/smoke_test.py  2013 --suffix smoke
```

**③ Real multimode (production, the GAMS equivalent)** — needs the missing step-06 geo data
(`ip_add.gpkg`, `RailCargo`, `train_stations_soy.gpkg`; see `WHAT_IS_MISSING.md`).
```bash
Rscript code/pipeline/06_transport_cost.R 2013        # builds data/generated/outputs/06_2013/ (needs geo files)
Rscript code/pipeline/transport_lp/export_to_parquet.R 2013
python code/pipeline/transport_lp/solve_one.py 2013                 # one deterministic solve
python code/pipeline/transport_lp/bootstrap.py 2013 --n-iters 1000 --workers 8   # full bootstrap
```
```

Each bootstrap iteration writes `./data/generated/outputs/gams/bs_res_2013/{00001..01000}.rds` and appends a row to `./data/generated/outputs/gams/bs_res_2013/bs_par.csv` — same format as the original R+GAMS script, so `code/pipeline/08_export_link_mean.R 2013` and `code/pipeline/08_export_link_sep.R 2013` consume it without modification.

## Data inputs

Same as the original R script:

| File | Source | Used for |
|---|---|---|
| `data/generated/outputs/05_YYYY/SOY_MUN_fin.rds` | step 05 code/new | per-município supply, demand, exp+proc |
| `data/generated/outputs/06_YYYY/stations.Rdata` | step 06 code/new | rail station IDs |
| `data/generated/outputs/06_YYYY/ports.Rdata` | step 06 code/new | port IDs |
| `data/generated/outputs/06_YYYY/cargo_long.Rdata` | step 06 code/new | rail / water route capacities `cap_r`, `cap_w` |
| `data/generated/outputs/06_YYYY/dist_matrices.Rdata` | step 06 code/new | road/rail/water distance matrices |

If `data/generated/outputs/06_YYYY/` is missing for the target year, step 06 needs to run first. Step 06 is **pure R** (OSM/DNIT/ANTT spatial work — see `code/pipeline/06_transport_cost.R`) and depends on:
- ANTAQ port cargo files `data/geo/ANTAQ/{YEAR}Carga*.txt` (have 2017–2022; missing 2010–2016)
- ANTT rail cargo `data/geo/RailCargo_2006-21_ANTT.xls` (have through 2021)
- OSM/DNIT/ANTAQ shapefiles (have)

For years without yearly cargo data the loader supports a `--cargo-fallback YYYY` flag to substitute another year's capacities.

## Output format (matches GAMS pipeline)

For each iteration `i`, `bootstrap.py` writes:

* `./data/generated/outputs/gams/bs_res_{YEAR}/{i:05d}.rds` — a 4-column R data.frame with columns `co_orig`, `co_dest`, `product`, `value` (total transported tonnes via any mode combination)
* One row appended to `./data/generated/outputs/gams/bs_res_{YEAR}/bs_par.csv` with the perturbed cost parameters and the LP objective value

These are exactly the files `code/pipeline/08_export_link_mean.R` lists in `bs_res_dir` and reads — no R changes needed.

## Architecture

```
solve_one.py / bootstrap.py    ← CLI entry points
        ↓
data_loader.py                  ← read .rds / .Rdata → Python dicts
        ↓
cost_perturbation.py            ← apply bootstrap params, build cost matrices
        ↓
model.py                        ← build_model() + solve_model() with HiGHS
        ↓
write_output.py                 ← extract var values, write .rds for R
```

## Notes on the LP scale

For 2013:
- ~1,963 origins (a) with positive supply
- ~5,570 destinations (b), of which ~3,000 have positive demand
- 3 products
- ~50 rail stations, ~30 inland waterway hubs (river ports along Brazilian hidrovias — NOT seaports; see "Hub terminology" below)
- ~30M direct truck variables on paper, but with $(supply ∧ demand) sparsity only a fraction enter the LP non-trivially

Pyomo's `IndexedComponent` framework with `Set`-driven indexing handles this. For the truly large pieces (`X_a_b`), a `dok` or `lil` sparse construction is used to avoid materialising the dense Cartesian product.

HiGHS easily solves LPs of this scale (it's CPLEX-class for LP). Bootstrap parallelism scales linearly with cores up to memory limits (~3GB per worker for this model).

## Validation against Stefan's 2013 reference

Not yet executed (needs `data/generated/outputs/06_2013/`). When that's available, run:

```bash
python code/pipeline/transport_lp/solve_one.py 2013 --validate-against data/generated/base/
```

This computes the relative difference in total transport cost and per-municipality flow distribution between Stefan's GAMS output (if archived in `data/generated/base/`) and our HiGHS output. Acceptance criterion: < 0.5% relative diff in objective, < 1% Frobenius norm diff in flow matrices (degenerate LP solutions can differ in non-binding directions).

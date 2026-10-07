# Stage 2 smoke test + Stage 4 inventory + schema gap analysis

Generated 2026-09-09T16:03:06+02:00. Year 2013. Steps invoked directly (`run_year_full.sh` not used,
and not modified).

## Stage 2 — smoke-test result

| Step | Result | Time | Note |
|---|---|---|---|
| 00_data_preparation | **OK** | 38s | 5,570 municipalities, 39 vars; POF fell back to 2008 as designed |
| 00_FAO | **OK** | 1s | |
| 01_consumption | **OK** | 2s | |
| 02_livestock | **OK** | 22s | all 8 GLW3/GLEAM rasters read |
| 03_feed | **OK** | 3s | |
| 04_trade | **OK** | 36s | used the documented 2013 trade-matrix fallback |
| 05_balancing | **OK** | 2s | `all items balanced: TRUE` |
| 07_transport_R | **OK** | 4s | Euclidean; no `data/geo/` required |
| 08_export_link_mean | **OK** | 4s | Euclidean-only (no GAMS bootstrap) |
| 08_export_link_sep | **OK** | 2s | |
| **10_create_benchmarks** | **FAILED** exit 1 | — | see error below |
| 11_analyse_benchmarks | **SKIPPED** exit 0 | — | self-skips cleanly |
| 12_re-exports | **OK** | ~60s | 2,068,993-row `btd_final` produced |

Total wall time for 00-08: about two minutes. Sanity check: step 00 reports production
81,724,477 t for 2013, matching IBGE's published soy harvest.

### The one genuine data failure

```
Error: No TRASE CSV found. Expected one of: data/trase/BRAZIL_SOY_2013_TRASE.csv,
data/trase/BRAZIL_SOY_2.5.1_TRASE.csv, data/trase/brazil_soy_v2_6_1_composite.csv
```

`10_create_benchmarks.R:52` — a hard `stop()`. Because `run_year_full.sh:57` runs step 10
with `|| exit 1`, **the documented entrypoint aborts every year at step 10** and never
reaches step 12, even though step 12 works.

### Two corrections to my own Stage 1 report

1. **Step 11 does not fail — it skips cleanly (exit 0).** Its guard at
   `11_analyse_benchmarks.R:45-51` returns before the GADM `st_read` on line 54. The missing
   GADM shapefile therefore does *not* block step 11 today; it would only bite once Trase
   data is supplied. Step 10 is the only real data blocker in 00-12.
2. **Step 12 runs and produces output.** I listed it as "blocked upstream"; that is true only
   of the runner, not of the step.

A third, benign observation: step 01 prints one `FALSE` among its balance checks
(`01_consumption_and_processing.R:52`). It is a floating-point artefact — the script uses
exact `==` on doubles. Measured relative difference 1.3e-16; `all.equal()` is TRUE. Not a
data problem, but it will read as a failure to anyone scanning the logs.

### Environment changes made

Installed into `~/R/x86_64-pc-linux-gnu-library/4.6` (user library; system R untouched):
`abind`, `transport`, `raster`, `exactextractr`, `mapview`, `leafsync` (needed by 00-08),
then `gmodels`, `ggsci`, `ggpubr`, `ggpointdensity`, `xtable`, `gtools`, `Metrics`, `reshape2`
so that steps 10/11 would fail on *data* rather than on a missing package — otherwise the
reported error would have been `there is no package called gmodels`, which would have hidden
the real blocker. Still not installed: `terra`, `gdistance`, `fasterize`, `foreach`,
`doParallel`, `janitor`-adjacent extras not required by any step that can currently run.

Python `duckdb` is still **not** installed — Stage 6 remains blocked.

## Stage 4 — output inventory

Full inventory: `results/reference/output_inventory.csv` (50 files, 50 rows, one year).
Recorded per file: path, bytes, format, object class, nrow, ncol, column names, notes.
Total footprint for 2013 alone: ~600 MB, dominated by two distance matrices (233 MB each).

| Step dir | Files | Largest artefact |
|---|---|---|
| `00_2013/` | 21 | `MUN_capital_dist.rds` 233 MB |
| `01_2013/` | 2 | `GEO_MUN_SOY_01.rds` 15.6 MB |
| `02_2013/` | 3 | `GEO_MUN_SOY_02.rds` 15.8 MB |
| `03_2013/` | 4 | `GEO_MUN_SOY_03.rds` 15.9 MB |
| `04_2013/` | 8 | `regions.csv` 48 KB |
| `05_2013/` | 5 | `GEO_MUN_SOY_fin.rds` 16.1 MB |
| `07_2013/` | 1 | `flows_euclid.rds` 230 KB |
| `08_2013/` | 3 | `source_to_export_mean.rds` 697 KB |
| `12_2013/` | 3 | `btd_final.rds` 14.1 MB |

## Schema gap analysis

**Figure 5 was not available to me** — it lives in the Overleaf draft, not this repo. So this
is not a comparison against Figure 5. It is an inventory-side statement of what the outputs
can and cannot support, which the author team can hold against the figure.

### Candidate fact-shaped outputs

| Output | Grain | Shape |
|---|---|---|
| `05/SOY_MUN_fin.rds` | municipality | 5,570 x 42, **wide** across product x flow |
| `05/EXP_MUN_SOY_cbs.rds` | municipality x HS4 x destination | 2,254 x 11 |
| `05/IMP_MUN_SOY_cbs.rds` | municipality x HS4 x origin | 47 x 11 |
| `08/flows_mu.rds` | origin mun x dest mun x product | 18,774 x 5 (`euclid`, `mean` scenarios) |
| `08/source_to_export_mean.rds` | list of 2 scenarios, each 38,842 x 4 | not a table |
| `05/CBS_SOY_bal.rds` | product (national) | 3 x 15, product in **rownames** |
| `02/LIVESTOCK_MUN_02.rds` | municipality | 5,570 x 27 |
| `03/{bean,cake}_feed_t.rds` | municipality | 5,570 x 15 each |
| `12/btd_final.rds` | year x item x from x to | 2,068,993 x 6 (global FABIO, not soy-only) |

### Candidate dimension-shaped outputs

| Dimension | Source | Status |
|---|---|---|
| Municipality | `SOY_MUN_fin` cols 1-4 + geometry in `GEO_MUN_SOY_fin.rds` | **derivable** (5,570 rows) |
| Country / region | `04/regions.rds` 294 x 21 (COMEX/FAO/BTD/ISO concordance) | **directly usable** |
| Product | — | **no standalone table exists** |
| Year | — | **no year column exists** |

### Four blockers for any release database

1. **No `year` column.** Only 4 of 31 data-frame outputs carry one (`btd_*`, `cbs_full`); for
   the other 27 the year exists solely in the directory name `NN_{YEAR}`. Any build script
   must inject it. This is fine but must be deliberate, and it is the partition key.
2. **The core table is wide, not tidy.** `SOY_MUN_fin` encodes product and flow in the column
   *name* (`prod_bean`, `exp_oil`, `feed_cake`, ...). Turning it into a fact table requires an
   editorial column-name -> (product, flow) mapping that is **not documented anywhere in the
   code**. Getting it wrong silently mislabels the headline numbers.
3. **No units are recorded anywhere.** Zero of `SOY_MUN_fin`'s 42 columns carry a `units` or
   `label` attribute, and the object has no metadata attributes at all. Every unit in the
   dictionary must come from the author team. Column names *suggest* tonnes, t/day and
   hectares, but I have deliberately not asserted that.
4. **The footprint results do not exist.** Steps 13-21 never ran. Any fact table about
   land-use footprints — the paper's headline result — has **no source at all**, and neither
   do the Trase validation tables (step 10) or the probability maps (step 21).

A release database built today would therefore cover the *supply-chain* half of the model
(municipal balances, inter-municipal flows, export linkage, re-exports) and none of the
*footprint* half.

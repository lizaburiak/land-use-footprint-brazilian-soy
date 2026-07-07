# code/pipeline/ changelog

Minimal-delta forks of Stefan Trsek's 2013 pipeline, adapted to run year-parameterized against the updated `data/new/00/new/` data sources. Each script's section lists what changed vs. `R/<script>.R`.

## Paths policy
- Raw data: `data/new/00/old/` → `data/new/00/new/<subfolder>/` with year suffix where applicable.
- Outputs: `results/outputs/NN/` → `results/outputs/NN_{YEAR}/`.
- Year: passed as `commandArgs(trailingOnly=TRUE)[1]`, default 2013. Range 2000–2022.

---

## 00_data_preparation.R (now in code/pipeline/00_data_preparation/)
See `code/pipeline/00_data_preparation/00_data_preparation.R` and the annotated blocks inside.
Main deltas vs R/00_data_preperation.R:
- Year parameterization + YEAR range guard (2000–2022)
- All paths moved to `data/new/00/new/<subfolder>/` with year selection
- Processing block (§1.4): replaced Stefan's 2013-only `processing_MUN` sheet with a per-year dispatcher that reads `ABIOVE_raw_capacity_2025.xlsx` sheet 2 (state capacity) and year-specific `pesquisa_capacidade_*` files (plant roster), then applies Trsek's equal-per-state allocation
- Refining block (§1.4b): new block that mirrors processing for `ref_cap` and `bot_cap`
- Bugfix: `.abiove_state_cap()` now restricts to Processamento block only (was summing Proc+Refino+Envase)
- Stray `!!!!!!!!!!!` parse error on line 855 removed
- Removed redundant hardcoded `YEAR <- 2013` on line 72

---

## 00_FAO_consistency_checks.R
File: `code/pipeline/00_FAO_consitency_checks.R` (pre-existing; now year-parameterized)

| Line (Stefan) | Change |
|---|---|
| 9 | `"results/outputs/00/CBS_SOY.rds"` → `paste0("results/outputs/00_", YEAR, "/CBS_SOY.rds")` |
| 10 | `"results/outputs/00/SOY_MUN_00.rds"` → `paste0("results/outputs/00_", YEAR, "/SOY_MUN_00.rds")` |
| 11 | `"data/new/00/CBS_SOY_2013_FAO.xlsx"` → `paste0("data/new/00/new/FAO_CBS/CBS_SOY_", YEAR, "_FAO.xlsx")` |
| top | Added `YEAR` parse from `commandArgs(trailingOnly=TRUE)`, default 2013 |
| bottom | `saveRDS` output paths moved to `results/outputs/00_{YEAR}/` |

---

## 01_consumption_and_processing.R
File: `code/pipeline/01_consumption_and_processing.R` (created)

Source: copy of `R/01_consumption_and_processing.R`.

| Line (Stefan) | Change |
|---|---|
| top | Added `YEAR <- as.integer(commandArgs(trailingOnly=TRUE)[1])` with default 2013 |
| 9–11 | Input paths: `results/outputs/00/*` → `paste0("results/outputs/00_", YEAR, "/*")` |
| 93–94 | Output paths: `results/outputs/01/*` → `paste0("results/outputs/01_", YEAR, "/*")` + `dir.create()` |

No logic changes.

---

## 04_trade_harmonization.R
File: `code/pipeline/04_trade_harmonization.R` (created)

Source: copy of `R/04_trade_harmonization.R`.

| Line (Stefan) | Change |
|---|---|
| top | Added `YEAR <- as.integer(commandArgs(trailingOnly=TRUE)[1])` with default 2013, range guard 2000–2022 |
| 15–16 | Input paths: `results/outputs/00/{EXP,IMP}_MUN_SOY_00.rds` → `paste0("results/outputs/00_", YEAR, "/...")` |
| 19–20 | `btd_imp`: switched from `readRDS("data/new/04/FABIO/btd_bal.rds") %>% filter(year == 2013)` to `load("data/new/04/FABIO/new/btd_bal.RData")` (covers 2010–2023) when present, else fall back to Stefan's `.rds`. In both cases, filter is now `year == YEAR`. |
| 21–24 | `btd_exp` / `btd_exp_pure`: kept Stefan's `data/new/04/FABIO/FABIO_exp/{v1,pure}/btd_bal.rds`, only changed `filter(year == 2013)` → `filter(year == YEAR)`. **Limitation:** these snapshots cover 1986–2013 only — for `YEAR ≥ 2014` the filtered tables are empty and a warning is emitted. Updated FABIO_exp data must be provided to fully run later years. |
| 26 | Trade matrix: prefer `data/new/04/FAOSTAT_tradematrix_BRAsoy_{YEAR}.csv` if present, else fall back to Stefan's 2013 `data/new/04/FABIO/FAOSTAT_tradematrix_BRAsoy.csv`. |
| 207–219 | Output paths: `results/outputs/04/*` → `paste0("results/outputs/04_", YEAR, "/*")` + `dir.create()` |

No other logic changes.

### Data dependencies for full year-extension
- `data/new/04/FABIO/new/btd_bal.RData` — multi-year (2010–2023) FABIO bilateral trade for the regular flow. **Provided.**
- `data/new/04/FABIO/FABIO_exp/v1/btd_bal.rds` — Stefan's 2013, needs multi-year refresh. **Missing for YEAR ≥ 2014.**
- `data/new/04/FABIO/FABIO_exp/pure/btd_bal.rds` — Stefan's 2013, needs multi-year refresh. **Missing for YEAR ≥ 2014.**
- `data/new/04/FAOSTAT_tradematrix_BRAsoy_{YEAR}.csv` — already present for 2014–2024.

---

## 05_balancing.R
File: `code/pipeline/05_balancing.R` (created)

Source: copy of `R/05_balancing.R`.

| Line (Stefan) | Change |
|---|---|
| top | Added `YEAR <- as.integer(commandArgs(trailingOnly=TRUE)[1])` with default 2013, range guard 2000–2022 |
| 10–14 | Input paths: `results/outputs/{03,00,04}/*` → `paste0("results/outputs/{03,00,04}_", YEAR, "/*")` |
| 137–143 | Output paths: `results/outputs/05/*` → `paste0("results/outputs/05_", YEAR, "/*")` + `dir.create()` |

No logic changes.

---

## 07_transport_R.R
File: `code/pipeline/07_transport_R.R` (created)

Source: copy of `R/07_transport_R.R`.

| Stefan path | Change |
|---|---|
| top | Added `YEAR` arg parsing + range guard |
| `results/intermediate/SOY_MUN_fin.rds` | → `results/outputs/05_{YEAR}/SOY_MUN_fin.rds` |
| `results/intermediate/MUN_capital_dist.rds` | → `results/outputs/05_{YEAR}/MUN_capital_dist.rds` |
| `results/intermediate/flows_euclid.rds` | → `results/outputs/07_{YEAR}/flows_euclid.rds` |

No logic changes.

---

## 08_export_link_mean.R / 08_export_link_sep.R
Files: `code/pipeline/08_export_link_mean.R` and `code/pipeline/08_export_link_sep.R` (created)

Sources: copies of the same-named scripts under `R/`.

Both files use the same path renames:

| Stefan path | Change |
|---|---|
| top | Added `YEAR` arg parsing + range guard |
| `results/intermediate/flows_euclid.rds` | → `results/outputs/07_{YEAR}/flows_euclid.rds` |
| `./results/outputs/gams/bs_res` listing | → `./results/outputs/gams/bs_res_{YEAR}/` |
| `results/intermediate/SOY_MUN_fin.rds` | → `results/outputs/05_{YEAR}/SOY_MUN_fin.rds` |
| `results/intermediate/EXP_MUN_SOY_cbs.rds` | → `results/outputs/05_{YEAR}/EXP_MUN_SOY_cbs.rds` |
| `results/intermediate/IMP_MUN_SOY_cbs.rds` | → `results/outputs/05_{YEAR}/IMP_MUN_SOY_cbs.rds` |
| `results/intermediate/{flows_mu, source_to_export_mean}.rds` (mean version) | → `results/outputs/08_{YEAR}/` |
| `results/intermediate/source_to_export_list.rds` (sep version) | → `results/outputs/08_{YEAR}/` |

No logic changes.

---

## 09_sensitivity.R
File: `code/pipeline/09_sensitivity.R` (created)

Source: copy of `R/09_sensitivity.R`.

| Stefan path | Change |
|---|---|
| top | Added `YEAR` arg parsing + range guard |
| `source("R/00_function_library.R")` | → `source("code/pipeline/00_function_library.R")` |
| `results/intermediate/SOY_MUN_fin.rds` | → `results/outputs/05_{YEAR}/SOY_MUN_fin.rds` |
| `results/intermediate/flows_euclid.rds` | → `results/outputs/07_{YEAR}/flows_euclid.rds` |
| `./results/outputs/gams/bs_res` listing | → `./results/outputs/gams/bs_res_{YEAR}/` |
| `results/intermediate/comp_list.rds` | → `results/outputs/10_{YEAR}/comp_list.rds` (note: 10 must run before 09 to produce this file — same dependency direction as Stefan's pipeline) |
| `results/figures/sensi_*.png` | → `results/figures/{YEAR}/sensi_*.png` |
| `results/intermediate/flows_mu_comp.rds` | → `results/outputs/09_{YEAR}/flows_mu_comp.rds` |

No logic changes.

---

## 10_create_benchmarks.R
File: `code/pipeline/10_create_benchmarks.R` (created)

Source: copy of `R/10_create_benchmarks.R`.

| Stefan path | Change |
|---|---|
| top | Added `YEAR` arg parsing + range guard |
| `source("R/00_function_library.R")` | → `source("code/pipeline/00_function_library.R")` |
| `results/intermediate/SOY_MUN_fin.rds`, `EXP_MUN_SOY_cbs.rds`, `CBS_SOY_bal.rds` | → `results/outputs/05_{YEAR}/` |
| `results/intermediate/EXP_MUN_SOY.rds` | → `results/outputs/04_{YEAR}/EXP_MUN_SOY.rds` |
| `results/intermediate/{source_to_export_mean,source_to_export_list}.rds` | → `results/outputs/08_{YEAR}/` |
| `results/intermediate/regions.rds` | → `results/outputs/04_{YEAR}/regions.rds` |
| `data/old/BRAZIL_SOY_2.5.1_TRASE.csv` | Prefer `data/old/BRAZIL_SOY_{YEAR}_TRASE.csv` if present, else fall back to Stefan's 2013 baseline |
| `results/intermediate/{comp_list,EXP_NAT_wide}.rds` | → `results/outputs/10_{YEAR}/` |
| `results/tables/export_summary_sorted.tex` | → `results/tables/{YEAR}/export_summary_sorted.tex` |

No logic changes. `data/old/trase_names.csv` kept at Stefan's path (static lookup).

---

## 11_analyse_benchmarks.R
File: `code/pipeline/11_analyse_benchmarks.R` (created)

Source: copy of `R/11_analyse_benchmarks.R`.

| Stefan path | Change |
|---|---|
| top | Added `YEAR` arg parsing + range guard |
| `source("R/00_function_library.R")` | → `source("code/pipeline/00_function_library.R")` |
| `results/intermediate/SOY_MUN_fin.rds`, `GEO_MUN_SOY_fin.rds`, `MUN_capital_dist.rds`, `CBS_SOY_bal.rds` | → `results/outputs/05_{YEAR}/` |
| `results/intermediate/{comp_list,EXP_NAT_wide}.rds` | → `results/outputs/10_{YEAR}/` |
| `results/maps/map_benchmark_*.png` | → `results/maps/{YEAR}/map_benchmark_*.png` |
| `results/figures/{scatter_global,scatter_targets}.png` | → `results/figures/{YEAR}/` |
| `results/tables/{pearson_dest,rmse_dest}.tex` | → `results/tables/{YEAR}/` |

No logic changes. The `data/old/geo/GADM_boundaries/gadm36_BRA_1.shp` file is kept at Stefan's path (static).

---

## 12_re-exports.R
File: `code/pipeline/12_re-exports.R` (created)

Source: copy of `R/12_re-exports.R`.

| Stefan path / value | Change |
|---|---|
| top | Added `YEAR` arg parsing + range guard |
| Comment "calculations are restricted to 2013" | → "calculations year-parameterized via YEAR" |
| `results/intermediate/SOY_MUN_fin.rds` | → `results/outputs/05_{YEAR}/SOY_MUN_fin.rds` |
| `data/old/FABIO/FABIO_exp/v1/btd_bal.rds` | → `data/new/04/FABIO/FABIO_exp/v1/btd_bal.rds` (path consistency with rest of project) |
| `data/old/FABIO/FABIO_exp/v1/cbs_full.rds` | → `data/new/04/FABIO/FABIO_exp/v1/cbs_full.rds` |
| `data/old/FABIO/FABIO_exp/items.csv` | → `data/new/04/FABIO/FABIO_exp/items.csv` |
| `results/intermediate/regions.rds` | → `results/outputs/04_{YEAR}/regions.rds` |
| `results/intermediate/{EXP,IMP}_MUN_SOY_cbs.rds` | → `results/outputs/05_{YEAR}/` |
| `results/intermediate/flows_mu.rds` | → `results/outputs/08_{YEAR}/flows_mu.rds` |
| `filter(year == 2013)` (×2) | → `filter(year == YEAR)` |
| Hard-coded `year = 2013` (×2) | → `year = YEAR` |
| `results/intermediate/FABIO/{reex,btd_final,cbs_full}.rds` | → `results/outputs/12_{YEAR}/` |
| Added: warning if FABIO_exp v1 returns 0 rows for the target year |

No logic changes. `code/shared/fabio_tidy_functions.R` source kept (shared helper).

### Known data limitation for 12
Stefan's `data/new/04/FABIO/FABIO_exp/v1/{btd_bal,cbs_full}.rds` snapshots cover years 1986–2013. For `YEAR ≥ 2014` the script emits a warning and produces empty/zero output until updated FABIO_exp data is provided (rebuild from `github.com/fineprint-global/fabio` or contact Martin Bruckner at WU Vienna). The user-provided multi-year `data/new/04/FABIO/new/btd_bal.RData` (2010–2023) is the regular FABIO base, **not** the FABIO_exp v1 variant — these are produced by separate methodologies.

---

## Path B fixes (bootstrap-absent / TRASE v2.6.1) — 2026-05-11

External-data constraints forced a deviation from the full multimodal pipeline. ANTAQ port cargo (`Carga.txt`) and ANTT rail cargo (`RailCargo_2006-21_ANTT.xls`) were not obtainable for 2010–2013 (ANTAQ portal returns 401/404, dados.gov.br link is broken, files were never committed to Stefan's GitHub dev branch either). To make the chain runnable end-to-end, scripts 07 → 12 were adapted to work without the GAMS bootstrap and with the newer TRASE v2.6.1 schema. Steps 06 and 07_GAMS remain unchanged (they require the missing cargo data) — Path B simply bypasses them via `code/pipeline/07_transport_R.R` (Euclidean only).

### 07_transport_R.R
- Read `MUN_capital_dist.rds` from `results/outputs/00_{YEAR}/` instead of `results/outputs/05_{YEAR}/`. (It is produced by step 00, not step 06.)

### 08_export_link_mean.R / 08_export_link_sep.R
- Detect missing `./results/outputs/gams/bs_res_{YEAR}/` directory or empty bootstrap. If absent, run with `flows_euclid` alone.
- In `08_mean`: when no bootstrap is present, the `mean` column collapses to the euclidean flow (instead of averaging over simulations).

### 10_create_benchmarks.R
- **TRASE v2.5.1 ↔ v2.6.1 schema adapter** at the top:
  - File search order: year-specific (`BRAZIL_SOY_{YEAR}_TRASE.csv`) → v2.5.1 baseline → v2.6.1 composite (`brazil_soy_v2_6_1_composite.csv`).
  - When v2.6.1 detected (column `country_of_first_import` present), remap columns to v2.5.1 conventions: `state→STATE`, `municipality_of_production→MUNICIPALITY`, `country_of_first_import→COUNTRY`, `economic_bloc→ECONOMIC.BLOC`, `volume→SOY_EQUIVALENT_TONNES`, `municipality_of_production_trase_id→TRASE_GEOCODE`.
  - Construct `ISOA3` (3-letter) from `country_of_first_import_trase_id` (2-letter) via inline ISO-2→ISO-3 lookup. (v2.6.1 doesn't carry a 3-letter ISO column; trase_names.csv lookup is bypassed when ISOA3 is built directly.)
  - Filter to `year == YEAR` if multi-year file.
  - `LAND_USE_HA` set to NA (not present in v2.6.1 composite; downstream code drops it anyway).
- **Bootstrap-absent guard** when reading `source_to_export_list.rds`:
  - If file missing, fall back to `source_to_export_mean.rds` alone.
  - If list has only 1 element (single-flow euclid), skip the `[-1]` drop.
- **Bootstrap-absent guard** in `comp_list` summary-stats lapply:
  - Detect `"00001"` column in `comp`.
  - When present (bootstrap exists), compute mean/min/max/sd/cv/CI95/CI99 over the simulation columns as before.
  - When absent, collapse to point estimates: set `mean = multimode_mean`, sd/cv = 0, CIs = mean, `trase_inrange*` checks are just `trase == mean`.

### Data dependencies for Path B
- `results/outputs/00_{YEAR}/MUN_capital_dist.rds` — produced by `code/pipeline/00_data_preparation/00_data_preparation.R` (already in `results/outputs/00_2013/`).
- `results/outputs/05_{YEAR}/SOY_MUN_fin.rds` — from step 05.
- `results/outputs/07_{YEAR}/flows_euclid.rds` — from step 07_R.
- `results/outputs/08_{YEAR}/source_to_export_mean.rds` — from step 08_mean.
- (Optional) `results/outputs/08_{YEAR}/source_to_export_list.rds` — from step 08_sep; downstream handles absence.
- `data/old/brazil_soy_v2_6_1_composite.csv` — TRASE v2.6.1 composite covering 2004–2022 (placed by user fetch).

### Run order for Path B
```
Rscript code/pipeline/07_transport_R.R       2013   # Euclidean flows
Rscript code/pipeline/08_export_link_mean.R  2013   # link to importers (mean variant)
Rscript code/pipeline/08_export_link_sep.R   2013   # link to importers (sep variant — optional, only matters for bootstrap)
Rscript code/pipeline/10_create_benchmarks.R 2013   # TRASE comparison
Rscript code/pipeline/11_analyse_benchmarks.R 2013  # benchmark analysis (maps, scatter, regressions)
Rscript code/pipeline/12_re-exports.R        2013   # FABIO MRIO re-export allocation
```

Step 09 (`09_sensitivity.R`) is meaningless without the bootstrap and is skipped in Path B.

## Stopping point: end of step 12

Steps 13–21 (supply, use, MRSUT, MRIO, Leontief, hybrid, footprints, probability maps) are not yet year-parameterized. They depend on the FABIO MRIO output of step 12 and on additional FABIO_exp data products that share the same 1986–2013 limitation as the inputs to step 12.

External requirements that still block end-to-end runs for `YEAR ≥ 2014`:
1. **Updated FABIO_exp v1/pure** data at `data/new/04/FABIO/FABIO_exp/{v1,pure}/btd_bal.rds` and `cbs_full.rds` covering the target year.
2. **Year-specific TRASE export** at `data/old/BRAZIL_SOY_{YEAR}_TRASE.csv` (10/11 fall back to the 2013 baseline if missing).

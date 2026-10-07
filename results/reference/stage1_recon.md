# Stage 1 — reconnaissance report

Generated 2026-09-09T15:35:52+02:00 — no files moved, no compute run.

## 1. Input path mapping (Problem 1)

The archive IS the pre-reorganisation layout, and the mapping is documented rather than
inferred. `code/pipeline/CHANGELOG.md` and `code/pipeline/00_data_preparation/CHANGELOG.md`
were written while the code still read `data/new/...`, and they name the old paths verbatim:

- `00_data_preparation/CHANGELOG.md:44-58` — a section-by-section table whose "current" column
  is `data/new/00/new/<subfolder>/...`, matching todays `data/raw/00/<subfolder>/...` 1:1.
- `CHANGELOG.md:6` — "Raw data: `data/new/00/old/` -> `data/new/00/new/<subfolder>/`".
- `CHANGELOG.md:62-64,70-73` — step 04/12 FABIO inputs at `data/new/04/FABIO/...`, i.e. todays
  `data/fabio/trade/...`; and `data/new/04/FAOSTAT_tradematrix_BRAsoy_{YEAR}.csv` -> `data/raw/04/`.

Four directory-level links therefore cover every resolvable input:

| Expected by code | Provided by archive | Basis |
|---|---|---|
| `data/raw/00/` | `data/new/00/new/` | CHANGELOG 00 §44-58; all 16 source subfolders match by name |
| `data/raw/02/` | `data/new/02/` | direct name match (`FeedlotCattle_*.xlsx`, `geo/FAO_gridded_livestock/`) |
| `data/raw/03/` | `data/new/03/` | direct name match (`Feed_ratios_FAO.xlsx`) |
| `data/raw/04/` | `data/new/04/` | direct name match (`PAIS_COMEX.csv`, `FAOSTAT_tradematrix_BRAsoy_*.csv`) |
| `data/fabio/trade/` | `data/new/04/FABIO/` | CHANGELOG §62-64,70-73; all 10 expected files present |

`data/new/00/old/` is Stefan's original 2013 flat layout (`archive/data_stefan_2013/` per
STRUCTURE.md). No active pipeline step reads it. `data/new/00/old/geo/` is NOT `data/geo/` —
it holds only boundaries / localities / logistic_network, none of the layers `data/geo/` needs.

### Per-file resolution for YEAR=2013

```
EXPECTED PATH (as code opens it)                               | STATUS   | FOUND AT / NEEDED BY
-------------------------------------------------------------------------------------------------------
data/raw/00/IBGE_municipalities/GEO_MUN_2013_IBGE.xlsx         | MATCHED  | data/new/00/new/IBGE_municipalities/GEO_MUN_2013_IBGE.xlsx  [step 00]
data/raw/00/COMEX_exports/EXP_2013_MUN_COMEX.csv               | MATCHED  | data/new/00/new/COMEX_exports/EXP_2013_MUN_COMEX.csv  [step 00]
data/raw/00/COMEX_imports/IMP_2013_MUN_COMEX.csv               | MATCHED  | data/new/00/new/COMEX_imports/IMP_2013_MUN_COMEX.csv  [step 00]
data/raw/00/COMEX_codes/UF_MUN_COMEX.csv                       | MATCHED  | data/new/00/new/COMEX_codes/UF_MUN_COMEX.csv  [step 00]
data/raw/00/COMEX_codes/PAIS_COMEX.csv                         | MATCHED  | data/new/00/new/COMEX_codes/PAIS_COMEX.csv  [step 00]
data/raw/00/IBGE_production/Production_tabela1612_IBGE_2013.csv | MATCHED  | data/new/00/new/IBGE_production/Production_tabela1612_IBGE_2013.csv  [step 00]
data/raw/00/ABIOVE_processing/ABIOVE_raw_capacity_2025.xlsx    | MATCHED  | data/new/00/new/ABIOVE_processing/ABIOVE_raw_capacity_2025.xlsx  [step 00]
data/raw/00/IBGE_population/Population_tabela6579_IBGE_2013.csv | MATCHED  | data/new/00/new/IBGE_population/Population_tabela6579_IBGE_2013.csv  [step 00]
data/raw/00/IBGE_livestock/Livestock_2013_tabela3939_IBGE.csv  | MATCHED  | data/new/00/new/IBGE_livestock/Livestock_2013_tabela3939_IBGE.csv  [step 00]
data/raw/00/IBGE_milkcows/MilkCows_2013_tabela94_IBGE.csv      | MATCHED  | data/new/00/new/IBGE_milkcows/MilkCows_2013_tabela94_IBGE.csv  [step 00]
data/raw/00/IBGE_storage/armazens_2014.shp                     | MATCHED  | data/new/00/new/IBGE_storage/armazens_2014.shp  [step 00]
data/raw/00/IBGE_POF/POF_soy_oil_2008_IBGE.csv                 | MATCHED  | data/new/00/new/IBGE_POF/POF_soy_oil_2008_IBGE.csv  [step 00 (nearest<=2013)]
data/raw/00/ANP_biodiesel/Biodiesel_capacity_2013_ANP.xlsx     | MATCHED  | data/new/00/new/ANP_biodiesel/Biodiesel_capacity_2013_ANP.xlsx  [step 00]
data/raw/00/ANP_biodiesel/Biodiesel_capacity_2013_ANP_original.xlsx | MATCHED  | data/new/00/new/ANP_biodiesel/Biodiesel_capacity_2013_ANP_original.xlsx  [step 00]
data/raw/00/IBGE_boundaries/municipios_2013.gpkg               | MATCHED  | data/new/00/new/IBGE_boundaries/municipios_2013.gpkg  [step 00]
data/raw/00/IBGE_localities/BR_Localidades_2010_v1.shx         | MATCHED  | data/new/00/new/IBGE_localities/BR_Localidades_2010_v1.shx  [step 00]
data/raw/00/FAO_CBS/CBS_SOY_2013_FAO.xlsx                      | MATCHED  | data/new/00/new/FAO_CBS/CBS_SOY_2013_FAO.xlsx  [step 00_FAO]
data/raw/02/FeedlotCattle_2006_tabela919_IBGE.xlsx             | MATCHED  | data/new/02/FeedlotCattle_2006_tabela919_IBGE.xlsx  [step 02]
data/raw/02/geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif     | MATCHED  | data/new/02/geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif     | MATCHED  | data/new/02/geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif      | MATCHED  | data/new/02/geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif      | MATCHED  | data/new/02/geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif     | MATCHED  | data/new/02/geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/5_Ct_2010_Da.tif         | MATCHED  | data/new/02/geo/FAO_gridded_livestock/5_Ct_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/5_Bf_2010_Da.tif         | MATCHED  | data/new/02/geo/FAO_gridded_livestock/5_Bf_2010_Da.tif  [step 02]
data/raw/02/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif | MATCHED  | data/new/02/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif  [step 02]
data/raw/03/Feed_ratios_FAO.xlsx                               | MATCHED  | data/new/03/Feed_ratios_FAO.xlsx  [step 03]
data/raw/04/PAIS_COMEX.csv                                     | MATCHED  | data/new/04/PAIS_COMEX.csv  [step 04]
data/raw/04/FAOSTAT_tradematrix_BRAsoy_2013.csv                | MISSING  | expected at data/new/04/FAOSTAT_tradematrix_BRAsoy_2013.csv  [step 04 (falls back if absent)]
data/fabio/trade/btd_bal.rds                                   | MATCHED  | data/new/04/FABIO/btd_bal.rds  [step 04]
data/fabio/trade/new/btd_bal.RData                             | MATCHED  | data/new/04/FABIO/new/btd_bal.RData  [step 04,12]
data/fabio/trade/new/cbs_full.rds                              | MATCHED  | data/new/04/FABIO/new/cbs_full.rds  [step 12]
data/fabio/trade/FABIO_exp/v1/btd_bal.rds                      | MATCHED  | data/new/04/FABIO/FABIO_exp/v1/btd_bal.rds  [step 04,12]
data/fabio/trade/FABIO_exp/v1/cbs_full.rds                     | MATCHED  | data/new/04/FABIO/FABIO_exp/v1/cbs_full.rds  [step 04]
data/fabio/trade/FABIO_exp/pure/btd_bal.rds                    | MATCHED  | data/new/04/FABIO/FABIO_exp/pure/btd_bal.rds  [step 04]
data/fabio/trade/FABIO_exp/items.csv                           | MATCHED  | data/new/04/FABIO/FABIO_exp/items.csv  [step 12]
data/fabio/trade/FABIO_regions.xlsx                            | MATCHED  | data/new/04/FABIO/FABIO_regions.xlsx  [step 04]
data/fabio/trade/FAO_regions_full.csv                          | MATCHED  | data/new/04/FABIO/FAO_regions_full.csv  [step 04]
data/fabio/trade/FAOSTAT_tradematrix_BRAsoy.csv                | MATCHED  | data/new/04/FABIO/FAOSTAT_tradematrix_BRAsoy.csv  [step 04 (2013 fallback)]
data/trase/brazil_soy_v2_6_1_composite.csv                     | MISSING  | -- (needed by step 10)
data/geo/GADM_boundaries/gadm36_BRA_1.shp                      | MISSING  | -- (needed by step 11,21)
data/geo/mb_tiles/                                             | MISSING  | -- (needed by step 21)
data/fabio/v2/inst/regions_full.csv                            | MISSING  | -- (needed by step 13,14,15,16,20,21)
data/exiobase/pxp/IO.codes.RData                               | MISSING  | -- (needed by step 18,19,20)
```

Every expected input resolves except the five recorded as MISSING. The single
`FAOSTAT_tradematrix_BRAsoy_2013.csv` miss is expected and handled by the code's own
documented fallback (`04_trade_harmonization.R:61-62`) to `data/fabio/trade/FAOSTAT_tradematrix_BRAsoy.csv`,
which is present. Per-year matrices exist only for 2014-2024; 2000-2013 use the fallback by design.

## 2. Missing-input inventory (Problem 2)

| Missing | Actually needed by | Consequence |
|---|---|---|
| `data/trase/` | step **10** (`10_create_benchmarks.R:43-52`) | step 10 hard-`stop()`s |
| `data/geo/GADM_boundaries/` | steps **11**, **21**; `code/shared/{flow_maps,mun_plots}.R` | step 11 fails at `st_read` |
| `data/geo/mb_tiles/` | step **21** only | step 21 stops (already soft) |
| `data/fabio/v2/` | steps 13,14,15,16,20,21 | footprint chain cannot run |
| `data/exiobase/pxp/` | steps 18,19,20 | footprint chain cannot run |
| `data/raw/{QCL,TCL}_SOY_FAO.csv` | `code/shared/prod_exp_plots.R` only — not any pipeline step | plotting helper only |

### Three corrections to the brief

1. **`data/geo/` is not needed by step 07.** `07_transport_R.R` reads only
   `05_{YEAR}/SOY_MUN_fin.rds` and `00_{YEAR}/MUN_capital_dist.rds` and uses Euclidean
   distances. Transport allocation runs fine without `data/geo/`. The real `data/geo/`
   consumers are steps 11 and 21.
2. **`data/fabio/trade/` is fully satisfied** by `data/new/04/FABIO/` — all 10 expected files.
   Steps 04 and 12 are not blocked.
3. **Steps 00-12 will not all run.** Steps 10 and 11 are blocked by the missing Trase and
   GADM data, and both are fatal (`|| exit 1`) in `run_year_full.sh`.

## 3. Steps that can and cannot run

| Step | Status | Reason |
|---|---|---|
| 00 data_preparation | CAN | all inputs resolve |
| 00 FAO checks | CAN | `CBS_SOY_2013_FAO.xlsx` present |
| 01 consumption | CAN | reads step-00 output only |
| 02 livestock | CAN | all 8 rasters + feedlot xlsx present |
| 03 feed | CAN | `Feed_ratios_FAO.xlsx` present |
| 04 trade | CAN | FABIO trade complete; 2013 matrix via documented fallback |
| 05 balancing | CAN | reads step 03/04/00 output |
| 07 transport | CAN | Euclidean; no `data/geo/` needed |
| 08 export_link (mean, sep) | CAN | Euclidean-only path; GAMS bootstrap absent but optional |
| **10 benchmarks** | **CANNOT** | no `data/trase/` -> hard `stop()`; **fatal, aborts the year** |
| **11 analyse** | **CANNOT** | no GADM shapefile (also gated behind 10) |
| 12 re-exports | blocked upstream | inputs present, but runner never reaches it |
| 13-21 footprints | CANNOT | no `data/fabio/v2/`, no `data/exiobase/pxp/` (soft-skip) |

Step 06 and step 09 are not invoked by `run_year_full.sh` at all.

**Real ceiling: steps 00-08, plus 12 if 10/11 are unblocked or made non-fatal.**

## 4. Environment gaps (blocking, not data-related)

R 4.6.1 present. 19 of the 37 required R packages are NOT installed:

```
reshape2 Metrics transport abind gtools gmodels foreach doParallel raster terra
gdistance exactextractr fasterize ggpubr ggsci ggpointdensity xtable mapview leafsync
```

Blocking ones: `raster` (step 02), `transport` + `abind` (steps 07/08), `Metrics`/`gmodels`/`xtable` (10/11).
Without these the smoke test fails at step 02.

Python `duckdb` is not installed — `code/build_data_dictionary.py` exits immediately with
"duckdb is not installed". This blocks Stage 6 entirely.

Disk: 351 GB free. Not a constraint.

## 5. Problem 3 — Figure 5 could not be located

**There is no Figure 5 depicting a database schema anywhere in this repo.**

- `paper/data_section/data.tex` contains **zero** `figure` environments.
- `paper/methods_section/methods.tex` has 6, none a schema: `fig:workflow`, `fig:feed`,
  `fig:flows`, `fig:reexport`, `fig:nesting`, `fig:fpscheme`. The fifth is the MRIO
  nesting diagram, not a database schema.
- Zero occurrences of `duckdb`, `parquet`, `schema`, `fact table`, `dimension table`,
  `meta_build` or `meta_provenance` anywhere under `paper/`.

The eight-fact/four-dimension schema cannot be verified against any artefact in the
repository. The gap analysis in Stage 4 will therefore inventory what the pipeline
actually produces; comparing it to Figure 5 requires someone to supply that figure.

Also: `docs/` holds only `workflow_scheme.png` — there is no 2013 validation record.

## 6. Open question — temporal coverage

Confirmed in-repo, adding a fifth statement to the four in the brief:

| Source | Says |
|---|---|
| `STRUCTURE.md:47,109` | pipeline runs 2000-2020 |
| `data.tex:62` | all series cover 2010-2020 |
| `data.tex:249-250` | FABIO v2 (2010-2023) binding; footprints 2010-2020; Trase back to 2004 |
| pipeline `stopifnot` | accepts 2000-2022 |
| `CHANGELOG.md:63` | FABIO_exp snapshots cover **1986-2013 only**; step 04/12 empty for >=2014 |

Unresolved — must be answered before Stage 3.

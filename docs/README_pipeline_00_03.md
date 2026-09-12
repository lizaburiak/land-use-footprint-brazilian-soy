# Soyprint Pipeline: Scripts 00–03

> **Note:** written under the old repo layout. Current equivalents: the scripts live in
> `code/pipeline/` (00–03), raw data in `data/new/` (the `inputs/` below) and `data/old/`, and
> outputs in `results/outputs/` (the `outputs/`/`intermediate_data/` below). The folder tree and
> `input_data/`/`R/` paths in the text are historical; the step-by-step descriptions still apply.

This document describes the data requirements and processing steps for scripts `00` through `03`, which build the subnational data foundation for the Brazilian soy supply chain model.

---

## Folder Structure

```
soyprint/
├── inputs/                         # All raw input data (must be sourced manually)
│   ├── geo/
│   │   ├── FAO_gridded_livestock/  # FAO gridded livestock rasters
│   │   ├── IBGE_logistic_network/  # IBGE grain storage shapefiles
│   │   └── IBGE_localities/        # IBGE municipality locality points
│   └── (tabular files at root)
├── outputs/                        # All intermediate outputs produced by scripts 00–03
└── R/                              # Processing scripts
```

---

## Input Data Required

All data is for **reference year 2013** unless noted otherwise. Files must be placed in the `inputs/` folder (the scripts currently reference `input_data/`; paths need to be adjusted or a symlink created).

### Tabular Data

| File | Source | Description |
|------|--------|-------------|
| `GEO_MUN_2013_IBGE_merged.xlsx` | IBGE | Municipality codes, names, state codes, and state names (~5,570 municipalities) |
| `EXP_2013_MUN_COMEX.csv` | COMEX/MDIC | Monthly municipality-level exports (year, month, HS4, destination country, state, municipality, kg, USD) |
| `IMP_2013_MUN_COMEX.csv` | COMEX/MDIC | Monthly municipality-level imports (same structure as exports) |
| `UF_MUN_COMEX.csv` | COMEX/MDIC | COMEX municipality code-to-name lookup table (ISO-8859-1 encoded) |
| `PAIS_COMEX.csv` | COMEX/MDIC | Country code-to-ISO3 lookup table (ISO-8859-1 encoded) |
| `Production_tabela1612_IBGE.csv` | IBGE (SIDRA) | Soybean production by municipality: area planted, area harvested, production (tons). Table 1612 |
| `Processing_facilities_2013_ABIOVE.xlsx` | ABIOVE | Soy processing facilities: two sheets — `processing_MUN` (crushing) and `refining_bottling_MUN` (refining/bottling). Contains active facility counts and daily capacities |
| `Population_tabela6579_IBGE.csv` | IBGE (SIDRA) | Municipality population estimates. Table 6579 |
| `Livestock_2013_tabela3939_IBGE.csv` | IBGE (SIDRA) | Livestock headcounts by municipality: cattle, buffalo, horse, pig, pig mothers, goat, sheep, chicken, laying hens, quail. Table 3939 |
| `MilkCows_2013_tabela94_IBGE.csv` | IBGE (SIDRA) | Number of milked cows by municipality. Table 94 |
| `POF_soy_oil_2017_IBGE.xlsx` | IBGE (POF 2017) | Per-capita annual soy oil acquisition (kg) by state |
| `Biodiesel_capacity_2013_ANP.xlsx` | ANP | Two sheets — `capacity`: biodiesel production facilities with daily capacity (m³/day) per municipality; `materials`: regional share of soy as biodiesel feedstock |
| `CBS_SOY_2013_FAO.xlsx` | FAO (FAOSTAT) | Commodity Balance Sheet for soybeans, soy oil, and soy cake in Brazil (production, exports, imports, food, feed, seed, other, processing, stock changes) |
| `FeedlotCattle_2006_tabela919_IBGE.xlsx` | IBGE (Census 2006) | Feedlot cattle numbers by municipality. Table 919 |
| `Feed_ratios_FAO.xlsx` | FAO/GLEAM | Soy feed ratios by livestock system: dry matter intake, % soybean, % soy cake per animal per year. Sheet 2 is used |

### Geospatial Data

| File | Source | Description |
|------|--------|-------------|
| `geo/GEO_MUN_2013_IBGE_merged.gpkg` | IBGE | Municipality polygon boundaries (GeoPackage) |
| `geo/IBGE_logistic_network/armazens_2014.shp` | IBGE | Grain storage facility locations with capacity in tons (2014) |
| `geo/IBGE_localities/BR_Localidades_2010_v1.shx` | IBGE | Point localities (cities, villages) with coordinates. Used to extract municipality capitals |
| `geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif` | FAO/GLW3 | Gridded chicken density — extensive systems (2010) |
| `geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif` | FAO/GLW3 | Gridded chicken density — intensive systems (2010) |
| `geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif` | FAO/GLW3 | Gridded pig density — extensive systems (2010) |
| `geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif` | FAO/GLW3 | Gridded pig density — intensive systems (2010) |
| `geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif` | FAO/GLW3 | Gridded pig density — industrial systems (2010) |
| `geo/FAO_gridded_livestock/5_Ct_2010_Da.tif` | FAO/GLW3 | Gridded cattle density (2010) |
| `geo/FAO_gridded_livestock/5_Bf_2010_Da.tif` | FAO/GLW3 | Gridded buffalo density (2010) |
| `geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif` | FAO/GLEAM | Global ruminant production system classification (grassland, mixed, urban, other, unsuitable) at 10 km resolution |

---

## Script-by-Script Description

### 00_data_preperation.R — Municipality-Level Data Preparation

**Purpose:** Prepares and combines all raw datasets on the Brazilian municipality level into one coherent data table (`SOY_MUN`) with unique municipality identifiers, and matches it to municipality polygon shapefiles.

**Process:**

1. **Export data (COMEX):**
   - Loads monthly municipality-level exports, filters for soy products (HS4 codes: 1201 = soybean, 1507 = soy oil, 2304 = soy cake)
   - Converts kg to tons, aggregates monthly to annual
   - Corrects COMEX municipality codes for states SP, MS, GO, DF (different numbering conventions)
   - Matches municipality codes to IBGE names and adds destination country ISO3 codes
   - Allocates "undeclared origin" exports proportionally to declared municipalities by destination

2. **Import data (COMEX):**
   - Same procedure as exports but for imports

3. **Production data (IBGE):**
   - Extracts 2013 soybean production (tons), area planted, and area harvested per municipality

4. **Processing facilities (ABIOVE):**
   - Merges crushing and refining/bottling facility data; retains only active facilities and their daily capacities

5. **Population (IBGE):**
   - Extracts 2013 population per municipality

6. **Livestock (IBGE):**
   - Loads headcounts for 10 animal types per municipality, plus milked cow data; merges both

7. **Storage capacity (IBGE):**
   - Aggregates grain storage facility capacities (tons) per municipality from point-level shapefile

8. **Soy oil acquisition (POF):**
   - State-level per-capita soy oil purchase data (used later as food consumption proxy)

9. **Biodiesel capacity (ANP):**
   - Computes soy-based biodiesel production capacity per municipality (daily capacity × regional soy feedstock share)

10. **Merge into `SOY_MUN`:**
    - Joins all above datasets into a single table by municipality code; NAs filled with 0

11. **Geospatial processing:**
    - Loads municipality polygons, joins with `SOY_MUN`, projects to SIRGAS 2000 Brazil Polyconic (EPSG:5880)
    - Computes municipality center points and pairwise Euclidean distance matrix
    - Loads municipality capital locations (with 7 manual additions), computes capital distance matrix

**Outputs:**
| File | Description |
|------|-------------|
| `SOY_MUN_00.rds` | Main municipality-level soy data table |
| `SOY_MUN.csv` | CSV version of the above |
| `EXP_MUN_SOY_00.rds` | Detailed export data (by municipality × destination × product) |
| `IMP_MUN_SOY_00.rds` | Detailed import data (by municipality × origin × product) |
| `GEO_MUN_SOY.gpkg` | Municipality polygons with all attributes (GeoPackage) |
| `GEO_MUN_SOY_00.rds` | Municipality polygons with all attributes (RDS) |
| `GEO_BRA.shp` | Merged Brazil boundary polygon |
| `GEO_BRA_EXT.shp` | Bounding box of Brazil |
| `MUN_capitals.rds` | Municipality capital point locations (RDS) |
| `MUN_capitals.gpkg` | Municipality capital point locations (GeoPackage) |
| `MUN_center_dist.rds` | Pairwise Euclidean distance matrix between municipality centers |
| `MUN_capital_dist.rds` | Pairwise Euclidean distance matrix between municipality capitals |

---

### 00_FAO_consitency_checks.R — FAO Consistency Checks

**Purpose:** Compares aggregated municipality-level data against national FAO Commodity Balance Sheet (CBS) values to verify data consistency.

**Process:**

1. Loads `SOY_MUN_00.rds` and FAO CBS data
2. Formats the CBS into a structured table with supply/use categories (production, export, import, food, feed, seed, other, processing, stock withdrawal) for beans, oil, and cake
3. Verifies supply-side identity: `domestic_supply = production - export + import + stock_withdrawal`
4. Verifies use-side identity: `domestic_supply = food + feed + other + processing + seed`
5. Compares municipality-aggregated production, exports, imports, and processing capacity against FAO national totals

**Outputs:**
| File | Description |
|------|-------------|
| `CBS_SOY.rds` | Formatted FAO Commodity Balance Sheet for Brazilian soy (bean/oil/cake × supply-use categories) |
| `FAO_consistency.rds` | Consistency comparison table (municipality aggregates vs FAO totals) |

---

### 01_consumption_and_processing.R — Consumption & Processing Use Estimation

**Purpose:** Estimates municipality-level quantities for domestic soy use categories: processing, food, other (biodiesel), seed, and stock changes.

**Process:**

1. **Processing use:**
   - Derives average annual operating days from national processing volume ÷ total daily capacity
   - Calculates municipality processing quantities: `proc_bean = proc_cap × proc_days`
   - Derives soybean-to-cake and soybean-to-oil conversion factors (~75% cake, ~20% oil, ~5% losses)
   - Computes municipality oil and cake production from processing

2. **Food use:**
   - Estimates municipality-level soy oil food consumption using state-level per-capita soy oil acquisition (POF) × municipality population
   - Allocates national FAO food use of both beans and oil proportionally to estimated municipal oil acquisition

3. **Other use (biodiesel):**
   - Allocates national FAO "other" oil use to municipalities by their share in soy-based biodiesel production capacity

4. **Seed use:**
   - Computes national seed-use share (FAO seed use ÷ total production)
   - Allocates to municipalities proportionally to their soybean production

5. **Stock additions:**
   - Allocates national stock changes to municipalities proportionally to their grain storage capacity

**Outputs:**
| File | Description |
|------|-------------|
| `SOY_MUN_01.rds` | Municipality table with added columns: `proc_bean`, `prod_oil`, `prod_cake`, `food_bean`, `food_oil`, `other_oil`, `seed_bean`, `stock_bean` |
| `GEO_MUN_SOY_01.rds` | Municipality polygons with the new consumption/processing columns |

---

### 02_livestock_systems.R — Livestock System Disaggregation

**Purpose:** Disaggregates IBGE 2013 municipal livestock headcounts into production system categories (e.g., extensive, intensive, industrial for pigs; grassland vs. mixed for cattle) using FAO gridded livestock and production system rasters.

**Process:**

1. **Chicken & Pigs:**
   - Loads FAO/GLW3 gridded livestock rasters (extensive/intensive for chicken; extensive/intensive/industrial for pigs)
   - Crops rasters to Brazil extent
   - Computes zonal sum per municipality to get animal counts by system from 2010 rasters
   - Calculates system shares per municipality; fills NAs with state-level averages
   - Applies shares to 2013 IBGE headcounts to obtain: `pig_byd`, `pig_int`, `pig_ind`, `chicken_byd`, `chicken_bro`, `chicken_lay`

2. **Cattle:**
   - Combines cattle distribution raster with ruminant production system map to separate grassland-based (codes 1–4, 14, 15) from mixed systems (codes 5–13)
   - Computes system shares per municipality; fills NAs with state averages
   - Adds feedlot cattle from IBGE 2006 census, extrapolated to 2013 using ABIEC growth rate (4.38/3.46)
   - Splits by dairy (using milked cow ratio) vs. meat (residual): `cattle_gra_dair`, `cattle_mix_dair`, `cattle_gra_meat`, `cattle_mix_meat`, `cattle_flot`

3. **Buffaloes:**
   - Same procedure as cattle (without feedlot), using milked cow share as proxy for dairy buffalo share: `buffalo_gra_dair`, `buffalo_mix_dair`, `buffalo_gra_meat`, `buffalo_mix_meat`

4. Validates that system subtotals sum back to original totals for each species

**Outputs:**
| File | Description |
|------|-------------|
| `SOY_MUN_02.rds` | Municipality table with disaggregated livestock columns by production system |
| `LIVESTOCK_MUN_02.rds` | Separate livestock-only table (municipality × animal system) |
| `GEO_MUN_SOY_02.rds` | Municipality polygons with livestock system columns |

---

### 03_feed_use.R — Feed Use Estimation

**Purpose:** Estimates municipality-level soybean and soy cake feed use by combining livestock numbers per production system with FAO/GLEAM feed ratios, then rescaling to match national FAO feed use totals.

**Process:**

1. **Prepare feed ratios:**
   - Loads FAO/GLEAM feed ratios (Sheet 2): dry matter intake per animal per year, % soybean, % soy cake
   - Converts to wet-matter intake in tons per animal per year using 88% dry matter content for both bean and cake

2. **Compute feed use:**
   - For each municipality and livestock system, multiplies animal headcounts by per-animal feed intake rates
   - Produces two matrices (municipalities × livestock systems): `bean_feed_t` and `cake_feed_t`

3. **Rescale to FAO totals:**
   - Compares bottom-up totals to FAO CBS national feed use values
   - Applies a uniform scaling factor so that totals match exactly: `bean_feed_t_fin = bean_feed_t × (FAO_feed / sum(bean_feed_t))`

4. **Aggregate:**
   - Adds total soybean and cake feed use per municipality to main table: `feed_bean`, `feed_cake`

**Note:** Script reads `CBS_SOY.csv` (line 14), but `00_FAO_consitency_checks.R` exports `CBS_SOY.rds`. You may need to either export a CSV version from the FAO script or change the read call in `03_feed_use.R` to `readRDS("intermediate_data/CBS_SOY.rds")`.

**Outputs:**
| File | Description |
|------|-------------|
| `bean_feed_t.rds` | Municipality × livestock-system matrix of soybean feed use (tons) |
| `cake_feed_t.rds` | Municipality × livestock-system matrix of soy cake feed use (tons) |
| `SOY_MUN_03.rds` | Municipality table with added `feed_bean` and `feed_cake` columns |
| `GEO_MUN_SOY_03.rds` | Municipality polygons with feed use columns |

---

## Data Flow Summary

```
                        ┌─────────────────────────────┐
                        │      Raw Input Data          │
                        │      (inputs/ folder)        │
                        └──────────────┬──────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    ▼                                      ▼
         00_data_preperation.R                 00_FAO_consitency_checks.R
         ├─ SOY_MUN_00.rds                    ├─ CBS_SOY.rds
         ├─ EXP_MUN_SOY_00.rds               └─ FAO_consistency.rds
         ├─ IMP_MUN_SOY_00.rds
         ├─ GEO_MUN_SOY_00.rds
         ├─ MUN_capitals.rds
         └─ MUN_center/capital_dist.rds
                    │                                      │
                    └──────────────┬───────────────────────┘
                                   ▼
                    01_consumption_and_processing.R
                    ├─ SOY_MUN_01.rds
                    └─ GEO_MUN_SOY_01.rds
                                   │
                                   ▼
                    02_livestock_systems.R
                    ├─ SOY_MUN_02.rds
                    ├─ LIVESTOCK_MUN_02.rds
                    └─ GEO_MUN_SOY_02.rds
                                   │
                                   ▼
                    03_feed_use.R
                    ├─ bean_feed_t.rds
                    ├─ cake_feed_t.rds
                    ├─ SOY_MUN_03.rds
                    └─ GEO_MUN_SOY_03.rds
```

---

## R Package Dependencies

```r
install.packages(c(
  "dplyr", "tidyr", "readr", "openxlsx",   # data wrangling & I/O
  "sf",                                      # vector geospatial
  "raster", "exactextractr",                 # raster geospatial
  "ggplot2", "ggpointdensity",               # plotting (function library)
  "gmodels",                                 # confidence intervals (function library)
  "mapview", "leafsync"                      # interactive maps (02)
))
```

---

## Known Issues / Notes

1. **Path adjustment needed:** Scripts reference `input_data/` and `intermediate_data/` as relative paths. To use the new `inputs/` and `outputs/` folders, either create symlinks (`ln -s inputs input_data && ln -s outputs intermediate_data`) or update paths in scripts.

2. **CBS_SOY format mismatch:** `00_FAO_consitency_checks.R` saves `CBS_SOY.rds`, but `03_feed_use.R` reads `CBS_SOY.csv` via `read.csv2()`. Either add a `write.csv2(CBS_SOY, "intermediate_data/CBS_SOY.csv")` line to the FAO script, or change the read call in script 03.

3. **Execution order matters:** `00_FAO_consitency_checks.R` depends on `00_data_preperation.R` having run first (needs `SOY_MUN_00.rds`). All subsequent scripts depend on prior outputs in strict numerical order.

4. **Data availability:** All input data is publicly available but cannot be redistributed due to varying licenses. Data must be downloaded directly from source (IBGE/SIDRA, COMEX/MDIC, FAO/FAOSTAT, FAO/GLW3, ABIOVE, ANP).

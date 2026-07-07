# 00_data_preparation.R — detailed changelog

Fork of `R/00_data_preperation.R` (Stefan Trsek, 2022). Lives at
`code/pipeline/00_data_preparation/00_data_preparation.R`.

Scope: year-parameterized (2000–2022) pipeline that reads from
`data/new/00/new/<subfolder>/` and writes to `results/outputs/00_{YEAR}/`. Processing
and refining capacity methodology replaced with per-year ABIOVE roster +
Trsek-style equal-per-state allocation.

---

## 1. Libraries

| Stefan | code/pipeline/ | Reason |
|---|---|---|
| `library(dplyr); library(openxlsx); library(tidyr); library(sf); library(readr)` | + `library(readxl)` | Legacy `.xls` ABIOVE pesquisa files (2003–2015) — `openxlsx` is `.xlsx`-only. |

## 2. Year selection (lines 62–80)

**Stefan:** no year parameter — entire file hardcoded to 2013.

**code/pipeline/:**
```r
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2013
stopifnot(YEAR >= 2000 & YEAR <= 2022)  # analysis window
OUT  <- paste0("results/outputs/00_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
```

**Bugfix:** The upstream `code/pipeline/00_data_preperation.R` (single file, pre-existing)
had a redundant `YEAR <- 2013` on line 72 that overrode the command-line arg.
Removed in this fork.

## 3. Helper functions (§2)

Lifted from the upstream `code/pipeline/00_data_preperation.R`:
- `find_lower_bound(avail, target)` — nearest available year ≤ target.
- `find_year_file(pattern, target)` — globs `path_{Y}.csv`, picks lower-bound file.

## 4. Raw data loads (§1.1–1.10)

| Section | Stefan path | code/pipeline/ path |
|---|---|---|
| 1.1 IBGE municipalities | `data/new/00/GEO_MUN_2013_IBGE_merged.xlsx` | `data/new/00/new/IBGE_municipalities/GEO_MUN_{Y}_IBGE.xlsx` (lower-bound) |
| 1.2 COMEX exports | `data/new/00/old/EXP_2013_MUN_COMEX.csv` | `data/new/00/new/COMEX_exports/EXP_{Y}_MUN_COMEX.csv` |
| 1.2 COMEX imports | `data/new/00/IMP_2013_MUN_COMEX.csv` | `data/new/00/new/COMEX_imports/IMP_{Y}_MUN_COMEX.csv` |
| 1.2 COMEX codes | `data/new/00/UF_MUN_COMEX.csv`, `PAIS_COMEX.csv` | `data/new/00/new/COMEX_codes/` (static) |
| 1.3 IBGE production (PAM) | `data/new/00/Production_tabela1612_IBGE.csv` | `data/new/00/new/IBGE_production/Production_tabela1612_IBGE_{Y}.csv` |
| 1.4 ABIOVE processing | `data/new/00/Processing_facilities_2013_ABIOVE.xlsx` (pre-computed sheet) | **Totally rewritten — see §5 below** |
| 1.4b ABIOVE refining + bottling | n/a (Stefan reads refining from same 2013 file sheet `refining_bottling_MUN`) | **New block — see §6 below** |
| 1.5 IBGE population | `data/new/00/Population_tabela6579_IBGE.csv` | `data/new/00/new/IBGE_population/Population_tabela6579_IBGE_{Y}.csv` (handles 4 CSV formats across era transitions: SIDRA pre-2022, 2022 Census, 2024–25 estimates) |
| 1.6 IBGE livestock (PPM) | `data/new/00/Livestock_2013_tabela3939_IBGE.csv` | `data/new/00/new/IBGE_livestock/Livestock_{Y}_tabela3939_IBGE.csv` |
| 1.7 IBGE milk cows | `data/new/00/MilkCows_2013_tabela94_IBGE.csv` | `data/new/00/new/IBGE_milkcows/MilkCows_{Y}_tabela94_IBGE.csv` |
| 1.8 IBGE storage | `data/new/00/geo/IBGE_logistic_network/armazens_2014.shp` | `data/new/00/new/IBGE_storage/armazens_2014.shp` (static, 2014 shapefile) |
| 1.9 IBGE POF | `data/new/00/POF_soy_oil_2017_IBGE.xlsx` (hardcoded) | `data/new/00/new/IBGE_POF/POF_soy_oil_{Y}_IBGE.csv` (lower-bound; POF has editions 2002, 2008, 2018) |
| 1.10 ANP biodiesel | `data/new/00/Biodiesel_capacity_2013_ANP.xlsx` | `data/new/00/new/ANP_biodiesel/Biodiesel_capacity_{Y}_ANP.xlsx` (with `_original.xlsx` fallback) — if `<2008`, zero-filled |

## 5. §1.4 Processing capacity — methodology rewrite

**Stefan's 2013-only method:**
```r
PROC_MUN_proc <- openxlsx::read.xlsx("data/new/00/Processing_facilities_2013_ABIOVE.xlsx",
                                      sheet = "processing_MUN")
```
One pre-computed sheet already contained Stefan's equal-per-state-allocation
result for 2013 (proc_cap_act per município).

**code/pipeline/ method — per-year recomputation:**

Added constants and helpers:
- `ABIOVE_CAP_FILE` — `data/new/00/new/ABIOVE_processing/ABIOVE_raw_capacity_2025.xlsx`
- `YEAR_COL_MAP` — list: year → column index in sheet 2 "Evolução" for the Ativa
  capacity column. Years 1989, 1995, 1997, 1998, 2000–2020, 2022–2025 available.
- `.decode_html_entities(x)` — undoes openxlsx's "Cuiab&#225;" encoding quirk.
- `.abiove_state_cap(year)` — reads sheet 2 of the ABIOVE 2025 file, restricted
  to the Processamento block (rows between the "Processamento" and "Refino"
  labels in column B). Returns `(nm_state, state_cap_td)`.

  **Bugfix (2026-04-21):** original `.abiove_state_cap` summed all state rows
  indiscriminately, inadvertently including the Refino and Envase sections
  below Processamento (193k t/d instead of 160k t/d for 2013). Fixed by
  scanning `ev$X1` for the section labels and slicing the block explicitly.

- `.PLANT_INDEX` — year → {file, era, sheet [, status_col]} mapping:
  - **early** (2003, 2004): `pesquisa_capacidade_YYYY_PT.xls`, sheet `unidproces`
  - **mid** (2005–2015): `pesquisa_capacidade_YYYY_PT.xls`, sheet `geralproces` /
    `3. geralproces` / `3. GeralProces` (case varies per year)
  - **new** (2018–2023): `pesquisa_capacidade_YYYY.xlsx` or
    `ABIOVE_raw_capacity_YYYY.xlsx`, sheet `3. Unidades Industriais` (2018) or
    `3.Unidades de Processamento` (2019+)
  - **multi** (2024, 2025): `ABIOVE_raw_capacity_2025.xlsx`, sheet
    `3.Unidades de Processamento`, multi-year status cols

- `.resolve_plant_entry(year)` — lower-bound fallback for missing years
  (2000–2002 → 2003; 2016, 2017 → 2015; 2021 → 2020).

- Three era-specific parsers (`.parse_plant_early/mid/new`) that all return
  the tidy schema: `(company, municipality, UF, status)`, filtered to active
  soy-processing plants.

- `.abiove_plant_list(year)` — dispatcher.

Then three lines of dplyr apply Trsek's equal-per-state rule:
```r
state_alloc <- plants %>%
  group_by(UF) %>%
  summarise(n_active_soy = n()) %>%
  left_join(state_cap, by = c("UF" = "nm_state")) %>%
  mutate(per_plant_cap = state_cap_td / n_active_soy)
plants_with_cap <- plants %>% left_join(state_alloc, by = "UF")
PROC_MUN_raw <- plants_with_cap %>%
  group_by(UF, municipality) %>%
  summarise(n_plants = n(), capacity_td = sum(per_plant_cap),
            companies = paste(sort(unique(company)), collapse = "; "))
```

Output schema compatible with the downstream §2.4 block (municipality, UF,
n_plants, capacity_td, companies, year).

## 6. §1.4b Refining + bottling capacity — NEW BLOCK

Stefan's pipeline read refining from `refining_bottling_MUN` sheet of the 2013
file. The upstream `code/pipeline/00_data_preperation.R` had `ref_fac = ref_cap =
bot_cap = 0` with a TODO. This fork actually implements it.

Mirror of §1.4 but for sheet 5 `5.Unidades de Refino e Envase`:
- `.REFINING_INDEX` — year → {file, era, sheet}. Note: 2018 has only a
  state-level refining table (sheet `6. Ref_Env_UF_Região`), **no plant list**
  → falls back to 2015.
- `.resolve_refining_entry(year)` — lower-bound fallback.
- `.abiove_state_sector_cap(year, sector)` — generalized state-cap reader that
  takes `sector ∈ {"Processamento", "Refino", "Envase"}`. Used for both ref
  and bot state denominators.
- `.parse_refining_early/mid/new(file, sheet[, status_col])` — parallel to
  the processing parsers, but expect "Óleos Refinados" text column (old eras)
  or "Soja" flag column (new era).
- `.abiove_refining_list(year)` — dispatcher.

Allocation (applied to both ref and bot in one pass):
- `ref_cap_per_plant = state_ref_cap[s, y] / n_active_soy_refining[s, y]`
- `bot_cap_per_plant = state_bot_cap[s, y] / n_active_soy_refining[s, y]`

Output: `REF_MUN_raw` with `(UF, municipality, n_ref_plants, ref_cap_td,
bot_cap_td, companies, year)`.

## 7. §2.4 Processing transform — join-logic rewrite

**Stefan:** simple `left_join(PROC_MUN_raw, MUN, by = "co_mun")` using the
pre-existing 2013 `processing_MUN` sheet's co_mun column.

**code/pipeline/:** Stefan's 2013 file had co_mun populated; our `pesquisa_capacidade`
files have município names only. Must join by name:

```r
name_fixes <- c("OSWALDO CRUZ" = "OSVALDO CRUZ",
                "CARIRI"       = "CARIRI DO TOCANTINS",
                "CARAPÓ"       = "CAARAPÓ")
PROC_MUN_raw <- PROC_MUN_raw %>% mutate(nm_mun_upper = toupper(municipality))
# apply name_fixes …
PROC_MUN <- PROC_MUN_raw %>%
  left_join(MUN[, c("co_mun", "nm_mun", "nm_state")],
            by = c("nm_mun_upper" = "nm_mun", "UF" = "nm_state"))
```

**New:** refining merge. Instead of `ref_cap = bot_cap = 0`:
```r
PROC_MUN <- PROC_MUN %>%
  full_join(REF_MUN %>% select(co_mun, ref_fac, ref_cap, bot_cap),
            by = "co_mun") %>%
  mutate(ref_fac = coalesce(ref_fac, 0),
         ref_cap = coalesce(ref_cap, 0),
         bot_cap = coalesce(bot_cap, 0),
         proc_fac = coalesce(proc_fac, 0),
         proc_cap = coalesce(proc_cap, 0))
```
`full_join` (not `left_join`) so municípios that refine but don't crush still
appear. Missing `nm_mun`/`nm_state` for such rows are filled from the MUN
master after the join.

## 8. §4.2 Capitals — parse-error bugfix

Stefan's `code/pipeline/00_data_preperation.R` (single file, pre-existing) had a
stray `!!!!!!!!!!!` on line 855 that broke R parsing before the
`st_read("BR_Localidades_2010_v1.shx")` call could run. Removed. In our fork
that line is now just the comment `# Source: IBGE Localities 2010 shapefile`.

## 9. §5 Writers (end of script)

All `saveRDS` / `st_write` targets moved from `results/outputs/00/` to
`paste0("results/outputs/00_", YEAR, "/")`. No content changes.

---

## Net diffs vs Stefan's output (verified 2013)

| Variable | Stefan | code/pipeline/ | Why |
|---|---|---|---|
| `proc_cap` | 151,546 | 159,900 | New uses 2013 Ativa state total (160,200) from ABIOVE 2025 file; allocates among 92 active soy plants |
| `proc_fac` | 97 | 92 | Strict soy filter; Stefan counted some non-soy facilities |
| `ref_cap` | 17,825 | 19,613 | Same methodology, new 2013 Refino Ativa source (20,103) |
| `ref_fac` | 43 | 35 | Strict soy filter |
| `bot_cap` | 12,448 | 13,610 | Same methodology |
| `oil_acq_pc` | 25,989 | 37,472 | POF 2018 (Stefan, hardcoded) vs POF 2008 (code/pipeline/, lower-bound for 2013) |
| `diesel_cap_soy` | 12,676 | 9,352 | Different ANP file: new folder has a variant with concatenated "Município/UF" field → UF=NaN → join drops ~25% of plants. Fix: point at `_original.xlsx` |
| `chicken` | 1.247 B | 1.241 B | IBGE revised 3 RS municípios (Vila Lângaro, Ibiaçá, Água Santa) between old and new SIDRA extract dates |

All other variables (production, exports, imports, population, other
livestock, storage, etc.) are identical to the last significant digit.

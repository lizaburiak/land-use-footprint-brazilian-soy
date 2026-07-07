
###############################################################################
# SCRIPT 00: Data Preparation — Municipality-Level Soy Supply Chain Dataset
###############################################################################
#
# PURPOSE:
#   Combines ~15 raw data sources into one coherent municipality-level dataset
#   (SOY_MUN) containing production, trade, processing capacity, population,
#   livestock, storage, food consumption, and biodiesel data for Brazilian soy.
#   Also produces spatial datasets (polygons, capitals, distance matrices).
#
# PARAMETERIZED BY YEAR:
#   All data sources auto-select the appropriate file for the target year.
#   For data not available annually, the nearest available year <= T is used
#   (lower-bound approximation).
#
# USAGE:
#   Rscript code/pipeline/00_data_preparation/00_data_preparation.R 2020   # from command line
#   or set YEAR manually below and source() in RStudio
#
# INPUT DATA (all from data/raw/00/):
#   ┌─────────────────────────────┬──────────────────┬────────────────────────┐
#   │ Data                        │ Years available   │ Selection method       │
#   ├─────────────────────────────┼──────────────────┼────────────────────────┤
#   │ IBGE municipality codes     │ 15 snapshots      │ lower bound            │
#   │ COMEX exports & imports     │ 2000-2025 yearly  │ exact year             │
#   │ COMEX lookup tables         │ current           │ static                 │
#   │ IBGE soy production (PAM)  │ 2000-2024 yearly  │ exact year             │
#   │ Processing capacity (ABIOVE)│ 2000,05,10,15,20,23│ lower bound           │
#   │ IBGE population             │ 2000-2022,24-25   │ exact/lower bound      │
#   │ IBGE livestock (PPM)        │ 2000-2025 yearly  │ exact year             │
#   │ IBGE milked cows            │ 2000-2024 yearly  │ exact year             │
#   │ Grain storage (IBGE)        │ 2014 only         │ static                 │
#   │ POF soy oil acquisition     │ 2002, 2008, 2018  │ lower bound            │
#   │ Biodiesel capacity (ANP)   │ 2008-2026 yearly  │ lower bound (0 if <08) │
#   │ Municipality boundaries     │ 15 snapshots      │ lower bound            │
#   │ Municipality capitals       │ 2010 shapefile    │ static                 │
#   │ FAO CBS (used in script 00_FAO) │ 2000-2023     │ exact year             │
#   └─────────────────────────────┴──────────────────┴────────────────────────┘
#
# OUTPUT (to data/generated/outputs/00_{YEAR}/):
#   - SOY_MUN_00.rds      : main municipality table (~5570 rows × 39 columns)
#   - SOY_MUN.csv          : same in CSV
#   - EXP_MUN_SOY_00.rds  : bilateral exports (MU × destination × product)
#   - IMP_MUN_SOY_00.rds  : bilateral imports (MU × origin × product)
#   - GEO_MUN_SOY_00.rds  : municipality polygons with all SOY_MUN attributes
#   - GEO_MUN_SOY.gpkg    : same as GeoPackage
#   - GEO_BRA.shp          : dissolved Brazil boundary
#   - MUN_capitals.rds      : municipality capital point locations
#   - MUN_center_dist.rds  : Euclidean distance matrix (centroid-to-centroid)
#   - MUN_capital_dist.rds  : Euclidean distance matrix (capital-to-capital)
#
###############################################################################

library(dplyr)
library(openxlsx)
library(tidyr)
library(sf)
library(readr)
library(readxl)   # needed for legacy .xls pesquisa files


# ═══════════════════════════════════════════════════════════════════════════════
# YEAR SELECTION
# ═══════════════════════════════════════════════════════════════════════════════

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 0) {
  YEAR <- as.integer(args[1])
} else {
  YEAR <- 2013
}
stopifnot(YEAR >= 2000 & YEAR <= 2022)  # analysis window 2000–2022

write <- TRUE
cat("============================================================\n")
cat("Script 00: Data Preparation for year", YEAR, "\n")
cat("============================================================\n\n")

OUT <- paste0("data/generated/outputs/00_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# For data not available every year (boundaries, POF, processing),
# pick the most recent available year that doesn't exceed the target.
# Example: if target=2012 and available={2000,2005,2010,2013}, returns 2010.
find_lower_bound <- function(available_years, target) {
  candidates <- available_years[available_years <= target]
  if (length(candidates) == 0) return(min(available_years))
  return(max(candidates))
}

# Given a file path pattern like "data_{Y}.csv", find the file for {Y}=target.
# If exact year file doesn't exist, scans the directory for all matching files,
# extracts their years, and picks the lower-bound year.
find_year_file <- function(pattern, target, available_years = NULL) {
  f <- gsub("\\{Y\\}", target, pattern)
  if (file.exists(f)) return(list(file = f, year = target))

  wildcard_path <- gsub("\\{Y\\}", "*", pattern)
  files <- Sys.glob(wildcard_path)
  if (length(files) == 0) stop(paste("No files found for pattern:", pattern))

  regex_pat <- gsub("\\{Y\\}", "([0-9]{4})", basename(pattern))
  years <- as.integer(gsub(paste0(".*", regex_pat, ".*"), "\\1", basename(files)))
  valid <- !is.na(years) & years >= 2000 & years <= 2030
  years <- years[valid]; files <- files[valid]
  if (length(years) == 0) stop(paste("No valid year files for:", pattern))

  nearest <- find_lower_bound(years, target)
  f <- gsub("\\{Y\\}", nearest, pattern)
  if (!is.na(nearest) && nearest != target) {
    cat("  [NOTE] Using", nearest, "instead of", target, "for",
        basename(dirname(pattern)), "\n")
  }
  return(list(file = f, year = nearest))
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: LOAD RAW DATA
# ═══════════════════════════════════════════════════════════════════════════════
# Each data source is loaded from data/raw/00/{subfolder}/.
# Year selection is automatic via find_year_file() or direct paste0().

cat("Loading data for year", YEAR, "...\n")

# ── 1.1 Municipality master list (IBGE) ──────────────────────────────────────
# Contains: co_mun (7-digit IBGE code), nm_mun (uppercase name),
#           co_state (2-digit state code), nm_state (2-letter abbreviation)
# Available years: 2000,2001,2005,2007,2010,2013-2022 (from geobr)
mun_info <- find_year_file(
  "data/raw/00/IBGE_municipalities/GEO_MUN_{Y}_IBGE.xlsx", YEAR)
MUN <- openxlsx::read.xlsx(mun_info$file)
cat("  Municipality codes:", nrow(MUN), "from year", mun_info$year, "\n")

# ── 1.2 COMEX international trade (MDIC) ─────────────────────────────────────
# Monthly municipality-level exports and imports, all products.
# Semicolon-separated CSV, one file per year. Available: 2000-2025.
# We filter for soy HS4 codes later: 1201 (beans), 1507 (oil), 2304 (cake).
EXP_MUN <- read.csv2(
  file = paste0("data/raw/00/COMEX_exports/EXP_", YEAR, "_MUN_COMEX.csv"),
  header = TRUE, stringsAsFactors = FALSE)
IMP_MUN <- read.csv2(
  file = paste0("data/raw/00/COMEX_imports/IMP_", YEAR, "_MUN_COMEX.csv"),
  header = TRUE, stringsAsFactors = FALSE)

# Lookup tables for COMEX municipality codes → names and country codes → names
# These are static (backward-compatible across all years).
COMEX_MUN <- read.csv2(
  file = "data/raw/00/COMEX_codes/UF_MUN_COMEX.csv",
  header = TRUE, fileEncoding = "ISO-8859-1", stringsAsFactors = FALSE)
PAIS <- read.csv2(
  file = "data/raw/00/COMEX_codes/PAIS_COMEX.csv",
  header = TRUE, fileEncoding = "ISO-8859-1")

# ── 1.3 Soy production (IBGE PAM, Table 1612) ───────────────────────────────
# Area planted, area harvested, production quantity by municipality.
# Available: 2000-2024 yearly. CSV with 2 header rows (skip=2).
prod_info <- find_year_file(
  "data/raw/00/IBGE_production/Production_tabela1612_IBGE_{Y}.csv", YEAR)
PROD_MUN <- read.csv(
  file = prod_info$file, header = TRUE, skip = 2,
  encoding = "UTF-8", stringsAsFactors = FALSE)

# ── 1.4 Processing/crushing facilities (ABIOVE) ──────────────────────────────
# NEW METHOD (replaces FINAL_municipality_level_2000_2023.csv approach):
#   Read ABIOVE_raw_capacity_2025.xlsx directly.
#     * Sheet "2.Evolução"                 → state t/day per year, 1989–2025
#     * Sheet "3.Unidades de Processamento" → plant list with status 2024 & 2025
#   Apply Trsek-style equal allocation per state:
#     per_plant_cap = state_cap_td[s, y] / n_active_soy_plants[s, y]
#   Plants change between 2024 and 2025, so the roster is filtered per year.
#   For years outside {2024, 2025} we fall back to the 2024 roster as a proxy.
ABIOVE_CAP_FILE <- "data/raw/00/ABIOVE_processing/ABIOVE_raw_capacity_2025.xlsx"

# Map: year → Ativa-column index in sheet 2 (R 1-based; openxlsx drops col A).
YEAR_COL_MAP <- list(
  "1989"=3, "1995"=6, "1997"=9, "1998"=12,
  "2000"=15, "2001"=18, "2002"=21, "2003"=24, "2004"=27,
  "2005"=30, "2006"=33, "2007"=36, "2008"=39, "2009"=42,
  "2010"=45, "2011"=48, "2012"=51, "2013"=54, "2014"=57,
  "2015"=60, "2016"=63, "2017"=66, "2018"=69, "2019"=72,
  "2020"=75, "2022"=78, "2023"=82, "2024"=86, "2025"=90
)

# openxlsx sometimes returns Portuguese accents as "Cuiab&#225;" — decode.
.decode_html_entities <- function(x) {
  x <- as.character(x); pat <- "&#([0-9]+);"
  while (any(grepl(pat, x), na.rm = TRUE)) {
    for (i in seq_along(x)) {
      if (!is.na(x[i]) && grepl(pat, x[i])) {
        code <- as.integer(sub(paste0(".*", pat, ".*"), "\\1", x[i]))
        x[i] <- sub(pat, intToUtf8(code), x[i])
      }
    }
  }
  x
}

.abiove_state_cap <- function(year) {
  ycol <- YEAR_COL_MAP[[as.character(year)]]
  if (is.null(ycol)) {
    avail <- as.integer(names(YEAR_COL_MAP))
    near <- max(avail[avail <= year])
    cat("  [NOTE] ABIOVE state-cap: no col for", year, "— using", near, "\n")
    ycol <- YEAR_COL_MAP[[as.character(near)]]
  }
  ev <- openxlsx::read.xlsx(ABIOVE_CAP_FILE, sheet = "2.Evolução",
                             colNames = FALSE, skipEmptyRows = FALSE)
  # BUGFIX: sheet 2 stacks Processamento/Refino/Envase in one long table. Without
  # restricting to the Processamento block we accidentally summed all three.
  proc_start   <- which(ev$X1 == "Processamento")[1] + 1
  refino_start <- which(ev$X1 == "Refino")[1]
  proc_block   <- ev[proc_start:(refino_start - 1), ]
  st <- proc_block[, c("X2", paste0("X", ycol))]
  names(st) <- c("UF", "state_cap_td")
  st$state_cap_td <- suppressWarnings(as.numeric(st$state_cap_td))
  st <- st[!is.na(st$UF) & nchar(st$UF) == 2, ]
  st$state_cap_td[is.na(st$state_cap_td)] <- 0
  st %>% group_by(UF) %>%
    summarise(state_cap_td = sum(state_cap_td), .groups = "drop") %>%
    rename(nm_state = UF)
}

# Year → { file, era, sheet }  — the ABIOVE Pesquisa de Capacidade file that
# carries the plant roster for that year. Three file eras:
#   early  (2003–2004): sheet "unidproces"
#                         cols: Empresa | Nº | Localização | UF | Processo |
#                                Oleaginosas (text "Soja"/"Algodão") | Situação
#   mid    (2005–2015): sheet "geralproces" (case varies)
#                         cols: Cod. | Empresas | Localização | UF | Processo |
#                                Oleaginosas | Situação
#   new    (2018–2022): sheet "3. Unidades Industriais" (2018) or
#                               "3.Unidades de Processamento" (2019+)
#                         cols: Empresas | Município | UF | Região |
#                                YYYY (status) | Processo | Soja (x/NA) | …
#   multi  (2023, 2025): sheet "3.Unidades de Processamento" with multiple
#                         year status cols. 2023 file holds 2023/2022/2020;
#                         2025 file holds 2025/2024.
# For missing years (2000, 2001, 2002, 2016, 2017, 2021) we fall back to the
# closest available LOWER-BOUND year.
.PLANT_PATH <- "data/raw/00/ABIOVE_processing"
.PLANT_INDEX <- list(
  "2003" = list(file = "pesquisa_capacidade_2003_PT.xls", era = "early", sheet = "unidproces"),
  "2004" = list(file = "pesquisa_capacidade_2004_PT.xls", era = "mid",   sheet = "geralproces"),  # 2004 uses the mid-era 'geralproces' sheet (no 'unidproces' like 2003)
  "2005" = list(file = "pesquisa_capacidade_2005_PT.xls", era = "mid",   sheet = "geralproces"),
  "2006" = list(file = "pesquisa_capacidade_2006_PT.xls", era = "mid",   sheet = "geralproces"),
  "2007" = list(file = "pesquisa_capacidade_2007_PT.xls", era = "mid",   sheet = "geralproces"),
  "2008" = list(file = "pesquisa_capacidade_2008_PT.xls", era = "mid",   sheet = "geralproces"),
  "2009" = list(file = "pesquisa_capacidade_2009_PT.xls", era = "mid",   sheet = "geralproces"),
  "2010" = list(file = "pesquisa_capacidade_2010_PT.xls", era = "mid",   sheet = "geralproces"),
  "2011" = list(file = "pesquisa_capacidade_2011_PT.xls", era = "mid",   sheet = "geralproces"),
  "2012" = list(file = "pesquisa_capacidade_2012_PT.xls", era = "mid",   sheet = "geralproces"),
  "2013" = list(file = "pesquisa_capacidade_2013_PT.xls", era = "mid",   sheet = "3. geralproces"),
  "2014" = list(file = "pesquisa_capacidade_2014_PT.xls", era = "mid",   sheet = NULL),
  "2015" = list(file = "pesquisa_capacidade_2015_PT.xls", era = "mid",   sheet = "3. GeralProces"),
  "2018" = list(file = "pesquisa_capacidade_2018.xlsx",   era = "new",   sheet = "3. Unidades Industriais",    status_col = "2018"),
  "2019" = list(file = "pesquisa_capacidade_2019.xlsx",   era = "new",   sheet = "3.Unidades de Processamento", status_col = "2019"),
  "2020" = list(file = "pesquisa_capacidade_2020.xlsx",   era = "new",   sheet = "3.Unidades de Processamento", status_col = "2020"),
  "2022" = list(file = "pesquisa_capacidade_2022.xlsx",   era = "new",   sheet = "3.Unidades de Processamento", status_col = "2022"),
  "2023" = list(file = "ABIOVE_raw_capacity_2023.xlsx",   era = "new",   sheet = "3.Unidades de Processamento", status_col = "2023"),
  "2024" = list(file = "ABIOVE_raw_capacity_2025.xlsx",   era = "multi", sheet = "3.Unidades de Processamento", status_col = "2024"),
  "2025" = list(file = "ABIOVE_raw_capacity_2025.xlsx",   era = "multi", sheet = "3.Unidades de Processamento", status_col = "2025")
)

# Resolve a target year to the file entry to use (lower-bound fallback).
.resolve_plant_entry <- function(year) {
  avail <- sort(as.integer(names(.PLANT_INDEX)))
  if (as.character(year) %in% names(.PLANT_INDEX)) {
    return(list(entry = .PLANT_INDEX[[as.character(year)]], effective_year = year))
  }
  candidates <- avail[avail <= year]
  if (length(candidates) == 0) {
    # year is earlier than all available → use the EARLIEST file (2003)
    eff <- min(avail)
  } else {
    eff <- max(candidates)
  }
  list(entry = .PLANT_INDEX[[as.character(eff)]], effective_year = eff)
}

# Parser for early era (2003-2004 unidproces sheet).
.parse_plant_early <- function(file, sheet) {
  df <- as.data.frame(readxl::read_excel(file, sheet = sheet, col_names = FALSE,
                                         skip = 5))
  # Columns (1-indexed): 1=code/blank, 2=Empresa, 3=Nº, 4=Localização, 5=UF,
  #                       6=Processo, 7=Oleaginosas, 8=Situação
  names(df)[1:8] <- c("x1","Empresas","num","Municipio","UF","Processo",
                       "Oleaginosas","Situacao")
  df %>%
    filter(!is.na(Empresas), !is.na(Municipio), !is.na(UF),
           nchar(as.character(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(as.character(Oleaginosas))) == "SOJA",
           status   = as.character(Situacao)) %>%
    filter(soy_flag, toupper(trimws(status)) == "ATIVA") %>%
    transmute(company = as.character(Empresas),
              municipality = as.character(Municipio),
              UF = as.character(UF),
              status)
}

# Parser for mid era (2005-2015 geralproces sheet). Header row varies by file.
# Strategy: read with no headers, scan for the row containing "Empresas" + "UF".
.parse_plant_mid <- function(file, sheet) {
  # Resolve the sheet name case/space/dot-insensitively against the file's actual
  # sheets — names vary by year ('geralproces' vs 'Geralproces' vs 'Geral proces').
  sheets <- readxl::excel_sheets(file)
  .norm <- function(s) gsub("[[:space:]\\.]", "", tolower(s))
  if (is.null(sheet)) {
    idx <- which(grepl("geralproces|empreproces", .norm(sheets)))
  } else {
    idx <- which(.norm(sheets) == .norm(sheet))
    if (length(idx) == 0) idx <- which(grepl("geralproces|empreproces", .norm(sheets)))
  }
  if (length(idx) == 0) stop("mid-era: no plant-list sheet matching '", sheet, "' in ", file)
  sheet <- sheets[idx[1]]
  raw <- as.data.frame(suppressMessages(
    readxl::read_excel(file, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  # Find the header row
  is_header <- apply(raw, 1, function(r) {
    v <- toupper(trimws(as.character(r)))
    any(grepl("EMPRESA", v), na.rm = TRUE) && any(v == "UF", na.rm = TRUE)
  })
  hdr <- which(is_header)[1]
  if (is.na(hdr)) stop("mid-era: header row not found in ", file)
  # Header names
  h <- as.character(raw[hdr, ])
  h <- trimws(h)
  # Find key columns by matching on upper-case content
  HU <- toupper(h)
  get_col <- function(pat) {
    i <- which(grepl(pat, HU))
    if (length(i) == 0) return(NA_integer_) else i[1]
  }
  emp <- get_col("EMPRESA")
  mun <- get_col("LOCALI|MUNIC")
  uf  <- which(HU == "UF")[1]
  ole <- get_col("OLEAGIN")
  sit <- get_col("SITUA|SITUAÇÃO")
  need <- c(emp = emp, mun = mun, uf = uf, ole = ole, sit = sit)
  if (any(is.na(need)))
    stop("mid-era: missing columns in ", file, " — got: ",
         paste(names(need)[is.na(need)], collapse=","))
  body <- raw[(hdr + 1):nrow(raw), , drop = FALSE]
  df <- data.frame(
    company      = as.character(body[[emp]]),
    municipality = as.character(body[[mun]]),
    UF           = as.character(body[[uf]]),
    oleaginosas  = as.character(body[[ole]]),
    status       = as.character(body[[sit]]),
    stringsAsFactors = FALSE
  )
  df %>%
    filter(!is.na(company), !is.na(municipality), !is.na(UF),
           nchar(trimws(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(oleaginosas)) == "SOJA") %>%
    filter(soy_flag, toupper(trimws(status)) == "ATIVA") %>%
    dplyr::select(company, municipality, UF, status)
}

# Parser for new/multi era (2018+ files with year-labeled status + Soja flag).
.parse_plant_new <- function(file, sheet, status_col) {
  raw <- as.data.frame(suppressMessages(
    readxl::read_excel(file, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  # Find header row (contains "Empresas" + "Município")
  is_header <- apply(raw, 1, function(r) {
    v <- toupper(trimws(as.character(r)))
    any(grepl("EMPRESA", v), na.rm = TRUE) &&
    any(grepl("MUNIC",    v), na.rm = TRUE)
  })
  hdr <- which(is_header)[1]
  if (is.na(hdr)) stop("new-era: header row not found in ", file)
  h <- as.character(raw[hdr, ])
  h <- trimws(h)
  HU <- toupper(h)
  emp <- which(grepl("EMPRESA", HU))[1]
  mun <- which(grepl("MUNIC|LOCALI", HU))[1]
  uf  <- which(HU == "UF")[1]
  soj <- which(HU == "SOJA")[1]
  # status col match: user-requested year literal
  stc <- which(h == status_col | trimws(h) == as.character(status_col))[1]
  if (is.na(stc)) {
    # sometimes the year is stored as numeric in the sheet → match on as.numeric
    stc <- which(suppressWarnings(as.numeric(h)) == as.numeric(status_col))[1]
  }
  if (any(is.na(c(emp, mun, uf, soj, stc))))
    stop("new-era: missing columns in ", file,
         " — emp=", emp, " mun=", mun, " uf=", uf, " soja=", soj, " stc=", stc)
  body <- raw[(hdr + 1):nrow(raw), , drop = FALSE]
  df <- data.frame(
    company      = as.character(body[[emp]]),
    municipality = as.character(body[[mun]]),
    UF           = as.character(body[[uf]]),
    soja_flag    = as.character(body[[soj]]),
    status       = as.character(body[[stc]]),
    stringsAsFactors = FALSE
  )
  df %>%
    filter(!is.na(company), !is.na(municipality), !is.na(UF),
           nchar(trimws(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(soja_flag)) == "X") %>%
    filter(soy_flag, toupper(trimws(status)) == "ATIVA") %>%
    dplyr::select(company, municipality, UF, status)
}

# Main dispatcher — returns tidy plant list for any year, with lower-bound fallback.
.abiove_plant_list <- function(year) {
  res <- .resolve_plant_entry(year)
  entry <- res$entry; eff <- res$effective_year
  if (eff != year) {
    cat("  [NOTE] Plant list: no file for", year, "— using", eff,
        "(lower-bound fallback)\n")
  }
  file <- file.path(.PLANT_PATH, entry$file)
  if (!file.exists(file)) stop("Plant-list file not found: ", file)

  out <- switch(entry$era,
    "early" = .parse_plant_early(file, entry$sheet),
    "mid"   = .parse_plant_mid(file, entry$sheet),
    "new"   = .parse_plant_new(file, entry$sheet, entry$status_col),
    "multi" = .parse_plant_new(file, entry$sheet, entry$status_col),
    stop("Unknown era: ", entry$era)
  )
  cat("  Plant list: year =", year, "(file =", entry$file,
      "); active soy plants =", nrow(out), "\n")
  out
}

.state_cap  <- .abiove_state_cap(YEAR)
.plants     <- .abiove_plant_list(YEAR)

# Allocation method: equal-per-plant within each state (Stefan-style).
# Each state's total ABIOVE capacity is split evenly across its active soy plants.
.state_alloc <- .plants %>%
  group_by(UF) %>%
  summarise(n_active_soy = n(), .groups = "drop") %>%
  left_join(.state_cap, by = c("UF" = "nm_state")) %>%
  mutate(per_plant_cap = ifelse(n_active_soy > 0,
                                state_cap_td / n_active_soy, 0))
.plants_with_cap <- .plants %>%
  left_join(.state_alloc %>% dplyr::select(UF, per_plant_cap), by = "UF") %>%
  mutate(per_plant_cap = ifelse(is.na(per_plant_cap), 0, per_plant_cap))

# Aggregate to município; matches schema Section 2.4 expects
# (columns: municipality, UF, year, n_plants, capacity_td, companies)
PROC_MUN_raw <- .plants_with_cap %>%
  group_by(UF, municipality) %>%
  summarise(n_plants    = n(),
            capacity_td = sum(per_plant_cap),
            companies   = paste(sort(unique(company)), collapse = "; "),
            .groups     = "drop") %>%
  mutate(year = YEAR)
cat("  Processing facilities:", nrow(PROC_MUN_raw),
    "municípios, national total",
    round(sum(PROC_MUN_raw$capacity_td), 1), "t/day\n")


# ── 1.4b Refining + bottling facilities (ABIOVE) ─────────────────────────────
# Parallel to processing, with equal-per-state allocation.
#   State Refino capacity:  sheet 2 rows 34-57 of ABIOVE_raw_capacity_2025
#   State Envase capacity:  sheet 2 rows 58-80 (same sheet)
#   Per-plant roster:        refining sheet of each year's pesquisa file
#
# Era mapping for refining plant lists:
#   early  (2003):           sheet "unidrefin"           (columns like unidproces)
#   mid    (2004-2015):      sheet "geralrefin" /         cols: Empresa, Município,
#                             "7. geralrefin"              UF, Óleos Refinados,
#                                                          Situação
#   new    (2019-2022):      sheet "5.Unidades de         cols: Empresas, Município,
#                             Refino e Envase"             UF, Região, YYYY (status),
#                                                          Soja (flag), …
#   multi  (2023, 2025):     same as new but multi-year status cols
#   2018 is state-level only (no plant list) → fall back to 2015.

.REFINING_INDEX <- list(
  "2003" = list(file = "pesquisa_capacidade_2003_PT.xls", era = "early", sheet = "unidrefin"),
  "2004" = list(file = "pesquisa_capacidade_2004_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2005" = list(file = "pesquisa_capacidade_2005_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2006" = list(file = "pesquisa_capacidade_2006_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2007" = list(file = "pesquisa_capacidade_2007_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2008" = list(file = "pesquisa_capacidade_2008_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2009" = list(file = "pesquisa_capacidade_2009_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2010" = list(file = "pesquisa_capacidade_2010_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2011" = list(file = "pesquisa_capacidade_2011_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2012" = list(file = "pesquisa_capacidade_2012_PT.xls", era = "mid",   sheet = "geralrefin"),
  "2013" = list(file = "pesquisa_capacidade_2013_PT.xls", era = "mid",   sheet = "7. geralrefin"),
  "2014" = list(file = "pesquisa_capacidade_2014_PT.xls", era = "mid",   sheet = NULL),
  "2015" = list(file = "pesquisa_capacidade_2015_PT.xls", era = "mid",   sheet = "7. GeralRefin"),
  "2019" = list(file = "pesquisa_capacidade_2019.xlsx",   era = "new",   sheet = "5.Unidades de Refino e Envase", status_col = "2019"),
  "2020" = list(file = "pesquisa_capacidade_2020.xlsx",   era = "new",   sheet = "5.Unidades de Refino e Envase", status_col = "2020"),
  "2022" = list(file = "pesquisa_capacidade_2022.xlsx",   era = "new",   sheet = "5.Unidades de Refino e Envase", status_col = "2022"),
  "2023" = list(file = "ABIOVE_raw_capacity_2023.xlsx",   era = "new",   sheet = "5.Unidades de Refino e Envase", status_col = "2023"),
  "2024" = list(file = "ABIOVE_raw_capacity_2025.xlsx",   era = "multi", sheet = "5.Unidades de Refino e Envase", status_col = "2024"),
  "2025" = list(file = "ABIOVE_raw_capacity_2025.xlsx",   era = "multi", sheet = "5.Unidades de Refino e Envase", status_col = "2025")
)

.resolve_refining_entry <- function(year) {
  avail <- sort(as.integer(names(.REFINING_INDEX)))
  if (as.character(year) %in% names(.REFINING_INDEX)) {
    return(list(entry = .REFINING_INDEX[[as.character(year)]], effective_year = year))
  }
  candidates <- avail[avail <= year]
  if (length(candidates) == 0) {
    eff <- min(avail)
  } else {
    eff <- max(candidates)
  }
  list(entry = .REFINING_INDEX[[as.character(eff)]], effective_year = eff)
}

# State refining or bottling capacity — reads rows 34-57 (Refino) or 58-80 (Envase)
# of sheet 2 Evolução. Row range determined by scanning col B for "Refino" / "Envase"
# labels and taking rows between that label and the next.
.abiove_state_sector_cap <- function(year, sector = "Refino") {
  ycol <- YEAR_COL_MAP[[as.character(year)]]
  if (is.null(ycol)) {
    avail <- as.integer(names(YEAR_COL_MAP))
    near <- max(avail[avail <= year])
    cat("  [NOTE]", sector, "state-cap: no col for", year, "— using", near, "\n")
    ycol <- YEAR_COL_MAP[[as.character(near)]]
  }
  ev <- openxlsx::read.xlsx(ABIOVE_CAP_FILE, sheet = "2.Evolução",
                             colNames = FALSE, skipEmptyRows = FALSE)
  # Locate the block boundaries by scanning col X1 for section headers
  section_rows <- which(ev[, "X1"] %in% c("Processamento", "Refino", "Envase"))
  names(section_rows) <- ev[section_rows, "X1"]
  if (!(sector %in% names(section_rows))) stop("Sector not found: ", sector)
  start <- section_rows[[sector]] + 1
  next_sections <- section_rows[section_rows > section_rows[[sector]]]
  end <- if (length(next_sections) > 0) min(next_sections) - 1 else nrow(ev)
  block <- ev[start:end, c("X2", paste0("X", ycol))]
  names(block) <- c("UF", "state_cap_td")
  block$state_cap_td <- suppressWarnings(as.numeric(block$state_cap_td))
  block <- block[!is.na(block$UF) & nchar(block$UF) == 2, ]
  block$state_cap_td[is.na(block$state_cap_td)] <- 0
  block %>% group_by(UF) %>%
    summarise(state_cap_td = sum(state_cap_td), .groups = "drop") %>%
    rename(nm_state = UF)
}

# Parsers for refining plant lists (very similar to processing parsers
# but with refining-specific column headers).

# early era (2003 unidrefin): cols Empresa, Nº, Localização, UF, Óleos Refinados, Situação
.parse_refining_early <- function(file, sheet) {
  df <- as.data.frame(readxl::read_excel(file, sheet = sheet, col_names = FALSE,
                                         skip = 5))
  # Structure matches unidproces but Oleaginosas → Óleos Refinados (text: "Soja"/"Algodão")
  names(df)[1:7] <- c("x1","Empresas","num","Municipio","UF","OleosRefinados","Situacao")
  df %>%
    filter(!is.na(Empresas), !is.na(Municipio), !is.na(UF),
           nchar(as.character(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(as.character(OleosRefinados))) == "SOJA",
           status   = as.character(Situacao)) %>%
    filter(soy_flag, toupper(trimws(status)) == "ATIVA") %>%
    transmute(company = as.character(Empresas),
              municipality = as.character(Municipio),
              UF = as.character(UF),
              status)
}

# mid era (2004-2015): geralrefin sheet; header row auto-detected (Empresa + UF + Óleos)
.parse_refining_mid <- function(file, sheet) {
  # Resolve the sheet name case/space/dot-insensitively (varies by year:
  # 'geralrefin' vs 'Geralrefin' vs '7. geralrefin').
  sheets <- readxl::excel_sheets(file)
  .norm <- function(s) gsub("[[:space:]\\.]", "", tolower(s))
  idx <- integer(0)
  if (!is.null(sheet)) idx <- which(.norm(sheets) == .norm(sheet))
  if (length(idx) == 0) {
    # Prefer geralrefin (per-plant) over empresasrefin (company roster)
    idx_g <- which(grepl("geralrefin", .norm(sheets)))
    idx <- if (length(idx_g) > 0) idx_g[1] else which(grepl("empresasrefin", .norm(sheets)))[1]
  }
  if (length(idx) == 0 || is.na(idx)) stop("mid-era refining: no plant-list sheet matching '", sheet, "' in ", file)
  sheet <- sheets[idx[1]]
  raw <- as.data.frame(suppressMessages(
    readxl::read_excel(file, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  is_header <- apply(raw, 1, function(r) {
    v <- toupper(trimws(as.character(r)))
    any(grepl("EMPRESA", v), na.rm = TRUE) && any(v == "UF", na.rm = TRUE)
  })
  hdr <- which(is_header)[1]
  if (is.na(hdr)) stop("mid-era refining: header row not found in ", file)
  h  <- trimws(as.character(raw[hdr, ]))
  HU <- toupper(h)
  get_col <- function(pat) {
    i <- which(grepl(pat, HU)); if (length(i) == 0) NA_integer_ else i[1]
  }
  emp <- get_col("EMPRESA")
  mun <- get_col("LOCALI|MUNIC")
  uf  <- which(HU == "UF")[1]
  ole <- get_col("ÓLEO|OLEO")   # "Óleos Refinados" text column
  sit <- get_col("SITUA")
  if (any(is.na(c(emp, mun, uf, ole, sit))))
    stop("mid-era refining: missing cols in ", file,
         " (emp=", emp, " mun=", mun, " uf=", uf, " ole=", ole, " sit=", sit, ")")
  body <- raw[(hdr + 1):nrow(raw), , drop = FALSE]
  df <- data.frame(
    company      = as.character(body[[emp]]),
    municipality = as.character(body[[mun]]),
    UF           = as.character(body[[uf]]),
    oleos        = as.character(body[[ole]]),
    status       = as.character(body[[sit]]),
    stringsAsFactors = FALSE
  )
  df %>%
    filter(!is.na(company), !is.na(municipality), !is.na(UF),
           nchar(trimws(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(oleos)) == "SOJA") %>%
    filter(soy_flag, toupper(trimws(status)) == "ATIVA") %>%
    dplyr::select(company, municipality, UF, status)
}

# new/multi era (2019+): 5.Unidades de Refino e Envase, Soja flag column
.parse_refining_new <- function(file, sheet, status_col) {
  raw <- as.data.frame(suppressMessages(
    readxl::read_excel(file, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  is_header <- apply(raw, 1, function(r) {
    v <- toupper(trimws(as.character(r)))
    any(grepl("EMPRESA", v), na.rm = TRUE) && any(grepl("MUNIC", v), na.rm = TRUE)
  })
  hdr <- which(is_header)[1]
  if (is.na(hdr)) stop("new-era refining: header row not found in ", file)
  h  <- trimws(as.character(raw[hdr, ]))
  HU <- toupper(h)
  emp <- which(grepl("EMPRESA", HU))[1]
  mun <- which(grepl("MUNIC|LOCALI", HU))[1]
  uf  <- which(HU == "UF")[1]
  soj <- which(HU == "SOJA")[1]
  stc <- which(h == status_col | trimws(h) == as.character(status_col))[1]
  if (is.na(stc)) {
    stc <- which(suppressWarnings(as.numeric(h)) == as.numeric(status_col))[1]
  }
  if (any(is.na(c(emp, mun, uf, soj, stc))))
    stop("new-era refining: missing cols in ", file,
         " (emp=", emp, " mun=", mun, " uf=", uf, " soja=", soj, " stc=", stc, ")")
  body <- raw[(hdr + 1):nrow(raw), , drop = FALSE]
  df <- data.frame(
    company      = as.character(body[[emp]]),
    municipality = as.character(body[[mun]]),
    UF           = as.character(body[[uf]]),
    soja_flag    = as.character(body[[soj]]),
    status       = as.character(body[[stc]]),
    stringsAsFactors = FALSE
  )
  df %>%
    filter(!is.na(company), !is.na(municipality), !is.na(UF),
           nchar(trimws(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(soja_flag)) == "X") %>%
    filter(soy_flag, toupper(trimws(status)) == "ATIVA") %>%
    dplyr::select(company, municipality, UF, status)
}

.abiove_refining_list <- function(year) {
  res <- .resolve_refining_entry(year)
  entry <- res$entry; eff <- res$effective_year
  if (eff != year) {
    cat("  [NOTE] Refining list: no file for", year, "— using", eff,
        "(lower-bound fallback)\n")
  }
  file <- file.path(.PLANT_PATH, entry$file)
  if (!file.exists(file)) stop("Refining-list file not found: ", file)
  out <- switch(entry$era,
    "early" = .parse_refining_early(file, entry$sheet),
    "mid"   = .parse_refining_mid(file, entry$sheet),
    "new"   = .parse_refining_new(file, entry$sheet, entry$status_col),
    "multi" = .parse_refining_new(file, entry$sheet, entry$status_col),
    stop("Unknown refining era: ", entry$era)
  )
  cat("  Refining list: year =", year, "(file =", entry$file,
      "); active soy refining plants =", nrow(out), "\n")
  out
}

# Build REF_MUN_raw with equal-per-state allocation for both ref_cap and bot_cap
.ref_state_cap <- .abiove_state_sector_cap(YEAR, sector = "Refino")
.bot_state_cap <- .abiove_state_sector_cap(YEAR, sector = "Envase")
.ref_plants    <- .abiove_refining_list(YEAR)

.ref_state_alloc <- .ref_plants %>%
  group_by(UF) %>%
  summarise(n_ref_plants = n(), .groups = "drop") %>%
  left_join(.ref_state_cap, by = c("UF" = "nm_state")) %>%
  rename(state_ref_cap_td = state_cap_td) %>%
  left_join(.bot_state_cap, by = c("UF" = "nm_state")) %>%
  rename(state_bot_cap_td = state_cap_td) %>%
  mutate(per_plant_ref_cap = ifelse(n_ref_plants > 0,
                                    state_ref_cap_td / n_ref_plants, 0),
         per_plant_bot_cap = ifelse(n_ref_plants > 0,
                                    state_bot_cap_td / n_ref_plants, 0))

.ref_plants_with_cap <- .ref_plants %>%
  left_join(.ref_state_alloc %>% dplyr::select(UF, per_plant_ref_cap, per_plant_bot_cap),
            by = "UF") %>%
  mutate(per_plant_ref_cap = ifelse(is.na(per_plant_ref_cap), 0, per_plant_ref_cap),
         per_plant_bot_cap = ifelse(is.na(per_plant_bot_cap), 0, per_plant_bot_cap))

REF_MUN_raw <- .ref_plants_with_cap %>%
  group_by(UF, municipality) %>%
  summarise(n_ref_plants = n(),
            ref_cap_td   = sum(per_plant_ref_cap),
            bot_cap_td   = sum(per_plant_bot_cap),
            .groups      = "drop") %>%
  mutate(year = YEAR)
cat("  Refining facilities:", nrow(REF_MUN_raw),
    "municípios, ref_cap national total",
    round(sum(REF_MUN_raw$ref_cap_td), 1), "t/day; bot_cap",
    round(sum(REF_MUN_raw$bot_cap_td), 1), "t/day\n")


# ── 1.5 Population estimates (IBGE) ──────────────────────────────────────────
# Available: 2000-2022, 2024-2025. Gap at 2023 (falls back to 2022 Census).
# Multiple formats: 2000-2021 = SIDRA CSV (skip=1);
#                   2022 = Census (semicolon CSV, CO_MUN column);
#                   2024-2025 = post-census estimates (semicolon CSV).
pop_info <- find_year_file(
  "data/raw/00/IBGE_population/Population_tabela6579_IBGE_{Y}.csv", YEAR)
if (pop_info$year %in% c(2022, 2024, 2025)) {
  pop_raw <- read.csv2(file = pop_info$file, header = TRUE, stringsAsFactors = FALSE)
  if ("CO_MUN" %in% names(pop_raw)) {
    POP_MUN <- data.frame(
      co_mun = as.numeric(pop_raw$CO_MUN),
      nm_mun_raw = pop_raw$NM_MUN,
      year = pop_info$year,
      variable = "População residente",
      population = as.numeric(pop_raw$POPULACAO),
      stringsAsFactors = FALSE)
  } else {
    POP_MUN <- read.csv(file = pop_info$file, header = TRUE, skip = 1,
                        encoding = "UTF-8", stringsAsFactors = FALSE)
    colnames(POP_MUN) <- c("co_mun", "nm_mun_raw", "year", "variable", "population")
  }
} else {
  POP_MUN <- read.csv(file = pop_info$file, header = TRUE, skip = 1,
                      encoding = "UTF-8", stringsAsFactors = FALSE)
  colnames(POP_MUN) <- c("co_mun", "nm_mun_raw", "year", "variable", "population")
}
cat("  Population from year:", pop_info$year, "\n")

# ── 1.6 Livestock headcounts (IBGE PPM, Table 3939) ─────────────────────────
# Available: 2000-2025 yearly. Semicolon CSV, skip=4.
# Contains: 10 animal types per municipality.
LSTOCK_MUN <- read.csv2(
  file = paste0("data/raw/00/IBGE_livestock/Livestock_", YEAR, "_tabela3939_IBGE.csv"),
  header = TRUE, skip = 4, encoding = "UTF-8", stringsAsFactors = FALSE)

# ── 1.7 Milked cows (IBGE, Table 94) ────────────────────────────────────────
# Available: 2000-2024 yearly. Used to compute dairy cattle share.
MILKCOWS_MUN <- read.csv2(
  file = paste0("data/raw/00/IBGE_milkcows/MilkCows_", YEAR, "_tabela94_IBGE.csv"),
  header = TRUE, skip = 3, encoding = "UTF-8", stringsAsFactors = FALSE)

# ── 1.8 Grain storage facilities (IBGE / CONAB) ─────────────────────────────
# Static: 2014 shapefile with individual warehouse locations and capacity (CAP_TON).
# Aggregated to municipality level below.
STORAGE_MUN <- st_read("data/raw/00/IBGE_storage/armazens_2014.shp", quiet = TRUE)

# ── 1.9 Per-capita soy oil acquisition (IBGE POF) ───────────────────────────
# Three editions: 2002-03, 2008-09, 2017-18. By state (27 values).
# Used to allocate national food use of soy oil to municipalities.
# Lower bound: e.g. for YEAR=2013, uses POF 2008 edition.
pof_info <- find_year_file(
  "data/raw/00/IBGE_POF/POF_soy_oil_{Y}_IBGE.csv", YEAR)
OIL_ACQ_raw <- read.csv(pof_info$file, stringsAsFactors = FALSE)

# Map full state names (e.g. "Rondônia") to 2-letter abbreviations ("RO")
# needed to match with MUN$nm_state used throughout the pipeline.
state_map <- data.frame(
  NM_STATE = c("Rondônia","Acre","Amazonas","Roraima","Pará","Amapá","Tocantins",
    "Maranhão","Piauí","Ceará","Rio Grande do Norte","Paraíba","Pernambuco",
    "Alagoas","Sergipe","Bahia","Minas Gerais","Espírito Santo","Rio de Janeiro",
    "São Paulo","Paraná","Santa Catarina","Rio Grande do Sul",
    "Mato Grosso do Sul","Mato Grosso","Goiás","Distrito Federal"),
  nm_state = c("RO","AC","AM","RR","PA","AP","TO","MA","PI","CE","RN","PB","PE",
    "AL","SE","BA","MG","ES","RJ","SP","PR","SC","RS","MS","MT","GO","DF"),
  stringsAsFactors = FALSE)
OIL_ACQ_STATE <- OIL_ACQ_raw %>%
  left_join(state_map, by = "NM_STATE") %>%
  rename(oil_acq_pc = SOY_OIL_KG_PERCAPITA) %>%
  dplyr::select(nm_state, oil_acq_pc)
cat("  POF soy oil from edition:", pof_info$year, "\n")

# ── 1.10 Biodiesel capacity (ANP) ───────────────────────────────────────────
# Available: 2008-2026 yearly (from yearbooks + panel data).
# Before 2008: Brazil had no significant biodiesel industry → set to zero.
# Two sheets: "capacity" (per-plant m³/day) and "materials" (soy % by region).
if (YEAR < 2008) {
  cat("  Biodiesel (ANP): year", YEAR,
      "< 2008, no biodiesel industry yet — setting to zero\n")
  DIESEL_CAP_MUN <- data.frame(Empresa = character(), nm_mun = character(),
                                nm_state = character(), diesel_cap = numeric(),
                                stringsAsFactors = FALSE)
  DIESEL_MAT_REG <- data.frame(X1 = numeric(0))
} else {
  diesel_info <- find_year_file(
    "data/raw/00/ANP_biodiesel/Biodiesel_capacity_{Y}_ANP.xlsx", YEAR)
  if (!file.exists(diesel_info$file)) {
    diesel_info <- find_year_file(
      "data/raw/00/ANP_biodiesel/Biodiesel_capacity_{Y}_ANP_original.xlsx", YEAR)
  }
  DIESEL_CAP_MUN <- openxlsx::read.xlsx(
    diesel_info$file, sheet = "capacity", startRow = 2, colNames = TRUE)

  # Materials sheet (soy feedstock % by region) may not exist in yearbook files.
  # If missing, fall back to 2013 original which has verified data.
  tryCatch({
    DIESEL_MAT_REG <- openxlsx::read.xlsx(
      diesel_info$file, sheet = "materials", startRow = 2, colNames = TRUE)
    if (ncol(DIESEL_MAT_REG) < 3 || is.null(DIESEL_MAT_REG[1, 2])) stop("no data")
  }, error = function(e) {
    cat("  [NOTE] Materials sheet not available for", diesel_info$year,
        "- using 2013 original\n")
    DIESEL_MAT_REG <<- openxlsx::read.xlsx(
      "data/raw/00/ANP_biodiesel/Biodiesel_capacity_2013_ANP_original.xlsx",
      sheet = "materials", startRow = 2, colNames = TRUE)
  })
  cat("  Biodiesel (ANP) from year:", diesel_info$year, "\n")
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: PREPARE, HARMONIZE AND FORMAT EACH DATASET
# ═══════════════════════════════════════════════════════════════════════════════

# ── 2.1 EXPORTS (COMEX) ─────────────────────────────────────────────────────
# Steps:
#   1. Filter for soy HS4 codes (1201=beans, 1507=oil, 2304=cake)
#   2. Convert kg → tonnes, aggregate monthly → annual
#   3. Fix COMEX state codes: SP(34→35), MS(52→50), GO(53→52), DF(54→53)
#   4. Redistribute "undeclared municipality" exports (co_mun=9999999)
#      proportionally to municipalities already exporting that product
#      to the same destination country
#   5. Generate aggregated version (summed across destination countries)
cat("  Processing exports...\n")

names(EXP_MUN) <- c("year", "month", "HS4", "co_destin", "nm_state_comex",
                     "co_mun_comex", "export_kg", "export_dol")
EXP_MUN_SOY <- filter(EXP_MUN, HS4 %in% c(1201, 1507, 2304))
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  mutate(export_kg = export_kg / 1000) %>%
  rename(export = export_kg)
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  group_by(HS4, co_destin, nm_state_comex, co_mun_comex) %>%
  summarise(export = sum(export, na.rm = TRUE),
            export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>%
  ungroup()
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  mutate(product = ifelse(HS4 == 1201, "soybean",
                   ifelse(HS4 == 1507, "soy_oil", "soy_cake"))) %>%
  relocate(product, .after = HS4)

# Add municipality names from COMEX lookup
colnames(COMEX_MUN) <- c("co_mun_comex", "nm_mun_comex",
                         "nm_mun_min_comex", "nm_state_comex")
COMEX_MUN$nm_mun_comex <- toupper(COMEX_MUN$nm_mun_min_comex)
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  left_join(COMEX_MUN[, 1:2], by = "co_mun_comex")
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  relocate(co_mun_comex, .before = HS4) %>%
  relocate(nm_mun_comex, .before = HS4) %>%
  relocate(nm_state_comex, .before = HS4)

# Add destination country ISO3 codes
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  left_join(PAIS[, c(1, 3)], by = c("co_destin" = "CO_PAIS")) %>%
  rename("nm_destin" = "CO_PAIS_ISOA3") %>%
  relocate(nm_destin, .after = co_destin)

# Correct COMEX municipality codes to IBGE standard
# COMEX uses different state prefixes for SP, MS, GO, DF
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  mutate(co_mun_corr = ifelse(nm_state_comex == "SP", co_mun_comex + 100000,
    ifelse(nm_state_comex == "MS", co_mun_comex - 200000,
      ifelse(nm_state_comex %in% c("GO", "DF"), co_mun_comex - 100000,
             co_mun_comex)))) %>%
  relocate(co_mun_corr, .after = co_mun_comex)

# Match corrected codes with IBGE municipality master
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  left_join(MUN, by = c("co_mun_corr" = "co_mun")) %>%
  relocate(nm_mun, .after = nm_mun_comex) %>%
  relocate(nm_state, .after = nm_state_comex) %>%
  relocate(co_state, .before = nm_state_comex) %>%
  arrange(co_mun_corr)
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  dplyr::select(-c(co_mun_comex, nm_mun, nm_state)) %>%
  rename(co_mun = co_mun_corr, nm_mun = nm_mun_comex, nm_state = nm_state_comex)

# Redistribute "undeclared municipality" exports
# Some exports are reported with co_mun=9999999 (municipality not declared).
# We distribute these proportionally to municipalities that DO export the
# same product to the same destination country.
EXP_MUN_SOY_ND <- filter(EXP_MUN_SOY, co_mun == 9999999) %>%
  rename("export_ND" = "export", "export_dol_ND" = "export_dol")
EXP_MUN_SOY <- filter(EXP_MUN_SOY, co_mun != 9999999)
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  group_by(product, nm_destin) %>%
  mutate(
    destin_share = ifelse(sum(export) > 0, export / sum(export), 0),
    destin_share_dol = ifelse(sum(export_dol) > 0, export_dol / sum(export_dol), 0)
  ) %>% ungroup()
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  left_join(EXP_MUN_SOY_ND[, 6:10],
            by = c("product", "nm_destin", "co_destin")) %>%
  replace_na(list(export_ND = 0, export_dol_ND = 0))
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  mutate(export = export + destin_share * export_ND,
         export_dol = export_dol + destin_share * export_dol_ND)
EXP_MUN_SOY <- EXP_MUN_SOY %>%
  dplyr::select(!c(destin_share:export_dol_ND))

# Aggregate: sum across destination countries → one row per MU × product
EXP_MUN_SOY_agg <- EXP_MUN_SOY %>%
  group_by(co_mun, nm_mun, co_state, nm_state, HS4, product) %>%
  summarise(export = sum(export, na.rm = TRUE),
            export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>%
  ungroup()

# Split into lists by product for later merging
EXP_MUN_list <- list(
  "soybean"  = filter(EXP_MUN_SOY, product == "soybean"),
  "soy_oil"  = filter(EXP_MUN_SOY, product == "soy_oil"),
  "soy_cake" = filter(EXP_MUN_SOY, product == "soy_cake"),
  "total"    = EXP_MUN_SOY %>%
    group_by(across(c(-product, -HS4, -export, -export_dol))) %>%
    summarise(export = sum(export, na.rm = TRUE),
              export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>%
    ungroup())

EXP_MUN_agg_list <- list(
  "soybean"  = filter(EXP_MUN_SOY_agg, product == "soybean"),
  "soy_oil"  = filter(EXP_MUN_SOY_agg, product == "soy_oil"),
  "soy_cake" = filter(EXP_MUN_SOY_agg, product == "soy_cake"),
  "total"    = EXP_MUN_SOY_agg %>%
    group_by(across(c(-product, -HS4, -export, -export_dol))) %>%
    summarise(export = sum(export, na.rm = TRUE),
              export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>%
    ungroup())

cat("  Exports:", round(sum(EXP_MUN_SOY$export)), "tonnes\n")


# ── 2.2 IMPORTS (COMEX) ─────────────────────────────────────────────────────
# Same processing as exports: filter soy, convert kg→t, aggregate, fix codes.
# No redistribution of undeclared imports (they're negligible).
cat("  Processing imports...\n")

names(IMP_MUN) <- c("year", "month", "HS4", "co_origin", "nm_state_comex",
                     "co_mun_comex", "import_kg", "import_dol")
IMP_MUN_SOY <- filter(IMP_MUN, HS4 %in% c(1201, 1507, 2304))
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  mutate(import_kg = import_kg / 1000) %>% rename(import = import_kg)
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  group_by(HS4, co_origin, nm_state_comex, co_mun_comex) %>%
  summarise(import = sum(import, na.rm = TRUE),
            import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>%
  ungroup()
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  mutate(product = ifelse(HS4 == 1201, "soybean",
                   ifelse(HS4 == 1507, "soy_oil", "soy_cake"))) %>%
  relocate(product, .after = HS4)
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  left_join(COMEX_MUN[, 1:2], by = "co_mun_comex")
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  relocate(co_mun_comex, .before = HS4) %>%
  relocate(nm_mun_comex, .before = HS4) %>%
  relocate(nm_state_comex, .before = HS4)
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  left_join(PAIS[, c(1, 3)], by = c("co_origin" = "CO_PAIS")) %>%
  rename("nm_origin" = "CO_PAIS_ISOA3") %>%
  relocate(nm_origin, .after = co_origin)
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  mutate(co_mun_corr = ifelse(nm_state_comex == "SP", co_mun_comex + 100000,
    ifelse(nm_state_comex == "MS", co_mun_comex - 200000,
      ifelse(nm_state_comex %in% c("GO", "DF"), co_mun_comex - 100000,
             co_mun_comex)))) %>%
  relocate(co_mun_corr, .after = co_mun_comex)
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  left_join(MUN, by = c("co_mun_corr" = "co_mun")) %>%
  relocate(nm_mun, .after = nm_mun_comex) %>%
  relocate(nm_state, .after = nm_state_comex) %>%
  relocate(co_state, .before = nm_state_comex) %>%
  arrange(co_mun_corr)
IMP_MUN_SOY <- IMP_MUN_SOY %>%
  dplyr::select(-c(co_mun_comex, nm_mun, nm_state)) %>%
  rename(co_mun = co_mun_corr, nm_mun = nm_mun_comex, nm_state = nm_state_comex)

IMP_MUN_SOY_agg <- IMP_MUN_SOY %>%
  group_by(co_mun, nm_mun, co_state, nm_state, HS4, product) %>%
  summarise(import = sum(import, na.rm = TRUE),
            import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>%
  ungroup()

IMP_MUN_agg_list <- list(
  "soybean"  = filter(IMP_MUN_SOY_agg, product == "soybean"),
  "soy_oil"  = filter(IMP_MUN_SOY_agg, product == "soy_oil"),
  "soy_cake" = filter(IMP_MUN_SOY_agg, product == "soy_cake"),
  "total"    = IMP_MUN_SOY_agg %>%
    group_by(across(c(-product, -HS4, -import, -import_dol))) %>%
    summarise(import = sum(import, na.rm = TRUE),
              import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>%
    ungroup())

cat("  Imports:", round(sum(IMP_MUN_SOY$import)), "tonnes\n")


# ── 2.3 PRODUCTION (IBGE PAM) ───────────────────────────────────────────────
# Clean column names, convert to numeric, filter for target year, match codes.
cat("  Processing production...\n")

colnames(PROD_MUN) <- c("co_mun", "nm_mun_raw", "product", "year",
                         "area_plant", "area_harv", "prod")
PROD_MUN <- PROD_MUN[!is.na(PROD_MUN$co_mun) & PROD_MUN$co_mun != "", ]
PROD_MUN[, c(1, 4:7)] <- apply(PROD_MUN[, c(1, 4:7)], 2,
  function(x) as.numeric(gsub("[^0-9.-]", "", x)))
PROD_MUN <- filter(PROD_MUN, year == prod_info$year)
PROD_MUN <- PROD_MUN %>% left_join(MUN[, 1:2], by = "co_mun")
PROD_MUN$nm_mun_raw <- gsub(" - [A-Z]{2}$", "", PROD_MUN$nm_mun_raw) %>% toupper()
PROD_MUN <- PROD_MUN %>% dplyr::select(-nm_mun_raw)
cat("  Production:", sum(PROD_MUN$prod, na.rm = TRUE), "tonnes from",
    nrow(PROD_MUN), "municipalities\n")


# ── 2.4 PROCESSING FACILITIES (ABIOVE) ──────────────────────────────────────
# Match municipality names from the longitudinal CSV to IBGE co_mun codes.
# Some names need manual correction (spelling differences ABIOVE vs IBGE).

name_fixes <- c(
  "OSWALDO CRUZ"     = "OSVALDO CRUZ",
  "CARIRI"           = "CARIRI DO TOCANTINS",
  "CARAPÓ"           = "CAARAPÓ"
)

PROC_MUN_raw <- PROC_MUN_raw %>% mutate(nm_mun_upper = toupper(municipality))
for (wrong in names(name_fixes)) {
  PROC_MUN_raw$nm_mun_upper[PROC_MUN_raw$nm_mun_upper == wrong] <- name_fixes[wrong]
}

PROC_MUN <- PROC_MUN_raw %>%
  left_join(MUN[, c("co_mun", "nm_mun", "nm_state")],
            by = c("nm_mun_upper" = "nm_mun", "UF" = "nm_state")) %>%
  dplyr::select(co_mun, nm_mun_upper, UF, n_plants, capacity_td) %>%
  rename(nm_mun = nm_mun_upper, nm_state = UF,
         proc_fac = n_plants, proc_cap = capacity_td) %>%
  filter(!is.na(co_mun))

# Refining + bottling: match refining municípios to IBGE co_mun codes (same logic
# as processing), apply the same name_fixes, then full_join into PROC_MUN so that
# municípios that only refine (not crush) still appear.
REF_MUN_raw <- REF_MUN_raw %>% mutate(nm_mun_upper = toupper(municipality))
for (wrong in names(name_fixes)) {
  REF_MUN_raw$nm_mun_upper[REF_MUN_raw$nm_mun_upper == wrong] <- name_fixes[wrong]
}
REF_MUN <- REF_MUN_raw %>%
  left_join(MUN[, c("co_mun", "nm_mun", "nm_state")],
            by = c("nm_mun_upper" = "nm_mun", "UF" = "nm_state")) %>%
  dplyr::select(co_mun, nm_mun_upper, UF, n_ref_plants, ref_cap_td, bot_cap_td) %>%
  rename(nm_mun = nm_mun_upper, nm_state = UF,
         ref_fac = n_ref_plants, ref_cap = ref_cap_td, bot_cap = bot_cap_td) %>%
  filter(!is.na(co_mun))

PROC_MUN <- PROC_MUN %>%
  full_join(REF_MUN %>% dplyr::select(co_mun, ref_fac, ref_cap, bot_cap),
            by = "co_mun") %>%
  mutate(ref_fac = ifelse(is.na(ref_fac), 0, ref_fac),
         ref_cap = ifelse(is.na(ref_cap), 0, ref_cap),
         bot_cap = ifelse(is.na(bot_cap), 0, bot_cap),
         # for new refining-only municípios, nm_mun/nm_state/proc_* may be NA
         proc_fac = ifelse(is.na(proc_fac), 0, proc_fac),
         proc_cap = ifelse(is.na(proc_cap), 0, proc_cap))
# If any refining município wasn't already in PROC_MUN, fill in nm_mun / nm_state
# from the MUN master table.
missing_names <- is.na(PROC_MUN$nm_mun)
if (any(missing_names)) {
  fill <- MUN %>% dplyr::select(co_mun, nm_mun_fill = nm_mun, nm_state_fill = nm_state)
  PROC_MUN <- PROC_MUN %>%
    left_join(fill, by = "co_mun") %>%
    mutate(nm_mun   = ifelse(is.na(nm_mun),   nm_mun_fill,   nm_mun),
           nm_state = ifelse(is.na(nm_state), nm_state_fill, nm_state)) %>%
    dplyr::select(-nm_mun_fill, -nm_state_fill)
}

cat("  Processing:", nrow(PROC_MUN), "municipalities;",
    "proc_cap", round(sum(PROC_MUN$proc_cap, na.rm = TRUE), 1), "t/d;",
    "ref_cap", round(sum(PROC_MUN$ref_cap, na.rm = TRUE), 1), "t/d;",
    "bot_cap", round(sum(PROC_MUN$bot_cap, na.rm = TRUE), 1), "t/d\n")


# ── 2.5 POPULATION (IBGE) ───────────────────────────────────────────────────
cat("  Processing population...\n")

if (!"co_mun" %in% names(POP_MUN))
  colnames(POP_MUN) <- c("co_mun", "nm_mun_raw", "year", "variable", "population")
POP_MUN <- POP_MUN[!is.na(POP_MUN$co_mun) & POP_MUN$co_mun != "", ]
POP_MUN[, c(1, 3, 5)] <- apply(POP_MUN[, c(1, 3, 5)], 2,
  function(x) as.numeric(gsub("[^0-9.-]", "", x)))
POP_MUN <- POP_MUN[!is.na(POP_MUN$population), ]
POP_MUN <- POP_MUN %>% left_join(MUN[, 1:2], by = "co_mun")
if ("nm_mun_raw" %in% names(POP_MUN)) {
  POP_MUN$nm_mun_raw <- gsub(" \\([A-Z]{2}\\)$| - [A-Z]{2}$", "",
                              POP_MUN$nm_mun_raw) %>% toupper()
  POP_MUN <- POP_MUN %>% dplyr::select(-nm_mun_raw)
}
cat("  Population:", sum(POP_MUN$population, na.rm = TRUE), "\n")


# ── 2.6 LIVESTOCK (IBGE PPM) ────────────────────────────────────────────────
# Filter for municipality-level rows (marked "MU" in col 1),
# rename animal types to English, merge with milked cows.
cat("  Processing livestock...\n")

LSTOCK_MUN <- LSTOCK_MUN[LSTOCK_MUN[, 1] == "MU", 2:ncol(LSTOCK_MUN)]
colnames(LSTOCK_MUN) <- c("co_mun", "nm_mun_raw",
  "cattle", "buffalo", "horse", "pig", "pig_mother",
  "goat", "sheep", "chicken", "chicken_layer", "quail")
LSTOCK_MUN[, c(1, 3:12)] <- apply(LSTOCK_MUN[, c(1, 3:12)], 2,
  function(x) as.numeric(gsub("[^0-9.-]", "", x)))

MILKCOWS_MUN <- MILKCOWS_MUN[MILKCOWS_MUN[, 1] == "MU", 2:ncol(MILKCOWS_MUN)]
colnames(MILKCOWS_MUN) <- c("co_mun", "nm_mun_raw", "cattle_milked")
MILKCOWS_MUN[, c(1, 3)] <- apply(MILKCOWS_MUN[, c(1, 3)], 2,
  function(x) as.numeric(gsub("[^0-9.-]", "", x)))

LSTOCK_MUN <- LSTOCK_MUN %>% full_join(MILKCOWS_MUN, by = "co_mun")
if ("nm_mun_raw.x" %in% names(LSTOCK_MUN)) {
  LSTOCK_MUN <- LSTOCK_MUN %>%
    dplyr::select(!nm_mun_raw.x) %>%
    rename("nm_mun_raw" = "nm_mun_raw.y")
}
LSTOCK_MUN <- LSTOCK_MUN %>%
  relocate(nm_mun_raw, .after = co_mun) %>%
  relocate(cattle_milked, .after = cattle)
LSTOCK_MUN <- LSTOCK_MUN %>% left_join(MUN[, 1:2], by = "co_mun")
LSTOCK_MUN$nm_mun_raw <- gsub(" \\([A-Z]{2}\\)$| - [A-Z]{2}$", "",
                               LSTOCK_MUN$nm_mun_raw) %>% toupper()
LSTOCK_MUN <- LSTOCK_MUN %>% dplyr::select(-nm_mun_raw)
cat("  Cattle:", sum(LSTOCK_MUN$cattle, na.rm = TRUE), "\n")


# ── 2.7 GRAIN STORAGE (IBGE) ────────────────────────────────────────────────
# Aggregate individual warehouse capacities (CAP_TON) to municipality level.
all(unique(STORAGE_MUN$GEOCODIGO %in% MUN$co_mun))
STORAGE_MUN <- STORAGE_MUN %>%
  as.data.frame %>%
  group_by(MUNICIPIO, GEOCODIGO) %>%
  summarise("storage_cap" = sum(CAP_TON, na.rm = TRUE), .groups = "drop") %>%
  rename("co_mun" = "GEOCODIGO")


# ── 2.8 SOY OIL ACQUISITION (POF) ───────────────────────────────────────────
# Already loaded and formatted in Section 1.9 (OIL_ACQ_STATE).


# ── 2.9 BIODIESEL (ANP) ─────────────────────────────────────────────────────
# Convert per-plant biodiesel capacity to soy-specific biodiesel capacity
# by applying regional soy feedstock shares.
if (nrow(DIESEL_CAP_MUN) > 0) {
  # Standardize column names (encoding differs across ANP file versions)
  diesel_names <- names(DIESEL_CAP_MUN)
  names(DIESEL_CAP_MUN)[grep("Munic", diesel_names)] <- "Municipio"
  names(DIESEL_CAP_MUN)[grep("Capacidade", diesel_names)] <- "diesel_cap"
  names(DIESEL_CAP_MUN)[grep("Empresa", diesel_names)] <- "Empresa"

  # Handle yearbook format where municipality+UF are combined: "City/UF" or "City (UF)"
  if (all(is.na(DIESEL_CAP_MUN$UF)) || !"UF" %in% names(DIESEL_CAP_MUN)) {
    DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>%
      mutate(nm_state = gsub(".*[/\\(]([A-Z]{2}).*", "\\1", Municipio),
             Municipio = gsub("[/\\(][A-Z]{2}[\\)]?$", "", Municipio) %>% trimws())
  } else {
    DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>% rename(nm_state = UF)
  }
  DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>%
    mutate(Municipio = toupper(Municipio), nm_state = as.character(nm_state)) %>%
    rename(nm_mun = Municipio) %>%
    dplyr::select(c(Empresa, nm_mun, nm_state, diesel_cap))

  # Fix known municipality name mismatches
  mismatches <- which(!DIESEL_CAP_MUN$nm_mun %in% MUN$nm_mun)
  if (length(mismatches) > 0) {
    fixes <- c("BARRA DO BUGRES", "COLÍDER")
    DIESEL_CAP_MUN$nm_mun[mismatches] <-
      fixes[1:min(length(fixes), length(mismatches))]
  }

  # Match to IBGE codes and extract macro-region (first digit of co_mun)
  DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>%
    left_join(MUN[, 1:4], by = c("nm_mun", "nm_state")) %>%
    mutate(co_reg = substr(as.character(co_mun), 1, 1)) %>%
    relocate(co_mun:co_reg, .after = nm_mun)
  DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>%
    group_by(across(nm_mun:nm_state)) %>%
    summarise(diesel_cap = sum(diesel_cap), .groups = "drop")

  # Apply regional soy feedstock share to get soy-specific biodiesel capacity
  # Regions: 1=Norte, 2=Nordeste, 3=Sudeste, 4=Sul, 5=Centro-Oeste
  regions <- data.frame(
    co_reg = 1:5,
    nm_reg = c("Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste"))
  mat_names <- names(DIESEL_MAT_REG)
  names(DIESEL_MAT_REG) <- ifelse(
    mat_names %in% regions$nm_reg,
    as.character(regions$co_reg[match(mat_names, regions$nm_reg)]),
    mat_names)
  soy_row <- DIESEL_MAT_REG[1, ]
  soy_share_vec <- setNames(
    as.numeric(unlist(soy_row[, as.character(1:5)])), as.character(1:5))
  DIESEL_CAP_MUN <- mutate(DIESEL_CAP_MUN, soy_share = soy_share_vec[co_reg])
  DIESEL_CAP_MUN <- mutate(DIESEL_CAP_MUN, diesel_cap_soy = diesel_cap * soy_share)
} else {
  # Pre-2008: empty table
  DIESEL_CAP_MUN <- data.frame(co_mun = integer(), diesel_cap_soy = numeric())
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: MERGE ALL INTO ONE COMPREHENSIVE TABLE (SOY_MUN)
# ═══════════════════════════════════════════════════════════════════════════════
# Start from the municipality master list and left-join each dataset.
# After merging, all NAs are replaced by zero.

cat("  Merging all data...\n")

# Start with municipalities + production
SOY_MUN <- left_join(MUN, PROD_MUN[, c("co_mun", "area_plant", "area_harv", "prod")],
                     by = "co_mun") %>%
  rename(prod_bean = prod)

# Add export data (bean, oil, cake separately)
SOY_MUN <- SOY_MUN %>%
  full_join(EXP_MUN_agg_list$soybean[, c(1, 7:8)], by = "co_mun") %>%
  rename(exp_bean = export, exp_bean_d = export_dol)
SOY_MUN <- SOY_MUN %>%
  left_join(EXP_MUN_agg_list$soy_oil[, c(1, 7:8)], by = "co_mun") %>%
  rename(exp_oil = export, exp_oil_d = export_dol)
SOY_MUN <- SOY_MUN %>%
  left_join(EXP_MUN_agg_list$soy_cake[, c(1, 7:8)], by = "co_mun") %>%
  rename(exp_cake = export, exp_cake_d = export_dol)

# Add import data
SOY_MUN <- SOY_MUN %>%
  left_join(IMP_MUN_agg_list$soybean[, c(1, 7:8)], by = "co_mun") %>%
  rename(imp_bean = import, imp_bean_d = import_dol)
SOY_MUN <- SOY_MUN %>%
  left_join(IMP_MUN_agg_list$soy_oil[, c(1, 7:8)], by = "co_mun") %>%
  rename(imp_oil = import, imp_oil_d = import_dol)
SOY_MUN <- SOY_MUN %>%
  left_join(IMP_MUN_agg_list$soy_cake[, c(1, 7:8)], by = "co_mun") %>%
  rename(imp_cake = import, imp_cake_d = import_dol)

# Add processing/refining capacity
SOY_MUN <- SOY_MUN %>%
  left_join(PROC_MUN[, c("co_mun", "proc_fac", "proc_cap",
                          "ref_fac", "ref_cap", "bot_cap")], by = "co_mun")

# Add population & livestock
SOY_MUN <- SOY_MUN %>%
  left_join(POP_MUN[, c("co_mun", "population")], by = "co_mun")
lstock_cols <- c("co_mun", "cattle", "cattle_milked", "buffalo", "horse",
                 "pig", "pig_mother", "goat", "sheep", "chicken",
                 "chicken_layer", "quail")
lstock_cols <- lstock_cols[lstock_cols %in% names(LSTOCK_MUN)]
SOY_MUN <- SOY_MUN %>% left_join(LSTOCK_MUN[, lstock_cols], by = "co_mun")

# Add grain storage capacity
SOY_MUN <- SOY_MUN %>% left_join(STORAGE_MUN[, 2:3], by = "co_mun")

# Add per-capita soy oil acquisition (state-level, joined by nm_state)
SOY_MUN <- SOY_MUN %>% left_join(OIL_ACQ_STATE, by = "nm_state")

# Add soy-based biodiesel capacity
SOY_MUN <- SOY_MUN %>%
  left_join(DIESEL_CAP_MUN[, c("co_mun", "diesel_cap_soy")], by = "co_mun")

# Clean up any duplicate nm_mun columns from multiple joins
dup_cols <- grep("^nm_mun\\.", names(SOY_MUN), value = TRUE)
if (length(dup_cols) > 0)
  SOY_MUN <- SOY_MUN %>% dplyr::select(-all_of(dup_cols))

# Replace all NAs with zero
SOY_MUN[is.na(SOY_MUN)] <- 0

cat("  SOY_MUN:", nrow(SOY_MUN), "municipalities,", ncol(SOY_MUN), "variables\n")
cat("  Production:", sum(SOY_MUN$prod_bean), "tonnes\n")
cat("  Processing:", sum(SOY_MUN$proc_cap), "t/day\n")


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: SPATIAL DATA — POLYGONS, CENTROIDS, DISTANCE MATRICES
# ═══════════════════════════════════════════════════════════════════════════════

# ── 4.1 Municipality boundaries (from geobr) ────────────────────────────────
# Load the boundary file for the nearest available year, rename columns
# from geobr format (code_muni, name_muni) to pipeline format (co_mun, nm_mun),
# merge with SOY_MUN, and project to SIRGAS 2000 Brazil Polyconic (EPSG:5880).

bnd_info <- find_year_file(
  "data/raw/00/IBGE_boundaries/municipios_{Y}.gpkg", YEAR)
GEO_MUN <- st_read(bnd_info$file, stringsAsFactors = FALSE, quiet = TRUE)
GEO_MUN <- GEO_MUN %>% rename(co_mun = code_muni, nm_mun = name_muni)
GEO_MUN$co_mun <- as.numeric(GEO_MUN$co_mun)
GEO_MUN$nm_mun <- toupper(GEO_MUN$nm_mun)

GEO_MUN_SOY <- left_join(GEO_MUN, SOY_MUN, by = "co_mun")
if ("nm_mun.x" %in% names(GEO_MUN_SOY) && "nm_mun.y" %in% names(GEO_MUN_SOY)) {
  GEO_MUN_SOY <- GEO_MUN_SOY %>%
    dplyr::select(-nm_mun.y) %>%
    rename("nm_mun" = "nm_mun.x")
}
GEO_MUN_SOY <- st_transform(GEO_MUN_SOY, 5880)

# Compute a representative point inside each municipality (not centroid,
# which may fall outside concave polygons)
MUN_center <- st_point_on_surface(GEO_MUN_SOY)

# Euclidean distance matrix between all municipality centers
MUN_center_dist <- st_distance(MUN_center)
dimnames(MUN_center_dist) <- list(GEO_MUN_SOY$co_mun, GEO_MUN_SOY$co_mun)

# Dissolved Brazil boundary (for GEE downloads and clipping)
GEO_BRA <- summarise(GEO_MUN_SOY)
GEO_BRA_EXT <- st_as_sfc(st_bbox(GEO_MUN_SOY))


# ── 4.2 Municipality capitals ───────────────────────────────────────────────
# Capital = "sede municipal" = the city seat of each municipality.
# Used for capital-to-capital distance matrix (alternative to centroid-based).
# Source: IBGE Localities 2010 shapefile (CD_NIVEL=1 = capital).

MUN_localities <- st_read(
  "data/raw/00/IBGE_localities/BR_Localidades_2010_v1.shx",
  stringsAsFactors = FALSE, quiet = TRUE)
MUN_capitals <- MUN_localities %>%
  filter(CD_NIVEL == 1) %>%
  dplyr::select(c(CD_GEOCODM, NM_MUNICIP, LONG, LAT)) %>%
  rename("co_mun" = "CD_GEOCODM", "nm_mun" = "NM_MUNICIP") %>%
  mutate(co_mun = as.numeric(co_mun))

# 7 municipalities created after 2010 are missing from the 2010 shapefile.
# Add them manually with coordinates from Google Maps.
Mojuidoscampos  <- c(1504752, "MOJUÍ DOS CAMPOS",    -54.640278, -2.684722)
PescariaBrava   <- c(4212650, "PESCARIA BRAVA",       -48.883333, -28.383333)
BalnearioRincao <- c(4220000, "BALNEÁRIO RINCÃO",     -49.236111, -28.834444)
LagoaMirim      <- c(4300001, "LAGOA MIRIM",          -52.899807, -32.697881)
LagoadosPatos   <- c(4300002, "LAGOA DOS PATOS",      -51.365753, -30.995042)
Paraisodasaguas <- c(5006275, "PARAÍSO DAS ÁGUAS",    -52.968333, -19.052222)
PintoBandeira   <- c(4314548, "PINTO BANDEIRA",       -51.450278, -29.097778)

MUN_capitals_missing <- data.frame(rbind(
  Mojuidoscampos, PescariaBrava, BalnearioRincao,
  LagoaMirim, LagoadosPatos, Paraisodasaguas, PintoBandeira))
names(MUN_capitals_missing) <- names(MUN_capitals)[1:4]
MUN_capitals_missing[, c(1, 3:4)] <- apply(
  MUN_capitals_missing[, c(1, 3:4)], 2, function(x) as.numeric(as.character(x)))
MUN_capitals_missing <- st_as_sf(
  MUN_capitals_missing, coords = c("LONG", "LAT"), remove = FALSE, crs = 4326)
MUN_capitals_missing <- st_transform(
  MUN_capitals_missing, st_crs(MUN_capitals))
MUN_capitals <- rbind(MUN_capitals, MUN_capitals_missing)
MUN_capitals <- MUN_capitals[order(MUN_capitals$co_mun), ]

# Replace raw names with standardized names from SOY_MUN
MUN_capitals <- left_join(MUN_capitals[, c(1, 3:5)], SOY_MUN[, 1:2],
                          by = "co_mun") %>%
  relocate(nm_mun, .after = co_mun) %>%
  arrange(co_mun)
MUN_capitals <- st_transform(MUN_capitals, crs = st_crs(GEO_MUN_SOY))

# Capital-to-capital distance matrix
MUN_capital_dist <- st_distance(MUN_capitals)
dimnames(MUN_capital_dist) <- list(MUN_capitals$co_mun, MUN_capitals$co_mun)


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: EXPORT RESULTS
# ═══════════════════════════════════════════════════════════════════════════════

if (write) {
  # Tables
  saveRDS(SOY_MUN,     file = paste0(OUT, "SOY_MUN_00.rds"))
  write.csv2(SOY_MUN,  file = paste0(OUT, "SOY_MUN.csv"))
  saveRDS(EXP_MUN_SOY, file = paste0(OUT, "EXP_MUN_SOY_00.rds"))
  saveRDS(IMP_MUN_SOY, file = paste0(OUT, "IMP_MUN_SOY_00.rds"))

  # Spatial: polygons with all attributes
  st_write(GEO_MUN_SOY, paste0(OUT, "GEO_MUN_SOY.gpkg"),
           driver = "GPKG", delete_dsn = TRUE, quiet = TRUE)
  saveRDS(GEO_MUN_SOY, file = paste0(OUT, "GEO_MUN_SOY_00.rds"))

  # Brazil boundary
  st_write(GEO_BRA,     paste0(OUT, "GEO_BRA.shp"), append = FALSE, quiet = TRUE)
  st_write(GEO_BRA_EXT, paste0(OUT, "GEO_BRA_EXT.shp"), append = FALSE, quiet = TRUE)

  # Capitals
  saveRDS(MUN_capitals, file = paste0(OUT, "MUN_capitals.rds"))
  st_write(MUN_capitals, paste0(OUT, "MUN_capitals.gpkg"),
           driver = "GPKG", delete_dsn = TRUE, quiet = TRUE)

  # Distance matrices
  saveRDS(MUN_center_dist,  file = paste0(OUT, "MUN_center_dist.rds"))
  saveRDS(MUN_capital_dist, file = paste0(OUT, "MUN_capital_dist.rds"))

  cat("  Saved to", OUT, "\n")
}

cat("\n============================================================\n")
cat("Script 00 COMPLETE for year", YEAR, "\n")
cat("============================================================\n")

rm(list = ls())
gc()


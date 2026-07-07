###############################################################################
# COMPARE PROCESSING-CAPACITY METHODS
###############################################################################
#
# OLD METHOD (Stefan Trsek 2022 thesis, 2013 only):
#   - Read Processing_facilities_2013_ABIOVE.xlsx sheet "processing_MUN"
#   - This sheet is pre-computed with equal-per-state allocation:
#       per-plant capacity_td = state_capacity_td / n_active_plants_in_state
#       then summed by município
#   - Single year: 2013
#
# NEW METHOD (this script, applied per year):
#   - Read ABIOVE_raw_capacity_2025.xlsx:
#       * sheet 2 "2.Evolução"              → state capacity t/day for ANY year
#                                              1989-2025 (continuous 2000-2020,
#                                              gaps at 1990-94, 96, 2021)
#       * sheet 3 "3.Unidades de Processamento" → plant list with status 2024+2025
#   - For each target year:
#       1. Filter plant list to plants that process soy AND are 'Ativa' that year
#       2. Read state capacity (Ativa column) for that year from sheet 2
#       3. For each state s: each active soy plant gets state_cap[s] / N_active[s]
#       4. Aggregate per município
#
# TEMPORAL NOTE:
#   Sheet 3 of the 2025 file only has status columns for 2024 and 2025.
#   Plants do change over time — a plant "Ativa" in 2024 may be "Parada" in 2025.
#   This script respects that: the plant roster is filtered per year.
#   For years <2024 the 2025 file cannot tell us which plants existed — this
#   script reports state-level only for those years (plant list = NA).
#
# OUTPUTS:
#   data/generated/outputs/00_comparison/compare_proc_cap_muni.csv    (município × method × year)
#   data/generated/outputs/00_comparison/compare_proc_cap_state.csv   (UF × method × year)
#   data/generated/outputs/00_comparison/compare_national_total.csv   (national × method × year)
###############################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(openxlsx)
  library(readr)
})

# Paths (project root)
ROOT <- "."
if (!file.exists(file.path(ROOT, "inputs"))) {
  # try walking up from this script's location
  ROOT <- ".."
  if (!file.exists(file.path(ROOT, "inputs"))) ROOT <- "../.."
  if (!file.exists(file.path(ROOT, "inputs"))) stop("Cannot locate project root.")
}
setwd(ROOT)
cat("Working dir:", getwd(), "\n\n")

OUT_DIR <- "data/generated/outputs/00_comparison"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ABIOVE_2025_FILE <- "data/raw/00/ABIOVE_processing/ABIOVE_raw_capacity_2025.xlsx"
STEFAN_FILE      <- "archive/data_stefan_2013/Processing_facilities_2013_ABIOVE.xlsx"


#===============================================================================
# OLD METHOD — Stefan's pre-computed 2013 output
#===============================================================================
cat("─── OLD (Stefan 2013) ───\n")

old_proc_mun <- openxlsx::read.xlsx(STEFAN_FILE, sheet = "processing_MUN",
                                    colNames = TRUE) %>%
  transmute(
    method    = "stefan_2013",
    year      = 2013,
    co_mun    = co_mun,
    nm_mun    = nm_mun,
    nm_state  = nm_state,
    n_plants  = proc_fac_act,
    proc_cap  = proc_cap_act
  )

cat("  Municípios:", nrow(old_proc_mun),
    " | National total proc_cap_td:", round(sum(old_proc_mun$proc_cap), 0),
    "\n\n")


#===============================================================================
# NEW METHOD — equal allocation from ABIOVE_raw_capacity_2025
#===============================================================================

# Decode sheet 2 column layout (Ativa/Parada/Total per year).
# Verified via Python: years 1989,1995,1997,1998,2000-2020,2022-2025;
# each year occupies 3 cols starting at base, with Part. in 4th col for 2022+.
YEAR_COL_MAP <- list(
  "1989"=3, "1995"=6, "1997"=9, "1998"=12,
  "2000"=15, "2001"=18, "2002"=21, "2003"=24, "2004"=27,
  "2005"=30, "2006"=33, "2007"=36, "2008"=39, "2009"=42,
  "2010"=45, "2011"=48, "2012"=51, "2013"=54, "2014"=57,
  "2015"=60, "2016"=63, "2017"=66, "2018"=69, "2019"=72,
  "2020"=75, "2022"=78, "2023"=82, "2024"=86, "2025"=90
)

get_state_capacity_td <- function(year) {
  # Returns data frame: nm_state, state_cap_td (Ativa only)
  if (!as.character(year) %in% names(YEAR_COL_MAP)) {
    stop(paste("Year", year, "not available in ABIOVE Evolução sheet."))
  }
  # YEAR_COL_MAP stores the Python 0-indexed column number for the Ativa col.
  # openxlsx drops Excel column A (leading blank), so the R 1-indexed column
  # number equals the Python 0-indexed number (no shift).
  ativa_r_col <- YEAR_COL_MAP[[as.character(year)]]
  ev <- openxlsx::read.xlsx(ABIOVE_2025_FILE, sheet = "2.Evolução",
                             colNames = FALSE, skipEmptyRows = FALSE)
  # Columns in R: X1 = state/region name, X2 = UF code, X3 onwards = year data.
  ativa_colname <- paste0("X", ativa_r_col)
  if (!ativa_colname %in% names(ev)) {
    stop(paste("Column", ativa_colname, "not found for year", year))
  }
  st <- ev[, c("X1", "X2", ativa_colname)]
  names(st) <- c("region_or_state", "UF", "state_cap_td")
  st$state_cap_td <- suppressWarnings(as.numeric(st$state_cap_td))
  # Keep only rows with a valid 2-letter UF (drops region rows + header rows)
  st <- st[!is.na(st$UF) & nchar(st$UF) == 2, ]
  st$state_cap_td[is.na(st$state_cap_td)] <- 0
  st <- st[, c("UF", "state_cap_td")]
  names(st) <- c("nm_state", "state_cap_td")
  # Dedupe in case the same UF appears in multiple rows (shouldn't, but safety)
  st <- st %>% group_by(nm_state) %>%
    summarise(state_cap_td = sum(state_cap_td), .groups = "drop")
  st
}

get_plant_list <- function(year) {
  # Returns data frame: company, nm_mun, nm_state, soy_flag, status
  # Only works for years where sheet 3 has a status column (2024, 2025).
  if (!year %in% c(2024, 2025)) return(NULL)
  pl <- openxlsx::read.xlsx(ABIOVE_2025_FILE,
                             sheet = "3.Unidades de Processamento",
                             startRow = 8, colNames = TRUE)
  # R drops the leading blank column A → 13 columns.
  # Rename positionally to avoid HTML-entity encoded accents in auto-names.
  stopifnot(ncol(pl) == 13)
  names(pl) <- c("Empresas","Municipio","UF","Regiao","st_2025","st_2024",
                 "Processo","Soja","Algodao","Girassol","Canola","Amendoim","Mamona")
  pl <- pl %>%
    mutate(status = if (year == 2024) st_2024 else st_2025) %>%
    filter(!is.na(Empresas), !is.na(Municipio), !is.na(UF)) %>%
    mutate(soy_flag = toupper(trimws(as.character(Soja))) == "X") %>%
    dplyr::select(company = Empresas,
                  nm_mun  = Municipio,
                  nm_state = UF,
                  soy_flag,
                  status)
  pl
}

apply_equal_allocation <- function(year) {
  plants <- get_plant_list(year)
  state_cap <- get_state_capacity_td(year)

  cat("  Year", year, ": state_cap total =", round(sum(state_cap$state_cap_td), 0),
      "t/day\n")

  if (is.null(plants)) {
    # Year outside sheet-3 coverage: return state-level only
    return(list(
      muni = NULL,
      state = state_cap %>% mutate(method = paste0("new_", year), year = year,
                                   n_active_soy = NA, muni_cap = NA)
    ))
  }

  # Filter to active soy plants
  active <- plants %>% filter(soy_flag, toupper(status) == "ATIVA")
  cat("  Year", year, ": active soy plants =", nrow(active), "\n")

  # Count active plants per state, divide state cap equally
  state_alloc <- active %>%
    group_by(nm_state) %>%
    summarise(n_active_soy = n(), .groups = "drop") %>%
    left_join(state_cap, by = "nm_state") %>%
    mutate(per_plant_cap = ifelse(n_active_soy > 0,
                                  state_cap_td / n_active_soy, 0))

  active_with_cap <- active %>%
    left_join(state_alloc %>% dplyr::select(nm_state, per_plant_cap),
              by = "nm_state") %>%
    mutate(per_plant_cap = ifelse(is.na(per_plant_cap), 0, per_plant_cap))

  # Aggregate to município (keep nm_mun as-is, canonicalise later if needed)
  muni <- active_with_cap %>%
    group_by(nm_state, nm_mun) %>%
    summarise(n_plants = n(),
              proc_cap = sum(per_plant_cap),
              companies = paste(sort(unique(company)), collapse = "; "),
              .groups = "drop") %>%
    mutate(method = paste0("new_", year), year = year)

  list(
    muni = muni,
    state = state_alloc %>% mutate(method = paste0("new_", year), year = year)
  )
}


#===============================================================================
# Run new method for the years we can fully compute (2024, 2025)
# Also produce state-only for earlier years to show the ABIOVE state totals.
#===============================================================================
cat("─── NEW (ABIOVE_raw_capacity_2025 + equal allocation) ───\n")

new_results <- list()
for (y in c(2024, 2025)) {
  new_results[[as.character(y)]] <- apply_equal_allocation(y)
}

# Also pull state totals for 2013 (so we can compare national / state-level
# capacity against Stefan's 2013 output)
state_2013 <- get_state_capacity_td(2013) %>%
  mutate(method = "abiove_state_2013", year = 2013)
cat("  2013 ABIOVE state_cap total (Ativa) =",
    round(sum(state_2013$state_cap_td), 0), "t/day\n\n")


#===============================================================================
# COMPARISON 1: National totals
#===============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("COMPARISON — NATIONAL TOTALS (t/day)\n")
cat("═══════════════════════════════════════════════════════════════\n")

nat_tbl <- bind_rows(
  data.frame(method = "stefan_2013_proc_MUN", year = 2013,
             total_td = sum(old_proc_mun$proc_cap)),
  data.frame(method = "ABIOVE_state_Ativa_2013", year = 2013,
             total_td = sum(state_2013$state_cap_td)),
  data.frame(method = "new_equal_alloc_2024", year = 2024,
             total_td = sum(new_results[["2024"]]$muni$proc_cap)),
  data.frame(method = "ABIOVE_state_Ativa_2024", year = 2024,
             total_td = sum(new_results[["2024"]]$state$state_cap_td, na.rm = TRUE)),
  data.frame(method = "new_equal_alloc_2025", year = 2025,
             total_td = sum(new_results[["2025"]]$muni$proc_cap)),
  data.frame(method = "ABIOVE_state_Ativa_2025", year = 2025,
             total_td = sum(new_results[["2025"]]$state$state_cap_td, na.rm = TRUE))
)
print(nat_tbl, row.names = FALSE)
cat("\n")
write.csv(nat_tbl, file.path(OUT_DIR, "compare_national_total.csv"), row.names = FALSE)


#===============================================================================
# COMPARISON 2: State-level
#===============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("COMPARISON — STATE TOTALS (top 10 states by Stefan 2013)\n")
cat("═══════════════════════════════════════════════════════════════\n")

stefan_by_state <- old_proc_mun %>%
  group_by(nm_state) %>%
  summarise(stefan_2013 = sum(proc_cap), .groups = "drop")

new_2024_by_state <- new_results[["2024"]]$muni %>%
  group_by(nm_state) %>%
  summarise(new_2024 = sum(proc_cap), .groups = "drop")

new_2025_by_state <- new_results[["2025"]]$muni %>%
  group_by(nm_state) %>%
  summarise(new_2025 = sum(proc_cap), .groups = "drop")

abiove_2013_state <- state_2013 %>%
  dplyr::select(nm_state, abiove_2013_ativa = state_cap_td)

abiove_2024_state <- new_results[["2024"]]$state %>%
  dplyr::select(nm_state, abiove_2024_ativa = state_cap_td) %>%
  distinct()

abiove_2025_state <- new_results[["2025"]]$state %>%
  dplyr::select(nm_state, abiove_2025_ativa = state_cap_td) %>%
  distinct()

state_cmp <- stefan_by_state %>%
  full_join(abiove_2013_state, by = "nm_state") %>%
  full_join(new_2024_by_state, by = "nm_state") %>%
  full_join(abiove_2024_state, by = "nm_state") %>%
  full_join(new_2025_by_state, by = "nm_state") %>%
  full_join(abiove_2025_state, by = "nm_state") %>%
  arrange(desc(ifelse(is.na(stefan_2013), 0, stefan_2013)))

print(state_cmp, row.names = FALSE)
cat("\n")
write.csv(state_cmp, file.path(OUT_DIR, "compare_proc_cap_state.csv"),
          row.names = FALSE)


#===============================================================================
# COMPARISON 3: Município-level (top 20 municípios by Stefan 2013)
#===============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("COMPARISON — TOP 20 MUNICÍPIOS (t/day, Stefan 2013 ranking)\n")
cat("═══════════════════════════════════════════════════════════════\n")

# openxlsx returns Portuguese accented chars as HTML entities like "Cuiab&#225;"
# from certain .xlsx files. Decode those first, then strip accents.
decode_html_entities <- function(x) {
  x <- as.character(x)
  pattern <- "&#([0-9]+);"
  repeat {
    m <- regmatches(x, regexpr(pattern, x))
    if (all(lengths(m) == 0)) break
    # Replace one occurrence at a time across all strings
    changed <- FALSE
    for (i in seq_along(x)) {
      if (grepl(pattern, x[i])) {
        code <- as.integer(sub(paste0(".*", pattern, ".*"), "\\1", x[i]))
        repl <- intToUtf8(code)
        x[i] <- sub(pattern, repl, x[i])
        changed <- TRUE
      }
    }
    if (!changed) break
  }
  x
}

# Normalize municipality names for cross-source joining:
#   ABIOVE: title case, UTF-8 or HTML-entity encoded accents
#   Stefan's file: upper case, UTF-8 accents
norm_mun <- function(x) {
  out <- decode_html_entities(x)
  out <- toupper(trimws(out))
  out <- iconv(out, from = "UTF-8", to = "ASCII//TRANSLIT")
  out <- gsub("[^A-Z0-9 ]", "", out)
  out <- gsub("\\s+", " ", out)
  out
}

stefan_m <- old_proc_mun %>%
  transmute(nm_state,
            nm_mun_norm = norm_mun(nm_mun),
            stefan_2013 = proc_cap)

new_2024_m <- new_results[["2024"]]$muni %>%
  transmute(nm_state,
            nm_mun_norm = norm_mun(nm_mun),
            new_2024 = proc_cap)

new_2025_m <- new_results[["2025"]]$muni %>%
  transmute(nm_state,
            nm_mun_norm = norm_mun(nm_mun),
            new_2025 = proc_cap)

muni_cmp <- stefan_m %>%
  full_join(new_2024_m, by = c("nm_state", "nm_mun_norm")) %>%
  full_join(new_2025_m, by = c("nm_state", "nm_mun_norm")) %>%
  arrange(desc(ifelse(is.na(stefan_2013), 0, stefan_2013)))

print(head(muni_cmp, 20), row.names = FALSE)
cat("\n")
write.csv(muni_cmp, file.path(OUT_DIR, "compare_proc_cap_muni.csv"),
          row.names = FALSE)

cat("═══════════════════════════════════════════════════════════════\n")
cat("Wrote 3 CSVs to", OUT_DIR, "\n")
cat("═══════════════════════════════════════════════════════════════\n")

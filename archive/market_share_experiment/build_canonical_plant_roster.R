#!/usr/bin/env Rscript
# Build a canonical multi-year plant roster from raw ABIOVE pesquisa_capacidade files.
# Output: inputs/00/new/ABIOVE_processing/canonical_plant_roster.csv
#
# One row per (year, company, municipality, UF, status) tuple actually present in
# an ABIOVE survey. Only uses years where we have a real file (no fallback to prior
# years). Both Ativa and Parada plants are kept; downstream caller filters.

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
})

PLANT_PATH <- "inputs/00/new/ABIOVE_processing"

# Year → file/era/sheet — same map as R/reproduction/00_data_preparation/00_data_preparation.R
# We add status_col only for new/multi-era files. We KEEP all plants (not just Ativa)
# in the canonical roster — caller decides.
PLANT_INDEX <- list(
  "2003" = list(file = "pesquisa_capacidade_2003_PT.xls", era = "early", sheet = "unidproces"),
  "2004" = list(file = "pesquisa_capacidade_2004_PT.xls", era = "mid",   sheet = "geralproces"),
  "2005" = list(file = "pesquisa_capacidade_2005_PT.xls", era = "mid",   sheet = "geralproces"),
  "2006" = list(file = "pesquisa_capacidade_2006_PT.xls", era = "mid",   sheet = "geralproces"),
  "2007" = list(file = "pesquisa_capacidade_2007_PT.xls", era = "mid",   sheet = "Geralproces"),
  "2008" = list(file = "pesquisa_capacidade_2008_PT.xls", era = "mid",   sheet = "Geralproces"),
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

# Early-era parser: 2003-2004 (unidproces sheet)
parse_early <- function(file, sheet) {
  df <- as.data.frame(read_excel(file, sheet = sheet, col_names = FALSE, skip = 5))
  names(df)[1:8] <- c("x1","Empresas","num","Municipio","UF","Processo","Oleaginosas","Situacao")
  df %>%
    filter(!is.na(Empresas), !is.na(Municipio), !is.na(UF),
           nchar(as.character(UF)) == 2) %>%
    mutate(soy_flag = toupper(trimws(as.character(Oleaginosas))) == "SOJA") %>%
    filter(soy_flag) %>%
    transmute(company      = as.character(Empresas),
              municipality = as.character(Municipio),
              UF           = as.character(UF),
              status       = as.character(Situacao),
              oleaginosas  = as.character(Oleaginosas))
}

# Mid-era parser: 2005-2015 (geralproces / variant)
parse_mid <- function(file, sheet) {
  if (is.null(sheet)) {
    sheets <- excel_sheets(file)
    idx <- which(grepl("geralproces|empreproces",
                       gsub("[[:space:]\\.]", "", tolower(sheets))))
    if (length(idx) == 0) stop("mid: no plant-list sheet in ", file)
    sheet <- sheets[idx[1]]
  }
  raw <- as.data.frame(suppressMessages(
    read_excel(file, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  is_header <- apply(raw, 1, function(r) {
    v <- toupper(trimws(as.character(r)))
    any(grepl("EMPRESA", v), na.rm = TRUE) && any(v == "UF", na.rm = TRUE)
  })
  hdr <- which(is_header)[1]
  if (is.na(hdr)) stop("mid: header row not found in ", file)
  h <- trimws(as.character(raw[hdr, ]))
  HU <- toupper(h)
  get_col <- function(pat) {
    i <- which(grepl(pat, HU))
    if (length(i) == 0) NA_integer_ else i[1]
  }
  emp <- get_col("EMPRESA"); mun <- get_col("LOCALI|MUNIC")
  uf  <- which(HU == "UF")[1]
  ole <- get_col("OLEAGIN"); sit <- get_col("SITUA|SITUAÇÃO")
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
    filter(soy_flag) %>%
    select(company, municipality, UF, status, oleaginosas)
}

# New/multi-era parser: 2018+ (Soja x flag, year status col)
parse_new <- function(file, sheet, status_col) {
  raw <- as.data.frame(suppressMessages(
    read_excel(file, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  is_header <- apply(raw, 1, function(r) {
    v <- toupper(trimws(as.character(r)))
    any(grepl("EMPRESA", v), na.rm = TRUE) && any(grepl("MUNIC", v), na.rm = TRUE)
  })
  hdr <- which(is_header)[1]
  if (is.na(hdr)) stop("new: header row not found in ", file)
  h <- trimws(as.character(raw[hdr, ]))
  HU <- toupper(h)
  emp <- which(grepl("EMPRESA", HU))[1]
  mun <- which(grepl("MUNIC|LOCALI", HU))[1]
  uf  <- which(HU == "UF")[1]
  soj <- which(HU == "SOJA")[1]
  stc <- which(h == status_col | trimws(h) == as.character(status_col))[1]
  if (is.na(stc)) stc <- which(suppressWarnings(as.numeric(h)) == as.numeric(status_col))[1]
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
    filter(soy_flag) %>%
    select(company, municipality, UF, status) %>%
    mutate(oleaginosas = "Soja")
}

# Iterate over all years and concatenate
all_rows <- list()
for (yr in names(PLANT_INDEX)) {
  entry <- PLANT_INDEX[[yr]]
  fpath <- file.path(PLANT_PATH, entry$file)
  if (!file.exists(fpath)) {
    cat("  [SKIP]", yr, "— missing", entry$file, "\n"); next
  }
  out <- tryCatch({
    switch(entry$era,
      "early" = parse_early(fpath, entry$sheet),
      "mid"   = parse_mid(fpath, entry$sheet),
      "new"   = parse_new(fpath, entry$sheet, entry$status_col),
      "multi" = parse_new(fpath, entry$sheet, entry$status_col),
      stop("Unknown era ", entry$era))
  }, error = function(e) {
    cat("  [ERR]", yr, "—", conditionMessage(e), "\n"); NULL
  })
  if (is.null(out)) next
  out$year <- as.integer(yr)
  out$source_file <- entry$file
  cat(sprintf("  %s  %4d plants from %s\n", yr, nrow(out), entry$file))
  all_rows[[yr]] <- out
}

roster <- bind_rows(all_rows) %>%
  mutate(company = trimws(company),
         municipality = trimws(municipality),
         UF = trimws(UF),
         status = trimws(status),
         status_norm = toupper(status)) %>%
  relocate(year, company, municipality, UF, status, status_norm, oleaginosas, source_file)

cat("\n=== Roster summary ===\n")
cat("Total rows:                 ", nrow(roster), "\n")
cat("Years covered:              ", length(unique(roster$year)), " (",
    paste(range(roster$year), collapse="-"), ")\n", sep="")
cat("Unique companies (raw):     ", length(unique(roster$company)), "\n")
cat("Unique municipalities:      ", length(unique(paste(roster$UF, roster$municipality))), "\n")
cat("Status distribution:        \n")
print(table(roster$status_norm, useNA = "ifany"))

out_csv <- file.path(PLANT_PATH, "canonical_plant_roster.csv")
write.csv(roster, out_csv, row.names = FALSE, fileEncoding = "UTF-8")
cat("\nWrote: ", out_csv, "\n", sep="")

# Also produce a unique-companies file as starting point for parent-group mapping
companies <- roster %>%
  group_by(company) %>%
  summarise(years = paste(sort(unique(year)), collapse=";"),
            n_plant_years = n(),
            n_distinct_plants = n_distinct(paste(UF, municipality)),
            .groups = "drop") %>%
  arrange(desc(n_plant_years))
out_companies <- file.path(PLANT_PATH, "canonical_companies_raw.csv")
write.csv(companies, out_companies, row.names = FALSE, fileEncoding = "UTF-8")
cat("Wrote: ", out_companies, "\n", sep="")
cat("\nTop 20 companies by plant-years:\n")
print(head(companies, 20))

#!/usr/bin/env Rscript
# Consolidate agent outputs into plant_strata.csv + company_revenue.csv,
# then run new allocation for 2013 and compare against equal-allocation baseline.
#
# Expects in /tmp/:
#   revenue_bunge_adm.csv
#   revenue_cargill_ldc_cofco.csv
#   revenue_brazilian_firms.csv
#   plant_strata_research.csv
#   deflators.csv

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

P <- "inputs/00/new/ABIOVE_processing"

# ---- 1. Load deflators ----
def <- read.csv("/tmp/deflators.csv", stringsAsFactors = FALSE)
cat("Deflators loaded: rows=", nrow(def), "\n", sep="")
stopifnot(all(c("year","brl_2020_per_brl_nominal","brl_2020_per_usd_nominal") %in% names(def)))

# ---- 2. Consolidate revenue CSVs and deflate to constant 2020 BRL ----
rev_files <- c("/tmp/revenue_bunge_adm.csv",
               "/tmp/revenue_cargill_ldc_cofco.csv",
               "/tmp/revenue_brazilian_firms.csv")
rev_raw <- bind_rows(lapply(rev_files, function(f) {
  if (!file.exists(f)) { cat("MISSING:", f, "\n"); return(NULL) }
  read.csv(f, stringsAsFactors = FALSE)
}))
cat("Raw revenue rows:", nrow(rev_raw), "\n")

# Deflate: prefer nominal BRL, else convert from USD
rev <- rev_raw %>%
  left_join(def, by = "year") %>%
  mutate(revenue_brl_2020_mn = case_when(
    !is.na(revenue_nominal_brl_mn) ~ revenue_nominal_brl_mn * brl_2020_per_brl_nominal,
    !is.na(revenue_nominal_usd_mn) ~ revenue_nominal_usd_mn * brl_2020_per_usd_nominal,
    TRUE ~ NA_real_)) %>%
  select(parent_group, year, revenue_brl_2020_mn, scope, source, source_url, confidence, notes)

# Write final revenue file
write.csv(rev, file.path(P, "company_revenue.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("Wrote: ", file.path(P, "company_revenue.csv"), " (", nrow(rev), " rows)\n", sep="")

# ---- 3. Build plant_strata.csv from agent stratum research + template ----
strata_template <- read.csv(file.path(P, "plant_strata_template.csv"),
                            stringsAsFactors = FALSE, encoding = "UTF-8")
strata_research <- read.csv("/tmp/plant_strata_research.csv",
                            stringsAsFactors = FALSE, encoding = "UTF-8")

stratum_midpoint <- c(`1` = 300, `2` = 1050, `3` = 2250, `4` = 4500)

# Standardize join keys
norm_key <- function(parent, company, municipality, uf) {
  paste(toupper(trimws(parent)), toupper(trimws(municipality)), toupper(trimws(uf)), sep = "|")
}

strata_research <- strata_research %>%
  mutate(key = norm_key(parent_group, company, municipality, UF))
strata_template <- strata_template %>%
  mutate(key = norm_key(parent_group, company, municipality, UF))

strata <- strata_template %>%
  left_join(strata_research %>%
              select(key, stratum_1to4_res = stratum_1to4,
                     capacity_td_res = capacity_td,
                     conf_res = confidence,
                     src_res = source, src_url_res = source_url,
                     notes_res = notes),
            by = "key") %>%
  mutate(stratum_1to4 = ifelse(!is.na(stratum_1to4_res), stratum_1to4_res, stratum_1to4),
         stratum_midpoint_td = stratum_midpoint[as.character(stratum_1to4)],
         capacity_source = ifelse(!is.na(src_res), src_res, capacity_source),
         capacity_source_url = ifelse(!is.na(src_url_res), src_url_res, capacity_source_url),
         confidence = ifelse(!is.na(conf_res), conf_res, confidence),
         notes = ifelse(!is.na(notes_res), notes_res, notes)) %>%
  select(-ends_with("_res"), -key)

write.csv(strata, file.path(P, "plant_strata.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("Wrote: ", file.path(P, "plant_strata.csv"), " (", nrow(strata),
    " rows; ", sum(!is.na(strata$stratum_1to4)), " with explicit stratum)\n", sep="")

cat("\n=== Data summary ===\n")
cat("plant_strata rows:                   ", nrow(strata), "\n")
cat("  with explicit stratum:             ", sum(!is.na(strata$stratum_1to4)), "\n")
cat("  using state-median fallback:       ", sum(is.na(strata$stratum_1to4)), "\n")
cat("company_revenue rows:                ", nrow(rev), "\n")
cat("  parent_groups with any revenue:    ", length(unique(rev$parent_group[!is.na(rev$revenue_brl_2020_mn)])), "\n")
cat("  years covered by revenue:          ", paste(range(rev$year[!is.na(rev$revenue_brl_2020_mn)]), collapse="-"), "\n")

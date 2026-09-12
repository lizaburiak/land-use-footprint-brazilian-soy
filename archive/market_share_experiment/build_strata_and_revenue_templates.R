#!/usr/bin/env Rscript
# Build plant_strata.csv and company_revenue.csv templates.
# Pre-fills what we can determine from primary data: single-plant-state strata
# (where state total = plant capacity by definition).

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(openxlsx)
})

P <- "inputs/00/new/ABIOVE_processing"

roster <- read.csv(file.path(P, "canonical_plant_roster.csv"),
                   stringsAsFactors = FALSE, encoding = "UTF-8")
parents <- read.csv(file.path(P, "canonical_companies_with_parents.csv"),
                    stringsAsFactors = FALSE, encoding = "UTF-8")

# Filter to ATIVA only (active plants — those the allocation actually distributes capacity to)
active <- roster %>% filter(status_norm == "ATIVA")

# Join parent group
active <- active %>%
  left_join(parents %>% select(company, parent_group),
            by = "company")

# ===== Plant strata template =====
# One row per (parent_group, municipality, UF) — collapse adjacent years where plant
# is continuously active. Plant entries are stable across years unless capacity
# expands; we mark `year_first_observed` and `year_last_observed`.

plant_strata <- active %>%
  group_by(parent_group, company, municipality, UF) %>%
  summarise(year_first_observed = min(year),
            year_last_observed  = max(year),
            n_years_active      = n_distinct(year),
            years_active        = paste(sort(unique(year)), collapse=";"),
            .groups = "drop") %>%
  arrange(parent_group, UF, municipality)

# Pre-fill stratum where we can determine from primary data:
# Read state-level capacity from ABIOVE Evolução sheet, identify states where
# only ONE plant is active in a given year — that plant's capacity = state total.
# For each plant-row, compute the YEARS in which it was the sole active plant in
# its state, and report any deduced capacity. We use this to suggest stratum.

state_cap_json <- "inputs/00/new/ABIOVE_processing/ABIOVE_state_processing_capacity.json"
if (file.exists(state_cap_json)) {
  state_cap <- jsonlite::fromJSON(state_cap_json)
  cat("Loaded ABIOVE state capacity time series\n")
} else {
  state_cap <- NULL
  cat("No state_cap json — skipping single-plant-state deduction\n")
}

# Count active plants per (UF, year) in roster
plants_per_state_year <- active %>%
  group_by(UF, year) %>%
  summarise(n_plants = n_distinct(paste(company, municipality)), .groups = "drop")

# For each plant-year, was it the sole plant in its state-year?
active_with_sole <- active %>%
  left_join(plants_per_state_year, by = c("UF","year")) %>%
  mutate(sole_in_state = n_plants == 1)

sole_plant_years <- active_with_sole %>%
  filter(sole_in_state) %>%
  select(parent_group, company, municipality, UF, year)

cat("\nSingle-plant-state observations (plant capacity == state total):\n")
sole_summary <- sole_plant_years %>%
  group_by(parent_group, company, municipality, UF) %>%
  summarise(years = paste(sort(year), collapse=";"), .groups = "drop")
print(sole_summary)

# Add columns for manual filling
plant_strata <- plant_strata %>%
  mutate(stratum_1to4 = NA_integer_,        # 1=<=599, 2=600-1499, 3=1500-2999, 4=>=3000
         stratum_midpoint_td = NA_real_,    # 300 / 1050 / 2250 / 4500
         capacity_source = NA_character_,
         capacity_source_url = NA_character_,
         confidence = NA_character_,        # high / medium / low
         expansion_year = NA_integer_,      # year capacity changed materially
         notes = NA_character_)

cat("\n=== plant_strata template ===\n")
cat("Rows:", nrow(plant_strata), "\n")
cat("Unique plants:", n_distinct(paste(plant_strata$UF, plant_strata$municipality, plant_strata$company)), "\n")
cat("Plants where we can deduce capacity from single-plant-state evidence:",
    n_distinct(paste(sole_plant_years$UF, sole_plant_years$municipality, sole_plant_years$company)), "\n")

write.csv(plant_strata,
          file.path(P, "plant_strata_template.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("\nWrote: ", file.path(P, "plant_strata_template.csv"), "\n", sep="")


# ===== Company revenue template =====
# One row per (parent_group, year) for years 2003-2025.
parent_year_grid <- active %>%
  group_by(parent_group) %>%
  summarise(year_first_observed = min(year),
            year_last_observed  = max(year),
            .groups = "drop") %>%
  rowwise() %>%
  mutate(year = list(seq(year_first_observed, year_last_observed))) %>%
  unnest(year) %>%
  ungroup() %>%
  select(parent_group, year) %>%
  distinct()

# Add columns
company_revenue <- parent_year_grid %>%
  mutate(revenue_brl_2020_mn = NA_real_,
         scope = NA_character_,           # brazil-segment / global-x-share / total / crushing-segment
         source = NA_character_,
         source_url = NA_character_,
         confidence = NA_character_,
         notes = NA_character_)

cat("\n=== company_revenue template ===\n")
cat("Rows (parent_group x year):", nrow(company_revenue), "\n")
cat("Unique parent groups:", n_distinct(company_revenue$parent_group), "\n")
cat("Year range:", paste(range(company_revenue$year), collapse="-"), "\n")

write.csv(company_revenue,
          file.path(P, "company_revenue_template.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("\nWrote: ", file.path(P, "company_revenue_template.csv"), "\n", sep="")


# ===== Coverage diagnostic =====
parent_plant_years <- active %>%
  group_by(parent_group) %>%
  summarise(plant_years = n(),
            distinct_plants = n_distinct(paste(UF, municipality)),
            year_first = min(year), year_last = max(year),
            .groups = "drop") %>%
  arrange(desc(plant_years)) %>%
  mutate(cum_share = round(cumsum(plant_years) / sum(plant_years), 3))

write.csv(parent_plant_years,
          file.path(P, "parent_coverage_for_revenue_collection.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("Wrote: ", file.path(P, "parent_coverage_for_revenue_collection.csv"), "\n", sep="")

cat("\nTop 25 parents by plant-years (revenue collection priority):\n")
print(head(parent_plant_years, 25))

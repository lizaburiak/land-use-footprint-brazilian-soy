
######## Estimation of MU consumption and processing use items #########
# code/pipeline/01_consumption_and_processing.R - minimal-delta fork of
# R/01_consumption_and_processing.R. Changes: year-parameterized I/O paths;
# the former `==` allocation printouts are halting assert_equal() checks.

library(dplyr)
library(sf)
library(openxlsx)
source("code/pipeline/00_checks.R")

# Year parameter (default 2013)
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2013
IN00 <- paste0("data/generated/outputs/00_", YEAR, "/")
OUT  <- paste0("data/generated/outputs/01_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# load data
CBS_SOY <- readRDS(paste0(IN00, "CBS_SOY.rds"))
SOY_MUN <- readRDS(paste0(IN00, "SOY_MUN_00.rds"))
GEO_MUN_SOY <- readRDS(paste0(IN00, "GEO_MUN_SOY_00.rds"))

# should results be written to file?
write = TRUE


# processing use ---------------------------------------------------------------------

## derive reference values for MU total processing estimation: -----

# average operation days of processing facilities
# SENSITIVITY: re-split each state's total ABIOVE crush capacity across its
# plant-municipalities by an alternative weight, holding the state total fixed
# (so national processing, proc_days and the assertion below are unchanged).
# The raw proc_cap from step 00 is an equal-per-plant split; this tests that
# within-state allocation assumption. MC_CRUSH_SPLIT (default "equal" = no-op):
#   prod      -> weight by municipal soy production (plant size proxy)
#   dirichlet -> seeded random weights ~ Gamma(MC_SPLIT_ALPHA); a Monte Carlo
#                over the unknown plant sizes (MC_SPLIT_SEED for reproducibility)
.mc_split <- tolower(Sys.getenv("MC_CRUSH_SPLIT", "equal"))
if (nzchar(.mc_split) && .mc_split != "equal") {
  .split_seed  <- suppressWarnings(as.integer(Sys.getenv("MC_SPLIT_SEED", "1")))
  .split_alpha <- suppressWarnings(as.numeric(Sys.getenv("MC_SPLIT_ALPHA", "2")))
  if (is.na(.split_seed))  .split_seed  <- 1L
  if (is.na(.split_alpha)) .split_alpha <- 2
  set.seed(.split_seed)
  .has_cap <- !is.na(SOY_MUN$proc_cap) & SOY_MUN$proc_cap > 0
  .df <- SOY_MUN[.has_cap, c("co_state", "proc_cap", "prod_bean")]
  .df$w <- switch(.mc_split,
    "prod"      = ifelse(is.na(.df$prod_bean), 0, .df$prod_bean),
    "dirichlet" = rgamma(nrow(.df), shape = .split_alpha, rate = 1),
    stop("Unknown MC_CRUSH_SPLIT: ", .mc_split))
  .df <- .df %>% group_by(co_state) %>%
    # per state: redistribute the fixed state total by w; if all w==0 fall back to equal
    mutate(new_cap = if (sum(w) > 0) sum(proc_cap) * w / sum(w)
                     else            sum(proc_cap) / dplyr::n()) %>%
    ungroup()
  SOY_MUN$proc_cap[.has_cap] <- .df$new_cap
  message(sprintf("[01] SENSITIVITY MC_CRUSH_SPLIT=%s (seed=%d, alpha=%.2f) re-split crush capacity within states",
                  .mc_split, .split_seed, .split_alpha))
}
# SENSITIVITY: sharpen (gamma>1) or flatten (gamma<1) the crush-capacity
# allocation weight by raising it to MC_CRUSHCAP_GAMMA (default 1 = no-op).
# Tests the "allocation weight" choice. Used by code/analysis/mc_sensitivity.R.
.mc_gamma <- suppressWarnings(as.numeric(Sys.getenv("MC_CRUSHCAP_GAMMA", "1")))
if (!is.na(.mc_gamma) && .mc_gamma != 1) {
  SOY_MUN$proc_cap <- SOY_MUN$proc_cap ^ .mc_gamma
  message(sprintf("[01] SENSITIVITY MC_CRUSHCAP_GAMMA = %.3f applied to crush-capacity weight", .mc_gamma))
}
proc_days <- CBS_SOY["bean", "processing"]/sum(SOY_MUN$proc_cap, na.rm = TRUE)
ref_days <- CBS_SOY["oil", "production"]/sum(SOY_MUN$ref_cap, na.rm = TRUE)

# conversion factor from soybean to cake and oil
(cake_conv <- CBS_SOY["cake", "production"]/CBS_SOY["bean", "processing"])
(oil_conv <- CBS_SOY["oil", "production"]/CBS_SOY["bean", "processing"])
# note: values are relatively consistent with Smalling et. al (2008)[75% and 20%] and Dei (2011)[79% / 19%]
# processing losses:
(proc_loss <- 1-cake_conv-oil_conv)
# SENSITIVITY: shift the oil:cake yield split by MC_OILSHARE_DELTA percentage
# points (default 0 = no-op), mass-conserving within the crushed beans (oil up,
# cake down); processing loss unchanged. Used by code/analysis/mc_sensitivity.R.
.mc_oil <- suppressWarnings(as.numeric(Sys.getenv("MC_OILSHARE_DELTA", "0")))
if (!is.na(.mc_oil) && .mc_oil != 0) {
  oil_conv  <- oil_conv  + .mc_oil
  cake_conv <- cake_conv - .mc_oil
  message(sprintf("[01] SENSITIVITY MC_OILSHARE_DELTA = %+.3f (oil_conv=%.3f, cake_conv=%.3f)",
                  .mc_oil, oil_conv, cake_conv))
}
# equivalence factor (for comparison with TRASE)
(equi_fact <- 1/(cake_conv+oil_conv))

## calculate MU totals ----

# annual bean processing quantity
SOY_MUN$proc_bean <- SOY_MUN$proc_cap*proc_days
assert_equal(sum(SOY_MUN$proc_bean, na.rm = TRUE), CBS_SOY["bean", "processing"],
             "01 crush allocation = national processing")

# annual cake and production (through conversion factor from annual processing quantity)
SOY_MUN$prod_oil <- SOY_MUN$proc_bean*oil_conv
SOY_MUN$prod_cake <- SOY_MUN$proc_bean*cake_conv
# target via the (possibly MC_OILSHARE_DELTA-shifted) conversion factors, so
# the check also holds under the OAT sensitivity runs; with the default
# factors it equals CBS production exactly
assert_equal(sum(SOY_MUN$prod_oil, na.rm = TRUE), CBS_SOY["bean","processing"]*oil_conv,
             "01 municipal oil output = national crush x oil yield")
assert_equal(sum(SOY_MUN$prod_cake, na.rm = TRUE), CBS_SOY["bean","processing"]*cake_conv,
             "01 municipal cake output = national crush x cake yield")


# food use -----------------------------------------------------------------

# allocate by per-capita annual acquisition of soy oil
SOY_MUN <- mutate(SOY_MUN, oil_acq = oil_acq_pc * population)
SOY_MUN <- mutate(SOY_MUN,
                  food_bean = oil_acq/sum(oil_acq) * CBS_SOY["bean", "food"],
                  food_oil = oil_acq/sum(oil_acq) * CBS_SOY["oil", "food"])
SOY_MUN <- dplyr::select(SOY_MUN, -oil_acq)

assert_equal(sum(SOY_MUN$food_bean, na.rm = TRUE), CBS_SOY["bean", "food"],
             "01 food allocation = national bean food use")
assert_equal(sum(SOY_MUN$food_oil, na.rm = TRUE), CBS_SOY["oil", "food"],
             "01 food allocation = national oil food use")


# other use ---------------------------------------------------------------------------

# allocate by municipal soy-based biodiesel production capacity
SOY_MUN <- mutate(SOY_MUN, other_oil = diesel_cap_soy/sum(diesel_cap_soy) * CBS_SOY["oil", "other"])
assert_equal(sum(SOY_MUN$other_oil, na.rm = TRUE), CBS_SOY["oil", "other"],
             "01 biodiesel allocation = national oil other use")


# seed use --------------------------------------------------------------------------------

# share of seed use in total soybean production (or supply)
seed_use_share <- CBS_SOY["bean", "seed"] / sum(SOY_MUN$prod_bean, na.rm = TRUE)

# calculate MU totals:
# seed use (proxy: soybean production)
SOY_MUN$seed_bean <- SOY_MUN$prod_bean*seed_use_share
assert_equal(sum(SOY_MUN$seed_bean, na.rm = TRUE), CBS_SOY["bean", "seed"],
             "01 seed allocation = national seed use")


# stock addition --------------------------------------------------------------------------

# stock addition (proxy: grain storage capacity)
# NB: this storage-capacity split is corrected for the WITHDRAWAL case (negative national
# stock change) downstream in 05_balancing.R, where the full municipal use base is known --
# a withdrawal must be drawn proportional to use, not storage, or non-using municipalities
# get negative total_use (which broke the step-12 re-export inversion for 2018-2020).
store_cap_tot <- sum(SOY_MUN$storage_cap, na.rm = T) # total storage capacity
SOY_MUN$stock_bean <- (SOY_MUN$storage_cap/store_cap_tot)*CBS_SOY["bean","stock_addition"]
assert_equal(sum(SOY_MUN$stock_bean, na.rm = TRUE), CBS_SOY["bean", "stock_addition"],
             "01 stock allocation = national stock addition")


# append results to GEO MUN file -----------------------------------------------------------

newcols <- SOY_MUN %>% dplyr::select(c(co_mun, proc_bean:stock_bean))
GEO_MUN_SOY <- GEO_MUN_SOY %>% left_join(newcols, by = "co_mun")

# write to file
if (write){
  saveRDS(SOY_MUN, file = paste0(OUT, "SOY_MUN_01.rds"))
  saveRDS(GEO_MUN_SOY, file = paste0(OUT, "GEO_MUN_SOY_01.rds"))
}

rm(list=ls())
gc()

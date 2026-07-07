
######## Estimation of MU consumption and processing use items #########
# code/pipeline/01_consumption_and_processing.R — minimal-delta fork of
# R/01_consumption_and_processing.R. Only change: year-parameterized I/O paths.

library(dplyr)
library(sf)
library(openxlsx)

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
proc_days <- CBS_SOY["bean", "processing"]/sum(SOY_MUN$proc_cap, na.rm = TRUE)
ref_days <- CBS_SOY["oil", "production"]/sum(SOY_MUN$ref_cap, na.rm = TRUE)

# conversion factor from soybean to cake and oil
(cake_conv <- CBS_SOY["cake", "production"]/CBS_SOY["bean", "processing"])
(oil_conv <- CBS_SOY["oil", "production"]/CBS_SOY["bean", "processing"])
# note: values are relatively consistent with Smalling et. al (2008)[75% and 20%] and Dei (2011)[79% / 19%]
# processing losses:
(proc_loss <- 1-cake_conv-oil_conv)
# equivalence factor (for comparison with TRASE)
(equi_fact <- 1/(cake_conv+oil_conv))

## calculate MU totals ----

# annual bean processing quantity
SOY_MUN$proc_bean <- SOY_MUN$proc_cap*proc_days
sum(SOY_MUN$proc_bean, na.rm = T) == CBS_SOY["bean", "processing"]

# annual cake and production (through conversion factor from annual processing quantity)
SOY_MUN$prod_oil <- SOY_MUN$proc_bean*oil_conv
SOY_MUN$prod_cake <- SOY_MUN$proc_bean*cake_conv
sum(SOY_MUN$prod_oil, na.rm = T) == CBS_SOY["oil","production"]
sum(SOY_MUN$prod_cake, na.rm = T) == CBS_SOY["cake","production"]


# food use -----------------------------------------------------------------

# allocate by per-capita annual acquisition of soy oil
SOY_MUN <- mutate(SOY_MUN, oil_acq = oil_acq_pc * population)
SOY_MUN <- mutate(SOY_MUN,
                  food_bean = oil_acq/sum(oil_acq) * CBS_SOY["bean", "food"],
                  food_oil = oil_acq/sum(oil_acq) * CBS_SOY["oil", "food"])
SOY_MUN <- dplyr::select(SOY_MUN, -oil_acq)

sum(SOY_MUN$food_bean, na.rm = T) == CBS_SOY["bean", "food"]
sum(SOY_MUN$food_oil, na.rm = T) == CBS_SOY["oil", "food"]


# other use ---------------------------------------------------------------------------

# allocate by municipal soy-based biodiesel production capacity
SOY_MUN <- mutate(SOY_MUN, other_oil = diesel_cap_soy/sum(diesel_cap_soy) * CBS_SOY["oil", "other"])
sum(SOY_MUN$other_oil, na.rm = T) == CBS_SOY["oil", "other"]


# seed use --------------------------------------------------------------------------------

# share of seed use in total soybean production (or supply)
seed_use_share <- CBS_SOY["bean", "seed"] / sum(SOY_MUN$prod_bean, na.rm = TRUE)

# calculate MU totals:
# seed use (proxy: soybean production)
SOY_MUN$seed_bean <- SOY_MUN$prod_bean*seed_use_share
sum(SOY_MUN$seed_bean, na.rm = T) == CBS_SOY["bean", "seed"]


# stock addition --------------------------------------------------------------------------

# stock addition (proxy: grain storage capacity)
# NB: this storage-capacity split is corrected for the WITHDRAWAL case (negative national
# stock change) downstream in 05_balancing.R, where the full municipal use base is known --
# a withdrawal must be drawn proportional to use, not storage, or non-using municipalities
# get negative total_use (which broke the step-12 re-export inversion for 2018-2020).
store_cap_tot <- sum(SOY_MUN$storage_cap, na.rm = T) # total storage capacity
SOY_MUN$stock_bean <- (SOY_MUN$storage_cap/store_cap_tot)*CBS_SOY["bean","stock_addition"]
sum(SOY_MUN$stock_bean, na.rm = T) == CBS_SOY["bean", "stock_addition"]


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

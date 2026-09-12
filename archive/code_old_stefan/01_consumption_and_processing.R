
######## Estimation of MU consumption and processing use items #########

library(dplyr)
library(sf)
library(openxlsx)

# load data 
CBS_SOY <- readRDS("results/intermediate/CBS_SOY.rds")
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_00.rds")
GEO_MUN_SOY <- readRDS("results/intermediate/GEO_MUN_SOY_00.rds")
# oil_acq_state <- read.xlsx("data/old/POF_soy_oil_2017_IBGE.xlsx")

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
# also add processing losses as difference between input and output
# SOY_MUN$loss_bean <- SOY_MUN$proc_bean*(1-oil_conv-cake_conv)


# food use -----------------------------------------------------------------

# old approach:
# # derive reference values for MU consumption estimation
# # per capita consumption (bean & oil)
# tot_pop <- sum(SOY_MUN$population, na.rm = TRUE)
# food_per_cap <- CBS_SOY$food/tot_pop
# names(food_per_cap) <- rownames(CBS_SOY)
#
# # human soybean consumption (proxy: population)
# SOY_MUN$food_bean <- SOY_MUN$population*food_per_cap["bean"]
# sum(SOY_MUN$food_bean, na.rm = T) == CBS_SOY["bean", "food"]
# 
# # human soy oil consumption (proxy: population)
# SOY_MUN$food_oil <- SOY_MUN$population*food_per_cap["oil"]
# sum(SOY_MUN$food_oil, na.rm = T) == CBS_SOY["oil", "food"]

# new approach: 

# allocate by per-capita annual acquisition of soy oil 

# option 1:
# # allocate national consumption to states by per-capita-purchase-weighted population:
# pop_state <- group_by(SOY_MUN, co_state, nm_state) %>%
#   summarise(population = sum(population, na.rm = TRUE), .groups = "drop")
# # match with state-level data on per capita soy oil purchases
# oil_acq_state <- rename(oil_acq_state, aqc = Óleo.de.soja, nm_state = subdivision)
# # compute weighted state population and allocation share
# oil_share_state <- left_join(pop_state, dplyr::select(oil_acq_state, aqc:nm_state), 
#                           by = c("nm_state")) %>%
#   mutate(pop_weighted = population * aqc)
# oil_share_state <- oil_share_state %>% mutate(share = pop_weighted/sum(oil_share_state$pop_weighted))
# # allocate national food use of oil AND beans to states with this share 
# food_use_state <- oil_share_state %>% mutate(food_oil = share*CBS_SOY["oil", "food"],
#                                              food_bean = share*CBS_SOY["bean", "food"])
# 
# # allocate state consumption to MUs by share in state population
# SOY_MUN <- group_by(SOY_MUN, co_state) %>%
#   mutate(pop_share_state = population/sum(population)) %>%
#   ungroup()
# 
# SOY_MUN <- left_join(SOY_MUN, dplyr::select(food_use_state, c(co_state, food_bean, food_oil)))
# SOY_MUN <- SOY_MUN %>% 
#   mutate(food_bean = food_bean*pop_share_state, 
#          food_oil = food_oil*pop_share_state) %>%
#   dplyr::select(-c(pop_share_state))

# option 2: allocate directly by estimated MU-level soy oil acquisition --> same result, but more straight-forward
SOY_MUN <- mutate(SOY_MUN, oil_acq = oil_acq_pc * population)
SOY_MUN <- mutate(SOY_MUN, 
                  food_bean = oil_acq/sum(oil_acq) * CBS_SOY["bean", "food"],
                  food_oil = oil_acq/sum(oil_acq) * CBS_SOY["oil", "food"])
SOY_MUN <- dplyr::select(SOY_MUN, -oil_acq)

sum(SOY_MUN$food_bean, na.rm = T) == CBS_SOY["bean", "food"]
sum(SOY_MUN$food_oil, na.rm = T) == CBS_SOY["oil", "food"]


# other use ---------------------------------------------------------------------------

# # old approach:
# # per capita other use (oil)
# other_per_cap <- CBS_SOY$other/tot_pop
# names(other_per_cap) <- rownames(CBS_SOY)
# 
# # calculate MU totals:
# # other use of oil (proxy: population)
# SOY_MUN$other_oil <- SOY_MUN$population*other_per_cap["oil"]
# sum(SOY_MUN$other_oil, na.rm = T) == CBS_SOY["oil", "other"]

# new approach:
# allocate by municipal soy-based biodiesel production capacity
SOY_MUN <- mutate(SOY_MUN, other_oil = diesel_cap_soy/sum(diesel_cap_soy) * CBS_SOY["oil", "other"])
sum(SOY_MUN$other_oil, na.rm = T) == CBS_SOY["oil", "other"]


# seed use --------------------------------------------------------------------------------

# share of seed use in total soybean production (or supply)
seed_use_share <- CBS_SOY["bean", "seed"] / sum(SOY_MUN$prod_bean, na.rm = TRUE) #  or /CBS_SOY["production", "soybean"]  
# seed_use_share_supp <- CBS_SOY["seed", "soybean"] / CBS_SOY["Domestic supply quantity", "soybean"] 	

# calculate MU totals:
# seed use (proxy: soybean production)
SOY_MUN$seed_bean <- SOY_MUN$prod_bean*seed_use_share
sum(SOY_MUN$seed_bean, na.rm = T) == CBS_SOY["bean", "seed"]


# stock addition --------------------------------------------------------------------------

# stock addition (proxy: grain storage capacity)
store_cap_tot <- sum(SOY_MUN$storage_cap, na.rm = T) # total storage capacity
SOY_MUN$stock_bean <- (SOY_MUN$storage_cap/store_cap_tot)*CBS_SOY["bean","stock_addition"]
sum(SOY_MUN$stock_bean, na.rm = T) == CBS_SOY["bean", "stock_addition"]


# append results to GEO MUN file -----------------------------------------------------------

newcols <- SOY_MUN %>% dplyr::select(c(co_mun, proc_bean:stock_bean)) 
GEO_MUN_SOY <- GEO_MUN_SOY %>% left_join(newcols, by = "co_mun")

# write to file
if (write){
  saveRDS(SOY_MUN, file = "results/intermediate/SOY_MUN_01.rds")
  saveRDS(GEO_MUN_SOY, file = "results/intermediate/GEO_MUN_SOY_01.rds")
  # st_write(GEO_MUN_SOY, "results/intermediate/GEO_MUN_SOY.gpkg", driver = "GPKG", overwrite=TRUE, delete_dsn=TRUE)
}

rm(list=ls())
gc()

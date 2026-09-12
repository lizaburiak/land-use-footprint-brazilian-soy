##### Generate benchmarks for sub-national supply chain results: TRASE & pure downscaling #####

library(dplyr)
library(data.table)
library(tidyr)
library(stringr)
library(purrr)
library(sf)
library(gmodels)
library(Metrics)
library(xtable)


write = TRUE

options(scipen = 9999)

# load function library
source("code/old/00_function_library.R")


# load data ----------

SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
EXP_MUN_SOY <- readRDS("results/intermediate/EXP_MUN_SOY.rds") # exports before re-balancing according to cbs
EXP_MUN_SOY_cbs <- readRDS("results/intermediate/EXP_MUN_SOY_cbs.rds") # after balancing
CBS_SOY <- readRDS("results/intermediate/CBS_SOY_bal.rds")

# trase data for Brazilian soy
trase <- read.csv("data/old/BRAZIL_SOY_2.5.1_TRASE.csv", stringsAsFactors = FALSE)
# country name ISO correspondence
trase_names <- read.csv2("data/old/trase_names.csv", fileEncoding="UTF-8-BOM", stringsAsFactors = FALSE)

# model results for source-to-importer flows
# from subnational mean flows
source_to_export_mean <- readRDS("results/intermediate/source_to_export_mean.rds")
# separate by simulation
source_to_export_list <- readRDS("results/intermediate/source_to_export_list.rds")
source_to_export_list <- source_to_export_list[-1]
source_to_export_list <- c(source_to_export_mean,source_to_export_list)
##

regions <- readRDS("results/intermediate/regions.rds")
regions_btd <- distinct(regions, CO_BTD, ISO_BTD) %>% arrange(CO_BTD) 


# create additional benchmark: pure downscaling of exports to producing municipalities  ------------

# aggregate exports by product
EXP_NAT <-  EXP_MUN_SOY_cbs %>% 
  group_by(product, to_name) %>% 
  summarise(export = sum(export, na.rm = TRUE)) %>%
  mutate(product = c("bean", "oil", "cake")[match(product,c("soybean", "soy_oil", "soy_cake"))])
# add domestic consumption
EXP_DOM <- data.frame(product = c("bean", "oil", "cake"), to_name = "BRA", export = c(
  sum(SOY_MUN$domestic_use_bean - SOY_MUN$proc_bean),
  sum(SOY_MUN$domestic_use_oil),
  sum(SOY_MUN$domestic_use_cake)
),stringsAsFactors = FALSE)
EXP_NAT <- bind_rows(EXP_NAT, EXP_DOM)
EXP_NAT_wide = pivot_wider(EXP_NAT, id_cols = to_name, names_from = product, values_from = export, values_fill = 0)


# scale export flows down to municipalities according to their share of their production in total national supply
source_shares <- mutate(SOY_MUN,
                  source_share_bean = prod_bean/sum(total_supply_bean),
                  # for oil and cake, assume that the processing use of each processing MU is itself downscaled to all bean-producing MUs 
                  # plus, we have to consider oil/cake imports by assuming that they are also proportionally passed on to all uses
                  source_share_oil  = prod_bean/sum(total_supply_bean)*sum(prod_oil)/sum(total_supply_oil), #prod_share_cake = prod_cake/sum(total_supply_cake),
                  source_share_cake = prod_bean/sum(total_supply_bean)*sum(prod_cake)/sum(total_supply_cake)  # prod_share_oil  = prod_oil /sum(total_supply_oil )*sum(prod_oil)/sum(total_supply_oil)
                  ) %>%
  dplyr::select(c(co_mun, starts_with("source_share")))  %>%
  pivot_longer(cols = starts_with(c("source_share")), names_to = c(".value", "product"), names_pattern = "(.+)_(.+$)")  #cols = prod_bean:domestic_use_cake
  
# create table containing all combinations of MU,product & destination
downscale <- expand.grid(co_mun = SOY_MUN$co_mun, product = c("bean", "oil", "cake"), to_name = EXP_NAT_wide$to_name) #a <- kronecker(EXP_NAT_wide$bean, SOY_MUN$prod_share_bean)
# add source shares per product and MU
downscale <- left_join(downscale, source_shares)
# add national exports per product and destination
downscale <- left_join(downscale, EXP_NAT)
# downscale national exports to source MU via source shares
downscale <- mutate(downscale, export = export*source_share) %>%
  filter(export != 0) 

# transform oil/cake flows into bean equivalents
# NOTE: we need to use OUR OWN equivalence factor here, 
#  which comes from the national average conversion factor from soybean to cake and oil according to FAO CBS! (see script 01_consumption_and_processing)
# for reference: conversion factor used by trase = 1.031
(equi_fact <- (CBS_SOY["bean", "processing"])/(CBS_SOY["cake", "production"] + CBS_SOY["oil", "production"]))
downscale <- mutate(downscale, export = ifelse(product == "bean", export, export*equi_fact))  %>%
  group_by(co_mun, to_name) %>% 
  summarise(downscale = sum(export))


# prepare TRASE data ----------------------------------------------

# add ISO codes to trase flows
trase <- left_join(trase, trase_names, by = "COUNTRY") %>% 
  relocate(ISOA3, .after = COUNTRY)

# remove columns not needed
trase_mun <- trase %>% 
  dplyr::select(STATE, MUNICIPALITY, COUNTRY, ISOA3, 
                ECONOMIC.BLOC, SOY_EQUIVALENT_TONNES, 
                TRASE_GEOCODE, LAND_USE_HA) %>% 
  rename("nm_state" = "STATE", 
         "nm_mun" = "MUNICIPALITY", 
         "nm_dest" = "COUNTRY", 
         "co_dest" = "ISOA3", 
         "gr_dest" = "ECONOMIC.BLOC", 
         "exp_tot" = "SOY_EQUIVALENT_TONNES", 
         "co_mun_trase" = "TRASE_GEOCODE", 
         "landuse" = "LAND_USE_HA") %>%
  mutate(co_mun_trase = as.numeric(substr(co_mun_trase, 4, nchar(co_mun_trase)))) %>% 
  replace_na(list(co_mun_trase = 9999999)) %>%
  relocate(co_mun_trase, .before=nm_mun)

# aggregate destination countries that belong to ROW in FABIO
iso_to_btd <- unique(dplyr::select(regions, CO_PAIS_ISOA3, ISO_BTD)) # BE CARFUL TO USE UNIQUE HERE to avoid duplications!!
trase_mun <- trase_mun %>% 
  left_join(iso_to_btd, by = c("co_dest" = "CO_PAIS_ISOA3")) %>%
  relocate(ISO_BTD, .after = co_dest) %>% 
  rename(to_code = ISO_BTD)

trase_mun <- trase_mun %>% 
  group_by(nm_state, co_mun_trase, nm_mun, to_code) %>% 
  summarise(exp_tot = sum(exp_tot, na.rm = TRUE), 
            landuse = sum(landuse, na.rm = TRUE), 
            .groups = "drop")


# check if MU codes from trase match IBGE codes from SOY_MUN
mun_code_comp <- dplyr::select(trase_mun, co_mun_trase, nm_mun) %>% 
  distinct(co_mun_trase, nm_mun) %>%
  left_join(dplyr::select(SOY_MUN, co_mun, nm_mun), by= c("co_mun_trase" = "co_mun")) %>%
  mutate(nm_mun.x = iconv(nm_mun.x, from = 'UTF-8', to = 'ASCII//TRANSLIT'), 
         nm_mun.y = iconv(nm_mun.y, from = 'UTF-8', to = 'ASCII//TRANSLIT')) %>% 
  mutate(check = nm_mun.x==nm_mun.y) 
# --> looks good! only spelling differences

trase_mun <- trase_mun %>% 
  rename(co_mun = co_mun_trase) %>%
  rename(trase = exp_tot) #%>% left_join(select(SOY_MUN, c(co_mun, co_state)), by = "co_mun") %>% relocate(co_state, .before = nm_state)



# match TRASE and downscaling with model results -----------------------------------------------------------

# translate flows of oil and cake into soybean equivalents and aggregate
results_list <- sapply(names(source_to_export_list), function(fl){
  results_mun_agg <- as.data.table(source_to_export_list[[fl]])  
  results_mun_agg[item_code != "bean", value := value*equi_fact] 
  results_mun_agg <- results_mun_agg[, list(value = sum(value)), by = c("from_code", "to_code")]
  results_mun_agg[, from_code := as.numeric(from_code)]
  setnames(results_mun_agg, c("from_code", "value"), c("co_mun", str_c(fl)))
}, USE.NAMES = TRUE, simplify = FALSE)


# join results of different models into a dataframe
results_df <- results_list %>% 
  reduce(full_join, by = c("co_mun", "to_code")) 

# join trase data with own results and downscaling
comp_mun <- trase_mun %>% 
  full_join(downscale, by = c("co_mun", "to_code" = "to_name")) %>%
  full_join(results_df, by = c("co_mun", "to_code")) 

  
# add state codes and missing names from join
comp_mun <- comp_mun %>% 
  dplyr::select(-c(nm_mun, nm_state)) %>% 
  left_join(SOY_MUN[,1:4], by = "co_mun") %>%
  relocate(nm_mun, .after = co_mun) %>% 
  relocate(c(co_state, nm_state), .before = co_mun)

# add state codes from SOY_MUN (redundant)
# comp_mun <- comp_mun %>% left_join(dplyr::select(SOY_MUN, c(co_mun, co_state)), by = "co_mun") %>% relocate(co_state, .before = nm_state)

# change NAs to zero
#comp_mun <- comp_mun %>% replace_na(list(trase = 0, own = 0))
comp_mun[,6:ncol(comp_mun)][is.na(comp_mun[,6:ncol(comp_mun)])] <- 0

# add country name and region from FABIO
regions_btd <- filter(regions, ISO_BTD != "ROW", btd == TRUE) %>% 
  dplyr::select(c(CO_BTD, ISO_BTD, name, region)) %>% 
  distinct(CO_BTD, ISO_BTD, region, .keep_all = TRUE)
EU <- c("AUT", "BGR", "DNK", "FIN", "FRA", "DEU", "GRC", "HUN", "HRV", "IRL", "ITA", "MLT", "NLD", "CZE", "POL", "PRT", "ROU", "SVN", "SVK", "ESP", "SWE", "GBR", "BEL", "LUX", "LVA", "LTU", "EST", "CYP")
regions_btd <- regions_btd %>% mutate(region = ifelse(ISO_BTD %in% EU, "EU", region))
comp_mun <- comp_mun %>% 
  left_join(dplyr::select(regions_btd, c(ISO_BTD, name, region)), by = c("to_code" = "ISO_BTD")) %>%
  rename(to_name = name, to_region = region) %>% 
  relocate(to_name, to_region, .after = to_code) %>%
  # separate China as distinct region
  mutate(to_region = ifelse(to_code == "CHN", "China", to_region)) %>%
  mutate(to_region = ifelse(to_code == "ROW", "ROW", to_region), to_name= ifelse(to_code == "ROW", "ROW", to_name)) %>%
  mutate(to_region = ifelse(to_code == "BRA", "Brazil", to_region))

# drop trase land-use (optional)
comp_mun <- dplyr::select(comp_mun, -landuse)

# add name for unknown origin
comp_mun <- comp_mun %>% 
  mutate(co_state = ifelse(is.na(co_state), 99, co_state), 
         nm_state = ifelse(is.na(nm_state), "UNKNOWN", nm_state), 
         nm_mun = ifelse(is.na(nm_mun), "UNKNOWN", nm_mun))

comp_mun <- as.data.table(comp_mun)
setkey(comp_mun, co_state, to_code)

# aggregate by state
comp_state <- comp_mun[, lapply(.SD, sum, na.rm=TRUE), 
                       by =.(co_state, nm_state, to_code, to_region), 
                       .SDcols=c("trase", "downscale", names(results_list))]

# aggregate by destination region
comp_mun_by_region <- comp_mun[, lapply(.SD, sum, na.rm=TRUE), 
                       by =.(co_mun, nm_mun, co_state, nm_state, to_region), 
                       .SDcols=c("trase", "downscale", names(results_list))]

# aggregate by state and destination region
comp_state_by_region <- comp_state[, lapply(.SD, sum, na.rm=TRUE), 
                               by =.(co_state, nm_state, to_region), 
                               .SDcols=c("trase", "downscale", names(results_list))]


# put all comparison levels in a list
comp_list <- list("mun" = comp_mun, "state" = comp_state, "mun_by_region" = comp_mun_by_region, "state_by_region" = comp_state_by_region)


## replace full set of simulation results by mean and other key statistics -------------------------------------------------------------

comp_list <- lapply(comp_list, function(comp){

  # detach simulations from main table
  comp_sim <- comp[,which(colnames(comp) == "00001"):ncol(comp)]
  comp <- comp[,1:(which(colnames(comp) == "00001")-1)]
  
  # add mean, standard deviation, min/max and coefficient of variation across simulations
  comp <- comp %>% mutate(mean = apply(as.matrix(comp_sim), 1, mean),
                                  min = apply(as.matrix(comp_sim), 1, min),
                                  max = apply(as.matrix(comp_sim), 1, max),
                                  sd = apply(as.matrix(comp_sim), 1, sd)
                                  ) %>%
                          mutate(cv = sd/mean,
                                 .after = max) %>%
                          replace_na(list(cv = 0))
  
  # compute confidence intervals
  comp_ci95 <- ci_funct(comp_sim, level = 95, stats = c("lower", "upper"))
  comp_ci99 <- ci_funct(comp_sim, level = 99, stats = c("lower", "upper"))
  # add CIs
  comp <- cbind(comp, comp_ci95, comp_ci99) %>% 
    relocate(lower95:upper99, .after = sd)
  
  # check if trase falls within Ci ranges
  comp <- comp %>% mutate(trase_inrangemax = (trase >= min & trase <= max),
                                  trase_inrange95 = (trase >= lower95 & trase <= upper95),
                                  trase_inrange99 = (trase >= lower99 & trase <= upper99), 
                                  .after = upper99)
  
  # compute difference statistics (exploratory)
  comp <- comp %>% 
    mutate(across(c(mean, euclid, downscale), 
                  .fns = list(diff = ~ .-trase, sle = ~ sle(trase,.), ape = ~ ape(trase,.)), 
                  .names = "{.fn}_{.col}")) 
    
return(comp)

})



# data check 1: compare total exports by destination -------------------------------------------------------

# select results to compare
res <- c("trase", "downscale", "euclid", "multimode_mean", "mean")

exp_by_dest <- dplyr::select(comp_list$mun, c(co_state:trase, downscale:mean)) %>% 
  group_by(to_code, to_name, to_region) %>% 
  summarise(across(all_of(res), sum, na.rm = TRUE), .groups = "drop") #summarise(across(c("trase", names(results_list)), sum, na.rm = TRUE), .groups = "drop")  #summarise(across(c(trase:mean), sum, na.rm = TRUE), .groups = "drop")
# add comex export values (post-balancing)
#exp_nat <- EXP_NAT %>% 
#  mutate(export = ifelse(product != "bean", export*equi_fact, export)) %>%
#  group_by(to_name) %>% 
#  summarise(comex = sum(export, na.rm = TRUE))
exp_nat <- EXP_NAT_wide %>%  mutate(comex = bean + equi_fact*(oil + cake))
exp_by_dest <- full_join(exp_by_dest,exp_nat, by = c("to_code" = "to_name")) 

# differences
exp_by_dest <- exp_by_dest %>% mutate(across(c(downscale:mean), 
                             .fns = list(diff_trase = ~ abs(.-trase),
                                         diff_comex = ~ abs(.-comex)), 
                             .names = "{.fn}_{.col}")) 

exp_by_dest_region <- exp_by_dest %>% 
  group_by(to_region) %>% 
  summarise(across(all_of(res), sum, na.rm = TRUE), .groups = "drop") #summarise(across(c("trase", names(results_list), "export"), sum, na.rm = TRUE), .groups = "drop")

# total export sums
# NOTE: export differences between our models can arise due differences in the allocation of imported soy
(exp_total <- sapply(filter(exp_by_dest, to_code != "BRA")%>%dplyr::select(c(trase:mean, comex, starts_with("diff_"))), sum, na.rm = TRUE)) # exp_total <- colSums(filter(exp_by_dest, to_code != "BRA") %>% select(c(all_of(res), "comex")), na.rm = TRUE)
(flow_total <- sapply(dplyr::select(exp_by_dest, c(trase:mean, comex, starts_with("diff_"))), sum, na.rm = TRUE)) # exp_total <- colSums(filter(exp_by_dest, to_code != "BRA") %>% select(c(all_of(res), "comex")), na.rm = TRUE)

# add total exports in trase and comex exports separate by product
trase_exp_known <- trase_mun %>% filter(co_mun != 9999999) %>% group_by(to_code) %>% summarise(trase_known = sum(trase))
exp_summary <- exp_by_dest %>% dplyr::select(c(to_code:trase, comex, euclid, multimode_mean, cake:bean)) %>% 
  left_join(trase_exp_known) 
 
exp_summary <- exp_summary %>% dplyr::select(to_code, to_name, trase, trase_known, euclid, multimode_mean, comex, bean, oil, cake)
exp_summary[is.na(exp_summary)] <- 0
exp_summary <- arrange(exp_summary, desc(comex))
exp_summary <- mutate(exp_summary, across(trase:cake, function(x){x/1000})) # to kilotons

# add totals in bottom row
exp_summary <- rbind(exp_summary, "Total" = c(NA, NA, colSums(exp_summary[,3:ncol(exp_summary)])))

print(xtable(exp_summary, caption = "Eport summary",digits = 3), 
      file = "results/tables/export_summary_sorted.tex",
      include.rownames=FALSE)

# data check 2: compare total flows by MU to production ------------------------------------------------------------

comp_mun_total <- comp_list$mun %>% 
  dplyr::select(c(co_state:trase, downscale:mean)) %>%
  group_by(co_state, nm_state, co_mun, nm_mun) %>% 
  summarise(across(c(trase, downscale:mean), sum, na.rm = TRUE), .groups = "drop") #summarise(across(c("trase", names(results_list)), sum, na.rm = TRUE), .groups = "drop")

# add soy production
comp_mun_total <- full_join(comp_mun_total, 
                            dplyr::select(SOY_MUN, c(co_mun, prod_bean)), 
                            by = "co_mun") # prod_oil, prod_cake
# add missing names
comp_mun_total <- comp_mun_total %>% 
  dplyr::select(-c(nm_mun, co_state, nm_state)) %>% 
  left_join(SOY_MUN[,1:4], by = "co_mun") %>%
  relocate(nm_mun, .after = co_mun) %>% 
  relocate(c(co_state, nm_state), .before = co_mun) %>%
  mutate(co_state = ifelse(is.na(co_state), 99, co_state), 
         nm_state = ifelse(is.na(nm_state), "UNKNOWN", nm_state), 
         nm_mun = ifelse(is.na(nm_mun), "UNKNOWN", nm_mun))

# change NA to zero
comp_mun_total <- comp_mun_total %>% 
  mutate(across(trase:prod_bean, ~replace_na(.x, 0)))

# add columns for differences to production
comp_mun_total <- comp_mun_total %>% 
  mutate(across(c(trase, downscale:mean), 
                .fns = list(diff_trase = ~ .-trase,
                            diff_prod = ~.-prod_bean)))

#### write results --------------------------------------------------


if (write){
  saveRDS(comp_list, "results/intermediate/comp_list.rds")
  saveRDS(EXP_NAT_wide, "results/intermediate/EXP_NAT_wide.rds")
}


rm(list = ls())
gc()


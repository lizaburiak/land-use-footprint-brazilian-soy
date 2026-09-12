
###### Harmonize municipality exports and imports with FAO bilateral trade data for 2013 ############

library(dplyr)
library(tidyr)
library(janitor)
library(openxlsx)
library(raster)
library(sf)

write <- TRUE

# load data ------------------------------------------------------------------------------------

EXP_MUN_SOY <- readRDS("results/intermediate/EXP_MUN_SOY_00.rds")
IMP_MUN_SOY <- readRDS("results/intermediate/IMP_MUN_SOY_00.rds")

soy_items <- c(2555, 2571, 2590)
btd_imp <- readRDS("data/old/FABIO/btd_bal.rds") %>% 
   filter(year == 2013, item_code %in% soy_items)
btd_exp <- readRDS("data/old/FABIO/FABIO_exp/v1/btd_bal.rds") %>% 
   filter(year == 2013, item_code %in% soy_items)
btd_exp_pure <- readRDS("data/old/FABIO/FABIO_exp/pure/btd_bal.rds") %>% 
   filter(year == 2013, item_code %in% soy_items)
cbs <- readRDS("data/old/FABIO/FABIO_exp/v1/cbs_full.rds")
trade_mat <- read.csv("data/old/FABIO/FAOSTAT_tradematrix_BRAsoy.csv", stringsAsFactors = FALSE)


# countries contained in COMEX
COMEX_regions <- read.csv2(file = "data/old/PAIS_COMEX.csv", header = TRUE, stringsAsFactors = F, fileEncoding = "ISO-8859-1")
# full sample of countries contained in FAO
FAO_regions <- read.csv(file = "data/old/FABIO/FAO_regions_full.csv", stringsAsFactors = F)
# countries contained in FABIO
FABIO_regions <- openxlsx::read.xlsx("data/old/FABIO/FABIO_regions.xlsx", colNames = TRUE)
#load("results/intermediate/FAO_areas.RData")


# harmonize country sample and codes of COMEX and FAO -------------------------------------------------------

### match COMEX country codes/names with FAO system used in FABIO

# set "ZZZ" region ISOA3 code from COMEX to "ROW" as used in FAO
COMEX_regions$CO_PAIS_ISOA3[COMEX_regions$CO_PAIS_ISOA3 == "ZZZ"] <- "ROW"
COMEX_regions$CO_PAIS_ISON3[COMEX_regions$CO_PAIS_ISON3 == 898] <- 999

# the FAO regions table contains duplicates of countries, but with different ISO codes: 
# detect them and remove the ones not used in FABIO
FAO_regions_dup <- FAO_regions %>% get_dupes(iso3c)
# remove codes 351 (China), 62 (Ethiopia PDR) and 206 (Sudan, former) 
FAO_regions <- filter(FAO_regions, !code %in% c(351,62,206))

# match COMEX with FAO by ISO3 code
regions <- full_join(COMEX_regions, FAO_regions, by = c("CO_PAIS_ISOA3" = "iso3c")) 
# unmatched regions (small islands etc.) can be assigned to ROW 
regions$code[is.na(regions$code)] <- 999

# rename "code" into "CO_FAO" and "CO_PAIS" into "CO_COMEX"
regions <- regions %>% 
   rename("CO_FAO" = "code", "CO_COMEX" = "CO_PAIS") %>% 
   relocate (CO_FAO, .after = CO_COMEX)

# create separate column with FAO code, 
# but setting it to the ROW code in case the region is not part of the BTD and therefore FABIO
btd_regions <- unique(btd_exp$from_code)
all.equal(FABIO_regions$FAO.Code, btd_regions)
regions <- regions %>% 
   mutate(btd = ifelse(CO_FAO %in% btd_regions, TRUE, FALSE)) %>% 
   mutate(CO_BTD = ifelse(btd == TRUE, CO_FAO, 999)) %>% 
   relocate (CO_BTD, .after = CO_FAO) 
regions <- regions %>% 
   mutate(ISO_BTD = ifelse(CO_BTD == 999, "ROW", CO_PAIS_ISOA3)) %>% 
   relocate(ISO_BTD, .after = CO_BTD)
# special cases: French Guiana, Guadeloupe, Martinique and Réunion are part of the French customs area from 1996 
regions <- regions %>% 
   mutate(ISO_BTD = ifelse(CO_PAIS_ISOA3 %in% c("GLP", "GUF", "MTQ", "REU"), "FRA", ISO_BTD), 
                              CO_BTD = ifelse(CO_PAIS_ISOA3 %in% c("GLP", "GUF", "MTQ", "REU"), 68, CO_BTD))
# also: Curacao belongs to Netherlands Antilles in FAO, but is not relevant here

# extract relevant COMEX country codes from municipality soy trade data (--> get rid of irrelevant countries)
#COMEX_codes_rel <- unique(c(EXP_MUN_SOY$co_destin, IMP_MUN_SOY$co_origin))
#regions_rel <- filter(regions, CO_PAIS %in% COMEX_codes_rel)


# harmonize MU trade data with FABIO format & country sample ----------------------------------------

### aggregate exports/imports to/from FABIO ROW countries

# add btd country codes
EXP_MUN_SOY <- EXP_MUN_SOY %>% left_join(regions[,c(1,3:4)], by = c("co_destin" = "CO_COMEX")) %>% 
   rename("to_code" = "CO_BTD", "to_name" = "ISO_BTD") %>% relocate(to_code:to_name, .after = nm_destin)
IMP_MUN_SOY <- IMP_MUN_SOY %>% left_join(regions[,c(1,3:4)], by = c("co_origin" = "CO_COMEX")) %>% 
   rename("from_code" = "CO_BTD", "from_name" = "ISO_BTD") %>% relocate(from_code:from_name, .after = nm_origin)

# aggregate destination/origin countries to match FABIO btd regions
EXP_MUN_SOY <- EXP_MUN_SOY %>% 
   group_by(across(c(-export, - export_dol, - co_destin, - nm_destin))) %>% 
   summarise(export = sum(export, na.rm = TRUE), export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>% 
   ungroup() 

IMP_MUN_SOY <- IMP_MUN_SOY %>% 
   group_by(across(c(-import, - import_dol, - co_origin, - nm_origin))) %>% 
   summarise(import = sum(import, na.rm = TRUE), import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>% 
   ungroup() 


# compare aggregate MU trade values with FAO BTD ------------------------------------------------

# filter soy products trade of Brazil from btd
# soybeans (2555), soybean oil (2571), soybean cake (2590)
btd_exp_BRA_soy_exp <- filter(btd_exp, from_code == 21, item_code %in% c(2555, 2571, 2590))
btd_imp_BRA_soy_exp <- filter(btd_exp, to_code == 21, item_code %in% c(2555, 2571, 2590))

btd_exp_BRA_soy_pure <- filter(btd_exp_pure, from_code == 21, item_code %in% c(2555, 2571, 2590))
btd_imp_BRA_soy_pure <- filter(btd_exp_pure, to_code == 21, item_code %in% c(2555, 2571, 2590))

btd_exp_BRA_soy_imp <- filter(btd_imp, from_code == 21, item_code %in% c(2555, 2571, 2590))
btd_imp_BRA_soy_imp <- filter(btd_imp, to_code == 21, item_code %in% c(2555, 2571, 2590))

rm(btd_imp,btd_exp_pure,btd_exp)

# add item codes to comex MU trade data
EXP_MUN_SOY <- EXP_MUN_SOY %>% 
   mutate (item_code = ifelse(product == "soybean", 2555, ifelse(product == "soy_oil", 2571, 2590))) %>% 
   relocate(item_code, .after = product)
IMP_MUN_SOY <- IMP_MUN_SOY %>% 
   mutate (item_code = ifelse(product == "soybean", 2555, ifelse(product == "soy_oil", 2571, 2590))) %>% 
   relocate(item_code, .after = product)


# aggregate municipality trade to national values
EXP_NAT_SOY <- EXP_MUN_SOY %>% 
   group_by(product, item_code, to_code, to_name) %>% 
   summarise(export = sum(export, na.rm = TRUE), export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>% 
   ungroup() 

IMP_NAT_SOY <- IMP_MUN_SOY %>% 
   group_by(product, item_code, from_code, from_name) %>% 
   summarise(import = sum(import, na.rm = TRUE), import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>% 
   ungroup() 

# merge comex with corresponding BTD trade data
EXP_NAT_SOY <- EXP_NAT_SOY %>% 
   full_join(btd_exp_BRA_soy_exp[,c(2,4:5)], by = c("item_code" = "item_code", "to_code" = "to_code")) %>% 
   rename("export_btd_exp" = "value")
EXP_NAT_SOY <- EXP_NAT_SOY %>% 
   full_join(btd_exp_BRA_soy_pure[,c(2,4:5)], by = c("item_code" = "item_code", "to_code" = "to_code")) %>% 
   rename("export_btd_exp_pure" = "value")
EXP_NAT_SOY <- EXP_NAT_SOY %>% 
   full_join(btd_exp_BRA_soy_imp[,c(2,4:5)], by = c("item_code" = "item_code", "to_code" = "to_code")) %>% 
   rename("export_btd_imp" = "value")

IMP_NAT_SOY <- IMP_NAT_SOY %>% 
   full_join(btd_imp_BRA_soy_exp[,c(2:3,5)], by = c("item_code" = "item_code", "from_code" = "from_code")) %>% 
   rename("import_btd_exp" = "value")
IMP_NAT_SOY <- IMP_NAT_SOY %>% 
   full_join(btd_imp_BRA_soy_pure[,c(2:3,5)], by = c("item_code" = "item_code", "from_code" = "from_code")) %>% 
   rename("import_btd_ex_pure" = "value")
IMP_NAT_SOY <- IMP_NAT_SOY %>% 
   full_join(btd_imp_BRA_soy_imp[,c(2:3,5)], by = c("item_code" = "item_code", "from_code" = "from_code")) %>% 
   rename("import_btd_imp" = "value")

# add product names for trade that was not registered in comex 
EXP_NAT_SOY <- mutate(EXP_NAT_SOY, product = ifelse(item_code == 2555, "soybean", ifelse(item_code == 2571, "soy_oil", "soy_cake")))
IMP_NAT_SOY <- mutate(IMP_NAT_SOY , product = ifelse(item_code == 2555, "soybean", ifelse(item_code == 2571, "soy_oil", "soy_cake")))

# add country codes names to trade that was not registered in comex
EXP_NAT_SOY <- EXP_NAT_SOY %>% left_join(FABIO_regions[,c(1,3)], by = c("to_code" = "FAO.Code")) %>% 
   mutate(to_name = ISO) %>% 
   dplyr::select(!ISO)
IMP_NAT_SOY <- IMP_NAT_SOY %>% left_join(FABIO_regions[,c(1,3)], by = c("from_code" = "FAO.Code")) %>% 
   mutate(from_name = ISO) %>% 
   dplyr::select(!ISO)

# add values from FAO trade matrix
trade_mat <- mutate(trade_mat, product = ifelse(Item.Code == 236, "soybean", ifelse(Item.Code == 237, "soy_oil", ifelse(Item.Code == 238, "soy_cake", "other")))) %>% 
   filter(product != "other")
trade_mat <- trade_mat %>% 
   rename("to_name" = "Partner.Country.Code..ISO3.", "FAO_trade_mat" = "Value") %>% 
   dplyr::select(c(to_name, product, FAO_trade_mat)) %>% 
   mutate(to_name = ifelse(to_name == "41", "CHN", to_name))
trade_mat <- trade_mat %>% 
   left_join(distinct(dplyr::select(regions,c(ISO_BTD, CO_PAIS_ISOA3)) %>% 
                         rename(to_name = CO_PAIS_ISOA3)), by = ("to_name"))
trade_mat_agg <- group_by(trade_mat, ISO_BTD, product) %>% 
   summarise(FAO_trade_mat = sum(FAO_trade_mat, na.rm = TRUE), .groups = "drop") %>% 
   rename(to_name = ISO_BTD)
EXP_NAT_SOY <- full_join(EXP_NAT_SOY, trade_mat_agg, by = c("product", "to_name"))

# replace NAs
EXP_NAT_SOY <-  EXP_NAT_SOY %>% mutate(across(where(is.numeric), ~replace_na(.x, 0)))
IMP_NAT_SOY <-  IMP_NAT_SOY %>% mutate(across(where(is.numeric), ~replace_na(.x, 0)))

# check differences between FAO trade matrix and comex
EXP_NAT_SOY <- mutate(EXP_NAT_SOY, comex_fao_diff = export - FAO_trade_mat)


# EXP_NAT_SOY = EXP_NAT_SOY %>% rename("to_code" = "co_btd", "to_name" = "nm_btd" )

# check overall consistency of trade sums
colSums(EXP_NAT_SOY[,c(5:ncol(EXP_NAT_SOY))], na.rm = TRUE)
colSums(IMP_NAT_SOY[,c(5:ncol(IMP_NAT_SOY))], na.rm = TRUE)


# check country sums by product
EXP_SOY <- EXP_NAT_SOY %>% 
   group_by(product) %>% 
   summarise(across(starts_with('export'), .fns = sum, na.rm = TRUE))

IMP_SOY <- IMP_NAT_SOY %>% 
   group_by(product) %>% 
   summarise(across(starts_with('import'), .fns = sum, na.rm = TRUE))


# # overwrite btd data with comex values
# NOTE: this is done later in th _re-exports
# EXP_NAT_SOY <- arrange(EXP_NAT_SOY, item_code,to_code )
# EXP_NAT_SOY_btd <- dplyr::select(EXP_NAT_SOY, c(item_code, to_code, export)) %>% 
#    mutate(year = 2013, .before = item_code) %>% mutate(from_code = 21, .before = to_code) %>%
#    rename(value = export)
# 

# export data --------------------------------------

if (write){
  
  # export data 
   saveRDS(EXP_MUN_SOY, file = "results/intermediate/EXP_MUN_SOY.rds") # consider renaming to "_harm" or the likes
   saveRDS(IMP_MUN_SOY, file = "results/intermediate/IMP_MUN_SOY.rds")
   saveRDS(EXP_NAT_SOY, file = "results/intermediate/EXP_NAT_SOY.rds")
   saveRDS(IMP_NAT_SOY, file = "results/intermediate/IMP_NAT_SOY.rds")
   saveRDS(regions, file = "results/intermediate/regions.rds")
   write.csv2(regions, file = "results/intermediate/regions.csv")
   saveRDS(btd_exp_BRA_soy_exp, file = "results/intermediate/btd_exp_BRA_soy.rds")
   saveRDS(btd_exp_BRA_soy_exp, file = "results/intermediate/btd_imp_BRA_soy.rds")
  
}

# clear environment
rm(list = ls())
gc()
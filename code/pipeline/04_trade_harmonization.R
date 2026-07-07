
###### Harmonize municipality exports and imports with FAO bilateral trade data ##############

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(dplyr)
library(tidyr)
library(janitor)
library(openxlsx)
library(raster)
library(sf)

write <- TRUE

# load data ------------------------------------------------------------------------------------

EXP_MUN_SOY <- readRDS(paste0("data/generated/outputs/00_", YEAR, "/EXP_MUN_SOY_00.rds"))
IMP_MUN_SOY <- readRDS(paste0("data/generated/outputs/00_", YEAR, "/IMP_MUN_SOY_00.rds"))

soy_items <- c(2555, 2571, 2590)

# btd_imp (import-side bilateral trade):
#   Stefan's btd_bal.rds covers 1986-2013; the new multi-year file covers 2010-2023.
#   Use the version Stefan used for the years he covered (<= 2013), the new file for 2014+.
.stefan_btd <- "data/fabio/trade/btd_bal.rds"
.new_btd    <- "data/fabio/trade/new/btd_bal.RData"
if (YEAR <= 2013 && file.exists(.stefan_btd)) {
  message("[04] btd_imp: Stefan's btd_bal.rds (1986-2013) for YEAR=", YEAR)
  btd_imp <- readRDS(.stefan_btd) %>%
    filter(year == YEAR, item_code %in% soy_items)
} else if (file.exists(.new_btd)) {
  message("[04] btd_imp: new multi-year btd_bal.RData (2010-2023) for YEAR=", YEAR)
  .e <- new.env(); load(.new_btd, envir = .e)
  btd_imp <- as.data.frame(.e$btd_bal) %>%
    filter(year == YEAR, item_code %in% soy_items)
  rm(.e)
} else {
  btd_imp <- readRDS(.stefan_btd) %>%
    filter(year == YEAR, item_code %in% soy_items)
}
btd_exp <- readRDS("data/fabio/trade/FABIO_exp/v1/btd_bal.rds") %>%
   filter(year == YEAR, item_code %in% soy_items)
btd_exp_pure <- readRDS("data/fabio/trade/FABIO_exp/pure/btd_bal.rds") %>%
   filter(year == YEAR, item_code %in% soy_items)
cbs <- readRDS("data/fabio/trade/FABIO_exp/v1/cbs_full.rds")

# FABIO_exp data only available up to 2013 in Stefan's snapshot; warn if year-extension data not yet provided
if (nrow(btd_exp) == 0 || nrow(btd_exp_pure) == 0) {
  warning(sprintf(
    "FABIO_exp (v1/pure) has no rows for YEAR=%d. Stefan's snapshots cover 1986-2013 only; ",
    YEAR),
    "downstream comparisons against btd_exp/btd_exp_pure will be empty until updated FABIO_exp data is provided.")
}

# trade matrix: prefer year-specific file in data/raw/04/, fall back to Stefan's 2013 file.
# FAOSTAT detailed trade matrices only exist here for 2013-2024; for years <= 2012
# we intentionally use Stefan's 2013 matrix as the structural reference (his vintage).
.tm_year <- paste0("data/raw/04/FAOSTAT_tradematrix_BRAsoy_", YEAR, ".csv")
.tm_path <- if (file.exists(.tm_year)) .tm_year else "data/fabio/trade/FAOSTAT_tradematrix_BRAsoy.csv"
message("[04] trade matrix: ", .tm_path,
        if (!file.exists(.tm_year)) sprintf("  (no %d-specific file; using Stefan's 2013 fallback)", YEAR) else "")
trade_mat <- read.csv(.tm_path, stringsAsFactors = FALSE)


# countries contained in COMEX
COMEX_regions <- read.csv2(file = "data/raw/04/PAIS_COMEX.csv", header = TRUE, stringsAsFactors = F, fileEncoding = "ISO-8859-1")
# full sample of countries contained in FAO
FAO_regions <- read.csv(file = "data/fabio/trade/FAO_regions_full.csv", stringsAsFactors = F)
# countries contained in FABIO
FABIO_regions <- openxlsx::read.xlsx("data/fabio/trade/FABIO_regions.xlsx", colNames = TRUE)


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
# FABIO_exp v1 only covers 1986-2013, so for YEAR >= 2014 btd_exp is empty and every
# destination collapses to ROW. Fall back to FABIO_regions (the authoritative country
# list used by btd_imp / new multi-year FABIO) when the legacy btd_exp is empty.
if (length(btd_regions) == 0) {
  btd_regions <- FABIO_regions$FAO.Code
  message("[04] btd_exp empty for YEAR=", YEAR,
          " — using FABIO_regions$FAO.Code (", length(btd_regions), " countries) as country list.")
}
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


# export data --------------------------------------

if (write){

  out_dir <- paste0("data/generated/outputs/04_", YEAR)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # export data
   saveRDS(EXP_MUN_SOY, file = file.path(out_dir, "EXP_MUN_SOY.rds"))
   saveRDS(IMP_MUN_SOY, file = file.path(out_dir, "IMP_MUN_SOY.rds"))
   saveRDS(EXP_NAT_SOY, file = file.path(out_dir, "EXP_NAT_SOY.rds"))
   saveRDS(IMP_NAT_SOY, file = file.path(out_dir, "IMP_NAT_SOY.rds"))
   saveRDS(regions, file = file.path(out_dir, "regions.rds"))
   write.csv2(regions, file = file.path(out_dir, "regions.csv"))
   saveRDS(btd_exp_BRA_soy_exp, file = file.path(out_dir, "btd_exp_BRA_soy.rds"))
   saveRDS(btd_exp_BRA_soy_exp, file = file.path(out_dir, "btd_imp_BRA_soy.rds"))

}

# clear environment
rm(list = ls())
gc()

##### Generate benchmarks for sub-national supply chain results: TRASE & pure downscaling #####

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

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

out_dir <- paste0("data/generated/outputs/10_", YEAR)
tab_dir <- paste0("results/tables/benchmarks/", YEAR)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

# load function library
source("code/pipeline/00_function_library.R")


# load data ----------

SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
EXP_MUN_SOY <- readRDS(paste0("data/generated/outputs/04_", YEAR, "/EXP_MUN_SOY.rds")) # exports before re-balancing according to cbs
EXP_MUN_SOY_cbs <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/EXP_MUN_SOY_cbs.rds")) # after balancing
CBS_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/CBS_SOY_bal.rds"))

# TRASE loading + schema adapter ----------------------------------------------------------
# Stefan's code was written for TRASE v2.5.1 (UPPERCASE column names).
# trase.earth now publishes v2.6.1 (lowercase columns, no LAND_USE_HA in composite,
# no separate ISO3 column — uses 2-letter trase_ids instead). Detect and remap.
.trase_year <- paste0("data/trase/BRAZIL_SOY_", YEAR, "_TRASE.csv")
.trase_v25  <- "data/trase/BRAZIL_SOY_2.5.1_TRASE.csv"
.trase_v26  <- "data/trase/brazil_soy_v2_6_1_composite.csv"
.trase_path <- if (file.exists(.trase_year)) .trase_year else
               if (file.exists(.trase_v25))  .trase_v25  else
               if (file.exists(.trase_v26))  .trase_v26  else
               stop("No TRASE CSV found. Expected one of: ", paste(c(.trase_year, .trase_v25, .trase_v26), collapse=", "))
trase <- read.csv(.trase_path, stringsAsFactors = FALSE)

if ("country_of_first_import" %in% colnames(trase) && !("COUNTRY" %in% colnames(trase))) {
  # v2.6.1 schema — remap to v2.5.1 conventions Stefan's code expects
  message("Detected TRASE v2.6.1 schema. Remapping columns to v2.5.1 conventions.")
  # Filter to year of interest if multi-year file
  if ("year" %in% colnames(trase) && length(unique(trase$year)) > 1) {
    trase <- trase[as.integer(trase$year) == YEAR, , drop = FALSE]
    message("Filtered TRASE to YEAR=", YEAR, " (", nrow(trase), " rows)")
  }
  # TRASE composite covers 2004-2022. For earlier years there is nothing to
  # benchmark against — skip cleanly (model outputs from steps 00-08 stay valid).
  if (nrow(trase) == 0) {
    message("[10] No TRASE data for YEAR=", YEAR,
            " (composite covers 2004-2022). Skipping benchmark — model outputs are valid.")
    quit(save = "no", status = 0)
  }
  # ISO2 → ISO3 lookup (inline, covers all TRASE destinations as of v2.6.1)
  .iso2to3 <- c(
    BR="BRA", AR="ARG", BO="BOL", CL="CHL", CO="COL", CR="CRI", CU="CUB", DO="DOM", EC="ECU",
    GT="GTM", HN="HND", JM="JAM", MX="MEX", NI="NIC", PA="PAN", PE="PER", PY="PRY", SV="SLV",
    UY="URY", VE="VEN", CA="CAN", US="USA",
    AT="AUT", BE="BEL", BG="BGR", HR="HRV", CY="CYP", CZ="CZE", DK="DNK", EE="EST", FI="FIN",
    FR="FRA", DE="DEU", GR="GRC", HU="HUN", IE="IRL", IT="ITA", LV="LVA", LT="LTU", LU="LUX",
    MT="MLT", NL="NLD", PL="POL", PT="PRT", RO="ROU", SK="SVK", SI="SVN", ES="ESP", SE="SWE",
    GB="GBR", CH="CHE", NO="NOR", IS="ISL", RU="RUS", UA="UKR", BY="BLR", MD="MDA", AL="ALB",
    BA="BIH", MK="MKD", ME="MNE", RS="SRB", TR="TUR",
    DZ="DZA", AO="AGO", BJ="BEN", BW="BWA", BF="BFA", BI="BDI", CM="CMR", CV="CPV", CF="CAF",
    TD="TCD", KM="COM", CG="COG", CD="COD", CI="CIV", DJ="DJI", EG="EGY", GQ="GNQ", ER="ERI",
    ET="ETH", GA="GAB", GM="GMB", GH="GHA", GN="GIN", GW="GNB", KE="KEN", LS="LSO", LR="LBR",
    LY="LBY", MG="MDG", MW="MWI", ML="MLI", MR="MRT", MU="MUS", MA="MAR", MZ="MOZ", "NA"="NAM",
    NE="NER", NG="NGA", RW="RWA", SN="SEN", SC="SYC", SL="SLE", SO="SOM", ZA="ZAF", SS="SSD",
    SD="SDN", SZ="SWZ", TZ="TZA", TG="TGO", TN="TUN", UG="UGA", ZM="ZMB", ZW="ZWE",
    AF="AFG", AM="ARM", AZ="AZE", BH="BHR", BD="BGD", BT="BTN", BN="BRN", KH="KHM", CN="CHN",
    GE="GEO", IN="IND", ID="IDN", IR="IRN", IQ="IRQ", IL="ISR", JP="JPN", JO="JOR", KZ="KAZ",
    KP="PRK", KR="KOR", KW="KWT", KG="KGZ", LA="LAO", LB="LBN", MY="MYS", MV="MDV", MN="MNG",
    MM="MMR", NP="NPL", OM="OMN", PK="PAK", PH="PHL", QA="QAT", SA="SAU", SG="SGP", LK="LKA",
    SY="SYR", TW="TWN", TJ="TJK", TH="THA", TL="TLS", AE="ARE", UZ="UZB", VN="VNM", YE="YEM",
    AU="AUS", FJ="FJI", NZ="NZL", PG="PNG"
  )
  trase$STATE                 <- trase$state
  trase$MUNICIPALITY          <- trase$municipality_of_production
  trase$COUNTRY               <- trase$country_of_first_import
  .iso2                       <- substr(as.character(trase$country_of_first_import_trase_id), 1, 2)
  trase$ISOA3                 <- ifelse(.iso2 %in% names(.iso2to3), .iso2to3[.iso2], NA_character_)
  trase$ECONOMIC.BLOC         <- trase$economic_bloc
  trase$SOY_EQUIVALENT_TONNES <- as.numeric(trase$volume)
  trase$TRASE_GEOCODE         <- trase$municipality_of_production_trase_id
  trase$LAND_USE_HA           <- NA_real_   # not in v2.6.1 composite; dropped downstream anyway
  trase_names <- NULL  # not needed — we built ISOA3 directly from trase_id
} else {
  # v2.5.1 schema — original code path
  trase_names <- read.csv2("data/trase/trase_names.csv", fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
}

# model results for source-to-importer flows
source_to_export_mean <- readRDS(paste0("data/generated/outputs/08_", YEAR, "/source_to_export_mean.rds"))
.list_path <- paste0("data/generated/outputs/08_", YEAR, "/source_to_export_list.rds")
if (file.exists(.list_path)) {
  source_to_export_list <- readRDS(.list_path)
  # drop the leading euclid entry from _list.rds before prepending the _mean version
  if (length(source_to_export_list) > 1) source_to_export_list <- source_to_export_list[-1]
  source_to_export_list <- c(source_to_export_mean, source_to_export_list)
} else {
  message("No source_to_export_list.rds — running benchmark with mean version only.")
  source_to_export_list <- source_to_export_mean
}
# Deduplicate by name (when bootstrap is absent, both _mean and _sep contribute "euclid")
source_to_export_list <- source_to_export_list[!duplicated(names(source_to_export_list))]

regions <- readRDS(paste0("data/generated/outputs/04_", YEAR, "/regions.rds"))
regions_btd <- distinct(regions, CO_BTD, ISO_BTD) %>% arrange(CO_BTD)


# create additional benchmark: pure downscaling of exports to producing municipalities  ------------

EXP_NAT <-  EXP_MUN_SOY_cbs %>%
  group_by(product, to_name) %>%
  summarise(export = sum(export, na.rm = TRUE)) %>%
  mutate(product = c("bean", "oil", "cake")[match(product,c("soybean", "soy_oil", "soy_cake"))])
EXP_DOM <- data.frame(product = c("bean", "oil", "cake"), to_name = "BRA", export = c(
  sum(SOY_MUN$domestic_use_bean - SOY_MUN$proc_bean),
  sum(SOY_MUN$domestic_use_oil),
  sum(SOY_MUN$domestic_use_cake)
),stringsAsFactors = FALSE)
EXP_NAT <- bind_rows(EXP_NAT, EXP_DOM)
# Some years' COMEX include "BRA" as a destination (e.g. 2019 re-imports), which
# would collide with the synthetic EXP_DOM BRA row and produce list-cols in
# pivot_wider. Aggregate duplicates by summing before pivoting.
EXP_NAT <- EXP_NAT %>% group_by(to_name, product) %>% summarise(export = sum(export, na.rm = TRUE), .groups = "drop")
EXP_NAT_wide = pivot_wider(EXP_NAT, id_cols = to_name, names_from = product, values_from = export, values_fill = 0)


source_shares <- mutate(SOY_MUN,
                  # domestic-origin supply = (total_supply - imports): bit-identical to
                  # production/total_supply under use_prop (total_supply = prod + imp), and
                  # counts withdrawal-supplied tonnes as domestic under supply_side, where
                  # total_supply includes |stock| (STOCK_MODE, step 05). See CHANGELOG.
                  source_share_bean = (total_supply_bean - imp_bean)/sum(total_supply_bean),
                  source_share_oil  = (total_supply_bean - imp_bean)/sum(total_supply_bean)*(sum(total_supply_oil)  - sum(imp_oil)) /sum(total_supply_oil),
                  source_share_cake = (total_supply_bean - imp_bean)/sum(total_supply_bean)*(sum(total_supply_cake) - sum(imp_cake))/sum(total_supply_cake)
                  ) %>%
  dplyr::select(c(co_mun, starts_with("source_share")))  %>%
  pivot_longer(cols = starts_with(c("source_share")), names_to = c(".value", "product"), names_pattern = "(.+)_(.+$)")

downscale <- expand.grid(co_mun = SOY_MUN$co_mun, product = c("bean", "oil", "cake"), to_name = EXP_NAT_wide$to_name)
downscale <- left_join(downscale, source_shares)
downscale <- left_join(downscale, EXP_NAT)
downscale <- mutate(downscale, export = export*source_share) %>%
  filter(export != 0)

(equi_fact <- (CBS_SOY["bean", "processing"])/(CBS_SOY["cake", "production"] + CBS_SOY["oil", "production"]))
downscale <- mutate(downscale, export = ifelse(product == "bean", export, export*equi_fact))  %>%
  group_by(co_mun, to_name) %>%
  summarise(downscale = sum(export))


# prepare TRASE data ----------------------------------------------

if (!is.null(trase_names)) {
  # v2.5.1 path — original join
  trase <- left_join(trase, trase_names, by = "COUNTRY") %>%
    relocate(ISOA3, .after = COUNTRY)
}  # v2.6.1: ISOA3 was already populated above from country_of_first_import_trase_id

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

iso_to_btd <- unique(dplyr::select(regions, CO_PAIS_ISOA3, ISO_BTD))
trase_mun <- trase_mun %>%
  left_join(iso_to_btd, by = c("co_dest" = "CO_PAIS_ISOA3")) %>%
  relocate(ISO_BTD, .after = co_dest) %>%
  rename(to_code = ISO_BTD)

trase_mun <- trase_mun %>%
  group_by(nm_state, co_mun_trase, nm_mun, to_code) %>%
  summarise(exp_tot = sum(exp_tot, na.rm = TRUE),
            landuse = sum(landuse, na.rm = TRUE),
            .groups = "drop")


mun_code_comp <- dplyr::select(trase_mun, co_mun_trase, nm_mun) %>%
  distinct(co_mun_trase, nm_mun) %>%
  left_join(dplyr::select(SOY_MUN, co_mun, nm_mun), by= c("co_mun_trase" = "co_mun")) %>%
  mutate(nm_mun.x = iconv(nm_mun.x, from = 'UTF-8', to = 'ASCII//TRANSLIT'),
         nm_mun.y = iconv(nm_mun.y, from = 'UTF-8', to = 'ASCII//TRANSLIT')) %>%
  mutate(check = nm_mun.x==nm_mun.y)

trase_mun <- trase_mun %>%
  rename(co_mun = co_mun_trase) %>%
  rename(trase = exp_tot)



# match TRASE and downscaling with model results -----------------------------------------------------------

results_list <- sapply(names(source_to_export_list), function(fl){
  results_mun_agg <- as.data.table(source_to_export_list[[fl]])
  results_mun_agg[item_code != "bean", value := value*equi_fact]
  results_mun_agg <- results_mun_agg[, list(value = sum(value)), by = c("from_code", "to_code")]
  results_mun_agg[, from_code := as.numeric(from_code)]
  setnames(results_mun_agg, c("from_code", "value"), c("co_mun", str_c(fl)))
}, USE.NAMES = TRUE, simplify = FALSE)


results_df <- results_list %>%
  reduce(full_join, by = c("co_mun", "to_code"))

comp_mun <- trase_mun %>%
  full_join(downscale, by = c("co_mun", "to_code" = "to_name")) %>%
  full_join(results_df, by = c("co_mun", "to_code"))


comp_mun <- comp_mun %>%
  dplyr::select(-c(nm_mun, nm_state)) %>%
  left_join(SOY_MUN[,1:4], by = "co_mun") %>%
  relocate(nm_mun, .after = co_mun) %>%
  relocate(c(co_state, nm_state), .before = co_mun)

comp_mun[,6:ncol(comp_mun)][is.na(comp_mun[,6:ncol(comp_mun)])] <- 0

regions_btd <- filter(regions, ISO_BTD != "ROW", btd == TRUE) %>%
  dplyr::select(c(CO_BTD, ISO_BTD, name, region)) %>%
  distinct(CO_BTD, ISO_BTD, region, .keep_all = TRUE)
EU <- c("AUT", "BGR", "DNK", "FIN", "FRA", "DEU", "GRC", "HUN", "HRV", "IRL", "ITA", "MLT", "NLD", "CZE", "POL", "PRT", "ROU", "SVN", "SVK", "ESP", "SWE", "GBR", "BEL", "LUX", "LVA", "LTU", "EST", "CYP")
regions_btd <- regions_btd %>% mutate(region = ifelse(ISO_BTD %in% EU, "EU", region))
comp_mun <- comp_mun %>%
  left_join(dplyr::select(regions_btd, c(ISO_BTD, name, region)), by = c("to_code" = "ISO_BTD")) %>%
  rename(to_name = name, to_region = region) %>%
  relocate(to_name, to_region, .after = to_code) %>%
  mutate(to_region = ifelse(to_code == "CHN", "China", to_region)) %>%
  mutate(to_region = ifelse(to_code == "ROW", "ROW", to_region), to_name= ifelse(to_code == "ROW", "ROW", to_name)) %>%
  mutate(to_region = ifelse(to_code == "BRA", "Brazil", to_region))

comp_mun <- dplyr::select(comp_mun, -landuse)

comp_mun <- comp_mun %>%
  mutate(co_state = ifelse(is.na(co_state), 99, co_state),
         nm_state = ifelse(is.na(nm_state), "UNKNOWN", nm_state),
         nm_mun = ifelse(is.na(nm_mun), "UNKNOWN", nm_mun))

comp_mun <- as.data.table(comp_mun)
setkey(comp_mun, co_state, to_code)

comp_state <- comp_mun[, lapply(.SD, sum, na.rm=TRUE),
                       by =.(co_state, nm_state, to_code, to_region),
                       .SDcols=c("trase", "downscale", names(results_list))]

comp_mun_by_region <- comp_mun[, lapply(.SD, sum, na.rm=TRUE),
                       by =.(co_mun, nm_mun, co_state, nm_state, to_region),
                       .SDcols=c("trase", "downscale", names(results_list))]

comp_state_by_region <- comp_state[, lapply(.SD, sum, na.rm=TRUE),
                               by =.(co_state, nm_state, to_region),
                               .SDcols=c("trase", "downscale", names(results_list))]


comp_list <- list("mun" = comp_mun, "state" = comp_state, "mun_by_region" = comp_mun_by_region, "state_by_region" = comp_state_by_region)


comp_list <- lapply(comp_list, function(comp){

  has_bootstrap <- "00001" %in% colnames(comp)

  if (has_bootstrap) {
    # split simulation columns off and compute summary stats across bootstrap runs
    comp_sim <- comp[,which(colnames(comp) == "00001"):ncol(comp)]
    comp <- comp[,1:(which(colnames(comp) == "00001")-1)]

    comp <- comp %>% mutate(mean = apply(as.matrix(comp_sim), 1, mean),
                                    min = apply(as.matrix(comp_sim), 1, min),
                                    max = apply(as.matrix(comp_sim), 1, max),
                                    sd = apply(as.matrix(comp_sim), 1, sd)
                                    ) %>%
                            mutate(cv = sd/mean,
                                   .after = max) %>%
                            replace_na(list(cv = 0))

    comp_ci95 <- ci_funct(comp_sim, level = 95, stats = c("lower", "upper"))
    comp_ci99 <- ci_funct(comp_sim, level = 99, stats = c("lower", "upper"))
    comp <- cbind(comp, comp_ci95, comp_ci99) %>%
      relocate(lower95:upper99, .after = sd)

    comp <- comp %>% mutate(trase_inrangemax = (trase >= min & trase <= max),
                                    trase_inrange95 = (trase >= lower95 & trase <= upper95),
                                    trase_inrange99 = (trase >= lower99 & trase <= upper99),
                                    .after = upper99)
  } else {
    # Bootstrap-absent: collapse to point estimates. Use multimode_mean as mean.
    # Add stub columns so downstream code that references mean/min/max/cv/sd/CIs doesn't break.
    comp <- comp %>% mutate(mean = multimode_mean,
                            min = multimode_mean,
                            max = multimode_mean,
                            sd = 0,
                            cv = 0,
                            lower95 = multimode_mean, upper95 = multimode_mean,
                            lower99 = multimode_mean, upper99 = multimode_mean,
                            trase_inrangemax = trase == mean,
                            trase_inrange95  = trase == mean,
                            trase_inrange99  = trase == mean)
  }

  comp <- comp %>%
    mutate(across(c(mean, euclid, downscale),
                  .fns = list(diff = ~ .-trase, sle = ~ sle(trase,.), ape = ~ ape(trase,.)),
                  .names = "{.fn}_{.col}"))

return(comp)

})



# data check 1: compare total exports by destination -------------------------------------------------------

res <- c("trase", "downscale", "euclid", "multimode_mean", "mean")

exp_by_dest <- dplyr::select(comp_list$mun, c(co_state:trase, downscale:mean)) %>%
  group_by(to_code, to_name, to_region) %>%
  summarise(across(all_of(res), sum, na.rm = TRUE), .groups = "drop")
exp_nat <- EXP_NAT_wide %>%  mutate(comex = bean + equi_fact*(oil + cake))
exp_by_dest <- full_join(exp_by_dest,exp_nat, by = c("to_code" = "to_name"))

exp_by_dest <- exp_by_dest %>% mutate(across(c(downscale:mean),
                             .fns = list(diff_trase = ~ abs(.-trase),
                                         diff_comex = ~ abs(.-comex)),
                             .names = "{.fn}_{.col}"))

exp_by_dest_region <- exp_by_dest %>%
  group_by(to_region) %>%
  summarise(across(all_of(res), sum, na.rm = TRUE), .groups = "drop")

(exp_total <- sapply(filter(exp_by_dest, to_code != "BRA")%>%dplyr::select(c(trase:mean, comex, starts_with("diff_"))), sum, na.rm = TRUE))
(flow_total <- sapply(dplyr::select(exp_by_dest, c(trase:mean, comex, starts_with("diff_"))), sum, na.rm = TRUE))

trase_exp_known <- trase_mun %>% filter(co_mun != 9999999) %>% group_by(to_code) %>% summarise(trase_known = sum(trase))
exp_summary <- exp_by_dest %>% dplyr::select(c(to_code:trase, comex, euclid, multimode_mean, bean, oil, cake)) %>%
  left_join(trase_exp_known)

exp_summary <- exp_summary %>% dplyr::select(to_code, to_name, trase, trase_known, euclid, multimode_mean, comex, bean, oil, cake)
exp_summary <- exp_summary %>% mutate(across(where(is.numeric), ~replace_na(.x, 0)))
exp_summary <- arrange(exp_summary, desc(comex))
exp_summary <- mutate(exp_summary, across(trase:cake, function(x){x/1000}))

exp_summary <- rbind(exp_summary, "Total" = c(NA, NA, colSums(exp_summary[,3:ncol(exp_summary)])))

print(xtable(exp_summary, caption = "Eport summary",digits = 3),
      file = file.path(tab_dir, "export_summary_sorted.tex"),
      include.rownames=FALSE)

# data check 2: compare total flows by MU to production ------------------------------------------------------------

comp_mun_total <- comp_list$mun %>%
  dplyr::select(c(co_state:trase, downscale:mean)) %>%
  group_by(co_state, nm_state, co_mun, nm_mun) %>%
  summarise(across(c(trase, downscale:mean), sum, na.rm = TRUE), .groups = "drop")

comp_mun_total <- full_join(comp_mun_total,
                            dplyr::select(SOY_MUN, c(co_mun, prod_bean)),
                            by = "co_mun")
comp_mun_total <- comp_mun_total %>%
  dplyr::select(-c(nm_mun, co_state, nm_state)) %>%
  left_join(SOY_MUN[,1:4], by = "co_mun") %>%
  relocate(nm_mun, .after = co_mun) %>%
  relocate(c(co_state, nm_state), .before = co_mun) %>%
  mutate(co_state = ifelse(is.na(co_state), 99, co_state),
         nm_state = ifelse(is.na(nm_state), "UNKNOWN", nm_state),
         nm_mun = ifelse(is.na(nm_mun), "UNKNOWN", nm_mun))

comp_mun_total <- comp_mun_total %>%
  mutate(across(trase:prod_bean, ~replace_na(.x, 0)))

comp_mun_total <- comp_mun_total %>%
  mutate(across(c(trase, downscale:mean),
                .fns = list(diff_trase = ~ .-trase,
                            diff_prod = ~.-prod_bean)))

#### write results --------------------------------------------------


if (write){
  saveRDS(comp_list, file.path(out_dir, "comp_list.rds"))
  saveRDS(EXP_NAT_wide, file.path(out_dir, "EXP_NAT_wide.rds"))
}


rm(list = ls())
gc()


###### Data preparation of Brazilian municipality-level data #########

# this script prepares and combines all the data sets on municipality level to one coherent data set with unique MU identifiers
# it also matches the aggregate data to the municipality polygon shapefiles 

library(dplyr)
library(openxlsx)
library(tidyr)
library(sf)
library(readr)

# should results be written to file ? (TRUE/FALSE)
write = TRUE


# load raw data -----------------------------------------------------------------------------------------------------------------------------------------------

# IBGE GEO-municipality names
MUN <- openxlsx::read.xlsx("data/old/GEO_MUN_2013_IBGE_merged.xlsx") 
# export and import (COMEX)
EXP_MUN <- read.csv2(file = "data/old/EXP_2013_MUN_COMEX.csv", header = TRUE, stringsAsFactors = FALSE)
IMP_MUN <- read.csv2(file = "data/old/IMP_2013_MUN_COMEX.csv", header = TRUE, stringsAsFactors = FALSE)
COMEX_MUN <- read.csv2(file = "data/old/UF_MUN_COMEX.csv", header = TRUE, fileEncoding = "ISO-8859-1", stringsAsFactors = FALSE)
#COMEX_MUN <- read_csv2(file = "data/old/UF_MUN_COMEX.csv", col_names = TRUE, locale = locale(encoding = "ISO-8859-1"), trim_ws = TRUE, show_col_types = FALSE)
PAIS <- read.csv2(file = "data/old/PAIS_COMEX.csv", header = TRUE, fileEncoding = "ISO-8859-1")
#PAIS <- read_csv2(file = "data/old/PAIS_COMEX.csv", col_names = TRUE, locale = locale(encoding = "ISO-8859-1"), trim_ws = TRUE, show_col_types = FALSE)
# production (IBGE)
PROD_MUN <- read.csv(file = "data/old/Production_tabela1612_IBGE.csv", header = TRUE, skip = 2, encoding = "UTF-8", stringsAsFactors = FALSE)
# processing facilities (ABIOVE)
PROC_MUN_proc <- openxlsx::read.xlsx("data/old/Processing_facilities_2013_ABIOVE.xlsx", sheet = "processing_MUN", colNames = T) 
PROC_MUN_refbot <- openxlsx::read.xlsx("data/old/Processing_facilities_2013_ABIOVE.xlsx", sheet = "refining_bottling_MUN", colNames = T) 
# population (IBGE)
POP_MUN <- read.csv(file = "data/old/Population_tabela6579_IBGE.csv", header = TRUE, skip = 1, encoding = "UTF-8", stringsAsFactors = FALSE)
# livestock (IBGE)
LSTOCK_MUN <- read.csv2(file = "data/old/Livestock_2013_tabela3939_IBGE.csv", header = TRUE, skip = 4, encoding = "UTF-8", stringsAsFactors = FALSE)
MILKCOWS_MUN <- read.csv2(file = "data/old/MilkCows_2013_tabela94_IBGE.csv", header = TRUE, skip = 3, encoding = "UTF-8", stringsAsFactors = FALSE)
# grain storage facilities (armazens) vector file from IBGE including capacity
STORAGE_MUN <- st_read("data/old/geo/IBGE_logistic_network/armazens_2014.shp")
# per-capita soy oil acquisition (IBGE POF)
OIL_ACQ_STATE <- openxlsx::read.xlsx("data/old/POF_soy_oil_2017_IBGE.xlsx", sheet = 1)
# biodiesel production facilities and regional material inputs (ANP)
DIESEL_CAP_MUN <- openxlsx::read.xlsx("data/old/Biodiesel_capacity_2013_ANP.xlsx", sheet = "capacity", startRow = 2, colNames = T) 
DIESEL_MAT_REG <- openxlsx::read.xlsx("data/old/Biodiesel_capacity_2013_ANP.xlsx", sheet = "materials", startRow = 2, colNames = T) 


# prepare, harmonize and format data ----------------------------------------------------------------------------------------------------------------------


###### export (COMEX) ----

# rename columns
names(EXP_MUN) <- c("year", "month", "HS4", "co_destin", "nm_state_comex", "co_mun_comex", "export_kg", "export_dol" )

# filter soy products
EXP_MUN_SOY <- filter(EXP_MUN, HS4 %in% c(1201, 1507, 2304))

# change unit of exports from kg to tons
EXP_MUN_SOY <- EXP_MUN_SOY %>% mutate(export_kg = export_kg/1000) %>% rename(export = export_kg)

# aggregate months to get annual data
EXP_MUN_SOY <- EXP_MUN_SOY %>% group_by(HS4, co_destin, nm_state_comex, co_mun_comex) %>% 
  summarise(export = sum(export, na.rm = TRUE), export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>% 
  ungroup() 

# add product names column and put it next to the product code
EXP_MUN_SOY <- EXP_MUN_SOY %>% mutate(product = ifelse(HS4 == 1201,"soybean", ifelse(HS4 == 1507, "soy_oil", "soy_cake"))) %>% 
  relocate(product, .after = HS4)

# add municipality names from accompanying Comex file 
colnames(COMEX_MUN) <- c("co_mun_comex", "nm_mun_comex", "nm_mun_min_comex", "nm_state_comex") # change column name to identify them more easily in next steps
COMEX_MUN$nm_mun_comex <- toupper(COMEX_MUN$nm_mun_min_comex)  #make sure the upper case names use the special characters (accents etc.) as well
#check <- full_join(MUN, COMEX_MUN, by=c("NM_MUN" = "NM_MUN_comex", "NM_STATE" = "SG_UF_comex"))
EXP_MUN_SOY <- EXP_MUN_SOY %>% left_join(COMEX_MUN[,1:2], by="co_mun_comex") # add MU names to export sheet
# put MU code, name and state in first columns  % (old idea: match with MU name from GEO polygons)
EXP_MUN_SOY <- EXP_MUN_SOY %>% relocate(co_mun_comex, .before = HS4) %>% relocate(nm_mun_comex, .before = HS4) %>% relocate(nm_state_comex, .before = HS4)

# add country names for destination countries from accompanying file PAIS
EXP_MUN_SOY <- EXP_MUN_SOY %>% left_join(PAIS[,c(1,3)], by=c("co_destin" = "CO_PAIS")) %>%  rename("nm_destin" = "CO_PAIS_ISOA3") %>% relocate(nm_destin, .after = co_destin)

# COMEX uses different, state codes (=first two digits of municipality code) for SP, MS, GO & DF
# add column for corrected MU codes (changing first 2 digits) for SP (34 to 35), MS (52 to 50), GO (53 to 52) & DF (54 to 53))
EXP_MUN_SOY <- EXP_MUN_SOY %>% mutate(co_mun_corr = ifelse(nm_state_comex == "SP", co_mun_comex + 100000, 
                                                           ifelse(nm_state_comex == "MS", co_mun_comex - 200000,
                                                                  ifelse(nm_state_comex %in% c("GO", "DF"), co_mun_comex - 100000, co_mun_comex)))) %>% 
  relocate(co_mun_corr, .after = co_mun_comex)


# match corrected MU codes with MU names & states from the IBGE GEO-municipalities 
EXP_MUN_SOY <- EXP_MUN_SOY %>% left_join(MUN, by=c("co_mun_corr" = "co_mun")) %>% relocate(nm_mun, .after = nm_mun_comex)  %>% relocate(nm_state, .after = nm_state_comex) %>% relocate(co_state, .before = nm_state_comex) %>% arrange(co_mun_corr)
#sum(is.na(EXP_MUN_SOY$nm_mun)) # only 7 items unmatched and these are exports from "MUNICIPIO N?O DECLARADO" in Comex 
# NOTE: undeclared origin no longer present in updated comex dataset !

# check if state and municipality names from COMEX and IBGE match each other
all.equal(EXP_MUN_SOY$nm_state_comex[1:2220], EXP_MUN_SOY$nm_state[1:2220])
all.equal(EXP_MUN_SOY$nm_mun_comex[1:2220], EXP_MUN_SOY$nm_mun[1:2220])

# remove redundant columns 
EXP_MUN_SOY <- EXP_MUN_SOY %>% dplyr::select(-c(co_mun_comex, nm_mun, nm_state)) %>% rename(co_mun = co_mun_corr, nm_mun = nm_mun_comex, nm_state = nm_state_comex)
names(EXP_MUN_SOY) 
(checksum_1 <- c(sum(EXP_MUN_SOY$export), sum(EXP_MUN_SOY$export_dol)))

# allocate "MUNICIPIO NAO DECLARADO" exports to municipalities who export in the corresponding countries 
# NOTE: undeclared origin no longer present in updated comex dataset !
# --> this can be commented out, but it does not change the data
# e.g. undeclared exports to China are allocated to municipalities who already export to china, according to their share in total (declared) exports (tons) to China
# separate undeclared exports from the main table:
EXP_MUN_SOY_ND <- filter(EXP_MUN_SOY, co_mun == 9999999) %>% rename("export_ND" = "export", "export_dol_ND" = "export_dol")
EXP_MUN_SOY <- filter(EXP_MUN_SOY, co_mun != 9999999)
# add column with share of this MUs exports in total exports of this product to this destination
EXP_MUN_SOY <- EXP_MUN_SOY %>% group_by(product, nm_destin) %>% mutate(destin_share = export/sum(export), destin_share_dol = export_dol/sum(export_dol)) %>% ungroup()
# add column with corresponding undeclared exports of this product to this destination
EXP_MUN_SOY <- EXP_MUN_SOY %>% left_join(EXP_MUN_SOY_ND[,6:10], by = c("product", "nm_destin", "co_destin")) %>% replace_na(list(export_ND = 0, export_dol_ND = 0))
# allocate undeclared exports according to destin_share
# NOTE: check if using the tonnage shares to allocate both tons and value is okay - potentially we could also use the value share for value 
EXP_MUN_SOY <- EXP_MUN_SOY %>% mutate(export = export + destin_share*export_ND, export_dol = export_dol + destin_share*export_dol_ND)
# remove redundant columns
EXP_MUN_SOY <- EXP_MUN_SOY %>% dplyr::select(!c(destin_share:export_dol_ND))
# check if total exports remained constant
(checksum_2 <- c(sum(EXP_MUN_SOY$export), sum(EXP_MUN_SOY$export_dol)))
all.equal(checksum_1, checksum_2)

# generate version with  total exports by municipality by aggregating destination countries 
EXP_MUN_SOY_agg <- EXP_MUN_SOY %>% group_by(co_mun, nm_mun, co_state, nm_state, HS4, product) %>% summarise(export = sum(export, na.rm = TRUE), export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>% ungroup() # can also group with across: group_by(across(c(-export, - export_dol, - co_destin, - nm_destin))) ## co_mun, nm_mun, co_state, nm_state, HS4, product

# optional: generate a wide version for exports in tons, where destination countries are spread out in columns
# EXP_MUN_SOY_wide <- EXP_MUN_SOY %>% dplyr::select(!export_dol) %>% pivot_wider(names_from = nm_destin, values_from = export, names_sort = TRUE, values_fill = 0)

# generate separate data.frames for each of the three export products and put them in a list
EXP_MUN_list <- list("soybean" = filter(EXP_MUN_SOY, product == "soybean"), 
                     "soy_oil" = filter(EXP_MUN_SOY, product == "soy_oil") , 
                     "soy_cake"= filter(EXP_MUN_SOY, product == "soy_cake"),
                     "total" = EXP_MUN_SOY %>% group_by(across(c(-product, -HS4, -export, - export_dol))) %>% summarise(export = sum(export, na.rm = TRUE), export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>% ungroup())

EXP_MUN_agg_list <- list("soybean" = filter(EXP_MUN_SOY_agg, product == "soybean"), 
                         "soy_oil" = filter(EXP_MUN_SOY_agg, product == "soy_oil") , 
                         "soy_cake"= filter(EXP_MUN_SOY_agg, product == "soy_cake"),
                         "total" = EXP_MUN_SOY_agg %>% group_by(across(c(-product, -HS4, -export, - export_dol))) %>% summarise(export = sum(export, na.rm = TRUE), export_dol = sum(export_dol, na.rm = TRUE), .groups = "drop") %>% ungroup())



###### import (COMEX) -------

# rename columns
names(IMP_MUN) <- c("year", "month", "HS4", "co_origin", "nm_state_comex", "co_mun_comex", "import_kg", "import_dol" )

# filter soy products
IMP_MUN_SOY <- filter(IMP_MUN, HS4 %in% c(1201, 1507, 2304))

# change imports in kg to imports in tons
IMP_MUN_SOY <- IMP_MUN_SOY %>% mutate(import_kg = import_kg/1000) %>% rename(import = import_kg)

# aggregate months to get annual data
IMP_MUN_SOY <- IMP_MUN_SOY %>% group_by(HS4, co_origin, nm_state_comex, co_mun_comex) %>% summarise(import = sum(import, na.rm = TRUE), import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>% ungroup() 

# add product names column and put it next to the product code
IMP_MUN_SOY <- IMP_MUN_SOY %>% mutate(product = ifelse(HS4 == 1201,"soybean", ifelse(HS4 == 1507, "soy_oil", "soy_cake"))) %>% relocate(product, .after = HS4)

# add municipality names from accompanying comex file 
IMP_MUN_SOY <- IMP_MUN_SOY %>% left_join(COMEX_MUN[,1:2], by = "co_mun_comex") # add MU names to import sheet
# put MU code, name and state in first columns  % (old idea: match with MU name from GEO polygons)
IMP_MUN_SOY <- IMP_MUN_SOY %>% relocate(co_mun_comex, .before = HS4) %>% relocate(nm_mun_comex, .before = HS4) %>% relocate(nm_state_comex, .before = HS4)

# add country names for destination countries from accompanying file PAIS
IMP_MUN_SOY <- IMP_MUN_SOY %>% left_join(PAIS[,c(1,3)], by=c("co_origin" = "CO_PAIS")) %>% rename("nm_origin" = "CO_PAIS_ISOA3") %>% relocate(nm_origin, .after = co_origin)

# COMEX uses different, state codes (=first two digits of municipality code for SP, MS, GO & DF)
# add column for corrected MU codes (changing first 2 digits) for SP (34 to 35), MS (52 to 50), GO (53 to 52) & DF (54 to 53))
IMP_MUN_SOY <- IMP_MUN_SOY %>% mutate(co_mun_corr = ifelse(nm_state_comex == "SP", co_mun_comex + 100000, 
                                                           ifelse(nm_state_comex == "MS", co_mun_comex - 200000,
                                                                  ifelse(nm_state_comex %in% c("GO", "DF"), co_mun_comex - 100000, co_mun_comex)))) %>% 
  relocate(co_mun_corr, .after = co_mun_comex)


# match corrected MU codes with MU names & states from the IBGE GEO-municipalities 
IMP_MUN_SOY <- IMP_MUN_SOY %>% left_join(MUN, by=c("co_mun_corr" = "co_mun")) %>% relocate(nm_mun, .after = nm_mun_comex)  %>% relocate(nm_state, .after = nm_state_comex) %>% relocate(co_state, .before = nm_state_comex) %>% arrange(co_mun_corr)
sum(is.na(IMP_MUN_SOY$nm_mun)) # no items unmatched

# check if state and municipality names from COMEX and IBGE match each other
all.equal(IMP_MUN_SOY$nm_state_comex, IMP_MUN_SOY$nm_state)
all.equal(IMP_MUN_SOY$nm_mun_comex, IMP_MUN_SOY$nm_mun)

# remove redundant columns 
IMP_MUN_SOY <- IMP_MUN_SOY %>% dplyr::select(-c(co_mun_comex, nm_mun, nm_state)) %>% rename(co_mun = co_mun_corr, nm_mun = nm_mun_comex, nm_state = nm_state_comex)
names(IMP_MUN_SOY) 

# generate version with  total imports by municipality by aggregating destination countries 
IMP_MUN_SOY_agg <- IMP_MUN_SOY %>% group_by(co_mun, nm_mun, co_state, nm_state, HS4, product) %>% summarise(import = sum(import, na.rm = TRUE), import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>% ungroup() 

# generate separate data.frames for each of the three import products and put them in a list
IMP_MUN_list <- list("soybean" = filter(IMP_MUN_SOY, product == "soybean"), 
                     "soy_oil" = filter(IMP_MUN_SOY, product == "soy_oil") , 
                     "soy_cake"= filter(IMP_MUN_SOY, product == "soy_cake"),
                     "total" = IMP_MUN_SOY %>% group_by(across(c(-product, -HS4, -import, - import_dol))) %>% summarise(import = sum(import, na.rm = TRUE), import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>% ungroup())

IMP_MUN_agg_list <- list("soybean" = filter(IMP_MUN_SOY_agg, product == "soybean"), 
                         "soy_oil" = filter(IMP_MUN_SOY_agg, product == "soy_oil") , 
                         "soy_cake"= filter(IMP_MUN_SOY_agg, product == "soy_cake"),
                         "total" = IMP_MUN_SOY_agg %>% group_by(across(c(-product, -HS4, -import, - import_dol))) %>% summarise(import = sum(import, na.rm = TRUE), import_dol = sum(import_dol, na.rm = TRUE), .groups = "drop") %>% ungroup())


###### production (IBGE) ####

colnames(PROD_MUN) <- c("co_mun", "nm_mun_raw", "product", "year", "area_plant", "area_harv", "prod")
PROD_MUN <- PROD_MUN[1:61193,]
# change factors to numeric
PROD_MUN[,c(1,4:7)] <- apply(PROD_MUN[ ,c(1,4:7)], 2, function(x) as.numeric(x))
# extract year 2013
PROD_MUN <- filter(PROD_MUN, year == 2013)
# match with MUN data and check for conformity of MU names
PROD_MUN <- PROD_MUN %>% left_join(MUN[,1:2], by="co_mun") %>% relocate(nm_mun, .after = nm_mun_raw)
PROD_MUN$nm_mun_raw <-  PROD_MUN$nm_mun_raw %>% substr(1,nchar(PROD_MUN$nm_mun_raw)-5) %>% toupper
PROD_MUN$check <- (PROD_MUN$nm_mun_raw == PROD_MUN$nm_mun) # add column checking for consistency --> only a few spelling mismatches!
PROD_MUN <- PROD_MUN %>% dplyr::select(-c(nm_mun_raw, check)) # remove columns no longer needed


###### processing (ABIOVE) ----------

# merge processing sheet with refining & bottling sheet
PROC_MUN <- full_join(PROC_MUN_proc, PROC_MUN_refbot, by = c("co_mun", "nm_mun", "nm_state"))
# for the analysis we are only interested in active facilities (re-enter other information if needed)
PROC_MUN <- PROC_MUN %>% dplyr::select(c(co_mun, nm_mun, nm_state, proc_fac_act, proc_cap_act, ref_fac_act, ref_cap_act, bot_cap_act)) %>% 
  rename(proc_fac = proc_fac_act, proc_cap = proc_cap_act, ref_fac = ref_fac_act, ref_cap = ref_cap_act, bot_cap = bot_cap_act)


###### population (IBGE) ----------

colnames(POP_MUN) <- c("co_mun", "nm_mun_raw", "year", "variable", "population")
POP_MUN <- POP_MUN[1:100260,] # remove legend descriptions at bottom if table
# change factors to numeric
POP_MUN[,c(1,3,5)] <- apply(POP_MUN[ ,c(1,3,5)], 2, function(x) as.numeric(x))
# extract year 2013
POP_MUN <- filter(POP_MUN, year == 2013)
# match with MUN data and check for consistency of MUN names
POP_MUN <- POP_MUN %>% left_join(MUN[,1:2], by="co_mun") %>% relocate(nm_mun, .after = nm_mun_raw)
POP_MUN$nm_mun_raw <- POP_MUN$nm_mun_raw %>% substr(1,nchar(POP_MUN$nm_mun_raw)-5) %>% toupper # reformat the NAME_MUN column to match the format of IBGE
POP_MUN$check <- (POP_MUN$nm_mun_raw == POP_MUN$nm_mun) # add column checking for consistency  --> only a few spelling mismatches!
POP_MUN <- POP_MUN %>% dplyr::select(-c(nm_mun_raw, check)) # remove columns noo longer needed


###### livestock (IBGE) ----------

LSTOCK_MUN <- LSTOCK_MUN[1:5567,2:13]
# rename columns, translating animal names
colnames(LSTOCK_MUN) <- c("co_mun", "nm_mun_raw", "cattle", "buffalo", "horse", "pig", "pig_mother","goat", "sheep", "chicken", "chicken_layer", "quail")
# change characters to numeric
LSTOCK_MUN[,c(1,3:12)] <- apply(LSTOCK_MUN[ ,c(1,3:12)], 2, function(x) as.numeric(x))

# add milked cows
MILKCOWS_MUN <- MILKCOWS_MUN[1:5569, 2:4]
colnames(MILKCOWS_MUN) <- c("co_mun", "nm_mun_raw", "cattle_milked")
MILKCOWS_MUN[,c(1,3)] <- apply(MILKCOWS_MUN[ ,c(1,3)], 2, function(x) as.numeric(x))
# merge and compare names
LSTOCK_MUN <- LSTOCK_MUN %>% full_join(MILKCOWS_MUN, by="co_mun") 
all.equal(LSTOCK_MUN$nm_mun_raw.x, LSTOCK_MUN$nm_mun_raw.y) # only 2 extra MU's in milked cows dataset (both have zero cows)
LSTOCK_MUN <- LSTOCK_MUN %>% dplyr::select(!nm_mun_raw.x) %>% rename("nm_mun_raw" = "nm_mun_raw.y") %>% relocate (nm_mun_raw, .after = co_mun) %>% relocate(cattle_milked, .after = cattle)

# match with MUN data and check for consistency of MUN names
LSTOCK_MUN <- LSTOCK_MUN %>% left_join(MUN[,1:2], by="co_mun") %>% relocate(nm_mun, .after = nm_mun_raw) 
LSTOCK_MUN$nm_mun_raw <-  LSTOCK_MUN$nm_mun_raw %>% substr(1,nchar(LSTOCK_MUN$nm_mun_raw)-5) %>% toupper # reformat the NAME_MUN column to match the format of IBGE
LSTOCK_MUN$check <- (LSTOCK_MUN$nm_mun_raw == LSTOCK_MUN$nm_mun) # as above, only a few spelling mismatches!
LSTOCK_MUN <- LSTOCK_MUN %>% dplyr::select(-c(nm_mun_raw, check)) # remove columns no longer needed

###### storage capacity (IBGE) ---------

# check if MU codes of storage facilities are all contained in main MU sheet 
all(unique(STORAGE_MUN$GEOCODIGO %in% MUN$co_mun))
# sum capacities by MU
STORAGE_MUN <- STORAGE_MUN %>% 
  as.data.frame %>% 
  group_by(MUNICIPIO, GEOCODIGO) %>% 
  summarise("storage_cap" = sum(CAP_TON, na.rm = TRUE), .groups = "drop") %>% 
  rename("co_mun" = "GEOCODIGO")


###### annual soy oil acquisition for food purposes per capita in kg (IBGE) ---------------------

# we assume homogeneity of consumption baskets within states and allocate the per-capita purchase quantity on state level to MUs
OIL_ACQ_STATE <- rename(OIL_ACQ_STATE, oil_acq_pc = "Óleo.de.soja", nm_state = "subdivision") %>%
  dplyr::select(c(nm_state, oil_acq_pc))


###### biodiesel production capacity (ANP) ---------------------

# check which MU names from ANP are not matching IBGE names
DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>% 
  mutate(Município = toupper(Município)) %>%
  rename(nm_mun = "Município", diesel_cap = "Capacidade.(m3/dia)", nm_state = "UF") %>%
  dplyr::select(c(Empresa, nm_mun, nm_state, diesel_cap))
DIESEL_CAP_MUN$nm_mun[which(!DIESEL_CAP_MUN$nm_mun %in% MUN$nm_mun)]
# correct spelling
DIESEL_CAP_MUN$nm_mun[which(!DIESEL_CAP_MUN$nm_mun %in% MUN$nm_mun)] <- 
  c("BARRA DO BUGRES", "COLÍDER")
# add mu codes and extract region code (first digit of MU code)
DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>% 
  left_join(MUN[,1:4], by = c("nm_mun", "nm_state")) %>% # match also by state in case of duplicate mu names
  mutate(co_reg = substr(as.character(co_mun),1,1)) %>%
  relocate(co_mun:co_reg, .after = nm_mun)
# aggregate by municipality
DIESEL_CAP_MUN <- DIESEL_CAP_MUN %>%
  group_by(across(nm_mun:nm_state)) %>%
  summarise(diesel_cap = sum(diesel_cap), .groups = "drop")

# add correct number macroregions (see https://biblioteca.ibge.gov.br/visualizacao/livros/liv101652.pdf, p.23)
regions <- data.frame(co_reg = 1:5, nm_reg = c("Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste"))
names(DIESEL_MAT_REG) <- regions$co_reg[match(names(DIESEL_MAT_REG), regions$nm_reg)]
soy_share <- c(DIESEL_MAT_REG[1,names(DIESEL_MAT_REG)[2:6]])
# add state soy input share to capacity
DIESEL_CAP_MUN <- mutate(DIESEL_CAP_MUN, soy_share = as.numeric(soy_share[co_reg]))
# compute production capacity using only soy inputs
DIESEL_CAP_MUN <- mutate(DIESEL_CAP_MUN, diesel_cap_soy = diesel_cap * soy_share)


# merge to one comprehensive table -----------------------------------------------------------------------------------------------

# start with GEO-municipalities and soy production: 
SOY_MUN <- left_join(MUN, PROD_MUN[,c(1,5:7)], by = "co_mun") %>% rename(prod_bean = prod)

# add export data 
SOY_MUN <- SOY_MUN %>%  full_join(EXP_MUN_agg_list$soybean[,c(1,7:8)], by = "co_mun") %>% rename(exp_bean = export,  exp_bean_d = export_dol)
SOY_MUN <- SOY_MUN %>%  left_join(EXP_MUN_agg_list$soy_oil[,c(1,7:8)], by = "co_mun") %>% rename(exp_oil = export,  exp_oil_d = export_dol)
SOY_MUN <- SOY_MUN %>%  left_join(EXP_MUN_agg_list$soy_cake[,c(1,7:8)], by = "co_mun") %>% rename(exp_cake = export, exp_cake_d = export_dol)
# SOY_MUN <- SOY_MUN %>%  left_join(EXP_MUN_agg_list$total[,c(1,5:6)], by = "co_mun") %>% rename(exp_tot = export, exp_tot_d = export_dol)

# add import data
SOY_MUN <- SOY_MUN %>%  left_join(IMP_MUN_agg_list$soybean[,c(1,7:8)], by = "co_mun") %>% rename(imp_bean = import,  imp_bean_d = import_dol)
SOY_MUN <- SOY_MUN %>%  left_join(IMP_MUN_agg_list$soy_oil[,c(1,7:8)], by = "co_mun") %>% rename(imp_oil = import,  imp_oil_d = import_dol)
SOY_MUN <- SOY_MUN %>%  left_join(IMP_MUN_agg_list$soy_cake[,c(1,7:8)], by = "co_mun") %>% rename(imp_cake = import, imp_cake_d = import_dol)
# SOY_MUN <- SOY_MUN %>%  left_join(IMP_MUN_agg_list$total[,c(1,5:6)], by = "co_mun") %>% rename(imp_tot = import, imp_tot_d = import_dol)

# add processing facility data
SOY_MUN <- SOY_MUN %>%  left_join(PROC_MUN[,c(1,4:8)], by = "co_mun")

# add population & livestock 
SOY_MUN <- SOY_MUN %>%  left_join(POP_MUN[,c(1,5)], by = "co_mun")
SOY_MUN <- SOY_MUN %>%  left_join(LSTOCK_MUN[,c(1,3:13)], by = "co_mun")

# add storage capacity
SOY_MUN <- SOY_MUN %>%  left_join(STORAGE_MUN[,2:3], by = "co_mun")

# add per capita oil acquisition
SOY_MUN <- SOY_MUN %>% left_join(OIL_ACQ_STATE, by = "nm_state")

# add soy biodiesel capacity
SOY_MUN <- SOY_MUN %>%  left_join(DIESEL_CAP_MUN[,c("co_mun", "diesel_cap_soy")], by = "co_mun")

# re-add name for MU 9999999 (MUNICIPIO NAO DECLARADO) if applicable --- NOTE: no longer necessary as these exports are allocated above
# SOY_MUN$nm_mun[SOY_MUN$co_mun == 9999999] <- "MUNICIPIO N?O DECLARADO"  

# replace NA's by zero 
SOY_MUN[is.na(SOY_MUN)] <- 0



# municipality polygons  ------------------------------------------------------------------------------------------------------------

# load data
GEO_MUN <- st_read("data/old/geo/GEO_MUN_2013_IBGE_merged.gpkg", stringsAsFactors = FALSE)
# remove unnecessary attributes
GEO_MUN <- dplyr::select(GEO_MUN, !c(layer, path))
# make MU code numeric
GEO_MUN$co_mun <- as.numeric(GEO_MUN$co_mun)
# merge with the main table
GEO_MUN_SOY <- left_join(GEO_MUN,SOY_MUN, by = "co_mun")
# final name check
all.equal(GEO_MUN_SOY$nm_mun.x, GEO_MUN_SOY$nm_mun.y)
GEO_MUN_SOY <- GEO_MUN_SOY %>% dplyr::select(-nm_mun.y) %>% rename("nm_mun" = "nm_mun.x")

# project to the Brazil polyconic projection of SIRGAS 2000 (EPSG:5880)
GEO_MUN_SOY <- st_transform(GEO_MUN_SOY, 5880)

# retrieve coordinates of a central point within each MU 
MUN_center <- st_point_on_surface(GEO_MUN_SOY) # or st_centroid(GEO_MUN_SOY)

# compute euclidean distance for points within MUs
MUN_center_dist <- st_distance(MUN_center)
dimnames(MUN_center_dist) <- list(GEO_MUN_SOY$co_mun, GEO_MUN_SOY$co_mun)

# check which polygons are adjacent
# MUN_adj <- st_touches(GEO_MUN_SOY, byid = FALSE, sparse = FALSE)
# dimnames(MUN_adj) <- list(GEO_MUN_SOY$co_mun, GEO_MUN_SOY$co_mun)
# set distance of adjacent polygons to zero
# MUN_dist[MUN_adj == TRUE] <- 0

# merge all MUs to obtain a polygon of the whole country (for download of MapBiomas data on GEE)
GEO_BRA <- summarise(GEO_MUN_SOY)
GEO_BRA_EXT <- st_as_sfc(st_bbox(GEO_MUN_SOY))


# municipality capitals ---------------------------------------------------

# load data
MUN_localities <- st_read("data/old/geo/IBGE_localities/BR_Localidades_2010_v1.shx", stringsAsFactors = FALSE)

# data contains several types of localities (cities, villages...) -> extract only capitals 
MUN_capitals <- MUN_localities %>% filter(CD_NIVEL == 1) %>% dplyr::select(c(CD_GEOCODM, NM_MUNICIP, LONG, LAT)) %>% rename("co_mun" = "CD_GEOCODM", "nm_mun" = "NM_MUNICIP") %>% mutate(co_mun = as.numeric(co_mun))

# check which MUs are missing
SOY_MUN[,1:4][which(!SOY_MUN$co_mun %in% MUN_capitals$co_mun, arr.ind = T),]

# add 7 missing MUs manually (coordinates taken from google maps)
# Note: LAGOA MIRIM and LAGOA DOS PATOS cover only the area of lakes, without any inhabitants and a capital
Mojuidoscampos  <- c(1504752, "MOJUÍ DOS CAMPOS", -54.640278, -2.684722)
PescariaBrava   <- c(4212650, "PESCARIA BRAVA", -48.883333, -28.383333) 
BalnearioRincao <- c(4220000, "BALNEÁRIO RINCÃO", -49.236111, -28.834444)
LagoaMirim      <- c(4300001, "LAGOA MIRIM", -52.899807, -32.697881)
LagoadosPatos   <- c(4300002, "LAGOA DOS PATOS",  -51.365753, -30.995042)
Paraisodasaguas <- c(5006275, "PARAÍSO DAS ÁGUAS", -52.968333, -19.052222)
PintoBandeira   <- c(4314548, "PINTO BANDEIRA", -51.450278, -29.097778) 

MUN_capitals_missing <- data.frame(rbind(Mojuidoscampos, PescariaBrava, BalnearioRincao, LagoaMirim, LagoadosPatos, Paraisodasaguas, PintoBandeira))
names(MUN_capitals_missing) <- names(MUN_capitals)[1:4]
MUN_capitals_missing[,c(1,3:4)] <- apply(MUN_capitals_missing[,c(1,3:4)], 2, function(x) as.numeric(as.character(x)))
# transform to sf object and project crs of main table
MUN_capitals_missing <- st_as_sf(MUN_capitals_missing, coords = c("LONG","LAT"), remove = FALSE, crs = 4326)
MUN_capitals_missing <- st_transform(MUN_capitals_missing, st_crs(MUN_capitals))
# append to MUN_capitals
MUN_capitals <- rbind(MUN_capitals, MUN_capitals_missing)
MUN_capitals <- MUN_capitals[order(MUN_capitals$co_mun),]
# correct names
MUN_capitals <- left_join(MUN_capitals[,c(1,3:5)], SOY_MUN[,1:2], by = "co_mun") %>% 
  relocate(nm_mun, .after = co_mun) %>% 
  arrange(co_mun)
# project to EPSG 5880
MUN_capitals <- st_transform(MUN_capitals, crs = st_crs(GEO_MUN_SOY))


# compute euclidean distance for MU capitals
MUN_capital_dist <- st_distance(MUN_capitals)
dimnames(MUN_capital_dist) <- list(MUN_capitals$co_mun, MUN_capitals$co_mun)



# export data ---------------------------------------------------------------------------------------------------------------------------

if (write){
  
  # tables
  saveRDS(SOY_MUN, file = "results/intermediate/SOY_MUN_00.rds")
  write.csv2(SOY_MUN, file = "results/intermediate/SOY_MUN.csv")
  saveRDS(EXP_MUN_SOY, file = "results/intermediate/EXP_MUN_SOY_00.rds")
  saveRDS(IMP_MUN_SOY, file = "results/intermediate/IMP_MUN_SOY_00.rds")
  
  # polygons with all attributes 
  st_write(GEO_MUN_SOY, "results/intermediate/GEO_MUN_SOY.gpkg", driver = "GPKG", overwrite=TRUE, delete_dsn=TRUE) # 
  saveRDS(GEO_MUN_SOY, file = "results/intermediate/GEO_MUN_SOY_00.rds")

  # Brazil Polygon
  st_write(GEO_BRA, "results/intermediate/GEO_BRA.shp", append=FALSE) # 
  st_write(GEO_BRA_EXT, "results/intermediate/GEO_BRA_EXT.shp", append=FALSE) # 
  
  # capitals
  saveRDS(MUN_capitals, file = "results/intermediate/MUN_capitals.rds")
  st_write(MUN_capitals, "results/intermediate/MUN_capitals.gpkg", driver = "GPKG", overwrite=TRUE, delete_dsn=TRUE)
  
  # distance matrices
  saveRDS(MUN_center_dist, file = "results/intermediate/MUN_center_dist.rds")
  saveRDS(MUN_capital_dist, file = "results/intermediate/MUN_capital_dist.rds")
  
}

rm(list=ls())
gc()

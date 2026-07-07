# ============================================================================
# REPRODUCTION PORT — FABIO MRIO / land-use footprint backend (steps 13-21).
# Year-parameterized continuation of steps 00-12. Minimal-delta fork of the
# matching archive/code_old_stefan/ script.
#
# REQUIRES WU/fineprint FABIO + EXIOBASE data that is NOT present on this
# machine (see DATA.md):
#   - data/generated/fabio/*                     (FABIO MRIO matrices)
#   - archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/*   (concordances / tidy data)
#   - /mnt/nfs_fineprint/tmp/{exiobase,fabio}/*      (EXIOBASE + FABIO v2, NFS)
# These stages cannot run here without that infrastructure.
# ============================================================================
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
# Fail fast with a clear message if none of the FABIO data is available.
if (!dir.exists("/mnt/nfs_fineprint") &&
    length(list.files("data/generated/fabio")) == 0 &&
    length(list.files("data/fabio/v2/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See DATA.md.", call. = FALSE)
}
# NOTE: year-keyed file paths below are parameterized via YEAR, but full
# year-extension is unvalidated until FABIO data is available to run against.

### calculate footprints on the level of municipalities ###

library(Matrix)
library(data.table)
library(countrycode)

write = TRUE

LA_mass <- readRDS(paste0("data/generated/fabio/", YEAR, "_L_mass.rds"))
LB_mass <- readRDS(paste0("data/generated/fabio/", YEAR, "_B_inv_mass.rds"))
LA_value <- readRDS(paste0("data/generated/fabio/", YEAR, "_L_value.rds"))
LB_value <- readRDS(paste0("data/generated/fabio/", YEAR, "_B_inv_value.rds"))
X <- readRDS("data/generated/fabio/X.rds")
X <- X
YA <- readRDS("data/generated/fabio/Y_hybrid.rds")
YA <- YA[[as.character(YEAR)]]
load(paste0("data/exiobase/pxp/", YEAR, "_Y.RData"))
YB <- as(Y, "sparseMatrix"); rm(Y)
load("data/exiobase/Y.codes.RData")
load("data/exiobase/pxp/IO.codes.RData")
Emat <- readRDS("data/fabio/v2/E.rds")[[as.character(YEAR)]]
cbs <- readRDS("data/generated/fabio/cbs_final.rds")
areas <- unique(cbs[,.(area_code, area)])
areas_mun <- areas[area_code > 1000,]
regions <- fread("data/fabio/v2/inst/regions_full.csv")
items <- fread("data/fabio/v2/inst/items_full.csv")


# prepare land-use data ------------------------------------------------------------------------
# v2 PORT: v2's E.rds is a MATRIX (stressors x 22263 national processes); Stefan's code used an
# older long-table E with one `landuse` column. Build a per-process land-use VECTOR aligned BY
# NAME to the nested process order (rownames of LA_mass / X = "areacode_commcode"):
#  - national land use = the 'land_crop' cropland stressor (E columns are "ISO3_commcode");
#  - Brazil's national soy rows are absent from the nested matrix (replaced by municipalities),
#    so municipal soy land comes from SOY_MUN$area_plant (the documented MapBiomas alternative),
#    attached to the soybean process c021.
proc_names <- rownames(LA_mass)
landuse <- setNames(numeric(length(proc_names)), proc_names)

# national: map E columns "ISO3_commcode" -> "areacode_commcode"
e_area <- regions$code[match(sub("_.*", "", colnames(Emat)), regions$iso3c)]
e_key  <- paste0(e_area, "_", sub(".*_", "", colnames(Emat)))
nat_lu <- setNames(as.numeric(Emat["land_crop", ]), e_key)
.nat_hit <- intersect(e_key, proc_names)
landuse[.nat_hit] <- nat_lu[.nat_hit]
cat("[20] national land rows matched:", length(.nat_hit), "/", ncol(Emat),
    "| E cols with no area_code:", sum(is.na(e_area)), "\n")

# municipal soy land (ha): soybean process = c021, key "co_mun_c021" = harvested soy area.
# NB: use area_harv (sum ~37 Mha, matches IBGE); SOY_MUN$area_plant actually holds production
# tonnes here (sum == prod_bean), not hectares.
soy_mun <- as.data.table(readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds")))
mun_lu  <- setNames(as.numeric(soy_mun$area_harv),
                    paste0(as.character(soy_mun$co_mun), "_c021"))
.mun_hit <- intersect(names(mun_lu), proc_names)
landuse[.mun_hit] <- mun_lu[.mun_hit]
cat("[20] municipal soy land rows matched:", length(.mun_hit), "/", nrow(soy_mun), "\n")


# compute demand-driven production and footprints ------------------------------------

# aggregate final demand categories
# for YA
# CONSUMPTION-FOOTPRINT FIX (2026-06-24): drop non-consumption final-demand
# categories before aggregating to country totals. `stock_addition` (net inventory
# change) and `balancing` (statistical residual closing the SUT) are NOT consumption.
# Stock drawn down in year t was produced -- and footprinted -- in EARLIER years, so
# counting it as negative year-t final demand pushes the producing country's domestic
# footprint negative in heavy-drawdown years (Brazil soybean stock_withdrawal: 2012
# -5 Mt, 2018 -14 Mt, 2022 -2.5 Mt + 4.85 Mt losses), and by mass-conservation inflates
# the export destinations. Keep food / other / losses / unspecified. YA_product and
# PA_prod_country derive from YA_country, so this single filter propagates to them.
# NB: the EXIOBASE nonfood side (YB) has an analogous "Changes in inventories" category
# left untouched here (small for soy; was not the source of the break).
.keep_fd <- !grepl("_(stock_addition|balancing)$", colnames(YA))
cat("[20] FD categories: dropping", sum(!.keep_fd), "stock_addition/balancing cols,",
    "keeping", sum(.keep_fd), "\n")
YA <- YA[, .keep_fd, drop = FALSE]
colnames(YA) <- sub("_.*", "", colnames(YA))
colnames(YA) <-  regions$iso3c[match(as.numeric(colnames(YA)), regions$code)] # change to ISO code
sum_mat <- as(sapply(unique(colnames(YA)),"==",colnames(YA)), "Matrix")*1
YA_country <- YA %*% sum_mat 
# for YB
# convert ISO2 codes to ISO3
Y.codes$ISO3 <- countrycode(Y.codes$`Region Name`, origin = "iso2c", destination = "iso3c")
Y.codes$ISO3[substr(Y.codes$`Region Name`,1,1) == "W"] <- paste0("ROW_",Y.codes$`Region Name`[substr(Y.codes$`Region Name`,1,1) == "W"] )
dimnames(YB) <- list(paste0(IO.codes$Country.Code,"_",IO.codes$Product.Code),Y.codes$ISO3)
sum_mat <- as(sapply(unique(colnames(YB)),"==",colnames(YB)), "Matrix")*1
YB_country <- YB %*% sum_mat 
  

## by consumer country: 

# calculate production embodied in final demand impulse 
PA_mass  <- LA_mass  %*% YA_country
PA_value <- LA_value %*% YA_country
PB_mass  <- LB_mass  %*% YB_country
PB_value <- LB_value %*% YB_country
# append food/nonfood to colnames
colnames(PA_mass) <-  paste0(colnames(PA_mass) ,"_food")
colnames(PA_value) <- paste0(colnames(PA_value),"_food")
colnames(PB_mass) <-  paste0(colnames(PB_mass) ,"_nonfood")
colnames(PB_value) <- paste0(colnames(PB_value),"_nonfood")

# calculate municipal land-use footprints by country
l <- landuse / as.vector(X)
l[!is.finite(l)] <- 0
FA_mass  <- l*PA_mass
FA_value <- l*PA_value
FB_mass  <- l*PB_mass 
FB_value <- l*PB_value


## by consumer product: 
YA_product <- Diagonal(x = rowSums(YA_country))
dimnames(YA_product) <- list(rownames(YA_country), sub(".*_", "", rownames(YA_country)))
sum_mat <- as(sapply(unique(colnames(YA_product)),"==",colnames(YA_product)), "Matrix")*1
YA_product <- YA_product %*% sum_mat
YB_product <- Diagonal(x = rowSums(YB_country))
dimnames(YB_product) <- list(rownames(YB_country), sub(".*_", "", rownames(YB_country)))
sum_mat <- as(sapply(unique(colnames(YB_product)),"==",colnames(YB_product)), "Matrix")*1
YB_product <- YB_product %*% sum_mat

# calculate production embodied in final demand impulse 
PA_mass_product <-  LA_mass  %*% YA_product
PA_value_product <- LA_value %*% YA_product
PB_mass_product <-  LB_mass  %*% YB_product
PB_value_product <- LB_value %*% YB_product

# calculate municipal land-use footprints by product
l <- landuse / as.vector(X)
l[!is.finite(l)] <- 0
FA_mass_product  <-  l*PA_mass_product
FA_value_product <- l*PA_value_product
FB_mass_product  <-  l*PB_mass_product 
FB_value_product <- l*PB_value_product


# for specifically relevant consumer products by country:

# define relevant products:
prod_sel <- list("c110", "c111", "c112", "c114", "c115", "c116", "c117", "c118")
names(prod_sel) <- items$item[match(prod_sel, items$comm_code)]
prod_group_sel <- list("dairy" = c("c110", "c111"), 
                       "meat" = c("c114", "c115", "c116", "c117", "c118"),
                       "meat-dairy" = c("c110", "c111", "c114", "c115", "c116", "c117", "c118"),
                       "meat-dairy-eggs" = c("c110", "c111", "c112", "c114", "c115", "c116", "c117", "c118"))
prod_sel <- c(prod_sel, prod_group_sel)

PA_prod_country <- # lapply(c("mass", "value"), function(alloc){
  sapply(names(prod_sel), function(prod_nm){
    prod <- prod_sel[[prod_nm]]
    YA_prod_country <- YA_country
    YA_prod_country[!grepl(paste(prod,collapse="|"), rownames(YA_prod_country)),] <- 0 
    colnames(YA_prod_country) <- paste0(colnames(YA_prod_country),"_",prod_nm)
    PA_mass_prod_country <- LA_mass  %*% YA_prod_country
    PA_value_prod_country <- LA_value  %*% YA_prod_country
    #FA_mass_prod_country  <- l*PA_mass_prod_country
    #FA_value_prod_country <- l*PA_value_prod_country
    return(list(mass = PA_mass_prod_country, value = PA_value_prod_country))
  }, USE.NAMES = TRUE, simplify = FALSE)
#})

PA_prod_country <- sapply(c("mass", "value"), function(alloc){
  do.call("cbind", lapply(PA_prod_country, function(x) x[[alloc]]))
}, USE.NAMES = TRUE, simplify = FALSE)

FA_prod_country <- lapply(PA_prod_country, function(PA){
  FA <- l*PA
})


P_mass  <- list("A_country" = PA_mass,  "B_country" = PB_mass,  "A_product" = PA_mass_product, "B_product" =  PB_mass_product, "A_product_country" = PA_prod_country$mass)
P_value <- list("A_country" = PA_value, "B_country" = PB_value, "A_product" = PA_value_product, "B_product" = PB_value_product, "A_product_country" = PA_prod_country$value)
F_mass  <- list("A_country" = FA_mass,  "B_country" = FB_mass,  "A_product" = FA_mass_product,  "B_product" = FB_mass_product, "A_prod_country" = FA_prod_country$mass)
F_value <- list("A_country" = FA_value, "B_country" = FB_value, "A_product" = FA_value_product, "B_product" = FB_value_product, "A_prod_country" = FA_prod_country$value)

# Store results -----------------------
if (write){
  saveRDS(P_mass , paste0("data/generated/footprints/", YEAR, "_P_mass.rds"))
  saveRDS(P_value, paste0("data/generated/footprints/", YEAR, "_P_value.rds"))
  saveRDS(F_mass , paste0("data/generated/footprints/", YEAR, "_F_mass.rds"))
  saveRDS(F_value, paste0("data/generated/footprints/", YEAR, "_F_value.rds"))
}

rm(list = ls())
gc()

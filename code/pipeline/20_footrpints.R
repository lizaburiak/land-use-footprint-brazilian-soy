# FABIO MRIO / land-use footprint stage (steps 13-21). Year-parameterized
# fork of the matching archive/code_old_stefan/ script. Needs the FABIO v2 +
# EXIOBASE backends (data/fabio/v2, data/exiobase, data/generated/fabio; see DATA.md).
# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR (e.g. isolated worker dirs).
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")

YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
if (!dir.exists("/mnt/nfs_fineprint") &&
    length(list.files(file.path(DATA_DIR, "generated/fabio"))) == 0 &&
    length(list.files(file.path(DATA_DIR, "fabio/v2/inst"))) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See DATA.md.", call. = FALSE)
}

### calculate footprints on the level of municipalities ###

library(Matrix)
library(data.table)
library(countrycode)

write = TRUE

LA_mass <- readRDS(paste0(DATA_DIR, "/generated/fabio/", YEAR, "_L_mass.rds"))
LB_mass <- readRDS(paste0(DATA_DIR, "/generated/fabio/", YEAR, "_B_inv_mass.rds"))
LA_value <- readRDS(paste0(DATA_DIR, "/generated/fabio/", YEAR, "_L_value.rds"))
LB_value <- readRDS(paste0(DATA_DIR, "/generated/fabio/", YEAR, "_B_inv_value.rds"))
X <- readRDS(file.path(DATA_DIR, "generated/fabio/X.rds"))
YA <- readRDS(file.path(DATA_DIR, "generated/fabio/Y_hybrid.rds"))
YA <- YA[[as.character(YEAR)]]
load(paste0(DATA_DIR, "/exiobase/pxp/", YEAR, "_Y.RData"))
YB <- as(Y, "sparseMatrix"); rm(Y)
load(file.path(DATA_DIR, "exiobase/Y.codes.RData"))
load(file.path(DATA_DIR, "exiobase/pxp/IO.codes.RData"))
# PRE-2010: v2's E.rds starts in 2010; the v1.1 build's E (data/fabio/v1.1/, from
# /mnt/nfs_fineprint/tmp/fabio/v1.1/) covers 1986-2013 as a long table -- the exact
# format Stefan's original code consumed. Branch again below where the land-use
# vector is built.
# SOYPRINT_FORCE_V11=1 forces the v1.1 path on 2010+ years (vintage cross-checks).
.use_v11 <- YEAR < 2010 || nzchar(Sys.getenv("SOYPRINT_FORCE_V11"))
Emat <- readRDS(if (.use_v11) file.path(DATA_DIR, "fabio/v1.1/E.rds") else
                  file.path(DATA_DIR, "fabio/v2/E.rds"))[[as.character(YEAR)]]
cbs <- readRDS(file.path(DATA_DIR, "generated/fabio/cbs_final.rds"))
areas <- unique(cbs[,.(area_code, area)])
areas_mun <- areas[area_code > 1000,]
regions <- fread(file.path(DATA_DIR, "fabio/v2/inst/regions_full.csv"))
items <- fread(file.path(DATA_DIR, "fabio/v2/inst/items_full.csv"))


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

if (!.use_v11) {
  # national: map E columns "ISO3_commcode" -> "areacode_commcode"
  e_area <- regions$code[match(sub("_.*", "", colnames(Emat)), regions$iso3c)]
  e_key  <- paste0(e_area, "_", sub(".*_", "", colnames(Emat)))
  nat_lu <- setNames(as.numeric(Emat["land_crop", ]), e_key)
  cat("[20] E cols with no area_code:", sum(is.na(e_area)), "\n")
} else {
  # PRE-2010: v1.1's E is a long table (area_code / item_code / landuse). Its
  # comm_codes are OFFSET relative to v2 (v1.1 c069 = v2 c068 etc.), so map through
  # the stable FAO item_code to the v2 comm_code the nested matrix rows use. NB the
  # v1.1 `landuse` stressor also covers pasture on livestock processes (v2's
  # land_crop is cropland-only); the soy rows themselves are cropland either way.
  Edt <- as.data.table(Emat)
  Edt[, comm_v2 := items$comm_code[match(item_code, items$item_code)]]
  Edt <- Edt[is.na(comm_v2) == FALSE & is.na(landuse) == FALSE]
  nat_lu <- setNames(as.numeric(Edt$landuse), paste0(Edt$area_code, "_", Edt$comm_v2))
}
.nat_hit <- intersect(names(nat_lu), proc_names)
landuse[.nat_hit] <- nat_lu[.nat_hit]
cat("[20] national land rows matched:", length(.nat_hit), "/", length(nat_lu), "\n")

# municipal soy land (ha): soybean process = c021, key "co_mun_c021" = harvested soy area.
# NB: use area_harv (sum ~37 Mha, matches IBGE); SOY_MUN$area_plant actually holds production
# tonnes here (sum == prod_bean), not hectares.
soy_mun <- as.data.table(readRDS(paste0(DATA_DIR, "/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds")))
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
# kept for the land-identity guard below: the final demand that is dropped, by category
.ya_stock <- Matrix::rowSums(YA[, grepl("_stock_addition$", colnames(YA)), drop = FALSE])
.ya_bal   <- Matrix::rowSums(YA[, grepl("_balancing$", colnames(YA)), drop = FALSE])
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
# CHANGED: |X| < 1e-6 t is floating-point residue (e.g. -1.3e-21 t); land / X exploded to +-1e20 ha in 2013
l[abs(as.vector(X)) < 1e-6] <- 0
FA_mass  <- l*PA_mass
FA_value <- l*PA_value
FB_mass  <- l*PB_mass 
FB_value <- l*PB_value

# LAND-IDENTITY GUARD (2026-10-06). Every hectare of municipal soy land must end in final demand:
#   harvested area = kept final demand (food side + nonfood side)
#                    + stock additions dropped + balancing dropped        (mass allocation)
# The identity holds exactly when the Leontief system conserves flows. It failed by 3.9-4.8 Mha
# per year while step 17 capped column sums, and nothing checked it. Stop if it is off by more
# than 0.01% of harvested area. The parts are written next to the footprints for every year.
.si <- match(.mun_hit, proc_names)
.lid <- c(year = YEAR,
          harvested_ha       = sum(as.numeric(soy_mun$area_harv), na.rm = TRUE),
          attached_ha        = sum(l[.si] * as.vector(X)[.si]),
          kept_food_ha       = sum(FA_mass[.si, , drop = FALSE]),
          kept_nonfood_ha    = sum(FB_mass[.si, , drop = FALSE]),
          stock_addition_ha  = sum(l[.si] * as.vector(LA_mass[.si, , drop = FALSE] %*% .ya_stock)),
          balancing_ha       = sum(l[.si] * as.vector(LA_mass[.si, , drop = FALSE] %*% .ya_bal)),
          min_soy_multiplier = min(as.vector(l[.si] %*% LA_mass[.si, , drop = FALSE])))
.lid["residual_ha"] <- .lid["harvested_ha"] - sum(.lid[c("kept_food_ha", "kept_nonfood_ha",
                                                         "stock_addition_ha", "balancing_ha")])
write.csv(as.data.frame(t(.lid)), paste0(DATA_DIR, "/generated/footprints/", YEAR, "_land_identity.csv"),
          row.names = FALSE)
cat(sprintf("[20] land identity %d: harvested %.0f = kept food %.0f + kept nonfood %.0f + stock additions %.0f + balancing %.0f; residual %.0f ha (%.4f%%)\n",
            YEAR, .lid["harvested_ha"], .lid["kept_food_ha"], .lid["kept_nonfood_ha"],
            .lid["stock_addition_ha"], .lid["balancing_ha"], .lid["residual_ha"],
            100 * .lid["residual_ha"] / .lid["harvested_ha"]))
if (abs(.lid["residual_ha"]) > 1e-4 * .lid["harvested_ha"])
  stop(sprintf("[20] land-identity guard failed for %d: %.0f ha of %.0f ha harvested (%.3f%%) are neither in kept final demand nor in dropped stock additions or balancing.",
               YEAR, .lid["residual_ha"], .lid["harvested_ha"],
               100 * .lid["residual_ha"] / .lid["harvested_ha"]), call. = FALSE)


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
# CHANGED: |X| < 1e-6 t is floating-point residue (e.g. -1.3e-21 t); land / X exploded to +-1e20 ha in 2013
l[abs(as.vector(X)) < 1e-6] <- 0
FA_mass_product  <-  l*PA_mass_product
FA_value_product <- l*PA_value_product
FB_mass_product  <-  l*PB_mass_product 
FB_value_product <- l*PB_value_product


# for specifically relevant consumer products by country:

# define relevant products:
# CHANGED: codes ported from FABIO v1.1 to v2 numbering (v1.1 c110 Milk = v2 c109, v1.1 c114 Bovine Meat = v2 c113, ...)
prod_sel <- list("c109", "c110", "c111", "c113", "c114", "c115", "c116", "c117")
names(prod_sel) <- items$item[match(prod_sel, items$comm_code)]
prod_group_sel <- list("dairy" = c("c109", "c110"), 
                       "meat" = c("c113", "c114", "c115", "c116", "c117"),
                       "meat-dairy" = c("c109", "c110", "c113", "c114", "c115", "c116", "c117"),
                       "meat-dairy-eggs" = c("c109", "c110", "c111", "c113", "c114", "c115", "c116", "c117"))
prod_sel <- c(prod_sel, prod_group_sel)

PA_prod_country <-
  sapply(names(prod_sel), function(prod_nm){
    prod <- prod_sel[[prod_nm]]
    YA_prod_country <- YA_country
    YA_prod_country[!grepl(paste(prod,collapse="|"), rownames(YA_prod_country)),] <- 0
    colnames(YA_prod_country) <- paste0(colnames(YA_prod_country),"_",prod_nm)
    PA_mass_prod_country <- LA_mass  %*% YA_prod_country
    PA_value_prod_country <- LA_value  %*% YA_prod_country
    return(list(mass = PA_mass_prod_country, value = PA_value_prod_country))
  }, USE.NAMES = TRUE, simplify = FALSE)

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
  saveRDS(P_mass , paste0(DATA_DIR, "/generated/footprints/", YEAR, "_P_mass.rds"))
  saveRDS(P_value, paste0(DATA_DIR, "/generated/footprints/", YEAR, "_P_value.rds"))
  saveRDS(F_mass , paste0(DATA_DIR, "/generated/footprints/", YEAR, "_F_mass.rds"))
  saveRDS(F_value, paste0(DATA_DIR, "/generated/footprints/", YEAR, "_F_value.rds"))
}

rm(list = ls())
gc()


####### Final adjustments to municipality-level data to balance supply with demand #######

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(dplyr)
library(sf)

write = TRUE

# Stock-change handling mode (env var STOCK_MODE; see code/pipeline/CHANGELOG.md):
#   "supply_side" (DEFAULT) — a net national stock WITHDRAWAL is treated as SUPPLY:
#                 |stock| is added to total_supply and excluded from total_use, keeping
#                 the step-01 storage allocation (no realloc). This matches the
#                 commodity-balance identity (a drawdown is a source of current-year
#                 supply; see paper Methods Eq. 2), is consistent with FABIO's own stock
#                 treatment, and keeps the consumption footprint within the harvested-area
#                 envelope (verified 2010-2022).
#   "use_prop"    — legacy: a net withdrawal is reallocated across municipalities by USE
#                 base and kept on the use side (total_use), via realloc_withdrawal().
# ADDITION years (and every product with a net addition) are identical in both modes.
STOCK_MODE <- Sys.getenv("STOCK_MODE", "supply_side")
stopifnot(STOCK_MODE %in% c("use_prop", "supply_side"))
cat("STOCK_MODE:", STOCK_MODE, "\n")

# load data -----------------------------------------------------------------------------------
SOY_MUN <- readRDS(paste0("data/generated/outputs/03_", YEAR, "/SOY_MUN_03.rds"))
GEO_MUN_SOY <- readRDS(paste0("data/generated/outputs/03_", YEAR, "/GEO_MUN_SOY_03.rds"))
CBS_SOY <- readRDS(paste0("data/generated/outputs/00_", YEAR, "/CBS_SOY.rds"))
EXP_MUN_SOY <- readRDS(paste0("data/generated/outputs/04_", YEAR, "/EXP_MUN_SOY.rds"))
IMP_MUN_SOY <- readRDS(paste0("data/generated/outputs/04_", YEAR, "/IMP_MUN_SOY.rds"))


# balance municipal cbs -----------------------------------

# compute cbs totals
CBS_SOY <- mutate(CBS_SOY,
                  total_supply = production + import,
                  total_use = export + food + feed + seed + processing + other + stock_addition)

# clear small imbalances in CBS by adding difference between total supply an demand to "stock addition"
CBS_SOY$stock_addition <- CBS_SOY$stock_addition + (CBS_SOY$total_supply - CBS_SOY$total_use)
CBS_SOY$stock_withdrawal <- -CBS_SOY$stock_addition
# update totals again
CBS_SOY <- mutate(CBS_SOY,
                  total_supply = production + import,
                  total_use = export + food + feed + seed + processing + other + stock_addition)
CBS_SOY <- CBS_SOY[c("bean", "oil", "cake"),]

# FAO 2014+ split oil's industrial use across "processing" (biodiesel feedstock) and
# "other" (other non-food). Stefan's pipeline only allocates "other_oil" to municipalities,
# so any non-zero oil processing leaks the balance. Roll it into other_oil at the CBS
# level so the existing biodiesel-based allocation captures both. Cake processing is
# always 0 in FAO CBS for Brazil but mirror the same treatment for safety.
if (!is.na(CBS_SOY["oil", "processing"]) && CBS_SOY["oil", "processing"] != 0) {
  CBS_SOY["oil", "other"]      <- CBS_SOY["oil", "other"] + CBS_SOY["oil", "processing"]
  CBS_SOY["oil", "processing"] <- 0
}
if (!is.na(CBS_SOY["cake", "processing"]) && CBS_SOY["cake", "processing"] != 0) {
  CBS_SOY["cake", "feed"]      <- CBS_SOY["cake", "feed"] + CBS_SOY["cake", "processing"]
  CBS_SOY["cake", "processing"] <- 0
}

# add storage columns for oil and cake in the MU table and allocate according to cake/oil production
SOY_MUN <- SOY_MUN %>%
  mutate(stock_oil = CBS_SOY["oil","stock_addition"]*prod_oil/sum(prod_oil),
         stock_cake = CBS_SOY["cake","stock_addition"]*prod_cake/sum(prod_cake),
         .after=stock_bean)


# harmonize municipal values with national totals -----------------------------

# compare aggregate MU data with target FAO/FABIO data
# create version of table containing only CBS items
SOY_MUN_cbs <- SOY_MUN %>%
  dplyr::select(prod_bean, prod_oil, prod_cake,
                imp_bean, imp_oil, imp_cake,
                exp_bean, exp_oil, exp_cake,
                food_bean, food_oil, feed_bean, feed_cake, seed_bean,
                other_oil, proc_bean, stock_bean:stock_cake)
SOY_agg <- colSums(SOY_MUN_cbs)
SOY_agg <- as.data.frame(cbind("MUN" = SOY_agg,
                               "FAO" = c(CBS_SOY$production, CBS_SOY$import, CBS_SOY$export,
                                         CBS_SOY$food[1:2], CBS_SOY$feed[c(1,3)], CBS_SOY$seed[1],
                                         CBS_SOY$other[2], CBS_SOY$processing[1], CBS_SOY$stock_addition)))
SOY_agg$ratio <- SOY_agg$FAO/SOY_agg$MUN
# Stefan-bug fix: when both FAO and MUN totals are 0 (e.g. cake stock_addition in 2013),
# ratio is 0/0 = NaN. Without this, 0 * NaN = NaN propagates into stock_cake (and any
# other balanced-at-zero item) and downstream blows up step 07_R cake transport.
SOY_agg$ratio[!is.finite(SOY_agg$ratio)] <- 1

# re-scale MU level data to match national FAO values
SOY_MUN[,names(SOY_MUN_cbs)] <- as.data.frame(t(t(SOY_MUN_cbs)*SOY_agg$ratio))

# check for balance, adding columns for total supply and demand of each product
SOY_agg$MUN_fin <- colSums(SOY_MUN[,names(SOY_MUN_cbs)])
SOY_agg$check <- SOY_agg$MUN_fin == SOY_agg$FAO
cat("all items balanced: ", all.equal(SOY_agg$FAO,SOY_agg$MUN_fin), "\n")

# --- stock WITHDRAWAL reallocation (fix for negative municipal total_use) -------------------
# A negative national stock change (drawdown) was distributed across municipalities by grain
# STORAGE capacity (step 01). That put large withdrawals on municipalities with little/no soy
# use, driving total_use negative -> the step-12 re-export inversion went degenerate for the
# drawdown years (2012, 2018-2020). A withdrawal is soy taken from stock to be used/exported,
# so allocate it proportional to each municipality's USE BASE instead. Then
#   total_use = base + base/sum(base)*S = base*(1 + S/sum(base)) >= 0   (since |S| < sum(base)).
# Additions (S >= 0) keep Stefan's storage-capacity split untouched (so 2010-2017 are unchanged).
realloc_withdrawal <- function(stock, base) {
  S <- sum(stock, na.rm = TRUE)
  if (S >= 0) return(stock)
  b <- pmax(base, 0); tb <- sum(b, na.rm = TRUE)
  if (tb <= 0) return(stock)
  w <- b / tb; w[!is.finite(w)] <- 0
  w * S
}
if (STOCK_MODE == "use_prop") {
  # current behaviour: reallocate a net withdrawal onto the use side by use base
  SOY_MUN$stock_bean <- realloc_withdrawal(SOY_MUN$stock_bean,
    with(SOY_MUN, exp_bean + food_bean + feed_bean + seed_bean + proc_bean))
  SOY_MUN$stock_oil  <- realloc_withdrawal(SOY_MUN$stock_oil,
    with(SOY_MUN, exp_oil + food_oil + other_oil))
  SOY_MUN$stock_cake <- realloc_withdrawal(SOY_MUN$stock_cake,
    with(SOY_MUN, exp_cake + feed_cake))
}
# supply_side: leave stock_* as the step-01 storage / production allocation (no realloc);
# a net national withdrawal is reclassified to the supply side just below.

# stock_split(): where does a product's stock term go in the balance?
#   supply_side + net national WITHDRAWAL (sum(stock) < 0) -> |stock| onto SUPPLY, none on use.
#   otherwise (all addition products; everything in use_prop) -> stock stays on the USE side.
# This makes ADDITION years bit-identical in both modes, and guarantees total_use >= 0 in
# supply_side (use side is then just the non-negative use base).
stock_split <- function(stock) {
  if (STOCK_MODE == "supply_side" && sum(stock, na.rm = TRUE) < 0)
    list(sup = -stock, use = rep(0, length(stock)))
  else
    list(sup = rep(0, length(stock)), use = stock)
}
.b <- stock_split(SOY_MUN$stock_bean)
.o <- stock_split(SOY_MUN$stock_oil)
.k <- stock_split(SOY_MUN$stock_cake)

# add totals to mun table
SOY_MUN  <- SOY_MUN %>%
  mutate(total_supply_bean = prod_bean + imp_bean + .b$sup,
                             total_supply_oil = prod_oil + imp_oil + .o$sup,
                             total_supply_cake = prod_cake + imp_cake + .k$sup,
                             total_use_bean = exp_bean + food_bean + feed_bean + seed_bean + proc_bean + .b$use,
                             total_use_oil = exp_oil + food_oil + other_oil + .o$use,
                             total_use_cake = exp_cake + feed_cake + .k$use)

# check balance again
sum(SOY_MUN$total_supply_bean) == sum(SOY_MUN$total_use_bean)
sum(SOY_MUN$total_supply_oil)  == sum(SOY_MUN$total_use_oil)
sum(SOY_MUN$total_supply_cake) == sum(SOY_MUN$total_use_cake)

# add columns for excess supply and demand of each product
SOY_MUN <- mutate(SOY_MUN,
                  excess_supply_bean = ifelse(total_supply_bean - total_use_bean > 0,
                                              total_supply_bean - total_use_bean, 0),
                  excess_supply_oil =  ifelse(total_supply_oil -  total_use_oil > 0,
                                              total_supply_oil -  total_use_oil, 0),
                  excess_supply_cake = ifelse(total_supply_cake - total_use_cake > 0,
                                              total_supply_cake - total_use_cake, 0),
                  excess_use_bean = ifelse(total_use_bean - total_supply_bean > 0,
                                           total_use_bean - total_supply_bean, 0),
                  excess_use_oil =  ifelse(total_use_oil -  total_supply_oil > 0,
                                           total_use_oil -  total_supply_oil, 0),
                  excess_use_cake = ifelse(total_use_cake - total_supply_cake > 0,
                                           total_use_cake - total_supply_cake, 0))

# add columns for domestic use of each product
SOY_MUN <- mutate(SOY_MUN,
                      domestic_use_bean =  total_use_bean - exp_bean,
                      domestic_use_oil  =  total_use_oil -  exp_oil ,
                      domestic_use_cake =  total_use_cake - exp_cake)

# remove redundant columns
SOY_MUN <- dplyr::select(SOY_MUN, -c(proc_fac:storage_cap,
                                     exp_bean_d, exp_oil_d, exp_cake_d,
                                     imp_bean_d, imp_oil_d, imp_cake_d,
                                     cattle:quail))

# merge with GEO file
GEO_MUN_SOY <- right_join(GEO_MUN_SOY,
                          dplyr::select(SOY_MUN, c(co_mun, total_supply_bean:excess_use_cake)),
                          by = "co_mun")

# re-scale MU exports/imports files to match CBS values as well
EXP_MUN_SOY <- mutate(EXP_MUN_SOY,
                      export     = ifelse(product == "soybean",
                                          export*SOY_agg["exp_bean","ratio"],
                                          ifelse(product == "soy_oil",
                                                 export*SOY_agg["exp_oil","ratio"],
                                                 export*SOY_agg["exp_cake","ratio"] )),
                      export_dol = ifelse(product == "soybean",
                                          export_dol*SOY_agg["exp_bean","ratio"],
                                          ifelse(product == "soy_oil",
                                                 export_dol*SOY_agg["exp_oil","ratio"],
                                                 export_dol*SOY_agg["exp_cake","ratio"] )))

IMP_MUN_SOY <- mutate(IMP_MUN_SOY,
                      import     = ifelse(product == "soybean",
                                          import*SOY_agg["imp_bean","ratio"],
                                          ifelse(product == "soy_oil",
                                                 import*SOY_agg["imp_oil","ratio"],
                                                 import*SOY_agg["imp_cake","ratio"] )),
                      import_dol = ifelse(product == "soybean",
                                          import_dol*SOY_agg["imp_bean","ratio"],
                                          ifelse(product == "soy_oil",
                                                 import_dol*SOY_agg["imp_oil","ratio"],
                                                 import_dol*SOY_agg["imp_cake","ratio"] )))

# export data -------------------------------------------------------------------
if(write){
  out_dir <- paste0("data/generated/outputs/05_", YEAR)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  saveRDS(SOY_MUN, file = file.path(out_dir, "SOY_MUN_fin.rds"))
  saveRDS(GEO_MUN_SOY, file = file.path(out_dir, "GEO_MUN_SOY_fin.rds"))
  saveRDS(CBS_SOY, file = file.path(out_dir, "CBS_SOY_bal.rds"))
  saveRDS(EXP_MUN_SOY, file = file.path(out_dir, "EXP_MUN_SOY_cbs.rds"))
  saveRDS(IMP_MUN_SOY, file = file.path(out_dir, "IMP_MUN_SOY_cbs.rds"))
}

# clear environment
rm(list = ls())
gc()

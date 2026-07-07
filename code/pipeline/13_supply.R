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

### supply table ###

# what is changed:
# - supply table is extended by municipal soy supply (taken from extended cbs)
# - grazing is not added for municipalities, as this supply remains national
# - prices: for Brazilian municipal products, the national price of Brazil is used


library(data.table)

write = TRUE 

regions <- fread("data/fabio/v2/inst/regions_full.csv")
items <- fread("data/fabio/v2/inst/items_full.csv")


# Supply ------------------------------------------------------------------

btd <- readRDS("data/fabio/v2/btd_full.rds")
# v2 PORT: FABIO v2 labels animal trade as 'An' / '1000 An'; Stefan's v1.1 code
# expects a 'head' unit (used in the price = usd/head logic below). Normalise:
# fold '1000 An' into 'An' (x1000), then rename 'An' -> 'head'.
if (is.data.table(btd) && "unit" %in% names(btd)) {
  btd[unit == "1000 An", `:=`(value = value * 1000, unit = "An")]
  btd[unit == "An", unit := "head"]
}
cbs <- readRDS(paste0("data/generated/outputs/12_", YEAR, "/cbs_full.rds"))
sup <- fread("data/fabio/v2/inst/items_supply.csv")


cat("Allocate production to supplying processes.\n")

# Add grazing placeholder to the CBS
grazing <- unique(cbs[, c("year", "area", "area_code")])
grazing[, `:=`(item = "Grazing", item_code = 2001)]
cbs <- rbindlist(list(cbs, grazing), use.names = TRUE, fill = TRUE)

## TODO: grazing is not relevant for MUs. Either remove it here or later
# remove grazing for MUs --> verify
cbs <- cbs[!(item == "Grazing" & area_code > 1000),]

# Allocate production to supplying processes including double-counting
sup <- merge(
  cbs[, c("area_code", "area", "year", "item_code", "item", "production")],
  sup[item_code %in% unique(cbs$item_code)],
  by = c("item_code", "item"), all = TRUE, allow.cartesian = TRUE)

# Downscale double-counted production
cat("Calculate supply shares for livestock products.\n")
shares <- fread("data/fabio/v2/inst/items_supply-shares.csv")
live <- readRDS("data/fabio/v2/tidy/live_tidy.rds")

shares <- merge(shares[source == "live"], live[element == "Production"],
  by.x = c("base_code", "base"), by.y = c("item_code", "item"),
  all.x = TRUE, allow.cartesian=TRUE)

# Add regions to RoW if not included in CBS
shares[, `:=`(area = ifelse(!area_code %in% regions$code[regions$cbs], "RoW", area),
              area_code = ifelse(!area_code %in% regions$code[regions$cbs], 999, area_code))]

# Aggregate values
shares <- shares[, list(value = sum(value, na.rm = TRUE)),
  by = list(area_code, area, year, proc_code, proc,
    comm_code, item_code, item)] # aggregating over base by process and item
# Add totals
shares <- merge(
  shares, all.x = TRUE,
  shares[, list(total = sum(value, na.rm = TRUE)),
    by = list(area_code, area, year, comm_code, item_code, item)]) # total production by commodity

shares[, share := value / total] # share of this process in total output of output commodity

sup <- merge(sup,
  shares[, c("area_code", "area", "year", "comm_code", "proc_code", "share")],
  by = c("area_code", "area", "year", "comm_code", "proc_code"), all.x = TRUE)

cat("Applying livestock shares to",
  sup[comm_code %in% shares$comm_code, .N], "observations.\n")
sup[is.na(share) & comm_code %in% shares$comm_code, production := 0]
sup[!is.na(share) & comm_code %in% shares$comm_code,
  production := production * share]

cat("Applying oil extraction shares to",
  sup[comm_code %in% c("c090"), .N],
  "observations of oilseed cakes.\n")
shares_o <- sup[comm_code %in% c("c079", "c080", "c081"),
  list(proc, share_o = production / sum(production, na.rm = TRUE)),
  by = list(area_code, year)]

sup <- merge(sup, shares_o, by = c("area_code", "year", "proc"), all.x = TRUE)
sup[is.na(share_o), share_o := 0]
sup[is.na(share) & comm_code %in% c("c090"),  # c090 = "Oilseed Cakes, Other"
  `:=`(production = production * share_o)]
sup[, share_o := NULL]

sup[, share := NULL]


# Fill prices using BTD ---------------------------------------------------

prices <- as.data.table(data.table::dcast(btd, from + from_code + to + to_code +
  item + item_code + year ~ unit, value.var = "value"))
prices <- prices[!is.na(usd) & usd > 0 & sum(head, tonnes, na.rm = TRUE) > 0 &
                   (!is.na(head) | !is.na(tonnes)),
  list(usd = sum(usd, na.rm = TRUE), head = sum(head, na.rm = TRUE),
    tonnes = sum(tonnes, na.rm = TRUE)),
    by = list(from, from_code, item_code, item, year)]

prices[, price := ifelse(tonnes != 0 & !is.na(tonnes), usd / tonnes,
  ifelse(head != 0 & !is.na(head), usd / head, NA))]

# Cap prices at 10th and 90th quantiles.
# We might want to add a yearly element.
caps <- prices[, list(price_q95 = quantile(price, .95, na.rm = TRUE),
  price_q90 = quantile(price, .90, na.rm = TRUE),
  price_q50 = quantile(price, .50, na.rm = TRUE),
  price_q10 = quantile(price, .10, na.rm = TRUE),
  price_q05 = quantile(price, .05, na.rm = TRUE)),
  by = list(item)]
prices <- merge(prices, caps, by = "item", all.x = TRUE)

cat("Capping ", prices[price > price_q90 | price < price_q10, .N],
  " prices at the specific item's 90th and 10th quantiles.\n", sep = "")
prices[, price := ifelse(price > price_q90, price_q90,
  ifelse(price < price_q10, price_q10, price))]

# Get worldprices to fill gaps
na_sum <- function(x) {ifelse(all(is.na(x)), NA_real_, sum(x, na.rm = TRUE))}
prices_world <- prices[!is.na(usd), list(usd = na_sum(usd),
                                         tonnes = na_sum(tonnes), head = na_sum(head)),
                       by = list(item, item_code, year)]
prices_world[, price_world := ifelse(head != 0, usd / head,
                                     ifelse(tonnes != 0, usd / tonnes, NA))]
prices_world_all <- prices_world[, list(price_world = mean(price_world, na.rm = TRUE)),
                                 by = list(item, item_code)]
prices <- merge(
  prices, prices_world[, c("year", "item_code", "item", "price_world")],
  by = c("year", "item_code", "item"), all.x = TRUE)
prices <- merge(
  prices, prices_world_all[, .(item_code, item, price_average = price_world)],
  by = c("item_code", "item"), all.x = TRUE)

cat("Filling ", prices[is.na(price) & !is.na(price_world), .N],
    " missing prices with world prices per year.\n", sep = "")
prices[is.na(price), price := price_world]
cat("Filling ", prices[is.na(price) & !is.na(price_average), .N],
    " missing prices with world average prices.\n", sep = "")
prices[is.na(price), price := price_average]


cat("Filling ", prices[!is.finite(price) & !is.na(price_q50), .N],
  " missing prices with median item prices.\n", sep = "")
prices[!is.finite(price), price := price_q50]
prices[!is.finite(price_world), price := price_q50]

sup <- merge(sup, all.x = TRUE,
  prices[, c("from_code", "from", "item", "item_code", "year", "price")],
  by.x = c("area_code", "area", "item", "item_code", "year"),
  by.y = c("from_code", "from", "item", "item_code", "year"))

## TODO: for Brazilian municipalities, use uniform Brazilian price
prices_brazil <- prices[from_code == 21,]
setnames(prices_brazil, 'price', 'price_brazil')

sup <- merge(sup, all.x = TRUE,
             prices_brazil[, c("item", "item_code", "year", "price_brazil")],
             by = c("item", "item_code", "year"))

# apply Brazilian price to MU
sup[, `:=`(price = ifelse(area_code > 1000, price_brazil, price),
           price_brazil = NULL)]

# apply world average price where price is NA
sup <- merge(sup, all.x = TRUE,
  prices_world[, c("item", "item_code", "year", "price_world")],
  by = c("item", "item_code", "year"))
sup <- merge(sup, all.x = TRUE,
  prices_world_all[, .(item, item_code, price_average = price_world)],
  by = c("item", "item_code"))
sup[, `:=`(price = ifelse(is.na(price), ifelse(is.na(price_world), price_average, price_world), price),
           price_world = NULL, price_average = NULL)]

# estimate the price of palm kernels at 60% of the price of palm oil
sup <- merge(sup, all.x = TRUE,
  sup[item == "Palm Oil", .(year, area_code, price_oil = price)],
  by = c("area_code", "year"))
sup[, `:=`(price = ifelse(item == "Palm kernels", price_oil * 0.6, price),
  price_oil = NULL)]

# # fill missing prices for oils and cakes with global averages
# price_oil <- prices[grepl(" Oil", item),
#   list(price_oil = na_sum(usd) / na_sum(tonnes)),
#   by = list(year)]
# price_oil <- merge(price_oil, all.x = TRUE,
#   prices[grepl("Cake", item),
#   list(price_cake = na_sum(usd) / na_sum(tonnes)),
#   by = list(year)],
#   by = "year")
# sup <- merge(sup, all.x = TRUE,
#   price_oil[, .(year, price_oil, price_cake)],
#   by = "year")
# sup[grepl("Cake", item), `:=`(price = ifelse(is.na(price), price_cake, price))]
# sup[grepl(" Oil", item), `:=`(price = ifelse(is.na(price), price_oil, price))]

# fill in milk prices
# v2 PORT: v1.1's prices_tidy split milk by species ("...cow"/"...buffalo"/...), so the
# original code spread those and averaged. v2 only carries "Milk, Total" and may lack USD
# rows, so the species spread yields an empty table and crashes. Use a version-agnostic
# milk price = mean USD value of any "Milk" item per area/year, with empty-table guards.
mprices <- readRDS("data/fabio/v2/tidy/prices_tidy.rds")
mprices <- mprices[grepl("Milk", item) & months == "Annual value" & unit == "USD",
                   .(area_code, area, year, value)]
milk_ay <- if (nrow(mprices)) mprices[, .(milk = mean(value, na.rm = TRUE)),
                                      by = .(area_code, area, year)] else
           data.table(area_code = integer(), area = character(),
                      year = integer(), milk = numeric())
sup <- merge(sup, all.x = TRUE, milk_ay[, .(year, area_code, milk)],
             by = c("area_code", "year"))
# earliest available price per area
milk_earliest <- if (nrow(milk_ay)) milk_ay[, .SD[which.min(year)], by = area][
                   , .(area_code, milk_earliest = milk)] else
                 data.table(area_code = integer(), milk_earliest = numeric())
sup <- merge(sup, all.x = TRUE, milk_earliest, by = "area_code")
# global average per year, with a scalar fallback for years with no data
milk_avg_tab <- if (nrow(milk_ay)) milk_ay[, .(milk_avg = mean(milk, na.rm = TRUE)),
                                           by = year] else
                data.table(year = integer(), milk_avg = numeric())
sup <- merge(sup, all.x = TRUE, milk_avg_tab, by = "year")
.milk_fallback <- if (nrow(milk_avg_tab)) milk_avg_tab[which.min(year), milk_avg] else NA_real_
sup[is.na(milk_avg), milk_avg := .milk_fallback]
sup[item == "Milk - Excluding Butter", price := data.table::fifelse(!is.na(milk), milk,
  data.table::fifelse(!is.na(milk_earliest), milk_earliest, milk_avg))]
sup[, `:=`(milk = NULL, milk_earliest = NULL, milk_avg = NULL)]

setkey(sup, year, area_code, comm_code, proc_code)

# Store results -----------------------------------------------------------

if(write){
  saveRDS(sup, "data/generated/fabio/sup.rds")
}

rm(list = ls())
gc()


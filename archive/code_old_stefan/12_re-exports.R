### re-allocation of re-exports, including the sub-national inter-municipality trade ###

# what is changed:
# - btd is extended by municipal soy trade, replacing Brazil for these items
# - cbs is extended by municipalities, replacing Brazil for these items
# - cbs is harmonized with new (extended) btd, using stock_addition as balancing vehicle
# - re-export algorithm is corrected for trade in goods taken from stock
# -- stock_addition is split into a positive (= use) and negative (= withdrawal, part of supply) part
# -- domestic and total supply includes stock withdrawals, domestic and total use also increases as (negative) stock_withdrawals are deducted
# -- the stock withdrawals are hence treated as a domestic supply item for the re-export allocation
# ---and will later be re-included as a negative (final) use item so that total domestic supply equals production
# - sparse matrix to data.table reshaping is made more efficient
# - calculations are restricted to 2013

library(data.table)
library(Matrix)
library(dplyr)
library(tidyr)
library(tibble)
source("code/shared/fabio_tidy_functions.R")

write = TRUE

# load data ---------------------------------------------------------------

SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
soy_items <- c("bean" = 2555, "oil" = 2571, "cake" = 2590)

# BTD 
btd <- readRDS("data/old/FABIO/FABIO_exp/v1/btd_bal.rds") %>% filter(year == 2013)
btd_soy <- filter(btd, item_code %in% soy_items)

# CBS
cbs <- readRDS("data/old/FABIO/FABIO_exp/v1/cbs_full.rds") %>% filter(year == 2013) # CBS from same FABIO version!

items <- read.csv("data/old/FABIO/FABIO_exp/items.csv")# unique(cbs$item_code)
regions <- readRDS("results/intermediate/regions.rds")
regions_btd <- distinct(regions, CO_BTD, ISO_BTD) %>% arrange(CO_BTD)
areas <- sort(unique(cbs$area_code))

# sub-national soy trade: imports, exports and intra-municipal trade flows
exp <- readRDS("results/intermediate/EXP_MUN_SOY_cbs.rds")
imp <- readRDS("results/intermediate/IMP_MUN_SOY_cbs.rds")
intra <- readRDS("results/intermediate/flows_mu.rds") # readRDS("results/intermediate/X_a_b_tot_nn.rds")


# prepare reallocation of re-exports --------------------------------------

## BTD -----------------

# extend bilateral trade data with sub-national soy trade (imp,exp,intra) of Brazilian MUs

# bring MU exports in same format as btd
btd_MUN_exp <- exp %>% dplyr::select(co_mun, item_code, to_code, export) %>%
  rename("from_code" = "co_mun", "value" = "export") %>%
  relocate(to_code, .after = from_code) %>% relocate(item_code, .before = from_code)

# bring MU imports in same format as btd
btd_MUN_imp <- imp %>% dplyr::select(co_mun, item_code, from_code, import) %>%
  rename("to_code" = "co_mun", "value" = "import") %>%
  relocate(to_code, .after = from_code) %>% relocate(item_code, .before = from_code)

# bring intra-MU trade in same format as btd
btd_MUN_intra <- intra %>% 
  mutate(item_code = soy_items[product]) %>% # ifelse(product=="bean", 2555, ifelse(product == "oil", 2571,2590))
  dplyr::select(!product) %>%
  rename("from_code" = "co_orig", "to_code" = "co_dest") %>%
  relocate(item_code, .before = from_code)
# select multimodal results as main results to move forward
btd_MUN_intra <- btd_MUN_intra %>% 
  dplyr::select(!euclid) %>%
  rename(value = mean)

# append to btd_soy table (after removing BRA)
btd_soy_ext <- btd_soy %>% 
  filter(from_code != 21 & to_code !=21) %>% 
  dplyr::select(!year) %>%
  bind_rows(btd_MUN_exp, btd_MUN_imp,btd_MUN_intra)

# append to full btd table (after removing soy_items)
btd_ext <- btd %>% 
  filter(!item_code %in% soy_items) %>% 
  dplyr::select(!year) %>%
  bind_rows(btd_soy_ext)

rm(btd_soy_ext)

# Create a structure to map importers to exporters per item (+ targets) 

# ...for non-soy commodities (standard FABIO countries with Brazil as a whole)
regions_code <- regions_btd$CO_BTD
mapping_templ <- data.table(expand.grid(
  from_code = regions_code, to_code = regions_code, stringsAsFactors = FALSE))
setkey(mapping_templ, from_code, to_code)

# ...for soy commodities (replacing Brazil with its municipalities)
regions_soy <- regions_btd %>% 
  filter(ISO_BTD != "BRA") %>% 
  bind_rows(setNames(SOY_MUN[,1:2], names(regions_btd)))
regions_code_soy <- regions_soy$CO_BTD

mapping_templ_soy <- data.table(expand.grid(
  from_code = regions_code_soy, to_code = regions_code_soy, stringsAsFactors = FALSE))
setkey(mapping_templ_soy, from_code, to_code)

# Assign btd data to mapping & restructure into sparse matrix by item

mapping_reex <- lapply(items$item_code, function(x){
  btd_item <- filter(btd_ext, item_code == x) %>% dplyr::select(!item_code)
  # use the appropriate template for the respective item
  if(x %in% soy_items){
    templ <- mapping_templ_soy
    dims <- regions_code_soy
    } else {
    templ <- mapping_templ 
    dims <- regions_code} 
  map <- left_join(templ, btd_item, by = c("from_code", "to_code")) %>% replace_na(list(value = 0))
  # restructure into sparse matrix
  mat <- with(map, sparseMatrix(i=dense_rank(from_code), j = dense_rank(to_code), x=value, dimnames=list(dims, dims)))
  return(mat)
  })
names(mapping_reex) <- items$item_code

rm(mapping_templ, mapping_templ_soy)


## CBS --------------------

# extend CBS with sub-national data for soy items for Brazilian MUs

# add domestic and total use to cbs
cbs[, dom_use := na_sum(feed, food, losses, other, processing, seed, stock_addition, balancing, unspecified)]
cbs[, total_use := na_sum(dom_use, exports)]

# reshape SOY_MUN so that soy products go into separate rows
SOY_MUN_long <- SOY_MUN %>% 
  pivot_longer(cols = ends_with(c("_bean", "_oil", "_cake")), names_to = c(".value", "product"), names_pattern = "(.+)_(.+$)") %>% #cols = prod_bean:domestic_use_cake
  mutate_all(~replace(., is.na(.), 0)) %>% 
  mutate(item_code = soy_items[product], .before = product) %>% # item_code = ifelse(product=="bean", 2555, ifelse(product == "oil", 2571,2590))
  rename(area_code = co_mun,
         area = nm_mun,
         production = prod, 
         imports = imp, 
         exports = exp, 
         processing = proc,
         stock_addition = stock, 
         dom_use = domestic_use)

# intra-MU trade is now part of imports/exports of MUs:
# add excess supply (supply that flows to other MUs) and excess use (use that is supplied by other MUs) across MUs needs to exports/imports
SOY_MUN_long <- mutate(SOY_MUN_long, 
                       imports = imports + excess_use, 
                       exports = exports + excess_supply, 
                       total_use = total_use + excess_supply, 
                       total_supply = total_supply + excess_use)


# extend cbs_ext with long SOY_MUN table, replacing Brazilian soy items
cbs_ext<- cbs %>% 
  dplyr::select(!c(item, year, stock_withdrawal)) %>% 
  filter(!(area_code == 21 & item_code %in% soy_items)) %>%
  bind_rows(dplyr::select(SOY_MUN_long, intersect(names(cbs), names(SOY_MUN_long)))) %>% #!c(co_state:nm_state, product, starts_with("excess"))
  mutate_all(~replace(., is.na(.), 0))

## append to full cbs table (after removing soy_items)
#cbs_ext <- cbs %>% 
#  dplyr::select(!c(item, year, stock_withdrawal)) %>% 
#  filter(!item_code %in% soy_items) %>%
#  bind_rows(cbs_soy_extended) %>% 
#  mutate_all(~replace(., is.na(.), 0))

# set negative domestic use to zero
# TODO: this is just a temporary fix
# cbs_soy_extended$dom_use[cbs_soy_extended$dom_use < 0] <- 0


## harmonize CBS with BTD ------------------

# adapt trade values in cbs to match full btd
exp <- group_by(btd_ext, item_code, from_code) %>% 
   summarise(exp_btd = sum(value, na.rm = TRUE)) %>% filter(exp_btd != 0)
imp <- group_by(btd_ext, item_code, to_code) %>% 
   summarise(imp_btd = sum(value, na.rm = TRUE)) %>% filter(imp_btd != 0)

cbs_ext <- full_join(cbs_ext, exp, by = c("area_code" = "from_code", "item_code" = "item_code")) %>%
  full_join(imp, by = c("area_code" = "to_code", "item_code" = "item_code")) %>%
  mutate(area = ifelse(is.na(area), regions$name[match(area_code, regions$CO_BTD)],area)) %>%
  mutate_all(~replace(., is.na(.), 0))

cbs_ext <- mutate(cbs_ext, exp_diff = exp_btd - exports, imp_diff = imp_btd - imports)

# add import difference to import and total supply, add export difference to export and total use
cbs_ext <- mutate(cbs_ext,
                           imports = imports + imp_diff, 
                           total_supply = total_supply + imp_diff,
                           exports = exports + exp_diff,
                           total_use = total_use + exp_diff)

# compensate difference between total supply and total use via stock addition
cbs_ext <- mutate(cbs_ext, sup_use_bal = total_supply - total_use) %>%
  mutate(stock_addition = stock_addition + sup_use_bal)

# finally also adapt domestic and total use according to new stock addition
cbs_ext <- mutate(cbs_ext, 
                           dom_use = dom_use + sup_use_bal, 
                           total_use = total_use + sup_use_bal)
# some checks
cbs_ext <- mutate(cbs_ext,
                           bal_check = total_supply == total_use,
                           sup_check = (production + imports) == total_supply,
                           use_check = (exports + feed + food + losses + other + processing + seed + stock_addition + balancing + unspecified) == total_use,
                           dom_use_check = (feed + food + losses + other + processing + seed + stock_addition + balancing + unspecified) == dom_use)

cbs_ext <- mutate(cbs_ext,
                           bal_diff = total_supply - total_use,
                           sup_diff = (production + imports) - total_supply,
                           use_diff = (exports + feed + food + losses + other + processing + seed + stock_addition + balancing + unspecified) - total_use,
                           dom_use_diff = (feed + food + losses + other + processing + seed + stock_addition + balancing + unspecified) - dom_use)

cbs_ext <- dplyr::select(cbs_ext, -c(exp_btd:dom_use_diff))


# finally, for the re-export allocation, we need to split stock changes into 
# - positive values (stock additions)  --> part of domestic use
# - negative values (stock withdrawals) --> part of domestic supply

cbs_ext <- cbs_ext %>% 
  mutate(stock_positive = ifelse(stock_addition > 0, stock_addition, 0),
         stock_negative = ifelse(stock_addition < 0, -stock_addition, 0), .after = stock_addition) %>%
  mutate(dom_supply = production + stock_negative,
         total_supply = total_supply + stock_negative,
         # negative stock additions previously decreased use
         dom_use = dom_use + stock_negative, 
         total_use = total_use + stock_negative, .after = unspecified)



# re-allocate re-exports ---------------------------------------------------------------------------

reex <- lapply(items$item_code, function(x){
  if(x %in% soy_items) {reg <- regions_code_soy} else {reg <- regions_code}
  data <- merge(data.table(area_code = reg),
              cbs_ext[item_code == x, .(area_code, dom_supply, dom_use, total_use, dom_share = dom_supply / total_use)],
              by = "area_code", all = TRUE) %>%
    mutate_all(~replace(., is.na(.), 0))

  denom <- data$total_use
  denom[denom == 0] <- 1 # make sure all colSums(mat[,denom == 0]) = 0 anyway
  #mat <- mapping_reex[[names(soy_items)[soy_items == x]]]
  mat <- mapping_reex[[paste(x)]]
  
  # divide bilateral trade matrix by total use (domestic use + exports) along columns --> technical coefficient matrix use/total use
  # i.e. what is the share of soy from country x in the total use of country y
  mat <- t(t(mat) / denom)
  
  # Leontief inverse (I - A)^-1: how much soy from country x is needed for an extra unit of use in y
  mat <- diag(nrow(mat)) - mat
  mat <- solve(mat, sparse = TRUE) # make sure to use sparse = TRUE so that the matrix remains in compressed dgC format!
  # mat <- Matrix(mat, sparse = TRUE)
  
  # remove re-exports
  mat <- mat * data$dom_share # for 100 soybeans consumed in country and sourced from country x, how many of them where produced in x?
  mat <- t(t(mat) * data$dom_use) # for the actual number of soybeans consumed in y, how many where produced in x?
  colnames(mat) <- rownames(mat)
  
  cat(x, ": ", 
      all.equal(colSums(mat), data$dom_use, check.attributes = FALSE), " / ",
      all.equal(rowSums(mat), data$dom_supply, check.attributes = FALSE), " \n")
  
  return(mat)
})
names(reex) <- items$item_code


# reshape back to long format

btd_final <- lapply(items$item_code, function(x) {
  # convert to triplet form
  #m <- reex[[names(soy_items)[soy_items == x]]]
  m <- reex[[paste(x)]]
  m <- as(m, "dgTMatrix")
  # convert to data frame: convert to 1-based indexing (see https://stackoverflow.com/questions/52662748/from-sparsematrix-to-dataframe)
  df <- data.frame(i=as.integer(rownames(m)[m@i + 1]), j=as.integer(colnames(m)[m@j + 1]), x=m@x)
  names(df) <- c("from_code", "to_code", "value")
  df <- mutate(df, item_code = x, .before = from_code)
  })

# bind to long list
btd_final <- rbindlist(btd_final)

# set negative values to zero
# NOTE: no longer necessary since there are no negative values
#btd_soy_final$value[btd_soy_final$value <0] <- 0

# add commodity code and year
btd_final <- mutate(btd_final, year = 2013, .before = item_code) %>%
  mutate(comm_code = items$comm_code[match(btd_final$item_code, items$item_code)])


# bring cbs values back into original format, deducting stock withdrawals again as a negative use item
cbs_full <- mutate(cbs_ext, 
                       item = items$item[match(cbs_ext$item_code, items$item_code)],  
                       year = 2013,
                       total_supply = total_supply - stock_negative, # remove stock withdrawals from supply/use aggregates again
                       dom_supply = dom_supply - stock_negative,
                       dom_use = dom_use - stock_negative,
                       total_use = total_use - stock_negative,
                       stock_withdrawal = - stock_addition) # just the mirror of original stock addition 

cbs_full <- dplyr::select(cbs_full, names(cbs))

# save results -----------------------------------------------
if (write){
  saveRDS(reex, "results/intermediate/FABIO/reex.rds")
  saveRDS(btd_final, "results/intermediate/FABIO/btd_final.rds")
  saveRDS(cbs_full, "results/intermediate/FABIO/cbs_full.rds")
}

rm(list = ls())
gc()

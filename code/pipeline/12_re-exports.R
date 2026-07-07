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
# - calculations year-parameterized via YEAR (was: restricted to 2013)

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(data.table)
library(Matrix)
library(dplyr)
library(tidyr)
library(tibble)
source("code/shared/fabio_tidy_functions.R")

write = TRUE

out_dir <- paste0("data/generated/outputs/12_", YEAR)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# load data ---------------------------------------------------------------

SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
soy_items <- c("bean" = 2555, "oil" = 2571, "cake" = 2590)

# BTD. Per Martin Bruckner (WU Vienna), the new multi-year btd_bal.RData (2010-2023)
# can be used in place of all three legacy variants (regular, FABIO_exp v1, FABIO_exp pure).
# Prefer it when available; fall back to Stefan's 2013-pinned snapshot otherwise.
.btd_new_path <- "data/fabio/trade/new/btd_bal.RData"
.btd_old_path <- "data/fabio/trade/FABIO_exp/v1/btd_bal.rds"
if (file.exists(.btd_new_path)) {
  .env <- new.env()
  load(.btd_new_path, envir = .env)
  btd <- as.data.frame(.env$btd_bal) %>% filter(year == YEAR)
  rm(.env)
  message(sprintf("[12] Loaded btd from new multi-year file (%d rows for YEAR=%d).", nrow(btd), YEAR))
} else {
  btd <- readRDS(.btd_old_path) %>% filter(year == YEAR)
}
btd_soy <- filter(btd, item_code %in% soy_items)

# CBS. New refreshed file at data/fabio/trade/new/cbs_full.rds covers 1961-2024 with
# full country & item coverage including Soyabean Cake post-2013. Schema differs from
# the legacy v1 cbs_full: rename supply -> total_supply, add unspecified = 0
# (the new schema folds it into balancing/residuals).
.cbs_new_path <- "data/fabio/trade/new/cbs_full.rds"
.cbs_old_path <- "data/fabio/trade/FABIO_exp/v1/cbs_full.rds"
if (file.exists(.cbs_new_path)) {
  cbs <- readRDS(.cbs_new_path) %>% filter(year == YEAR)
  if ("supply" %in% names(cbs) && !"total_supply" %in% names(cbs)) {
    cbs <- dplyr::rename(cbs, total_supply = supply)
  }
  if (!"unspecified" %in% names(cbs)) cbs$unspecified <- 0
  message(sprintf("[12] Loaded cbs from new multi-year file (%d rows for YEAR=%d).", nrow(cbs), YEAR))
} else {
  cbs <- readRDS(.cbs_old_path) %>% filter(year == YEAR)
}

if (nrow(btd) == 0 || nrow(cbs) == 0) {
  warning(sprintf(
    "FABIO data has no rows for YEAR=%d. Check data/fabio/trade/new/{btd_bal.RData,cbs_full.rds}.",
    YEAR))
}

items <- read.csv("data/fabio/trade/FABIO_exp/items.csv")
regions <- readRDS(paste0("data/generated/outputs/04_", YEAR, "/regions.rds"))
regions_btd <- distinct(regions, CO_BTD, ISO_BTD) %>% arrange(CO_BTD)
areas <- sort(unique(cbs$area_code))

# sub-national soy trade: imports, exports and intra-municipal trade flows
exp <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/EXP_MUN_SOY_cbs.rds"))
imp <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/IMP_MUN_SOY_cbs.rds"))
intra <- readRDS(paste0("data/generated/outputs/08_", YEAR, "/flows_mu.rds"))


# prepare reallocation of re-exports --------------------------------------

## BTD -----------------

btd_MUN_exp <- exp %>% dplyr::select(co_mun, item_code, to_code, export) %>%
  rename("from_code" = "co_mun", "value" = "export") %>%
  relocate(to_code, .after = from_code) %>% relocate(item_code, .before = from_code)

btd_MUN_imp <- imp %>% dplyr::select(co_mun, item_code, from_code, import) %>%
  rename("to_code" = "co_mun", "value" = "import") %>%
  relocate(to_code, .after = from_code) %>% relocate(item_code, .before = from_code)

btd_MUN_intra <- intra %>%
  mutate(item_code = soy_items[product]) %>%
  dplyr::select(!product) %>%
  rename("from_code" = "co_orig", "to_code" = "co_dest") %>%
  relocate(item_code, .before = from_code)
btd_MUN_intra <- btd_MUN_intra %>%
  dplyr::select(!euclid) %>%
  rename(value = mean)

btd_soy_ext <- btd_soy %>%
  filter(from_code != 21 & to_code !=21) %>%
  dplyr::select(!year) %>%
  bind_rows(btd_MUN_exp, btd_MUN_imp,btd_MUN_intra)

btd_ext <- btd %>%
  filter(!item_code %in% soy_items) %>%
  dplyr::select(!year) %>%
  bind_rows(btd_soy_ext)

rm(btd_soy_ext)

regions_code <- regions_btd$CO_BTD
mapping_templ <- data.table(expand.grid(
  from_code = regions_code, to_code = regions_code, stringsAsFactors = FALSE))
setkey(mapping_templ, from_code, to_code)

regions_soy <- regions_btd %>%
  filter(ISO_BTD != "BRA") %>%
  bind_rows(setNames(SOY_MUN[,1:2], names(regions_btd)))
regions_code_soy <- regions_soy$CO_BTD

mapping_templ_soy <- data.table(expand.grid(
  from_code = regions_code_soy, to_code = regions_code_soy, stringsAsFactors = FALSE))
setkey(mapping_templ_soy, from_code, to_code)

mapping_reex <- lapply(items$item_code, function(x){
  btd_item <- filter(btd_ext, item_code == x) %>% dplyr::select(!item_code)
  if(x %in% soy_items){
    templ <- mapping_templ_soy
    dims <- regions_code_soy
    } else {
    templ <- mapping_templ
    dims <- regions_code}
  map <- left_join(templ, btd_item, by = c("from_code", "to_code")) %>% replace_na(list(value = 0))
  mat <- with(map, sparseMatrix(i=dense_rank(from_code), j = dense_rank(to_code), x=value, dimnames=list(dims, dims)))
  return(mat)
  })
names(mapping_reex) <- items$item_code

rm(mapping_templ, mapping_templ_soy)


## CBS --------------------

cbs[, dom_use := na_sum(feed, food, losses, other, processing, seed, stock_addition, balancing, unspecified)]
cbs[, total_use := na_sum(dom_use, exports)]

SOY_MUN_long <- SOY_MUN %>%
  pivot_longer(cols = ends_with(c("_bean", "_oil", "_cake")), names_to = c(".value", "product"), names_pattern = "(.+)_(.+$)") %>%
  mutate_all(~replace(., is.na(.), 0)) %>%
  mutate(item_code = soy_items[product], .before = product) %>%
  rename(area_code = co_mun,
         area = nm_mun,
         production = prod,
         imports = imp,
         exports = exp,
         processing = proc,
         stock_addition = stock,
         dom_use = domestic_use)

SOY_MUN_long <- mutate(SOY_MUN_long,
                       imports = imports + excess_use,
                       exports = exports + excess_supply,
                       total_use = total_use + excess_supply,
                       total_supply = total_supply + excess_use)


cbs_ext<- cbs %>%
  dplyr::select(!c(item, year, stock_withdrawal)) %>%
  filter(!(area_code == 21 & item_code %in% soy_items)) %>%
  bind_rows(dplyr::select(SOY_MUN_long, intersect(names(cbs), names(SOY_MUN_long)))) %>%
  mutate_all(~replace(., is.na(.), 0))


## harmonize CBS with BTD ------------------

exp <- group_by(btd_ext, item_code, from_code) %>%
   summarise(exp_btd = sum(value, na.rm = TRUE)) %>% filter(exp_btd != 0)
imp <- group_by(btd_ext, item_code, to_code) %>%
   summarise(imp_btd = sum(value, na.rm = TRUE)) %>% filter(imp_btd != 0)

cbs_ext <- full_join(cbs_ext, exp, by = c("area_code" = "from_code", "item_code" = "item_code")) %>%
  full_join(imp, by = c("area_code" = "to_code", "item_code" = "item_code")) %>%
  mutate(area = ifelse(is.na(area), regions$name[match(area_code, regions$CO_BTD)],area)) %>%
  mutate_all(~replace(., is.na(.), 0))

# Brazil soy (bean/oil/cake) is fully municipalized (line ~178 removed area 21 for soy
# items), so Brazil-national must never carry these. The full_join above can re-introduce
# an area_code==21 row for a soy item when the harmonized BTD has a residual Brazil-keyed
# flow (observed for soybean OIL 2571 in 2016/2021/2022). That stray row is NOT in
# `regions_code_soy` (the re-export matrix dimensions, 5761), so it later sneaks a 5762nd
# row into the per-commodity merge below and recycles/corrupts the WHOLE oil re-export
# (btd_final BRA -2744 Mt, RoW +9130 Mt -> negative Brazil footprint downstream).
# Re-assert the invariant here so 21 can't leak back in.
cbs_ext <- cbs_ext[!(area_code == 21 & item_code %in% soy_items)]

cbs_ext <- mutate(cbs_ext, exp_diff = exp_btd - exports, imp_diff = imp_btd - imports)

cbs_ext <- mutate(cbs_ext,
                           imports = imports + imp_diff,
                           total_supply = total_supply + imp_diff,
                           exports = exports + exp_diff,
                           total_use = total_use + exp_diff)

cbs_ext <- mutate(cbs_ext, sup_use_bal = total_supply - total_use) %>%
  mutate(stock_addition = stock_addition + sup_use_bal)

cbs_ext <- mutate(cbs_ext,
                           dom_use = dom_use + sup_use_bal,
                           total_use = total_use + sup_use_bal)
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


cbs_ext <- cbs_ext %>%
  mutate(stock_positive = ifelse(stock_addition > 0, stock_addition, 0),
         stock_negative = ifelse(stock_addition < 0, -stock_addition, 0), .after = stock_addition) %>%
  mutate(dom_supply = production + stock_negative,
         total_supply = total_supply + stock_negative,
         dom_use = dom_use + stock_negative,
         total_use = total_use + stock_negative, .after = unspecified)



# re-allocate re-exports ---------------------------------------------------------------------------

# Robust inverse of (I - mat). Stefan only ran 2013, where the sparse solver always
# succeeds. For YEAR >= 2014 the newer multi-year FABIO trade data can make (I - mat)
# near-singular for an individual commodity (a re-export chain that forms a near-closed
# loop), which aborts the WHOLE script with
#   "LU factorization of .gCMatrix failed: out of memory or near-singular".
# This inverter falls back gracefully so one bad commodity no longer kills the run:
#   1) original sparse solver (exact, unchanged for the normal case);
#   2) plain dense solve  -- recovers exact values when only the sparse LU choked;
#   3) dense solve with a tiny diagonal ridge (eps) -- lifts a true unit eigenvalue.
# Every commodity that needs (2) or (3) is recorded in `reex_singular` and printed.
reex_singular <- list()
invert_reex <- function(M, item) {
  dn <- dimnames(M)
  # 1) original sparse solver (exact, unchanged for the normal case)
  r <- tryCatch(solve(M, sparse = TRUE), error = function(e) NULL)
  if (!is.null(r)) return(r)
  Md <- as.matrix(M)
  finish <- function(r, how) {            # restore dimnames, record path, return sparse
    dimnames(r) <- dn
    reex_singular[[as.character(item)]] <<- how
    as(r, "CsparseMatrix")
  }
  # 2) plain dense solve — recovers exact values when only the sparse LU choked
  r <- tryCatch(solve(Md), error = function(e) NULL)
  if (!is.null(r)) return(finish(r, "dense (sparse LU failed)"))
  # 3) dense solve with a ridge SCALED to the matrix magnitude. A fixed 1e-8 is too
  #    small when a near-zero total_use denominator inflates the entries (item 2555,
  #    2018+), so scale it so the regularization actually lifts the singularity.
  eps <- 1e-6 * max(abs(Md))
  r <- tryCatch(solve(Md + diag(eps, nrow(Md))), error = function(e) NULL)
  if (!is.null(r)) return(finish(r, sprintf("dense + scaled ridge eps=%.2e", eps)))
  # 4) truly singular -> Moore-Penrose pseudo-inverse (always defined; least-norm).
  #    The re-export balance (colSums≈dom_use / rowSums≈dom_supply) is then only
  #    approximate for this one commodity — flagged here so it's transparent.
  return(finish(MASS::ginv(Md), "pseudo-inverse (MASS::ginv) — re-export balance approximate"))
}

reex <- lapply(items$item_code, function(x){
  if(x %in% soy_items) {reg <- regions_code_soy} else {reg <- regions_code}
  # all.x = TRUE (NOT all = TRUE): the share/use vectors MUST align row-for-row with the
  # re-export matrix, whose dimensions are exactly `reg`. A full outer join would append any
  # cbs_ext area outside `reg` (e.g. a leaked Brazil-21 soy row) as an extra row, making
  # `data` length 5762 vs the 5761x5761 matrix; the element-wise ops below then recycle and
  # silently corrupt the entire commodity's re-export. Left join on the matrix dims is exact.
  data <- merge(data.table(area_code = reg),
              cbs_ext[item_code == x, .(area_code, dom_supply, dom_use, total_use, dom_share = dom_supply / total_use)],
              by = "area_code", all.x = TRUE) %>%
    mutate_all(~replace(., is.na(.), 0))
  # Guard: total_use == 0 makes dom_share = dom_supply/0 = Inf. mutate_all replaces NA but not
  # Inf, so the Inf survives and, via the matrix product below, poisons the ENTIRE commodity's
  # re-export. A single total_use==0 municipality (e.g. Chui, 2018-2020) collapsed the whole
  # soybean re-export this way. Set non-finite shares to 0 (those regions supply nothing here).
  data$dom_share[!is.finite(data$dom_share)] <- 0

  denom <- data$total_use
  denom[denom == 0] <- 1
  mat <- mapping_reex[[paste(x)]]

  # Hard guard: the share/use vectors and the re-export matrix must be dimensionally aligned.
  # If they ever diverge the products below recycle and produce garbage (see the soybean-oil
  # off-by-one). Fail loudly here rather than emitting a corrupt btd_final.
  stopifnot(nrow(data) == nrow(mat), length(denom) == ncol(mat))

  mat <- t(t(mat) / denom)

  mat <- diag(nrow(mat)) - mat
  mat <- invert_reex(mat, x)

  mat <- mat * data$dom_share
  mat <- t(t(mat) * data$dom_use)
  colnames(mat) <- rownames(mat)

  cat(x, ": ",
      all.equal(colSums(mat), data$dom_use, check.attributes = FALSE), " / ",
      all.equal(rowSums(mat), data$dom_supply, check.attributes = FALSE), " \n")

  return(mat)
})
names(reex) <- items$item_code

# report which commodities (if any) needed the robust-inversion fallback
if (length(reex_singular)) {
  cat(sprintf("[12] %d commodity(ies) needed a robust re-export inversion fallback (YEAR=%d):\n",
              length(reex_singular), YEAR))
  for (it in names(reex_singular)) cat(sprintf("     item %s -> %s\n", it, reex_singular[[it]]))
} else {
  cat("[12] all re-export matrices inverted with the original sparse solver.\n")
}


btd_final <- lapply(items$item_code, function(x) {
  m <- reex[[paste(x)]]
  m <- as(m, "dgTMatrix")
  df <- data.frame(i=as.integer(rownames(m)[m@i + 1]), j=as.integer(colnames(m)[m@j + 1]), x=m@x)
  names(df) <- c("from_code", "to_code", "value")
  df <- mutate(df, item_code = x, .before = from_code)
  })

btd_final <- rbindlist(btd_final)

btd_final <- mutate(btd_final, year = YEAR, .before = item_code) %>%
  mutate(comm_code = items$comm_code[match(btd_final$item_code, items$item_code)])


cbs_full <- mutate(cbs_ext,
                       item = items$item[match(cbs_ext$item_code, items$item_code)],
                       year = YEAR,
                       total_supply = total_supply - stock_negative,
                       dom_supply = dom_supply - stock_negative,
                       dom_use = dom_use - stock_negative,
                       total_use = total_use - stock_negative,
                       stock_withdrawal = - stock_addition)

cbs_full <- dplyr::select(cbs_full, names(cbs))

# save results -----------------------------------------------
if (write){
  saveRDS(reex, file.path(out_dir, "reex.rds"))
  saveRDS(btd_final, file.path(out_dir, "btd_final.rds"))
  saveRDS(cbs_full, file.path(out_dir, "cbs_full.rds"))
}

rm(list = ls())
gc()

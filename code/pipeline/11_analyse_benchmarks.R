##### Benchmark comparison / validation  #####

# Computes the model-vs-TRASE agreement metrics consumed by the paper:
#   results/tables/benchmarks/{YEAR}/pearson_global.csv   (compile_multimode_panel.R)
#   results/tables/benchmarks/{YEAR}/rmse_global.csv      (compile_multimode_panel.R)
#   results/tables/benchmarks/{YEAR}/rmsle_global.csv     (compile_multimode_panel.R)
#   results/tables/benchmarks/{YEAR}/pearson_by_dest.csv  (fig_model_comparison.py, fig_dest_sets.py)
#   results/tables/benchmarks/{YEAR}/rmse_rmsle_by_dest.csv
# (The former diagnostic benchmark maps / scatter panels / regression tables were
#  retired 2026-08; see git history. The paper's scatter is code/analysis/rocket_plot.py.)

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(dplyr)
library(data.table)
library(Matrix)
library(sf)
library(gtools)
library(Metrics)

write = TRUE
options(scipen = 99999)

# year-scoped output directory
tab_dir <- paste0("results/tables/benchmarks/", YEAR)
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

# load data ----------

# If step 10 produced no benchmark (no TRASE data for this year, e.g. < 2004),
# there is nothing to analyse - skip cleanly.
.comp_path <- paste0("data/generated/outputs/10_", YEAR, "/comp_list.rds")
if (!file.exists(.comp_path)) {
  message("[11] No benchmark for YEAR=", YEAR, " (", .comp_path,
          " missing - no TRASE data). Skipping analysis.")
  quit(save = "no", status = 0)
}

SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
GEO_MUN_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/GEO_MUN_SOY_fin.rds"))
comp_list <- readRDS(paste0("data/generated/outputs/10_", YEAR, "/comp_list.rds"))
MUN_capital_dist <- readRDS(paste0("data/generated/outputs/00_", YEAR, "/MUN_capital_dist.rds"))  # produced by step 00
class(MUN_capital_dist) <- "numeric"
# Subset distance matrix to municipalities present in SOY_MUN. Step 00 emits a
# 5572-row matrix; step 05 filters SOY_MUN down to 5570. Without this, logical
# masking later recycles wrong and dimensions drift.
.mun <- as.character(SOY_MUN$co_mun)
# Drop non-geographic placeholder municipalities (e.g. COMEX 9300000) absent from
# the distance matrix, keeping SOY_MUN / GEO_MUN_SOY aligned with it.
.in_dist <- .mun %in% rownames(MUN_capital_dist)
if (any(!.in_dist)) {
  message("[11] dropping ", sum(!.in_dist), " non-geographic municipality(ies): ",
          paste(.mun[!.in_dist], collapse = ", "))
  SOY_MUN <- SOY_MUN[.in_dist, , drop = FALSE]
  GEO_MUN_SOY <- GEO_MUN_SOY[as.character(GEO_MUN_SOY$co_mun) %in% .mun[.in_dist], , drop = FALSE]
  .mun <- .mun[.in_dist]
}
MUN_capital_dist <- MUN_capital_dist[.mun, .mun]
EXP_NAT_wide <- readRDS(paste0("data/generated/outputs/10_", YEAR, "/EXP_NAT_wide.rds"))
CBS_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/CBS_SOY_bal.rds"))

# extract only required columns from benchmark tables, renaming "mean" to "multimode"
comp_list <- lapply(comp_list, function(comp){dplyr::select(comp,co_state:multimode_mean) %>% rename(multimode = multimode_mean)})
# transfrom flows from tons to kilotons for plots
comp_list <- lapply(comp_list, function(comp){mutate(comp, across(trase:multimode, function(x){x/1000}))})
comp_mun <- comp_list$mun

# results to compare
res <- c("trase", "euclid", "multimode", "downscale")
names(res) <- res


# compute focal sums/means -----------------------------------------------------------------------

# filter those MUs that produce soy --> these are the only MUs relevant for the comparison
SOY_MUN_prod <- SOY_MUN[SOY_MUN$prod_bean>0,]
GEO_MUN_SOY_prod  <- GEO_MUN_SOY[GEO_MUN_SOY$prod_bean>0,]
MUN_capital_dist_prod <- MUN_capital_dist[SOY_MUN$prod_bean>0, SOY_MUN$prod_bean>0]

# create (different spatial weights matrices)
# direct neighbors (queens contiguity)
w_q <- st_touches(GEO_MUN_SOY_prod, byid = FALSE, sparse = FALSE)*1
w_q <- as(w_q, "sparseMatrix")
dimnames(w_q) <- list(GEO_MUN_SOY_prod$co_mun, GEO_MUN_SOY_prod$co_mun)
diag(w_q) <- 1

# MUs in distance of max 100km
w_d100 <- MUN_capital_dist_prod
w_d100[MUN_capital_dist_prod >  100000] <- 0
w_d100[MUN_capital_dist_prod <= 100000] <- 1
w_d100 <- as(w_d100, "sparseMatrix")
diag(w_d100) <- 1

# MUs inverse distance
w_id <- 1/MUN_capital_dist_prod
w_id[!is.finite(w_id)] <- 0
w_id <- as(w_id, "sparseMatrix")
diag(w_id) <- rowSums(w_id)

# add column/row for unknown MU
c_unknown <- c(rep(0,nrow(GEO_MUN_SOY_prod)), 1)
add_unknown <- function(mat){mat <- rbind(mat, "9999999" = rep(0, ncol(mat))); mat <- cbind(mat, "9999999" = c_unknown)}
w_q     <- add_unknown(w_q)
w_d100  <- add_unknown(w_d100)
w_id <- add_unknown(w_id)

# row-standardize
w_q_s  <- w_q/rowSums(w_q)
w_d100_s  <- w_d100/rowSums(w_d100)
w_id_s <- w_id/rowSums(w_id)
w_list <- list(w_q, w_q_s, w_d100, w_d100_s, w_id_s)
names(w_list) <- w_nms <- c("sum_q", "mean_q", "sum_100", "mean_100", "mean_id" )


# create df containing all possible combinations of origins and destinations

# optional: remove the unknown origin flows in trase
comp_mun_known <- filter(comp_mun, co_mun != "9999999")
# how many flows do we lose?
sum(comp_mun$trase) - sum(comp_mun_known$trase) # a lot!

# sort destinations by aggregate export volume
comp_nat <- comp_mun_known %>% group_by(to_code, to_name) %>% summarise(across(trase:multimode, sum)) %>% arrange(desc(downscale))
# use only those that have exports in both trase and comex
dests <- comp_nat$to_code[comp_nat$trase>0 & comp_nat$downscale>0] ; names(dests) <- dests

comp_mun_long <- expand.grid(co_mun = SOY_MUN_prod$co_mun,
                             "to_code" = dests, stringsAsFactors = FALSE)
comp_mun_long <- merge(comp_mun_long,
                       as.data.table(comp_mun),
                        by = c("co_mun", "to_code"), all.x = TRUE) %>%
                 dplyr::arrange(to_code)
# NOTE: some NAs due destination LCA, which is only contained in TRASE --> not relevant for comparison, will be discarded below
# separate by destination
comp_mun_long_dest <- sapply(dests, function(dest){
  filter(comp_mun_long, to_code == dest)},
  simplify = FALSE, USE.NAMES = TRUE)


## compute focal values
comp_mun_long_dest <- lapply(comp_mun_long_dest, function(comp){
  by_weight <- lapply(names(w_list), function(w){
    w_co  <- w_list[[w]][as.character(comp$co_mun), as.character(comp$co_mun)]
    comp_focal <- comp %>% dplyr::select(all_of(res)) %>% as("Matrix")
    comp_focal <- as.data.frame(as.matrix(w_co %*% comp_focal))
    names(comp_focal) <- paste0(names(comp_focal),"_",w)
    return(comp_focal)
  })
  comp_focal <-  do.call("cbind", by_weight)
  comp_focal <- cbind(comp,comp_focal)
  return(comp_focal)
})

# bind to long list
comp_mun_long <- rbindlist(comp_mun_long_dest)

# models and weightings compared in the metric tables
models <- c("multimode", "euclid", "downscale"); names(models) = models
w_nms <- c("base", "mean_q", "mean_100"); names(w_nms) <- w_nms


# pearson corellation -------------------------------------------------------------------------

# globally
comp_mun_long <- as.data.frame(comp_mun_long)
pearson_global <- lapply(w_nms, function(w){
  lapply(models, function(mod){
    if(w != "base"){w = paste0("_",w)} else {w = ""}
    test <- cor.test(x = unlist(comp_mun_long[,paste0("trase",w)]), y = comp_mun_long[,paste0(mod,w)], method = "pearson", conf.level = 0.95)
    result <- paste0(round(test$estimate,4), stars.pval(test$p.value))
    return(result)
  })
})
pearson_global <- lapply(pearson_global, data.frame, stringsAsFactors = FALSE)
pearson_global <- bind_rows(pearson_global)
rownames(pearson_global) <- names(w_nms)

# by destination
pearson_dest <- lapply(comp_mun_long_dest, function(comp_dest){
  lapply(w_nms, function(w){
    lapply(models, function(mod){
      if(w != "base"){w = paste0("_",w)} else {w = ""}
      test <- cor.test(x = unlist(comp_dest[paste0("trase",w)]), y = unlist(comp_dest[paste0(mod,w)]), method = "pearson", conf.level = 0.95)
      result <- paste0(round(test$estimate,4), stars.pval(test$p.value))
      return(result)
    })
  })
})

pearson_dest <- lapply(pearson_dest, data.frame, stringsAsFactors = FALSE)
pearson_dest <- bind_rows(pearson_dest)
pearson_dest <- mutate(pearson_dest, to_code = names(comp_mun_long_dest), .before = base.multimode)

# add column for total exports in trase and my data
pearson_df <- comp_nat %>% dplyr::select(c(to_code:to_name, trase, multimode)) %>%
  rename(exports_trase = trase, exports_model = multimode) %>%
  left_join(pearson_dest, by = "to_code") %>%
  arrange(desc(exports_trase))
# transform to kilotons
pearson_df <- mutate(pearson_df, exports_trase = round(exports_trase/1000,3), exports_model = round(exports_model/1000,4))
# replace NA by -
pearson_df[is.na(pearson_df)] <- "-"

# add column for share of raw soy in exports
(equi_fact <- (CBS_SOY["bean", "processing"])/(CBS_SOY["cake", "production"] + CBS_SOY["oil", "production"]))
EXP_NAT_wide_eq <- EXP_NAT_wide %>%  mutate(oil = oil*equi_fact, cake = cake * equi_fact) %>%
  mutate(bean_share = bean/(bean+oil+cake))

pearson_df <- dplyr::left_join(pearson_df, EXP_NAT_wide_eq %>% dplyr::select(c(to_name, bean_share)), by = c("to_code" = "to_name"))
pearson_df <- pearson_df %>% relocate(bean_share, .after = exports_model)

# extract only columns we need
pearson_df_fin <- select(pearson_df, -c(to_name, bean_share, starts_with("sum_")))


# rmse and rmsle ---------------------------------------------------------------------------------------

# rmse
# globally
rmse_global <- lapply(w_nms, function(w){
  lapply(models, function(mod){
    if(w != "base"){w = paste0("_",w)} else {w = ""}
    rmse <- rmse(actual = unlist(comp_mun_long[,paste0("trase",w)]), predicted = comp_mun_long[,paste0(mod,w)])
    result <- round(rmse, 4)
    return(result)
  })
})
rmse_global <- lapply(rmse_global, data.frame, stringsAsFactors = FALSE)
rmse_global <- bind_rows(rmse_global)
rownames(rmse_global) <- names(w_nms)

# by destination
rmse_dest <- lapply(comp_mun_long_dest, function(comp_dest){
  lapply(w_nms, function(w){
    lapply(models, function(mod){
      if(w != "base"){w = paste0("_",w)} else {w = ""}
      rmse <- rmse(actual = unlist(comp_dest[,paste0("trase",w)]), predicted = comp_dest[,paste0(mod,w)])
      result <- round(rmse, 4)
      return(result)
    })
  })
})

rmse_dest <- lapply(rmse_dest, data.frame, stringsAsFactors = FALSE)
rmse_dest <- bind_rows(rmse_dest)
rmse_dest <- mutate(rmse_dest, to_code = names(comp_mun_long_dest), .before = base.multimode)
# add global row
rmse_global_row <- c("Total",  as.vector(t(rmse_global)))
rmse_dest <- rbind(rmse_dest, rmse_global_row)

# rmsle
# globally
rmsle_global <- lapply(w_nms, function(w){
  lapply(models, function(mod){
    if(w != "base"){w = paste0("_",w)} else {w = ""}
    rmsle <- rmsle(actual = unlist(comp_mun_long[,paste0("trase",w)]), predicted = comp_mun_long[,paste0(mod,w)])
    result <- round(rmsle, 4)
    return(result)
  })
})
rmsle_global <- lapply(rmsle_global, data.frame, stringsAsFactors = FALSE)
rmsle_global <- bind_rows(rmsle_global)
rownames(rmsle_global) <- names(w_nms)

# by destination
rmsle_dest <- lapply(comp_mun_long_dest, function(comp_dest){
  lapply(w_nms, function(w){
    lapply(models, function(mod){
      if(w != "base"){w = paste0("_",w)} else {w = ""}
      rmsle <- rmsle(actual = unlist(comp_dest[,paste0("trase",w)]), predicted = comp_dest[,paste0(mod,w)])
      result <- round(rmsle, 4)
      return(result)
    })
  })
})


rmsle_dest <- lapply(rmsle_dest, data.frame, stringsAsFactors = FALSE)
rmsle_dest <- bind_rows(rmsle_dest)
rmsle_dest <- mutate(rmsle_dest, to_code = names(comp_mun_long_dest), .before = base.multimode)
# Stefan-bug fix: add the same "Total" row that rmse_dest gets, so the cbind below
# doesn't fail with mismatched row counts (rmse_dest has 59, rmsle_dest had 58).
rmsle_global_row <- c("Total", as.vector(t(rmsle_global)))
rmsle_dest <- rbind(rmsle_dest, rmsle_global_row)

names(rmsle_dest) <- paste0("rmsle_",names(rmsle_dest))
names(rmse_dest) <- paste0("rmse_",names(rmse_dest))
names(pearson_dest) <- paste0("r_",names(pearson_dest))

rms <- cbind(rmse_dest, rmsle_dest[,-1])

# --- save the summary metrics as CSV ------------------------------------------
if (write){
  # headline: global Pearson r (rows = direct / focal-mean weightings, cols = models)
  write.csv(cbind(weighting = rownames(pearson_global), pearson_global),
            file.path(tab_dir, "pearson_global.csv"), row.names = FALSE)
  write.csv(cbind(weighting = rownames(rmse_global), rmse_global),
            file.path(tab_dir, "rmse_global.csv"), row.names = FALSE)
  write.csv(cbind(weighting = rownames(rmsle_global), rmsle_global),
            file.path(tab_dir, "rmsle_global.csv"), row.names = FALSE)
  # by destination: correlation table (with national export volumes) + rmse/rmsle
  write.csv(pearson_df_fin, file.path(tab_dir, "pearson_by_dest.csv"), row.names = FALSE)
  write.csv(rms,            file.path(tab_dir, "rmse_rmsle_by_dest.csv"), row.names = FALSE)
  cat("[11] ", YEAR, " wrote metrics CSVs to ", tab_dir, "/\n", sep = "")
}

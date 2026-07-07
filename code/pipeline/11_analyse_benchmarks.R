##### Benchmark comparison / validation  #####

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(dplyr)
library(data.table)
library(Matrix)
library(tidyr)
library(ggplot2)
library(purrr)
library(sf)
library(viridis)
library(mapview)
library(sf)
library(leafsync)
library(patchwork)
library(ggsci)
library(gtools)
library(ggpubr)
library(Metrics)
library(xtable)


# load function library
source("code/pipeline/00_function_library.R")

write = TRUE
options(scipen = 99999)

# year-scoped output directories
map_dir <- paste0("results/maps/benchmark_maps/", YEAR)
fig_dir <- paste0("results/figures/correlation_scatter/", YEAR)
tab_dir <- paste0("results/tables/benchmarks/", YEAR)
dir.create(map_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

# load data ----------

# If step 10 produced no benchmark (no TRASE data for this year, e.g. < 2004),
# there is nothing to analyse — skip cleanly.
.comp_path <- paste0("data/generated/outputs/10_", YEAR, "/comp_list.rds")
if (!file.exists(.comp_path)) {
  message("[11] No benchmark for YEAR=", YEAR, " (", .comp_path,
          " missing — no TRASE data). Skipping analysis.")
  quit(save = "no", status = 0)
}

SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
GEO_MUN_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/GEO_MUN_SOY_fin.rds"))
GEO_states <- st_read("data/geo/GADM_boundaries/gadm36_BRA_1.shp", stringsAsFactors = FALSE) %>%
  mutate(nm_state = substr(HASC_1, 4,5))
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
comp_state <- comp_list$state


# maps of flow origins for selected destinations --------------------------

# select destination country
targets <- c("CHN", "BRA", "NLD", "ESP", "THA", "DEU", "KOR", "NOR")
for (dest in targets){

#dest <- "CHN"

# merge benchmark results with GEOdata
GEO_MUN_SOY_dest <- GEO_MUN_SOY %>% 
  left_join(filter(comp_mun, to_code == dest)) %>%
  mutate_all(~replace(., is.na(.), 0))
GEO_STATE_SOY_dest <- GEO_states %>% 
  left_join(filter(comp_state, to_code == dest)) %>% 
  mutate_all(~replace(., is.na(.), 0))

# # or by destination region
# dest <- "EU"
# # merge results with GEOdata
# GEO_MUN_SOY_dest <- GEO_MUN_SOY %>% left_join(filter(comp_mun_by_region, to_region == dest))# %>% replace(is.na(.), 0)
# GEO_STATE_SOY_dest <- GEO_states %>% left_join(filter(comp_state_by_region, to_region == dest))


# select results to compare
res <- c("trase", "euclid", "multimode", "downscale") 
names(res) <- res
resdata <- GEO_MUN_SOY_dest %>% st_drop_geometry() %>% dplyr::select(all_of(res)) 
resdata_state <- GEO_STATE_SOY_dest %>% st_drop_geometry() %>% dplyr::select(all_of(res)) 

# generate ggplots (using gg_funct from function library)
limits <- c(min(resdata[resdata>0]), max(resdata))
# NOTE: The cutoff allows to not plot flows below a certain level (in tons)
exp_dest <- lapply(res, gg_funct, 
                   GEO = GEO_MUN_SOY_dest, cutoff = 10, unit = "kilotons", title = '', pal = "plasma", limits = limits)
exp_dest <- map2(exp_dest, res, ~ .x + ggtitle(.y))
(wrap <- wrap_plots(exp_dest, nrow = ceiling(length(exp_dest)/2), guides = "collect"))
if(write) ggsave(file.path(map_dir, paste0("map_benchmark_",dest,".png")), wrap, bg='transparent', scale = 1.5, width = 20,  height = 20, units = "cm")


limits_state <- c(min(resdata_state[resdata_state>0]), max(resdata_state))
exp_dest_state <- lapply(res, gg_funct, 
                         GEO = GEO_STATE_SOY_dest, unit = "tons", cutoff = 10, pal = "plasma", limits = limits_state)
exp_dest_state <- map2(exp_dest_state, res, ~ .x + ggtitle(.y))
(wrap_state <- wrap_plots(exp_dest_state, nrow = ceiling(length(exp_dest_state)/2), guides = "collect"))
if(write) ggsave(file.path(map_dir, paste0("map_benchmark_state_",dest,".png")), wrap_state, bg='transparent', scale = 1.5, width = 30,  height = 10, units = "cm")

# interactive mapview approach (using mv_funct from function library)
# UNCOMMENT IF NEEDED!

# exp_dest_mv <- lapply(res, mv_funct,  GEO = GEO_MUN_SOY_dest, cutoff = 0)
# (sync <- sync(exp_dest_mv, ncol = 2))
# #save_tags(sync, paste0("results/benchmark_",dest,".html"), selfcontained=TRUE)
# 
# exp_dest_mv_state <- lapply(res, mv_funct,  GEO = GEO_STATE_SOY_dest,cutoff = 10)
# (sync_state <- sync(exp_dest_mv_state, ncol = 2))
# #save_tags(sync, paste0("results/benchmark_state_",dest,".html"), selfcontained=TRUE)

}


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
# how many flows do we lose?
comp_nat_loss <- filter(comp_nat, !to_code %in% dests) %>% summarise(across(trase:multimode, ~ sum(.x)))
#dest_regs <- (unique(comp_mun[,c("to_code","to_region")])) %>% arrange(to_code)

comp_mun_long <- expand.grid(co_mun = SOY_MUN_prod$co_mun, # c(SOY_MUN_prod$co_mun, 9999999),
                             "to_code" = dests, stringsAsFactors = FALSE)
#comp_mun_long$to_region <- dest_regs$to_region[match(comp_mun_long$to_code, dest_regs$to_code)]
comp_mun_long <- merge(comp_mun_long, 
                       as.data.table(comp_mun), #[, .(co_mun, to_code, trase, multimode, euclid, downscale)]
                        by = c("co_mun", "to_code"), all.x = TRUE) %>%
                 dplyr::arrange(to_code) 
# NOTE: some NAs due destination LCA, which is only contained in TRASE --> not relevant for comparison, will be discarded below
#comp_mun_long[is.na(comp_mun_long)] <- 0
# separate by destination
comp_mun_long_dest <- sapply(dests, function(dest){
  filter(comp_mun_long, to_code == dest)}, 
  simplify = FALSE, USE.NAMES = TRUE)
#all.equal(as.character(comp_mun_long_dest$AGO$co_mun), rownames(w_d100_s))


## compute focal values
comp_mun_long_dest <- lapply(comp_mun_long_dest, function(comp){
  by_weight <- lapply(names(w_list), function(w){
    w_co  <- w_list[[w]][as.character(comp$co_mun), as.character(comp$co_mun)] # w[as.character(comp$co_mun), as.character(comp$co_mun)]
    comp_focal <- comp %>% dplyr::select(all_of(res)) %>% as("Matrix") 
    comp_focal <- as.data.frame(as.matrix(w_co %*% comp_focal))
    names(comp_focal) <- paste0(names(comp_focal),"_",w)
    return(comp_focal)
  })
  comp_focal <-  do.call("cbind", by_weight)
  comp_focal <- cbind(comp,comp_focal)
  return(comp_focal)
})



# remove countries that are only present in either trase or our results
#trase_dests <- unique(comp_mun_long$to_code[comp_mun_long$trase>0])
#comex_dests <- unique(comp_mun_long$to_code[comp_mun_long$euclid>0])
#(setdiff(trase_dests, comex_dests))
#comp_mun_long_dest <- comp_mun_long_dest[!names(comp_mun_long_dest) %in% setdiff(trase_dests, comex_dests)]

# bind to long list
comp_mun_long <- rbindlist(comp_mun_long_dest)
#comp_mun_long <- group_by(comp_mun_long, to_code) %>% mutate(exp_nat = sum(downscale, na.rm = T))
#comp_mun_long <- arrange(comp_mun_long, desc(exp_nat))
  


# scatterplots ---------------------------------------------------------------

models <- c("multimode", "euclid", "downscale"); names(models) = models
w_nms <- c("base", "mean_q", "mean_100"); names(w_nms) <- w_nms

## globally ------------------

scatter_global <- lapply(w_nms, function(w){
    gg <- lapply(models, function(mod){
    if(w != "base"){w = paste0("_",w)} else {w = ""}
    bw = ifelse(w == "",100, 50)
    scatter <- scatter_funct_dens2(comp_mun_long, paste0(mod,w), paste0("trase",w), legend = FALSE,
                                   bwx = bw, bwy = bw,
                                   ylab = "TRASE", xlab = mod, rsize = 4,
                                   col = "firebrick",
                                   alph = 0.4) 
    return(scatter) 
  })
  wlab <- ggplot() + 
    annotate("text", x = 0.8, y = 0.5, size=5.5, label = ifelse(w == "base", "direct", "focal mean")) + 
    theme_void()
  gg <- c(lab = list(wlab), gg)
  wrap_plots(gg, nrow = 1) + plot_layout(widths = c(0.5,1,1,1))
})


# combine plots
scat_wrap_global <- scatter_global$base / scatter_global$mean_q
if (write) ggsave(scat_wrap_global, file = file.path(fig_dir, "scatter_global.png"), height = 20, width = 38, units = "cm")



## by country ------------------------------------

#w_nms <- c("base", "mean_q")
#names(w_nms) <- w_nms
targets <- c("CHN", "ESP", "NOR"); names(targets) <- targets
targets_long <- c("China", "Spain", "Norway"); names(targets_long) <- targets
target_cols <- c("darkblue", "firebrick", "darkmagenta"); names(target_cols) = targets
# Some years' TRASE/COMEX may not include all three preset targets (e.g. NOR absent
# in some years' v2.6.1 composite). Keep only those actually present.
.have <- intersect(targets, names(comp_mun_long_dest))
if (length(.have) < length(targets)) {
  cat("[11] Skipping scatter for missing target(s):",
      paste(setdiff(targets, .have), collapse=", "), "\n")
  targets      <- .have;       names(targets)      <- targets
  targets_long <- targets_long[targets]
  target_cols  <- target_cols[targets]
}

scatter_dest <- lapply(targets, function(targ){
  comp_dest <- comp_mun_long_dest[[targ]]
  lapply(w_nms, function(w){
    gg <- lapply(models, function(mod){
      if(w != "base"){w = paste0("_",w)} else {w = ""}
      options(scipen = 9999) 
      scatter <- scatter_funct(comp_dest, paste0(mod,w), paste0("trase",w), 
                               col = target_cols[targ],
                               xlab = mod,
                               legend = FALSE) 
      return(scatter) 
    })
    destlab <- ggplot() + 
      annotate("text", x = 0.8, y = 0.5, size=6, label = targets_long[targ]) + 
      theme_void()
    gg <- c(lab = list(destlab), gg)
    wrap_plots(gg, nrow = 1) + plot_layout(widths = c(0.5,1,1,1))
  })
})


scatter_targets <-  scatter_dest$CHN$mean_q / scatter_dest$ESP$mean_q / scatter_dest$NOR$mean_q
#scatter_targets[[1]][[2]] <-  scatter_targets[[1]][[2]] + labs(title = 'China') + theme(plot.title = element_text(hjust = 0.5))
#scatter_targets[[2]][[2]] <-  scatter_targets[[2]][[2]] + labs(title = 'Spain') + theme(plot.title = element_text(hjust = 0.5))
#scatter_targets[[3]][[2]] <-  scatter_targets[[3]][[2]] + labs(title = 'Norway') + theme(plot.title = element_text(hjust = 0.5))

if (write) ggsave(scatter_targets, filename = file.path(fig_dir, "scatter_targets.png"), height = 15, width = 17.5, units = "cm", scale = 1.5)



# regressions --------------------------------------------------------------------------------------

# globally
reg_global <- lapply(models, function(mod){
  m_base <- lm(as.formula(paste0("trase ~ ",mod)), data = comp_mun_long) %>% summary
  m_sum_q <- lm(as.formula(paste0("trase_sum_q ~ ",mod,"_sum_q")), data = comp_mun_long) %>% summary
  m_mean_q <- lm(as.formula(paste0("trase_mean_q ~ ",mod,"_mean_q")), data = comp_mun_long) %>% summary
  m_sum_100 <- lm(as.formula(paste0("trase_sum_100 ~ ",mod,"_sum_100")), data = comp_mun_long) %>% summary
  m_mean_100 <- lm(as.formula(paste0("trase_mean_100 ~ ",mod,"_mean_100")), data = comp_mun_long) %>% summary
  m_mean_id <- lm(as.formula(paste0("trase_mean_id ~ ",mod,"_mean_id")), data = comp_mun_long) %>% summary
  return(list(base = m_base$r.squared, mean_q = m_mean_q$r.squared, sum_q = m_sum_q$r.squared, mean_100 = m_mean_100$r.squared, sum_100 = m_sum_100$r.squared, mean_id = m_mean_id$r.squared)) 
})

reg_global <- lapply(reg_global, data.frame, stringsAsFactors = FALSE)
reg_global <- bind_rows(reg_global)
rownames(reg_global) <- names(models)
#dfs_global <- t(dfs_global)

# globally with country fixed effects
reg_global_fe <- lapply(models, function(mod){
  m_base <- lm(as.formula(paste0("trase ~ to_code + ",mod,":to_code")), data = comp_mun_long) %>% summary
  m_sum_q <- lm(as.formula(paste0("trase_sum_q ~ to_code + ",mod,"_sum_q : to_code")), data = comp_mun_long) %>% summary
  m_mean_q <- lm(as.formula(paste0("trase_mean_q ~ to_code + ",mod,"_mean_q : to_code")), data = comp_mun_long) %>% summary
  m_sum_100 <- lm(as.formula(paste0("trase_sum_100 ~ to_code + ",mod,"_sum_100 : to_code")), data = comp_mun_long) %>% summary
  m_mean_100 <- lm(as.formula(paste0("trase_mean_100 ~ to_code + ",mod,"_mean_100 : to_code")), data = comp_mun_long) %>% summary
  m_mean_id <- lm(as.formula(paste0("trase_mean_id ~ to_code + ",mod,"_mean_id : to_code")), data = comp_mun_long) %>% summary
  return(list(base = m_base$r.squared, mean_q = m_mean_q$r.squared, sum_q = m_sum_q$r.squared, mean_100 = m_mean_100$r.squared, sum_100 = m_sum_100$r.squared, mean_id = m_mean_id$r.squared)) 
})

reg_global_fe <- lapply(models, function(mod){
  m_base <- lm(as.formula(paste0("trase ~ ",mod,"*to_code")), data = comp_mun_long) %>% summary
  m_sum_q <- lm(as.formula(paste0("trase_sum_q ~ ",mod,"_sum_q * to_code")), data = comp_mun_long) %>% summary
  m_mean_q <- lm(as.formula(paste0("trase_mean_q ~ ",mod,"_mean_q * to_code")), data = comp_mun_long) %>% summary
  m_sum_100 <- lm(as.formula(paste0("trase_sum_100 ~ ",mod,"_sum_100 * to_code")), data = comp_mun_long) %>% summary
  m_mean_100 <- lm(as.formula(paste0("trase_mean_100 ~ ",mod,"_mean_100 * to_code")), data = comp_mun_long) %>% summary
  m_mean_id <- lm(as.formula(paste0("trase_mean_id ~ ",mod,"_mean_id * to_code")), data = comp_mun_long) %>% summary
  return(list(base = m_base$r.squared, mean_q = m_mean_q$r.squared, sum_q = m_sum_q$r.squared, mean_100 = m_mean_100$r.squared, sum_100 = m_sum_100$r.squared, mean_id = m_mean_id$r.squared)) 
})

reg_global <- lapply(reg_global, data.frame, stringsAsFactors = FALSE)
reg_global_fe <- bind_rows(reg_global_fe)
rownames(reg_global_fe) <- names(models)


# by destination ----------
#w_nms <- c("base",w_nms)
#names(w_nms) <- w_nms

reg_dest <- lapply(comp_mun_long_dest, function(comp_dest){
  lapply(w_nms, function(w){
    lapply(models, function(mod){
      if(w != "base"){w = paste0("_",w)} else {w = ""}
      m<- lm(as.formula(paste0("trase",w," ~ ",mod,w)), data = comp_dest) %>% summary
      return(m$r.squared) 
    })
  })
})


reg_dest <- lapply(reg_dest, data.frame, stringsAsFactors = FALSE)
reg_dest <- bind_rows(reg_dest)
rownames(reg_dest) <- names(comp_mun_long_dest)
#dfs <- t(dfs)

# simple pearson correlation
# by destination
#pearson <- lapply(comp_mun_long_dest, function(comp_dest){
#  lapply(models, function(mod){
#    c_base <- cor(comp_dest$trase, comp_dest[mod])
#    c_sum_q <- lm(as.formula(paste0("trase_sum_q ~ ",mod,"_sum_q")), data = comp_dest) %>% summary
#    c_mean_q <- lm(as.formula(paste0("trase_mean_q ~ ",mod,"_mean_q")), data = comp_dest) %>% summary
#    c_sum_100 <- lm(as.formula(paste0("trase_sum_100 ~ ",mod,"_sum_100")), data = comp_dest) %>% summary
#    c_mean_100 <- lm(as.formula(paste0("trase_mean_100 ~ ",mod,"_mean_100")), data = comp_dest) %>% summary
#    c_mean_id <- lm(as.formula(paste0("trase_mean_id ~ ",mod,"_mean_id")), data = comp_mun_long) %>% summary
#    return(list(base = m_base, mean_q = m_mean_q, sum_q = m_sum_q, mean_100 = m_mean_100, sum_100 = m_sum_100, mean_id = m_mean_id)) 
#  })
#})



# pearson corellation -------------------------------------------------------------------------

# globally
comp_mun_long <- as.data.frame(comp_mun_long)
pearson_global <- lapply(w_nms, function(w){
  lapply(models, function(mod){
    if(w != "base"){w = paste0("_",w)} else {w = ""}
    #coeff <- cor(comp_dest[paste0("trase",w)], comp_dest[paste0(mod,w)])
    test <- cor.test(x = unlist(comp_mun_long[,paste0("trase",w)]), y = comp_mun_long[,paste0(mod,w)], method = "pearson", conf.level = 0.95)
    result <- paste0(round(test$estimate,4), stars.pval(test$p.value)) # ,"(", round(test$conf.int[1],4),",", round(test$conf.int[2],4), ")"
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
      #coeff <- cor(comp_dest[paste0("trase",w)], comp_dest[paste0(mod,w)])
      test <- cor.test(x = unlist(comp_dest[paste0("trase",w)]), y = unlist(comp_dest[paste0(mod,w)]), method = "pearson", conf.level = 0.95)
      result <- paste0(round(test$estimate,4), stars.pval(test$p.value)) # ,"(", round(test$conf.int[1],4),",", round(test$conf.int[2],4), ")"
      return(result) 
    })
  })
})

pearson_dest <- lapply(pearson_dest, data.frame, stringsAsFactors = FALSE)
pearson_dest <- bind_rows(pearson_dest)
#rownames(pearson_df) <- names(comp_mun_long_dest)
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


# save table to tex
# extract only columns we need
pearson_df_fin <- select(pearson_df, -c(to_name, bean_share, starts_with("sum_"))) # ends_with("multimode"), contains("_id.")
if (write){
  print(xtable(pearson_df_fin, caption = "Corrleation between different model approaches and TRASE by destination country",digits = 1), 
      file = file.path(tab_dir, "pearson_dest.tex"),
      include.rownames=FALSE)
}


# other statistics
comp_mun_dest_stats <- comp_mun_long %>% group_by(to_code) %>% 
  summarise(across(downscale:multimode, .fns = list(diff = ~ sum(abs(.-trase)), msle = ~ msle(trase,.), rmse = ~rmse(trase,.)), #mape = ~ mape(trase,.)
                   .names = "{.fn}_{.col}")) 


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

# save table to tex
# extract only columns we need
if (write){
  print(xtable(rmse_dest, caption = "RMSE between different model approaches and TRASE by destination country",digits = 1), 
        file = file.path(tab_dir, "rmse_dest.tex"),
        include.rownames=FALSE)
}

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

#bind
#metrics <- cbind(pearson_dest, rmse_dest[,-1], rmsle_dest[,-1])
#write.csv(metrics, "r_rmse_rmsle.csv")

rms <- cbind(rmse_dest, rmsle_dest[,-1])

# --- save the summary metrics as CSV ------------------------------------------
# The original script computes these but only ever wrote .tex tables BY DESTINATION
# (pearson_dest, rmse_dest) and never the headline GLOBAL numbers. Export the key
# tables as readable CSVs so the model-vs-TRASE comparison is usable directly.
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
  cat("[11] ", YEAR, " wrote metrics CSVs + figures/maps to results/{tables,figures,maps}/", YEAR, "/\n", sep = "")
}

#rm(list = ls())
#gc()

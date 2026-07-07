
#### linking subnational to international flows: from MU of origin to country of first import ####

## this version conducts the linkage separately for each simulation of the multimodal model

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(dplyr)
library(data.table)
library(tibble)
library(tidyr)
library(abind)
library(Matrix)
# Note: Stefan's original loaded Matrix.utils (removed from CRAN in 2022).
library(parallel)

write = TRUE

out_dir <- paste0("data/generated/outputs/08_", YEAR)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
bs_res_dir <- paste0("./data/generated/outputs/gams/bs_res_", YEAR)

flows_euclid <- readRDS(paste0("data/generated/outputs/07_", YEAR, "/flows_euclid.rds"))
bs_files <- if (dir.exists(bs_res_dir)) list.files(bs_res_dir, pattern="*.rds", full.names=F) else character(0)
if (length(bs_files) > 0) {
  flows_bs <- lapply(bs_files, function(file){
    readRDS(file.path(bs_res_dir, file))
  })
  names(flows_bs) <- gsub(".rds","",bs_files)
  flows <- c(flows_euclid, flows_bs)
  rm(flows_bs)
} else {
  message("No GAMS bootstrap files at ", bs_res_dir, " — running Euclidean-only.")
  flows <- flows_euclid
}

SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
EXP_MUN_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/EXP_MUN_SOY_cbs.rds"))
IMP_MUN_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/IMP_MUN_SOY_cbs.rds"))

co_mun <- SOY_MUN$co_mun
product <- c("bean", "oil", "cake"); names(product) <- product

EXP_MUN_SOY <- mutate(EXP_MUN_SOY,
                      product = ifelse(product == "soybean",
                                       "bean",
                                       ifelse(product == "soy_oil", "oil", "cake")))

destin <- unique(EXP_MUN_SOY$to_name)
destin <- c("BRA", destin)
destin <- unique(destin)  # COMEX may already include BRA (e.g. 2019)
destin <- sort(destin)

exp_templ <- data.frame(
  co_orig = rep(co_mun, each = length(destin), times = length(product)),
  co_dest = rep(destin, times = length(co_mun) * length(product)),
  product = rep(product, each = length(destin) * length(co_mun)))

exp_long  <- left_join(exp_templ, dplyr::select(EXP_MUN_SOY, c(co_mun, product, to_name, export)),
                       by = c("co_orig" = "co_mun", "co_dest" = "to_name", "product" = "product")) %>%
  replace_na(list(export = 0))

exp_long$export[exp_long$co_dest == "BRA" & exp_long$product == "bean"] <-
  SOY_MUN$domestic_use_bean - SOY_MUN$proc_bean
exp_long$export[exp_long$co_dest == "BRA" & exp_long$product == "oil"]  <- SOY_MUN$domestic_use_oil
exp_long$export[exp_long$co_dest == "BRA" & exp_long$product == "cake"] <- SOY_MUN$domestic_use_cake


exp_wide <- sapply(product, function(x){
  filter(exp_long, product == x) %>%
    dplyr::select(!product) %>%
    pivot_wider(names_from = co_dest, values_from = export) %>%
    column_to_rownames("co_orig") %>%
    as("Matrix")
}, USE.NAMES = TRUE, simplify = FALSE)




system.time(
  source_2_export <- mclapply(flows, function(x){

    flow_wide <- sapply(product, function(prod){
      df <- filter(x, product == prod, value != 0) %>% dplyr::select(!product)
      mat <- with(df, sparseMatrix(i = match(co_orig, co_mun),
                                   j = match(co_dest, co_mun),
                                   x = value,
                                   dims = c(length(co_mun), length(co_mun)),
                                   dimnames = list(co_mun,co_mun)))
    }, USE.NAMES = TRUE, simplify = FALSE)


    flow_wide_full <- sapply(product, function(x){
      mat <- flow_wide[[x]]
      diag(mat) <- as.numeric(pull(SOY_MUN, paste0("total_supply_",x)) - pull(SOY_MUN, paste0("excess_supply_",x)))
      return(as(mat, "Matrix"))}, USE.NAMES = TRUE, simplify = FALSE)

    lapply(product, function(x){
      all.equal(rowSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_supply_",x), name = "co_mun"))
      all.equal(colSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_use_",x), name = "co_mun"))})


    dom_share <- sapply(product, function(x){
      # Own-production (domestic-origin) share. Written as (total_supply - imports) instead
      # of production/total_supply: bit-identical when total_supply = prod + imp (use_prop,
      # and all addition products), and correctly counts withdrawal-supplied tonnes as
      # domestically originating in supply_side mode, where total_supply also includes
      # |stock| (STOCK_MODE, step 05). See code/pipeline/CHANGELOG.md.
      dom_share <- ((pull(SOY_MUN, paste0("total_supply_",x)) - pull(SOY_MUN, paste0("imp_",x))) /
                      pull(SOY_MUN, paste0("total_supply_",x)))
      dom_share[is.na(dom_share)] <- 0
      return(dom_share)
    }, USE.NAMES = TRUE, simplify = TRUE) %>% as.data.frame() %>% `rownames<-`(SOY_MUN$co_mun)

    flow_wide_full <- sapply(product, function(x){
      flow_wide_full[[x]] * dom_share[[x]]},
      USE.NAMES = TRUE, simplify = FALSE)


    flow_long_full <- bind_rows(lapply(product, function(x){
      summ <- summary(flow_wide_full[[x]])
      df <- data.frame(co_orig = co_mun[summ$i],
                       co_dest = co_mun[summ$j],
                       product = x, value = summ$x,
                       stringsAsFactors = FALSE)}))


    flow_wide_rel <- lapply(product, function(x){
                              rel <- flow_wide_full[[x]]
                              rel@x <- rel@x / rep.int(pull(SOY_MUN, paste0("total_use_",x)), diff(rel@p))
                              return(rel)})


    source_to_export <- sapply(product, function(x){
      flow_wide_rel[[x]] %*% exp_wide[[x]]},
      USE.NAMES = TRUE, simplify = FALSE)


    source_to_export[2:3] <- lapply(source_to_export[2:3], function(x){
      (flow_wide_rel$bean %*% x)})

    sapply(source_to_export, sum, na.rm = T)

    source_to_export_df <- lapply(product, function(x) {
      m <- source_to_export[[x]]
      m <- as(m, "dgTMatrix")
      df <- data.frame(i=(rownames(m)[m@i + 1]),
                       j=(colnames(m)[m@j + 1]),
                       x=m@x,
                       stringsAsFactors = FALSE)
      names(df) <- c("from_code", "to_code", "value")
      df <- mutate(df, item_code = x, .before = from_code)
    })

    source_to_export_fin <- bind_rows(source_to_export_df)

    source_to_export_fin <- filter(source_to_export_fin, value > 0)

    return(source_to_export_fin)

  }, mc.cores = 12)

)


if (write){
  saveRDS(source_2_export, file.path(out_dir, "source_to_export_list.rds"))
}

rm(list = ls())
gc()

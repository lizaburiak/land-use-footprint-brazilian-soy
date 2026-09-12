
#### linking subnational to international flows: from MU of origin to country of first import ####

## this version averages subnational flows across the simulations of the multimodal model and then conducts the linkage

library(dplyr)
library(data.table)
library(tibble)
library(tidyr)
library(abind)
library(Matrix.utils)
library(purrr)
library(parallel)

write = TRUE

flows_euclid <- readRDS("results/intermediate/flows_euclid.rds")
bs_files <- list.files("./results/outputs/gams/bs_res", pattern="*.rds", full.names=F)
flows_bs <- lapply(bs_files, function(file){
  readRDS(paste0("./results/outputs/gams/bs_res/", file))
})
names(flows_bs) <- gsub(".rds","",bs_files)
 
flows <- c(flows_euclid, flows_bs)
rm(flows_bs)

#GEO_MUN_SOY <- readRDS("results/intermediate/GEO_MUN_SOY_fin.rds")
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
EXP_MUN_SOY <- readRDS("results/intermediate/EXP_MUN_SOY_cbs.rds")
IMP_MUN_SOY <- readRDS("results/intermediate/IMP_MUN_SOY_cbs.rds")

co_mun <- SOY_MUN$co_mun
product <- c("bean", "oil", "cake")


# bring exports into wide format

EXP_MUN_SOY <- mutate(EXP_MUN_SOY, 
                      product = ifelse(product == "soybean", 
                                       "bean", 
                                       ifelse(product == "soy_oil", "oil", "cake")))

destin <- unique(EXP_MUN_SOY$to_name)
destin <- c("BRA", destin)
destin <- sort(destin)

# template to contain all origins and destinations
exp_templ <- data.frame(
  co_orig = rep(co_mun, each = length(destin), times = length(product)),
  co_dest = rep(destin, times = length(co_mun) * length(product)),
  product = rep(product, each = length(destin) * length(co_mun)))

exp_long  <- left_join(exp_templ, dplyr::select(EXP_MUN_SOY, c(co_mun, product, to_name, export)), 
                       by = c("co_orig" = "co_mun", "co_dest" = "to_name", "product" = "product")) %>% 
  replace_na(list(export = 0))

# add domestic consumption as "exports to Brazil"
#all.equal(exp_long$co_orig[exp_long$co_dest == "BRA" & exp_long$product == "bean"], SOY_MUN$co_mun) 
# NOTE: for bean, remove processing use from domestic use as it is no final use in our soy supply chain
exp_long$export[exp_long$co_dest == "BRA" & exp_long$product == "bean"] <- 
  SOY_MUN$domestic_use_bean - SOY_MUN$proc_bean # (SOY_MUN$prod_oil + SOY_MUN$prod_cake)
exp_long$export[exp_long$co_dest == "BRA" & exp_long$product == "oil"]  <- SOY_MUN$domestic_use_oil
exp_long$export[exp_long$co_dest == "BRA" & exp_long$product == "cake"] <- SOY_MUN$domestic_use_cake


# put data into a list of separate wide-format matrices for each product
exp_wide <- sapply(product, function(x){
  filter(exp_long, product == x) %>% 
    dplyr::select(!product) %>% 
    pivot_wider(names_from = co_dest, values_from = export) %>% 
    column_to_rownames("co_orig") %>% 
    as("Matrix")
}, USE.NAMES = TRUE, simplify = FALSE)


# create uniform format of subnational flows across simulations to be able to compute averages

system.time(
  mu_to_mu <- mclapply(names(flows), function(nm){
    
    x <- flows[[nm]]
  
     # Create wide-format sparse matrix of municpality-to-municpality flows
    flow_wide <- sapply(product, function(prod){
      df <- filter(x, product == prod, value != 0) %>% dplyr::select(!product)
      mat <- with(df, sparseMatrix(i = match(co_orig, co_mun), # dense_rank(co_orig), 
                                   j = match(co_dest, co_mun), # dense_rank(co_dest), 
                                   x = value, 
                                   dims = c(length(co_mun), length(co_mun)),
                                   dimnames = list(co_mun,co_mun))) # list(sort(unique(co_orig)), sort(unique(co_dest)))))
    }, USE.NAMES = TRUE, simplify = FALSE)
  
    
    # add back self-supply to the diagonals
    flow_wide_full <- sapply(product, function(x){
      mat <- flow_wide[[x]]
      diag(mat) <- as.numeric(pull(SOY_MUN, paste0("total_supply_",x)) - pull(SOY_MUN, paste0("excess_supply_",x)))
      return(as(mat, "Matrix"))}, USE.NAMES = TRUE, simplify = FALSE)
    
    # check whether row and column sums add up to total supply and demand
    lapply(product, function(x){
      all.equal(rowSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_supply_",x), name = "co_mun"))
      all.equal(colSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_use_",x), name = "co_mun"))
      })
    
    lapply(product, function(x){
      all.equal(rowSums(flow_wide[[x]]), pull(SOY_MUN, paste0("excess_supply_",x), name = "co_mun"))
      all.equal(colSums(flow_wide[[x]]), pull(SOY_MUN, paste0("excess_use_",x), name = "co_mun"))
    })
    
    # bring back into long format
    flow_long_full <- bind_rows(lapply(product, function(x){
      summ <- summary(flow_wide_full[[x]])
      dt <- data.table(co_orig = co_mun[summ$i], 
                       co_dest = co_mun[summ$j], 
                       product = x, value = summ$x,
                       stringsAsFactors = FALSE)}))
    
    setnames(flow_long_full, "value", nm )
    
  
    return(flow_long_full)
    
    }, mc.cores = 12)
  )

names(mu_to_mu) <- names(flows)

# merge flows of all simulations into single long table  
mu_to_mu_dt <- reduce(mu_to_mu, merge, by = c("co_orig", "co_dest", "product"), all = TRUE) 
mu_to_mu_dt[is.na(mu_to_mu_dt)] <- 0

# compute mean across simulations
mu_to_mu_bs <- mu_to_mu_dt[,which(colnames(mu_to_mu_dt) == "00001"):ncol(mu_to_mu_dt)] %>% as.matrix() %>% as("sparseMatrix")
mu_to_mu_dt <- dplyr::select(mu_to_mu_dt, c(co_orig:euclid))
mu_to_mu_dt <- mu_to_mu_dt %>% mutate(mean = rowSums(mu_to_mu_bs)/ncol(mu_to_mu_bs))
#mu_to_mu_dt <- mu_to_mu_dt %>% mutate(diff = euclid - mean)

# check aggregates outflows per municipality of euclidean and multimodal mean
# --> they should be the same and correspond to municipal total supply
mu_to_mu_agg <- group_by(mu_to_mu_dt, co_orig, product) %>% summarise(across(euclid:mean, .fns = sum))
mu_to_mu_agg <- mu_to_mu_agg %>% mutate(diff = euclid - mean)



# connect subnational with international flows ---------------------------------------------------

## map MU sources to export destinations by multiplying the MU flow matrix in relative terms with the export matrix for each product

system.time(
  source_to_export <- mclapply(c("euclid", "mean"), function(mod){
    
    # put flows into wide format matrices per product again
    dt_mod <- dplyr::select(mu_to_mu_dt, all_of(c("co_orig", "co_dest", "product", mod))) %>% rename(value = paste(mod))
    flow_wide_full <- sapply(product, function(prod){
      dt_mod_prod <- filter(dt_mod, product == prod, value != 0) %>% dplyr::select(!product)
      mat <- with(dt_mod_prod, sparseMatrix(i = match(co_orig, co_mun), # dense_rank(co_orig), 
                                 j = match(co_dest, co_mun), # dense_rank(co_dest), 
                                 x = value, 
                                 dims = c(length(co_mun), length(co_mun)),
                                 dimnames = list(co_mun,co_mun))) # list(sort(unique(co_orig)), sort(unique(co_dest)))))
    }, USE.NAMES = TRUE, simplify = FALSE)
  
    
    # check if rowsums == total supply and colsums == total use
    lapply(product, function(x){
      all.equal(rowSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_supply_",x), name = "co_mun")) &
      all.equal(colSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_use_",x), name = "co_mun"))
    })
    
    # compute "flow coefficient matrix", giving the source shares of each using MU  
    flow_wide_rel <- lapply(flow_wide_full, 
                            function(x){ 
                              rel <- x 
                              rel@x <- rel@x / rep.int(colSums(rel), diff(rel@p))
                              #rel[is.na(rel)] <- 0 
                              return(rel)})
    
  
    # map sources to exports by multiplying the flow coefficient matrix with the export matrix 
    # this entails the implicit assumption that all uses of soy products in a MU (exports, processing, domestic consumption) have the same spatial source structure (proportionality assumption common in IO)
    source_to_export <- sapply(product, function(x){
      flow_wide_rel[[x]] %*% exp_wide[[x]]}, 
      USE.NAMES = TRUE, simplify = FALSE)
    
    ##option2: use exp_wide_rel
    #exp_wide_rel <- lapply(exp_wide, function(x){ rel <- x/rowSums(x); rel[is.na(rel)] <- 0; return(rel)})
    #source_to_export2 <- sapply(product, function(x){flow_wide_full[[x]] %*% exp_wide_rel[[x]]}, USE.NAMES = TRUE, simplify = FALSE)
    ##NOTE: it should not matter which option is used 
    #--> sums of flow_wide and exp_wide need to match!
    # currently there are still slight discrepancies because the export in SOY_MUN are adapted to match the CBS data and EXP_MUN_SOY not yet!
    # after harmonizing the two the issue should be resolved
    # --> ~~NO!, because flow_wide_full for beans contains also flows destined for processing, while "exports to Brazil" have been cleared by that
    
    # check if results match total exports
    Map(function(x,y){all.equal(sum(x),sum(y))}, source_to_export, exp_wide)
    
    # take into account that some of the MU level supply is imported by multiplying rows by "domestic supply share" of each MU
    dom_share <- sapply(product, function(x){
      dom_share <- (pull(SOY_MUN, paste0("prod_",x))/pull(SOY_MUN, paste0("total_supply_",x)))
      dom_share[is.na(dom_share)] <- 0
      return(dom_share)
      }, USE.NAMES = TRUE, simplify = TRUE) %>% as.data.frame() %>% `rownames<-`(SOY_MUN$co_mun)
    
    source_to_export <- sapply(product, function(x){
      source_to_export[[x]] * dom_share[[x]]}, 
      USE.NAMES = TRUE, simplify = FALSE)
    
    sapply(source_to_export, sum, na.rm = T) 
    
    # finally, map oil and cake exports back to the origin of soybean production... 
    # ..by multiplying the bean flow coefficient matrix with the export matrices of oil and cake
    # this again assumes that all uses of beans in a MU (export, processing ...) share the same spatial source structure
    # the result is in turn corrected by the domestic bean supply share of each MU to remove bean imports at the source
    source_to_export[2:3] <- lapply(source_to_export[2:3], function(x){
      (flow_wide_rel$bean %*% x) * dom_share$bean}) 
    
    sapply(source_to_export, sum, na.rm = T) 
    
    # bring back into long format
    source_to_export_df <- lapply(product, function(x) {
      # convert to triplet form
      m <- source_to_export[[x]]
      m <- as(m, "dgTMatrix")
      # convert to data frame: convert to 1-based indexing (see https://stackoverflow.com/questions/52662748/from-sparsematrix-to-dataframe)
      df <- data.frame(i=(rownames(m)[m@i + 1]), 
                       j=(colnames(m)[m@j + 1]), 
                       x=m@x, 
                       stringsAsFactors = FALSE)
      names(df) <- c("from_code", "to_code", "value")
      df <- mutate(df, item_code = x, .before = from_code)
    }) 
    
    # bind results
    source_to_export_fin <- bind_rows(source_to_export_df)
    
    # filter zero-flows
    source_to_export_fin <- filter(source_to_export_fin, value > 0)
    
    return(source_to_export_fin)
    
  }, mc.cores = 12)

)
names(source_to_export) <- c("euclid","multimode_mean")


# export results
if (write){
  #saveRDS(source_2_export, "results/intermediate/source_to_export_list.rds")
  saveRDS(mu_to_mu_dt, "results/intermediate/flows_mu.rds")
  saveRDS(source_to_export, "results/intermediate/source_to_export_mean.rds")
}

rm(list = ls())
gc()

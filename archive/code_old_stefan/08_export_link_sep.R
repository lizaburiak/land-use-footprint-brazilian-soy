
#### linking subnational to international flows: from MU of origin to country of first import ####

## this version conducts the linkage separately for each simulation of the multimodal model 

library(dplyr)
library(data.table)
library(tibble)
library(tidyr)
library(abind)
library(Matrix.utils)
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

SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
EXP_MUN_SOY <- readRDS("results/intermediate/EXP_MUN_SOY_cbs.rds")
IMP_MUN_SOY <- readRDS("results/intermediate/IMP_MUN_SOY_cbs.rds")

co_mun <- SOY_MUN$co_mun
product <- c("bean", "oil", "cake"); names(product) <- product

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




system.time(
  source_2_export <- mclapply(flows, function(x){  
  
     ## Create a wide-format version of flows as a sparse matrix
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
      all.equal(colSums(flow_wide_full[[x]]), pull(SOY_MUN, paste0("total_use_",x), name = "co_mun"))})
    
    
    # take into account that some of the MU level supply is imported by multiplying rows by "domestic supply share" of each MU
    dom_share <- sapply(product, function(x){
      dom_share <- (pull(SOY_MUN, paste0("prod_",x))/pull(SOY_MUN, paste0("total_supply_",x)))
      dom_share[is.na(dom_share)] <- 0
      return(dom_share)
    }, USE.NAMES = TRUE, simplify = TRUE) %>% as.data.frame() %>% `rownames<-`(SOY_MUN$co_mun)
    
    flow_wide_full <- sapply(product, function(x){
      flow_wide_full[[x]] * dom_share[[x]]}, 
      USE.NAMES = TRUE, simplify = FALSE)
    
    
    # bring back into long format
    flow_long_full <- bind_rows(lapply(product, function(x){
      summ <- summary(flow_wide_full[[x]])
      df <- data.frame(co_orig = co_mun[summ$i], 
                       co_dest = co_mun[summ$j], 
                       product = x, value = summ$x,
                       stringsAsFactors = FALSE)}))
    
   
    # create relative source shares by dividing columns by total use of each MU
    flow_wide_rel <- lapply(product, function(x){ 
                              rel <- flow_wide_full[[x]] 
                              rel@x <- rel@x / rep.int(pull(SOY_MUN, paste0("total_use_",x)), diff(rel@p))
                              #rel[is.na(rel)] <- 0 
                              return(rel)})
    
  
    # map sources to exports by multiplying the flow coefficient matrix with the export matrix 
    # this entails the implicit assumption that all uses of soy products in a MU (exports, processing, domestic consumption) have the same spatial source structure (proportionality assumption common in IO)
    source_to_export <- sapply(product, function(x){
      flow_wide_rel[[x]] %*% exp_wide[[x]]}, 
      USE.NAMES = TRUE, simplify = FALSE)
    
  
    # finally, map oil and cake exports back to the origin of soybean production... 
    # ..by multiplying the bean flow coefficient matrix with the export matrices of oil and cake
    # this again assumes that all uses of beans in a MU (export, processing ...) share the same spatial source structure
    # the result is in turn corrected by the domestic bean supply share of each MU to remove bean imports at the source
    source_to_export[2:3] <- lapply(source_to_export[2:3], function(x){
      (flow_wide_rel$bean %*% x)}) 
    
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


# export results
if (write){
  saveRDS(source_2_export, "results/intermediate/source_to_export_list.rds")
}

rm(list = ls())
gc()

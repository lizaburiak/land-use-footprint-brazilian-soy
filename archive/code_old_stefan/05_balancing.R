
####### Final adjustments to municipality-level data to balance supply with demand #######

library(dplyr)
library(sf)

write = TRUE

# load data -----------------------------------------------------------------------------------
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_03.rds")
GEO_MUN_SOY <- readRDS("results/intermediate/GEO_MUN_SOY_03.rds")
CBS_SOY <- readRDS("results/intermediate/CBS_SOY.rds")
EXP_MUN_SOY <- readRDS("results/intermediate/EXP_MUN_SOY.rds")
IMP_MUN_SOY <- readRDS("results/intermediate/IMP_MUN_SOY.rds")


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

# re-scale MU level data to match national FAO values
SOY_MUN[,names(SOY_MUN_cbs)] <- as.data.frame(t(t(SOY_MUN_cbs)*SOY_agg$ratio))

# check for balance, adding columns for total supply and demand of each product
SOY_agg$MUN_fin <- colSums(SOY_MUN[,names(SOY_MUN_cbs)])
SOY_agg$check <- SOY_agg$MUN_fin == SOY_agg$FAO
cat("all items balanced: ", all.equal(SOY_agg$FAO,SOY_agg$MUN_fin), "\n")

# add totals to mun table
SOY_MUN  <- SOY_MUN %>%  
  mutate(total_supply_bean = prod_bean + imp_bean, 
                             total_supply_oil = prod_oil + imp_oil, 
                             total_supply_cake = prod_cake + imp_cake, 
                             total_use_bean = exp_bean + food_bean + feed_bean + seed_bean + proc_bean + stock_bean,
                             total_use_oil = exp_oil + food_oil + other_oil + stock_oil,
                             total_use_cake = exp_cake + feed_cake + stock_cake)

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
  saveRDS(SOY_MUN, file = "results/intermediate/SOY_MUN_fin.rds")
  saveRDS(GEO_MUN_SOY, file = "results/intermediate/GEO_MUN_SOY_fin.rds")
  saveRDS(CBS_SOY, file = "results/intermediate/CBS_SOY_bal.rds")
  #write.csv2(CBS_SOY, file = "results/intermediate/CBS_SOY.csv")
  saveRDS(EXP_MUN_SOY, file = "results/intermediate/EXP_MUN_SOY_cbs.rds")
  saveRDS(IMP_MUN_SOY, file = "results/intermediate/IMP_MUN_SOY_cbs.rds")
}

# clear environment
rm(list = ls())
gc()

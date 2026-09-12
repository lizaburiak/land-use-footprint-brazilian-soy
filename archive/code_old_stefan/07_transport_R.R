####### simple transport optimization within R, using the transport package #######

library(transport)
library(openxlsx)
library(dplyr)
library(abind)

write = TRUE

# load modified version of the transport function
#source("R/function_library.R")

# load data
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
MUN_capital_dist <- readRDS("results/intermediate/MUN_capital_dist.rds")


# specify distance type: we only use Euclidean here, but any other cost/distance type could also be used 
dist <- list(euclid = MUN_capital_dist)

flows <- lapply(dist, function(d){
  MUN_dist <- d
  class(MUN_dist) <- "numeric"

  product <- c("bean", "oil", "cake")

  MUN_transport <- sapply(product, function(x){
    suppliers <- SOY_MUN$co_mun[pull(SOY_MUN, paste0("excess_supply_",x))>0]
    demanders <- SOY_MUN$co_mun[pull(SOY_MUN, paste0("excess_use_",x))>0]
    solve <- transport(a = pull(SOY_MUN, paste0("excess_supply_",x)), b = pull(SOY_MUN, paste0("excess_use_",x)), costm = MUN_dist, method = "networkflow", fullreturn=TRUE, threads=4)
    cat("total cost ", x, ": ", solve$cost, "\n")
    sol <- solve$default
    sol$co_orig <- suppliers[sol$from]
    sol$co_dest <- demanders[sol$to]
    sol$product <- x
    sol <- sol[,c("co_orig", "co_dest", "product", "mass")]
    names(sol)[4] <- "value"
    return(sol)
    }, 
    simplify = FALSE, USE.NAMES = TRUE)
  
  flows <- abind(MUN_transport, along = 1, force.array = FALSE)
  return(flows)
})


if (write){
  saveRDS(flows, file = "results/intermediate/flows_euclid.rds")
  
}

rm(list = ls())

####### Script to compare aggregate MU data with national data from FAO

library(dplyr)
library(openxlsx)

# Year parameter (default 2013)
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2013
OUT  <- paste0("data/generated/outputs/00_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# should results be written to file?
write = TRUE

# load and format data ---------------------------------------------------------------------------------
SOY_MUN <- readRDS(paste0(OUT, "SOY_MUN_00.rds"))
CBS_SOY <- openxlsx::read.xlsx(paste0("data/raw/00/FAO_CBS/CBS_SOY_", YEAR, "_FAO.xlsx"))

# format FAO CBS
CBS_SOY <- CBS_SOY[-c(1,2, nrow(CBS_SOY)),]
rownames(CBS_SOY) <- c("domestic_supply","production", "export", "import" , "food" , "feed", "seed", "other", "processing", "stock_withdrawal")
CBS_SOY <- CBS_SOY[,5:3]
colnames(CBS_SOY) <- c("bean", "oil", "cake")
CBS_SOY <- as.data.frame(t(CBS_SOY), stringsAsFactors = FALSE)
CBS_SOY <- CBS_SOY %>% mutate(across(everything(), ~as.numeric(as.character(.x))))
CBS_SOY[is.na(CBS_SOY)] <- 0
CBS_SOY<- mutate(CBS_SOY, stock_addition = -stock_withdrawal)


# investigate structure of CBS ---------------------------------------------------------------------------

# supply side:
CBS_SOY$domestic_supply
CBS_SOY <- mutate(CBS_SOY, dom_supply_side = production - export + import + stock_withdrawal)
# --> domestic_supply = production - export + import + stock_withdrawal

# use side:
CBS_SOY <- mutate(CBS_SOY, dom_use_side = food + feed + other + processing + seed)
# --> domestic_supply = food + feed + other + processing + seed


# consistency checks between FAO and gathered MU data on aggregate -----------------------------------------------

consistency <- data.frame(row.names = c("MU_data","FAO"))

###  check if MU soybean production sums up to FOA data
consistency$prod[1] <- sum(SOY_MUN$prod, na.rm = TRUE)
consistency$prod[2] <- CBS_SOY["bean", "production"]


### check exports
consistency$exp_bean[1] <- sum(SOY_MUN$exp_bean, na.rm = TRUE)
consistency$exp_bean[2] <- CBS_SOY["bean","export"]

consistency$exp_oil[1] <- sum(SOY_MUN$exp_oil, na.rm = TRUE)
consistency$exp_oil[2] <- CBS_SOY["oil", "export"]

consistency$exp_cake[1] <- sum(SOY_MUN$exp_cake, na.rm = TRUE)
consistency$exp_cake[2] <- CBS_SOY["cake", "export"]


### check imports
consistency$imp_bean[1] <- sum(SOY_MUN$imp_bean, na.rm = TRUE)
consistency$imp_bean[2] <- CBS_SOY["bean","import"]

consistency$imp_oil[1] <- sum(SOY_MUN$imp_oil, na.rm = TRUE)
consistency$imp_oil[2] <- CBS_SOY["oil","import"]

consistency$imp_cake[1] <- sum(SOY_MUN$imp_cake, na.rm = TRUE)
consistency$imp_cake[2] <- CBS_SOY["cake", "import"]


### check processing
# compare with preliminary annual soybean processing amount by multiplying daily capacities with 5 weekdays*52
consistency$proc_cap[1] <- sum(SOY_MUN$proc_cap, na.rm = TRUE)*5*52
consistency$proc_cap[2] <- CBS_SOY["bean", "processing"]

consistency$ref_cap[1] <- sum(SOY_MUN$ref_cap, na.rm = TRUE)*5*52
consistency$ref_cap[2] <- CBS_SOY["oil", "production"]


# write data
if (write == TRUE) {
  saveRDS(CBS_SOY, file = paste0(OUT, "CBS_SOY.rds"))
  write.csv2(CBS_SOY, file = paste0(OUT, "CBS_SOY.csv"))
  saveRDS(consistency, file = paste0(OUT, "FAO_consistency.rds"))
}

rm(list=ls())
gc()

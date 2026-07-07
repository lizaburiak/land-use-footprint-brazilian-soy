# ============================================================================
# Descriptive-statistics tables (LaTeX) for the municipal commodity balance:
#   (1) per-item summary (n>0, mean, sd, min, max, sum) across municipalities,
#   (2) the aggregate Brazilian soy CBS for 2013.
# Interactive helper.
# Inputs : data/generated/base/{SOY_MUN_fin,GEO_MUN_SOY_03,CBS_SOY}.rds
# Outputs: results/tables/{summary_stats_mun,cbs_bra_2013}.tex
# ============================================================================

### create nice paper summary table for all cbs items on municpality level ###

library(dplyr)
library(sf)
library(units)
library(stringr)
library(xtable)

SOY_MUN <- readRDS("data/generated/base/SOY_MUN_fin.RDS")
#SOY_MUN_full <- readRDS("data/generated/base/SOY_MUN_03.rds")
GEO_MUN_SOY <- readRDS("data/generated/base/GEO_MUN_SOY_03.rds")

# convert to kiltons/km2
SOY_MUN_kilo <- SOY_MUN %>% mutate(area_plant = area_plant/1e3, area_harv = area_harv/1e3) %>% mutate(across(ends_with(c("_bean", "_cake", "_oil")), function(x) x/1e3 ))
# compute area per MU and population in 1000s
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(area = as.numeric(st_area(GEO_MUN_SOY)/1e6), population = population/1e3)
# bind and create table
SOY_MUN_kilo <- cbind(SOY_MUN_kilo, select(st_drop_geometry(GEO_MUN_SOY), c(population, area)))
soy_table <- select(SOY_MUN_kilo, c(#co_mun:nm_state,
                               population, area, area_plant,
                               prod_bean, imp_bean, exp_bean, proc_bean, feed_bean, seed_bean, stock_bean, 
                               prod_oil, imp_oil, exp_oil, food_oil, other_oil, stock_oil,
                               prod_cake, imp_cake, exp_cake, feed_cake, stock_cake))

summary_funct <- function(var){
  smry <- as.character(c("n>0" = round(sum(var!=0, na.rm = TRUE),0),
            "mean"= round(mean(var[var!=0], na.rm = TRUE),1),
            "sd"  = round(sd(var[var!=0], na.rm = TRUE),1),
            "min" = round(min(var[var!=0], na.rm = TRUE),1),
            "max" = round(max(var[var!=0], na.rm = TRUE),1),
            "sum" = round(sum(var[var!=0], na.rm = TRUE),1)))
  names(smry) <- c("n>0", "mean", "sd", "min", "max", "sum")
  return(smry)
  }


soy_summary <- sapply(soy_table, summary_funct)
soy_summary <- as.data.frame(t(soy_summary))

print(xtable(soy_summary, caption = "Descriptive statistics of CBS for municipalities",digits = 1), 
      file = "results/tables/summary_stats_mun.tex",
      include.rownames=TRUE)

## create same table grouped by state 
#stargazer(soy_table, 
#          type = 'text', min.max=TRUE, mean.sd = TRUE, 
#          nobs = TRUE, median = FALSE, iqr = FALSE,
#          digits=1, align=T,
#          title = "Summary Statistics")


## baseline cbs table
CBS_SOY <- readRDS("data/generated/base/CBS_SOY.rds")
CBS_SOY_table <- CBS_SOY %>% select(production, import, export, processing, feed, food, other, seed, stock_addition)
rownames(CBS_SOY_table) <- c("Soybean", "Soy Oil", "Soy Cake")
colnames(CBS_SOY_table) <- str_to_sentence(colnames(CBS_SOY_table))
# change units from tons into kilotons
CBS_SOY_table <- CBS_SOY_table %>% mutate(across(where(is.numeric), function(x){x/1000}))

# save to tex
print(xtable(CBS_SOY_table, caption = "CBS for the Brazilian soy complex in 2013",digits = 1), 
      file = "results/tables/cbs_bra_2013.tex",
      include.rownames=TRUE)

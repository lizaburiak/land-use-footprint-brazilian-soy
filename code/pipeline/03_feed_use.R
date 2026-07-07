
####### Feed use estimation, using estimated animal numbers by livestock system and FAO feed ratios ############

library(dplyr)
library(sf)
library(openxlsx)

# Year parameter (default 2013)
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2013
IN00 <- paste0("data/generated/outputs/00_", YEAR, "/")
IN02 <- paste0("data/generated/outputs/02_", YEAR, "/")
OUT  <- paste0("data/generated/outputs/03_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# should results be written to file ?
write = TRUE

# load data ---------
SOY_MUN <- readRDS(paste0(IN02, "SOY_MUN_02.rds"))
GEO_MUN_SOY <- readRDS(paste0(IN02, "GEO_MUN_SOY_02.rds"))
feed_ratios <- openxlsx::read.xlsx("data/raw/03/Feed_ratios_FAO.xlsx", sheet = 2)
CBS_SOY <- readRDS(paste0(IN00, "CBS_SOY.rds"))


# prepare feed ratios --------------

# compute average soy feed use per animal and year in tons, using dry matter content of 88% for both bean and cake (EMBRAPA) -------------
dm_content <- c("bean" = 0.88, "cake" = 0.88)
# dry matter intake per animal and year
feed_ratios <- mutate(feed_ratios, bean_dm = DM*bean/100, cake_dm = DM*cake/100)
# total (wet matter) intake per animal and year in kg and tons
feed_ratios <- mutate(feed_ratios, bean_kg = bean_dm / dm_content["bean"], cake_kg = cake_dm / dm_content["cake"])
feed_ratios <- mutate(feed_ratios, bean_t = bean_kg/1000, cake_t = cake_kg/1000)


# compute feed use for each MU by specie ------------------------

## soybeans
bean_feed_t <- t(t(SOY_MUN[,feed_ratios$system_name]) * feed_ratios$bean_t)

## soy cake
cake_feed_t <- t(t(SOY_MUN[,feed_ratios$system_name]) * feed_ratios$cake_t)

### compare with FAO national feed use aggregates and re-scale to match these values
sum(bean_feed_t)
CBS_SOY["bean", "feed"]

sum(cake_feed_t)
CBS_SOY["cake", "feed"]

# na.rm so a single non-geographic placeholder municipality (e.g. COMEX code
# 9300000, which has NA livestock counts) does not poison the scale factor and
# turn every municipality's feed into NA. Real municipalities are unaffected.
bean_feed_t_fin <- bean_feed_t*(CBS_SOY["bean", "feed"]/sum(bean_feed_t, na.rm = TRUE))
cake_feed_t_fin <- cake_feed_t*(CBS_SOY["cake", "feed"]/sum(cake_feed_t, na.rm = TRUE))


### add total soybean and cake feed use per MU to the main table
SOY_MUN <- mutate(SOY_MUN, feed_bean = rowSums(bean_feed_t_fin, na.rm = TRUE), feed_cake = rowSums(cake_feed_t_fin, na.rm = TRUE))

all.equal(sum(SOY_MUN$feed_bean),CBS_SOY["bean", "feed"])
all.equal(sum(SOY_MUN$feed_cake),CBS_SOY["cake", "feed"])

# add new columns to GEO dataset
GEO_MUN_SOY <- left_join(GEO_MUN_SOY, SOY_MUN[,c("co_mun","feed_bean", "feed_cake")], by="co_mun")

# add back MU codes to feed data
bean_feed_t_fin <- as.data.frame(bean_feed_t_fin) %>% `rownames<-`(SOY_MUN$co_mun)
cake_feed_t_fin <- as.data.frame(cake_feed_t_fin) %>% `rownames<-`(SOY_MUN$co_mun)

# export data -----------------------
if (write){
  saveRDS(bean_feed_t_fin, file = paste0(OUT, "bean_feed_t.rds"))
  saveRDS(cake_feed_t_fin, file = paste0(OUT, "cake_feed_t.rds"))
  saveRDS(SOY_MUN, file = paste0(OUT, "SOY_MUN_03.rds"))
  saveRDS(GEO_MUN_SOY, file = paste0(OUT, "GEO_MUN_SOY_03.rds"))
}

rm(list=ls())
gc()

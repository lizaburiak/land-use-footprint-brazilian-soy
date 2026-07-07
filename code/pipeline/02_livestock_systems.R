
######## Estimation of MU livestock numbers by production system #########
#
# YEAR-DEPENDENCE — two caveats for the multi-year extension:
#  (A) Production-SYSTEM SHARES (pig ext/int/ind, chicken, cattle grassland/mixed)
#      are derived from the 2010 GLW3 / Gilbert-et-al-2015 rasters and the static
#      GLPS map, then applied to each YEAR's IBGE headcounts. Only the *totals* move
#      with YEAR; the *spatial system composition* is held at 2010. There is no
#      annual production-system product (GLW3 is 2010-only; newer GLW / the 2025
#      annual gridded-livestock dataset give totals but no ext/int/ind split), so
#      this is a stated methodological limitation, not a fixable input.
#  (B) FEEDLOT cattle: the 2006 IBGE census municipal pattern is scaled to YEAR by
#      the national ABIEC confinement series (see the feedlot block below) — no
#      longer frozen at the 2013 growth factor.

library(raster)
library(sf)
library(exactextractr)
library(dplyr)
library(tidyr)
library(openxlsx)
library(mapview)
library(leafsync)

# Year parameter (default 2013)
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2013
IN01 <- paste0("data/generated/outputs/01_", YEAR, "/")
OUT  <- paste0("data/generated/outputs/02_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# should results be written to file?
write = TRUE

# load and prepare gridded livestock data ----------------------------------------------------------------------------------------------------

# municipalities
GEO_MUN_SOY <- readRDS(paste0(IN01, "GEO_MUN_SOY_01.rds"))
SOY_MUN <- readRDS(paste0(IN01, "SOY_MUN_01.rds"))

# GUARD (2026-07): the total-chicken IBGE column ("Galináceos - total") is empty
# in the 2014+ raw files (fixed in download_data.py). When it reads 0 while
# chicken_layer > 0, the broiler residual (chicken - chicken_layer) below turns
# negative -> negative cake feed (step 03) -> negative total_use_cake (step 05)
# -> the cake re-export inversion (step 12) needs a ridge fallback. Floor the
# total at the reported layer count so herds stay non-negative and the three-way
# partition (byd+lay+bro == chicken) still holds. On correct data this is a no-op.
.floor_chicken <- function(df) {
  if (!all(c("chicken", "chicken_layer") %in% names(df))) return(df)
  bad <- !is.na(df$chicken_layer) & df$chicken < df$chicken_layer
  if (any(bad, na.rm = TRUE))
    warning(sprintf("[02] YEAR=%d: %d municipalities have chicken_layer > total chicken; flooring total at layers. Check raw IBGE 'Galináceos - total' (see download_data.py).",
                    YEAR, sum(bad, na.rm = TRUE)))
  df$chicken <- ifelse(!is.na(df$chicken_layer),
                       pmax(df$chicken, df$chicken_layer), df$chicken)
  df
}
GEO_MUN_SOY <- .floor_chicken(GEO_MUN_SOY)
SOY_MUN     <- .floor_chicken(SOY_MUN)

# chicken rasters
ChExt <- raster("data/raw/02/geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif")
ChInt <- raster("data/raw/02/geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif")

# pig rasters
PgExt <- raster("data/raw/02/geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif")
PgInt <- raster("data/raw/02/geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif")
PgInd <- raster("data/raw/02/geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif")


# cattle distribution raster (only numbers, no systems)
Cattle <- raster("data/raw/02/geo/FAO_gridded_livestock/5_Ct_2010_Da.tif")
# buffalo distribution raster (only numbers, no systems)
Buffalo <- raster("data/raw/02/geo/FAO_gridded_livestock/5_Bf_2010_Da.tif")
# ruminant systems
RumSys <- raster("data/raw/02/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif")

# feedlot cattle data (IBGE 2006 census)
feedlot <- openxlsx::read.xlsx("data/raw/02/FeedlotCattle_2006_tabela919_IBGE.xlsx", rows = 6:5455, na.strings = c("X", "-"))

# crop data to extent of Brazil
GEO_MUN_SOY_WGS84 <- st_transform(GEO_MUN_SOY, crs = st_crs(ChExt))
ChExt <- crop(ChExt, GEO_MUN_SOY_WGS84)
ChInt <- crop(ChInt, GEO_MUN_SOY_WGS84)
PgExt <- crop(PgExt, GEO_MUN_SOY_WGS84)
PgInt <- crop(PgInt, GEO_MUN_SOY_WGS84)
PgInd <- crop(PgInd, GEO_MUN_SOY_WGS84)
Cattle <- crop(Cattle, GEO_MUN_SOY_WGS84)
Buffalo <- crop(Buffalo, GEO_MUN_SOY_WGS84)
RumSys <- crop(RumSys, GEO_MUN_SOY_WGS84)


### compute number of animals per livestock system for each MU:

# chicken and pigs --------------------------------------------------------------------------------------------------

# compute total number of animals per MU through zonal sum statistic
# NOTE that the Polygons in WGS84 are used to compute sums but results are added to the original file
GEO_MUN_SOY$ChExt <- exact_extract(ChExt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$ChInt <- exact_extract(ChInt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$PgExt <- exact_extract(PgExt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$PgInt <- exact_extract(PgInt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$PgInd <- exact_extract(PgInd, GEO_MUN_SOY_WGS84, 'sum')

# check consistency with IBGE YEAR livestock data (raster reference year: 2010)
sum(GEO_MUN_SOY$chicken, na.rm = T)
sum(GEO_MUN_SOY$ChExt) + sum(GEO_MUN_SOY$ChInt)

sum(GEO_MUN_SOY$pig, na.rm = T)
sum(GEO_MUN_SOY$PgExt, na.rm = T) + sum(GEO_MUN_SOY$PgInt, na.rm = T) + sum(GEO_MUN_SOY$PgInd, na.rm = T)

# compute shares of livestock systems for pigs and chicken for each MU
GEO_MUN_SOY <- GEO_MUN_SOY %>%
  mutate(PgExtShare = PgExt / (PgExt+PgInt+PgInd),
         PgIntShare = PgInt / (PgExt+PgInt+PgInd),
         PgIndShare = PgInd / (PgExt+PgInt+PgInd))

GEO_MUN_SOY <- GEO_MUN_SOY %>%
  mutate(ChExtShare = ChExt / (ChExt+ChInt),
         ChIntShare = ChInt / (ChExt+ChInt))

# replace NA shares by state averages (for MUs which have no animals in 2010 gridded data but have some in 2013 IBGE data)
GEO_MUN_SOY <- GEO_MUN_SOY %>% group_by(co_state) %>%
   mutate(PgExtShare = if_else(is.na(PgExtShare), mean(PgExtShare, na.rm=TRUE), PgExtShare),
          PgIntShare = if_else(is.na(PgIntShare), mean(PgIntShare, na.rm=TRUE), PgIntShare),
          PgIndShare = if_else(is.na(PgIndShare), mean(PgIndShare, na.rm=TRUE), PgIndShare),
          ChExtShare = if_else(is.na(ChExtShare), mean(ChExtShare, na.rm=TRUE), ChExtShare),
          ChIntShare = if_else(is.na(ChIntShare), mean(ChIntShare, na.rm=TRUE), ChIntShare)) %>% ungroup()


## apply 2010-derived system shares to YEAR headcounts to obtain pig and chicken numbers by system
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(pig_byd = pig*PgExtShare,
                                      pig_int = pig*PgIntShare,
                                      pig_ind = pig*PgIndShare,
                                      # chicken: backyard = extensive (includes extensive layers as well as broilers)
                                      chicken_byd = chicken*ChExtShare,
                                      # broilers = intensive broilers = part of total - layers
                                      # considering cases where there are no layers (chicken_layer = NA)
                                      chicken_bro = ifelse(is.na(chicken_layer), chicken*ChIntShare, (chicken - chicken_layer)*ChIntShare),
                                      # layers = intensive part of layers from IBGE
                                      chicken_lay = chicken_layer*ChIntShare) %>%
                              # remove "old" layer chicken (which include both backyard and industrial)
                              dplyr::select(-chicken_layer) %>%
                              relocate(c(pig_byd, pig_int, pig_ind), .after = pig_mother) %>%
                              relocate(c(chicken_byd, chicken_lay, chicken_bro), .after = chicken)



# ruminants (cattle & buffaloes) ------------------------------------------------------------------------------------------------

### cattle:

## extract numbers of animals for each management system by combining the cattle number grid with the management system areas
# extract cattle numbers where system is livestock-only & grassland based (values 1-4)
CattGrass <- Cattle
CattGrass[!RumSys %in% c(1:4)] <- 0
# cattle numbers where system is mixed (values 5-12)
CattMix <- Cattle
CattMix[!RumSys %in% c(5:12)] <- 0
# cattle numbers where system is urban (value 13) "other tree based" (14, e.g. rainforest) and "unsuitable" (15)
CattUrb <- Cattle ; CattUrb[!RumSys %in% c(13)] <- 0
CattOth <- Cattle ; CattOth[!RumSys %in% c(14)] <- 0
CattUns <- Cattle ; CattUns[!RumSys %in% c(15)] <- 0

# check sum
cellStats(Cattle, sum)
cellStats(CattGrass, sum) + cellStats(CattMix, sum) + cellStats(CattUrb, sum) + cellStats(CattOth, sum) + cellStats(CattUns, sum)

# add "other" and "unsuitable" to Grassland and "urban" to Mixed
CattGrass <- CattGrass + CattOth + CattUns
CattMix <- CattMix + CattUrb

# set original NA cells of cattle dataset back to NA (not really necessary)
CattGrass[is.na(Cattle)] <- NA
CattMix[is.na(Cattle)] <- NA

# compute total number of grass and mixed cattle per MU through zonal sum statistic
GEO_MUN_SOY$CattGrass <- exact_extract(CattGrass, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$CattMix <- exact_extract(CattMix, GEO_MUN_SOY_WGS84, 'sum')

# check consistency with IBGE YEAR livestock data (raster reference year: 2010)
sum(GEO_MUN_SOY$cattle, na.rm = T)
sum(GEO_MUN_SOY$CattGrass, na.rm = T) + sum(GEO_MUN_SOY$CattMix, na.rm = T)

# compute shares
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(CattGrassShare = CattGrass / (CattGrass+CattMix),
                                      CattMixShare = CattMix / (CattGrass+CattMix))

# replace NA shares by state averages (for MUs which have no animals in 2010 gridded data but have some in 2013 IBGE data)
GEO_MUN_SOY <- GEO_MUN_SOY %>% group_by(co_state) %>%
  mutate(CattGrassShare = if_else(is.na(CattGrassShare), mean(CattGrassShare, na.rm=TRUE), CattGrassShare),
         CattMixShare = if_else(is.na(CattMixShare), mean(CattMixShare, na.rm=TRUE), CattMixShare)) %>% ungroup()


## include feedlot cattle numbers from the IBGE 2006 census, scaled to YEAR.
## The 2006 census provides the *municipal distribution* of feedlot cattle; we scale
## the national total to YEAR by the ABIEC/Athenagro confinement series (below).
## LIMITATION: the 2006 municipal *pattern* is held fixed — only the national total
## moves with YEAR. The 2006 census (SIDRA tabela 919) is the ONLY municipal
## confined-cattle source: the 2017 Censo Agropecuário dropped the confinement
## question (no 2017 municipal feedlot table exists), so national scaling is the
## best available approach for the municipal distribution.
feedlot <- feedlot[,-c(3,5,6)]
colnames(feedlot) <- c("co_mun", "nm_mun", "cattle_tot", "cattle_flot" )
feedlot <- mutate(feedlot, co_mun = as.numeric(co_mun), cattle_tot = as.numeric(cattle_tot), cattle_flot = as.numeric(cattle_flot))

sum(feedlot$cattle_flot, na.rm = TRUE)
sum(feedlot$cattle_tot, na.rm = TRUE)
sum(SOY_MUN$cattle)# much more because the census data considers only farms with >50 animals

# National confined-cattle totals (million head), ABIEC/Athenagro "Bovinos Confinados"
# series, Beef Report 2023 (abiec.com.br) — the same source as the original 2006/2013
# anchors. Values for unlabeled chart years are read from the bar chart (~±0.1 M);
# 2006, 2013, 2021 and 2022 are confirmed. Refine against exact ABIEC data if needed.
.confined_Mhead <- c(`2006`=3.46, `2007`=3.90, `2008`=4.05, `2009`=3.35, `2010`=3.05,
                     `2011`=3.85, `2012`=4.10, `2013`=4.38, `2014`=4.70, `2015`=5.20,
                     `2016`=5.20, `2017`=5.25, `2018`=6.65, `2019`=7.15, `2020`=6.90,
                     `2021`=7.20, `2022`=7.62)
.fl_yr <- as.character(min(max(YEAR, 2006L), 2022L))          # clamp to series range
if (YEAR < 2006L || YEAR > 2022L)
  warning("feedlot: YEAR ", YEAR, " outside ABIEC series 2006-2022; clamped to ", .fl_yr)
# extrapolate feedlot cattle from 2006 by the national confinement growth to YEAR
feedlot_growth <- .confined_Mhead[[.fl_yr]] / .confined_Mhead[["2006"]]
cat("  Feedlot growth factor (", YEAR, "/2006):", round(feedlot_growth, 3), "\n")
feedlot <- mutate(feedlot, cattle_flot_yr = round(cattle_flot*feedlot_growth))

# merge with main table
feedlot <- feedlot %>% left_join(SOY_MUN[,c(1,2,4)], by = "co_mun") # check for consistency
GEO_MUN_SOY <- GEO_MUN_SOY %>% left_join(feedlot[,c(1,5)], by = "co_mun") %>%
            rename("cattle_flot"  = "cattle_flot_yr") %>%
            relocate(cattle_flot, .after = cattle_milked) %>%
            replace_na(list(cattle_flot = 0))



## apply 2010-derived system shares to YEAR headcounts to obtain cattle numbers by system
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(# dairy cattle
                                        cattle_gra_dair = cattle_milked*CattGrassShare,
                                        cattle_mix_dair = cattle_milked*CattMixShare,
                                        # meat as residual of total - dairy - feedlot
                                        cattle_gra_meat = (cattle - cattle_milked - cattle_flot)*CattGrassShare,
                                        cattle_mix_meat = (cattle - cattle_milked - cattle_flot)*CattMixShare) %>%
                                relocate(c(cattle_gra_dair, cattle_mix_dair, cattle_gra_meat, cattle_mix_meat), .after = cattle_milked)


## buffaloes: repeat procedure of cattle (except the feedlot part)

## extract numbers of animals for each management system by combining the buffalo number grid with the management system areas
# grassland - already including other tree based and unsuited areas (14 & 15)
BuffGrass <- Buffalo
BuffGrass[!RumSys %in% c(1:4, 14, 15)] <- 0
# mixed - already including urban areas (13)
BuffMix <- Buffalo
BuffMix[!RumSys %in% c(5:13)] <- 0

cellStats(Buffalo, sum)
cellStats(BuffGrass, sum) + cellStats(BuffMix, sum)

# set original NA cells of buffalo dataset back to NA (not really necessary)
BuffGrass[is.na(Buffalo)] <- NA
BuffMix[is.na(Buffalo)] <- NA

# compute total number of grass and mixed buffalo per MU through zonal sum statistic
GEO_MUN_SOY$BuffGrass <- exact_extract(BuffGrass, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$BuffMix <- exact_extract(BuffMix, GEO_MUN_SOY_WGS84, 'sum')

# check consistency with IBGE YEAR livestock data (raster reference year: 2010)
sum(GEO_MUN_SOY$buffalo, na.rm = T)
sum(GEO_MUN_SOY$BuffGrass, na.rm = T) + sum(GEO_MUN_SOY$BuffMix, na.rm = T)

# compute shares
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(BuffGrassShare = BuffGrass / (BuffGrass+BuffMix),
                                      BuffMixShare = BuffMix / (BuffGrass+BuffMix))

# replace NA shares by state averages (for MUs which have no animals in 2010 gridded data but have some in 2013 IBGE data)
GEO_MUN_SOY <- GEO_MUN_SOY %>% group_by(co_state) %>%
  mutate(BuffGrassShare = if_else(is.na(BuffGrassShare), mean(BuffGrassShare, na.rm=TRUE), BuffGrassShare),
         BuffMixShare = if_else(is.na(BuffMixShare), mean(BuffMixShare, na.rm=TRUE), BuffMixShare)) %>% ungroup()


## apply 2010-derived system shares to YEAR headcounts, using additional share of diary cows as proxy for dairy buffaloes

# add column with share of milked cows in total cattle
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(MilkShare = cattle_milked/cattle) %>% group_by(co_state) %>%
  # for cases where there are no cattle (but maybe buffaloes), use state average
  mutate(MilkShare = ifelse(is.na(MilkShare), mean(MilkShare, na.rm=TRUE), MilkShare)) %>% ungroup()

# apply shares to obtain buffalo systems
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(# dairy buffaloes
                                        buffalo_gra_dair = buffalo*MilkShare*BuffGrassShare,
                                        buffalo_mix_dair = buffalo*MilkShare*BuffMixShare,
                                        # meat as residual of total - dairy - feedlot
                                        buffalo_gra_meat = buffalo*(1 - MilkShare)*BuffGrassShare,
                                        buffalo_mix_meat = buffalo*(1 - MilkShare)*BuffMixShare) %>%
                                        relocate(c(buffalo_gra_dair, buffalo_mix_dair, buffalo_gra_meat, buffalo_mix_meat), .after = buffalo)


# check and merge results ---------------------------------------------------------------------------------------------------

# check validity of results
all.equal(GEO_MUN_SOY$pig, GEO_MUN_SOY$pig_byd + GEO_MUN_SOY$pig_int + GEO_MUN_SOY$pig_ind)
all.equal(GEO_MUN_SOY$chicken, GEO_MUN_SOY$chicken_byd + GEO_MUN_SOY$chicken_lay + GEO_MUN_SOY$chicken_bro)
all.equal(GEO_MUN_SOY$cattle, GEO_MUN_SOY$cattle_gra_meat + GEO_MUN_SOY$cattle_gra_dair + GEO_MUN_SOY$cattle_mix_meat + GEO_MUN_SOY$cattle_mix_dair + GEO_MUN_SOY$cattle_flot)
all.equal(GEO_MUN_SOY$buffalo, GEO_MUN_SOY$buffalo_gra_meat + GEO_MUN_SOY$buffalo_gra_dair + GEO_MUN_SOY$buffalo_mix_meat + GEO_MUN_SOY$buffalo_mix_dair)

# GUARD (2026-07): no production-system herd may be negative. Broilers were the
# systematic offender (empty total-chicken column, now floored above); cattle_meat
# can still go slightly negative where milked+feedlot exceed the reported herd in a
# few munis. Warn loudly so a negative herd never again silently produces negative
# feed downstream, rather than passing the sum-only checks above.
.sys_cols <- c("cattle_gra_meat","cattle_gra_dair","cattle_mix_meat","cattle_mix_dair","cattle_flot",
               "buffalo_gra_meat","buffalo_gra_dair","buffalo_mix_meat","buffalo_mix_dair",
               "pig_byd","pig_int","pig_ind","chicken_byd","chicken_lay","chicken_bro")
.neg <- sapply(.sys_cols, function(cc)
  if (cc %in% names(GEO_MUN_SOY)) sum(GEO_MUN_SOY[[cc]] < -1e-6, na.rm = TRUE) else 0L)
if (any(.neg > 0))
  warning(sprintf("[02] YEAR=%d: negative herd counts after system split -> %s",
                  YEAR, paste(names(.neg)[.neg > 0], .neg[.neg > 0], sep = "=", collapse = ", ")))

# and round number of heads tho whole numbers
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(across(cattle:quail, round, 0))

# remove redundant columns and add results to SOY_MUN dataframe
colnames(GEO_MUN_SOY)
GEO_MUN_SOY <- dplyr::select(GEO_MUN_SOY, -c(ChExt:MilkShare))

GEO_MUN_SOY_temp <- GEO_MUN_SOY %>% as.data.frame() %>%
  dplyr::select(c(co_mun, cattle_gra_dair:cattle_flot, buffalo_gra_dair:buffalo_mix_meat, pig_byd:pig_ind, chicken_byd:chicken_bro))

SOY_MUN <- SOY_MUN  %>% dplyr::select(-chicken_layer) %>%   # remove "old" layer chicken (which include both backyard and industrial)
           left_join(GEO_MUN_SOY_temp, by = "co_mun")

SOY_MUN <- SOY_MUN %>%  relocate(cattle_gra_dair:cattle_flot, .after = cattle_milked) %>%
                        relocate(buffalo_gra_dair:buffalo_mix_meat, .after = buffalo) %>%
                        relocate(pig_byd:pig_ind, .after = pig_mother) %>%
                        relocate(chicken_byd:chicken_bro, .after = chicken)

# create separate dataframe only containing livestock numbers
LSTOCK_MUN <- dplyr::select(SOY_MUN, c(co_mun:nm_mun, cattle:quail))

############# write results ####################

if (write){
  # save data
  saveRDS(SOY_MUN, file = paste0(OUT, "SOY_MUN_02.rds"))
  saveRDS(LSTOCK_MUN, file = paste0(OUT, "LIVESTOCK_MUN_02.rds"))

  # export polygons with all attributes (uncomment if needed)
  saveRDS(GEO_MUN_SOY, file = paste0(OUT, "GEO_MUN_SOY_02.rds"))
}

rm(list=ls())
gc()

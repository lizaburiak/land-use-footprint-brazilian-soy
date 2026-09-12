
######## Estimation of MU livestock numbers by production system #########

library(raster)
library(sf)
library(exactextractr)
library(dplyr)
library(tidyr)
library(openxlsx)
library(mapview)
library(leafsync)

# should results be written to file?
write = TRUE

# load and prepare gridded livestock data ----------------------------------------------------------------------------------------------------

# municipalities
GEO_MUN_SOY <- readRDS("results/intermediate/GEO_MUN_SOY_01.rds")
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_01.rds")

# chicken rasters
ChExt <- raster("data/old/geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif")
ChInt <- raster("data/old/geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif")
#ChExt_si <- projectRaster(ChExt, crs = "+proj=poly +lat_0=0 +lon_0=-54 +x_0=5000000 +y_0=10000000 +ellps=GRS80 +units=m +no_defs +type=crs") # "+proj=poly +lat_0=0 +lon_0=-54 +x_0=5000000 +y_0=10000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs" 

# pig rasters
PgExt <- raster("data/old/geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif")
PgInt <- raster("data/old/geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif")
PgInd <- raster("data/old/geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif")


# cattle distribution raster (only numbers, no systems)
Cattle <- raster("data/old/geo/FAO_gridded_livestock/5_Ct_2010_Da.tif")
# buffalo distribution raster (only numbers, no systems)
Buffalo <- raster("data/old/geo/FAO_gridded_livestock/5_Bf_2010_Da.tif")
# ruminant systems
RumSys <- raster("data/old/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif")

# feedlot cattle data (IBGE 2006 census)
feedlot <- openxlsx::read.xlsx("data/old/FeedlotCattle_2006_tabela919_IBGE.xlsx", rows = 6:5455, na.strings = c("X", "-"))

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

# # observe data
# m1 <- mapview(PgExt, verbose = FALSE) # maxpixels = 10e+06
# m2 <- mapview(PgInt, verbose = FALSE)
# m3 <- mapview(PgInd, verbose = FALSE)
# m4 <- mapview(ChExt, verbose = FALSE)
# m5 <- mapview(ChInt, verbose = FALSE)
# m6 <- mapview(Cattle, verbose = FALSE)
# m7 <- mapview(Buffalo, verbose = FALSE)
# m8 <- mapview(RumSys, verbose = FALSE)
# sync(m1,m2,m3,m4,m5,m6,m7, m8, ncol = 5)


### compute number of animals per livestock system for each MU:

# chicken and pigs --------------------------------------------------------------------------------------------------

# compute total number of animals per MU through zonal sum statistic 
# NOTE that the Polygons in WGS84 are used to compute sums but results are added to the original file
GEO_MUN_SOY$ChExt <- exact_extract(ChExt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$ChInt <- exact_extract(ChInt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$PgExt <- exact_extract(PgExt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$PgInt <- exact_extract(PgInt, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$PgInd <- exact_extract(PgInd, GEO_MUN_SOY_WGS84, 'sum')

# check consistency with IBGE 2013 livestock data (raster data reference year: 2010)
sum(GEO_MUN_SOY$chicken, na.rm = T) 
sum(GEO_MUN_SOY$ChExt) + sum(GEO_MUN_SOY$ChInt) 

sum(GEO_MUN_SOY$pig, na.rm = T) 
sum(GEO_MUN_SOY$PgExt, na.rm = T) + sum(GEO_MUN_SOY$PgInt, na.rm = T) + sum(GEO_MUN_SOY$PgInd, na.rm = T)

#cellStats(ChExt, stat='sum', na.rm=TRUE)

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


## apply shares to 2013 data to obtain pig and chicken numbers by system
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(pig_byd = pig*PgExtShare, 
                                      pig_int = pig*PgIntShare, 
                                      pig_ind = pig*PgIndShare,
                                      # chicken: backyard = extensive (includes extensive layers as well as broilers)
                                      chicken_byd = chicken*ChExtShare,
                                      # broilers = intensive broilers = part of total - layers
                                      # considering cases where there are no layers (chicken_layer = NA)
                                      chicken_bro = ifelse(is.na(chicken_layer), chicken*ChIntShare, (chicken - chicken_layer)*ChIntShare), # chicken_bro = ifelse(is.na(chicken_layer), chicken*ChIntShare, chicken*ChIntShare - chicken_layer)) %>%
                                      # layers = intensive part of layers from IBGE
                                      chicken_lay = chicken_layer*ChIntShare) %>% 
                              # remove "old" layer chicken (which include both backyard and industrial) 
                              dplyr::select(-chicken_layer) %>% 
                              relocate(c(pig_byd, pig_int, pig_ind), .after = pig_mother) %>%
                              relocate(c(chicken_byd, chicken_lay, chicken_bro), .after = chicken)

# remove redundant columns
# GEO_MUN_SOY <- GEO_MUN_SOY %>% dplyr::select(-c(PgExt,PgInd,PgInt, ChExt, ChInt))



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
# see note in GlobalRuminant dataset legend: "pixels under the Other_Tree based systems class should be assigned to the GRASSLANDS in GLEAM"
CattGrass <- CattGrass + CattOth + CattUns
CattMix <- CattMix + CattUrb 

# set original NA cells of cattle dataset back to NA (not really necessary)
CattGrass[is.na(Cattle)] <- NA 
CattMix[is.na(Cattle)] <- NA 

# compute total number of grass and mixed cattle per MU through zonal sum statistic
GEO_MUN_SOY$CattGrass <- exact_extract(CattGrass, GEO_MUN_SOY_WGS84, 'sum')
GEO_MUN_SOY$CattMix <- exact_extract(CattMix, GEO_MUN_SOY_WGS84, 'sum')

# check consistency with IBGE 2013 livestock data (raster data reference year: 2010)
sum(GEO_MUN_SOY$cattle, na.rm = T) 
sum(GEO_MUN_SOY$CattGrass, na.rm = T) + sum(GEO_MUN_SOY$CattMix, na.rm = T) 

# compute shares 
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(CattGrassShare = CattGrass / (CattGrass+CattMix), 
                                      CattMixShare = CattMix / (CattGrass+CattMix)) 

# replace NA shares by state averages (for MUs which have no animals in 2010 gridded data but have some in 2013 IBGE data)
GEO_MUN_SOY <- GEO_MUN_SOY %>% group_by(co_state) %>% 
  mutate(CattGrassShare = if_else(is.na(CattGrassShare), mean(CattGrassShare, na.rm=TRUE), CattGrassShare),
         CattMixShare = if_else(is.na(CattMixShare), mean(CattMixShare, na.rm=TRUE), CattMixShare)) %>% ungroup()
                              

## include feedlot cattle numbers from IBGE census 2006, extrapolating to 2013
feedlot <- feedlot[,-c(3,5,6)]
colnames(feedlot) <- c("co_mun", "nm_mun", "cattle_tot", "cattle_flot" )
feedlot <- mutate(feedlot, co_mun = as.numeric(co_mun), cattle_tot = as.numeric(cattle_tot), cattle_flot = as.numeric(cattle_flot))

sum(feedlot$cattle_flot, na.rm = TRUE)
sum(feedlot$cattle_tot, na.rm = TRUE)
sum(SOY_MUN$cattle)# much more because the census data considers only farms with >50 animals

# extrapolate number of feedlot cattle with growth rate from 2006 to 2013 according to ABIEC/ANUALPEC (https://www.cicarne.com.br/wp-content/uploads/2020/05/SUM%c3%81RIO-BEEF-REPORT-2020_NET.pdf)
feedlot_growth <- 4.38/3.46 # see page  24 of report
feedlot <- mutate(feedlot, cattle_flot_13 = round(cattle_flot*feedlot_growth))

# merge with main table
feedlot <- feedlot %>% left_join(SOY_MUN[,c(1,2,4)], by = "co_mun") # check for consistency
GEO_MUN_SOY <- GEO_MUN_SOY %>% left_join(feedlot[,c(1,5)], by = "co_mun") %>% 
            rename("cattle_flot"  = "cattle_flot_13") %>% 
            relocate(cattle_flot, .after = cattle_milked) %>% 
            replace_na(list(cattle_flot = 0))



## apply shares to 2013 data to obtain cattle numbers by system
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

# check consistency with IBGE 2013 livestock data (raster data reference year: 2010)
sum(GEO_MUN_SOY$buffalo, na.rm = T) 
sum(GEO_MUN_SOY$BuffGrass, na.rm = T) + sum(GEO_MUN_SOY$BuffMix, na.rm = T) 

# compute shares 
GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(BuffGrassShare = BuffGrass / (BuffGrass+BuffMix), 
                                      BuffMixShare = BuffMix / (BuffGrass+BuffMix)) 

# replace NA shares by state averages (for MUs which have no animals in 2010 gridded data but have some in 2013 IBGE data)
GEO_MUN_SOY <- GEO_MUN_SOY %>% group_by(co_state) %>% 
  mutate(BuffGrassShare = if_else(is.na(BuffGrassShare), mean(BuffGrassShare, na.rm=TRUE), BuffGrassShare),
         BuffMixShare = if_else(is.na(BuffMixShare), mean(BuffMixShare, na.rm=TRUE), BuffMixShare)) %>% ungroup()


## apply shares to 2013 data, using additional share of diary cows as proxy for dairy buffaloes 
# e.g. if 10% of a MU's cattle are milked, then we also assume 10% of buffaloes are milked (TODO: check if this is justified)

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
  saveRDS(SOY_MUN, file = "results/intermediate/SOY_MUN_02.rds")
  # write.csv2(SOY_MUN, file = "results/intermediate/SOY_MUN.csv")
  saveRDS(LSTOCK_MUN, file = "results/intermediate/LIVESTOCK_MUN_02.rds")
  
  # export polygons with all attributes (uncomment if needed)
  saveRDS(GEO_MUN_SOY, file = "results/intermediate/GEO_MUN_SOY_02.rds")
  # st_write(GEO_MUN_SOY, "results/intermediate/GEO_MUN_SOY.gpkg", driver = "GPKG", overwrite=TRUE, layer_options = "ENCODING=ISO-8859-1", delete_dsn=TRUE)
}

rm(list=ls())
gc()
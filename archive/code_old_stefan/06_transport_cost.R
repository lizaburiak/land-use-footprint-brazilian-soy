
##### Computation of transport cost matrices for truck, train and ship based on logistic networks #######

library(sf)
library(dplyr)
library(mapview)
library(raster)
library(fasterize)
library(gdistance)
library(exactextractr)
library(parallel)
library(tidyr)
library(tibble)
library(xlsx)
library(abind)
library(janitor)

# should results be written to file?
write = TRUE

# load data -------------------------------------------------------------------

# MU polygons
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
GEO_MUN_SOY <- readRDS("results/intermediate/GEO_MUN_SOY_fin.rds")

# OSM roads
osm2014 <- st_read("data/old/geo/OSM_logistic_network/gis_osm_roads_free_1.shp", stringsAsFactors = FALSE)

# DNIT waterway lines data
water <- st_read("data/old/geo/DNIT_logistic_network/Hidrovias.shp", stringsAsFactors = FALSE) 
# ANTAQ ports and cargo data
ports <- st_read("data/old/geo/ANTAQ/IP.shp", stringsAsFactors = FALSE, options = "ENCODING=WINDOWS-1252")
cargo_water <- read.csv2("data/old/geo/ANTAQ/2013Carga.txt", encoding="UTF-8", stringsAsFactors=FALSE)
cargo_water_cont <- read.csv2("data/old/geo/ANTAQ/2013Carga_Conteinerizada.txt", encoding="UTF-8", stringsAsFactors=FALSE)

# ANTT rail lines, stations and cargo data
rail <-  st_read("data/old/geo/ANTT/Linhas.shp", stringsAsFactors = FALSE)
stations <- st_read("data/old/geo/ANTT/Estacoes.shp", stringsAsFactors = FALSE)
stations_man <- st_read("data/old/geo/ANTT/train_stations_soy.gpkg", stringsAsFactors = FALSE)
cargo_rail <- xlsx::read.xlsx("data/old/RailCargo_2006-21_ANTT.xls", sheetName="2013")

# MU capitals
MUN_capitals <- readRDS("results/intermediate/MUN_capitals.rds")


# create distance rasters for all modes --------------------------------------------

## road ----------------------------------------------------------------------------

## prepare data for rasterization

# create blank raster with desired resolution and extent of Brazil
# NOTE: resolution of 5 km is chosen for now to keep computational requirements manageable
rast_temp <- raster(ext = extent(GEO_MUN_SOY), resolution = 5000, crs = 5880)
writeRaster(rast_temp,"results/intermediate/rast_temp.tif", overwrite = TRUE, format="GTiff") 

# create raster covering Brazilian territory
# using fasterize, which is much faster than rasterize but only works for polygons
Brazil_rast <- fasterize(GEO_MUN_SOY, rast_temp, field = NULL)
Brazil_rast <- buffer(Brazil_rast, width = 5000, doEdge = TRUE)
# buffer around Fernando do Noronha to connect it to the mainland 
# (necessary to avoid non-connected MUs later)
fdn_buffer <- st_buffer(filter(GEO_MUN_SOY, co_mun == 2605459), dist = 400000)
fdn_buffer_rast <- fasterize(fdn_buffer, Brazil_rast, field = NULL)
Brazil_rast[is.na(Brazil_rast) & fdn_buffer_rast ==1] <- 1

# prepare OSM road data
osm2014 <- st_transform(osm2014, crs = st_crs(GEO_MUN_SOY))
# remove unnecessary fclasses (small roads not relevant for cargo movement) 
# -> significantly reduces size
# TODO: clarify if we should keep them
osm2014 <- filter(osm2014, 
                  fclass %in% c("motorway", "motorway_link", 
                                "primary", "primary_link", 
                                "secondary", "secondary_link", 
                                "tertiary", "tertiary_link", 
                                "trunk", "trunk_link",
                                "service", "track"))

# to each road, add municipality and state of location
# for the sake of computational feasibility, this is done by rasterizing the MU polygons
# and using exact_extract instead of using st_join with the MU polygons
GEO_MUN_rast <- fasterize(GEO_MUN_SOY, rast_temp, field = "co_mun")
# polygonize roads (necessary "trick" to work with exact_extract) and use exact_extract to get MU code
osm_poly <- st_buffer(osm2014, 1e-6)
osm_poly <- osm_poly[!is.na(st_dimension(osm_poly)),]
osm_mun <- exact_extract(GEO_MUN_rast, osm_poly, fun = "mode", default_weight = 1)
# remove roads that are too small to be polygonized (?)
osm2014 <- filter(osm2014, osm_id %in% osm_poly$osm_id)
# remove roads outside of Brazil (not necessary)
#GEO_STATE <- group_by(GEO_MUN_SOY, co_state, nm_state) %>% summarize()
#osm2014_BRA <- st_intersects(osm2014, GEO_STATE)
# add MU and state code to OSM 
osm2014$mun <- osm_mun
osm2014$state <- as.numeric(substr(as.character(osm_mun),1,2))
# set maxspeed values of 0 to NA
osm2014 <- osm2014 %>% mutate(maxspeed = ifelse(maxspeed == 0, NA, maxspeed))
osm_att <- st_drop_geometry(osm2014)
#clear memory
rm(osm_poly)

## fill missing maxspeed values: 2 options

# NOTE: computationally intensive, uncomment if needed 
# NOTE: consider unionizing neighboring segments of same type!!

option = 2

if(option == 1) {

  # 1. use most frequent value of same road type in MU/state/country
  
  # get most frequent speed value per road type and state
  maxspeed_BRA   <- osm_att %>% 
    group_by(fclass) %>% 
    summarise(maxspeed_BRA = modal(maxspeed, ties = "highest", na.rm = T), .groups = "drop")
  maxspeed_state <- osm_att %>% 
    filter(!is.na(state)) %>% 
    group_by(fclass, state) %>% 
    summarise(maxspeed_state = modal(maxspeed, ties = "highest", na.rm = T), .groups = "drop")
  maxspeed_mun   <- osm_att %>% 
    filter(!is.na(mun)) %>% 
    group_by(fclass, mun) %>% 
    summarise(maxspeed_mun = modal(maxspeed, ties = "highest", na.rm = T), .groups = "drop")
  maxspeed_mun_ref <- osm_att %>% 
    filter(!is.na(mun)) %>% 
    group_by(fclass, mun, ref) %>% 
    summarise(maxspeed_mun_ref = modal(maxspeed, ties = "highest", na.rm = T), .groups = "drop")
  
  # fill missing maxspeed values
  osm2014 <- left_join(osm2014, maxspeed_mun_ref, by = c("fclass", "mun", "ref"))
  osm2014 <- left_join(osm2014, maxspeed_mun, by = c("fclass", "mun"))
  osm2014 <- left_join(osm2014, maxspeed_state, by = c("fclass", "state"))
  osm2014 <- left_join(osm2014, maxspeed_BRA, by = c("fclass"))
  osm2014 <- mutate(osm2014, maxspeed_fin = coalesce(maxspeed, maxspeed_mun_ref, maxspeed_mun, maxspeed_state, maxspeed_BRA))

} else {
  
  # 2. use value of closest road of same road type
  # split osm data in list by road class
  osm_byclass <- sapply(unique(osm2014$fclass), function(x){
    filter(osm2014, !is.na(maxspeed) & fclass == x)}, simplify = F, USE.NAMES = T)
  # for each feature in each class, get closest feature
  nn <- lapply(osm_byclass, function(x){
    st_nearest_feature(osm2014, x)})
  # get maxspeed of closest feature
  nn_maxspeed <- sapply(names(nn), function(x){
      maxspeed <- osm_byclass[[x]]$maxspeed[nn[[x]]]
      df = data.frame(fclass = x, osm_id = osm2014$osm_id, maxspeed_nn = maxspeed)
      return(df)}, simplify = F, USE.NAMES = T) %>% 
    bind_rows()
  # merge with original osm
  osm2014 <- left_join(osm2014, nn_maxspeed, by = c("osm_id", "fclass"))
  # final maxspeed value: if own value exists, take it, otherwise take nn value
  osm2014 <- mutate(osm2014, maxspeed_fin = coalesce(maxspeed, maxspeed_nn))
  
  # transform maxspeed into a weighted conductance value 
  # this will weight the distance to traverse a pixel by the deviation of the maxspeed from 80km/h, 
  # which is assumed to be the average maxspeed on long distance routes
  # NOTE: no strict need to this here, as we can do this transformation in directly in the gDistance transformation matrix below!
  osm2014 <- mutate(osm2014, 
                    #conduct_mf = maxspeed_mf_fin/80, 
                    #conduct_mf_sqrt = sqrt(maxspeed_mf_fin/80), 
                    conduct = maxspeed_fin/80, 
                    conduct_sqrt = sqrt(maxspeed_fin/80))
}


## rasterize OSM data with now filled speed values

# write to file
osm2014 <- arrange(osm2014, maxspeed_fin)
st_write(osm2014, 
         dsn = "results/intermediate/osm2014.gpkg", 
         driver = "GPKG", 
         delete_dsn = TRUE)
osm2014conduct <- arrange(osm2014, conduct_sqrt)
st_write(osm2014conduct, 
         dsn = "results/intermediate/osm2014conduct.gpkg", 
         driver = "GPKG", 
         delete_dsn = TRUE)


# define file source and target extent for rasterization
ext <- as.character(st_bbox(GEO_MUN_SOY))
# rasterize from file to file with resolution of 5000m
src <- "results/intermediate/osm2014.gpkg"
gdal_utils('rasterize', src, "results/intermediate/osm2014_rasterized.tif", 
           options = c("-tr", "5000", "5000", "-a", "maxspeed_fin", "-te", ext, "-a_nodata", "NA", "-at"))
# "conductance version"
src <- "results/intermediate/osm2014conduct.gpkg"
gdal_utils('rasterize', src, "results/intermediate/osm2014conduct_rasterized.tif", 
           options = c("-tr", "5000", "5000", "-a", "conduct_sqrt", "-te", ext, "-a_nodata", "NA", "-at"))

# load in rasterized file and set NA values to no network value
osm2014_rast <- raster("results/intermediate/osm2014_rasterized.tif")
osm2014_rast[is.na(osm2014_rast) & Brazil_rast == 1] <- 10 # 

osm2014conduct_rast <- raster("results/intermediate/osm2014conduct_rasterized.tif")
osm2014conduct_rast[is.na(osm2014conduct_rast) & Brazil_rast == 1] <- sqrt(10/80) # 

mapview(osm2014_rast, maxpixels =  20841183)



## rail --------------------------------------------------------------------------------

# cargo: extract soy movements
cargo_rail <- filter(cargo_rail, Mercadoria.ANTT %in% c("Soja", "Farelo de Soja", "Óleo Vegetal"))

# aggregate rail cargo to annual values
cargo_rail <- group_by(cargo_rail, Mercadoria.ANTT, Origem, NA., Destino, NA..1) %>%
  summarise(TU = sum(TU, na.rm = TRUE), TKU = sum(TKU, na.rm = TRUE), .groups = "drop")
# rename variables and add standard product names
cargo_rail <- cargo_rail %>% rename(orig = Origem, dest = Destino, orig_state = NA., dest_state = NA..1) %>%
      mutate(product = ifelse(Mercadoria.ANTT == "Soja", 
                              "bean", 
                              ifelse(Mercadoria.ANTT == "Farelo de Soja", "cake", "oil"))) %>% 
      relocate(product, .before = orig) %>% dplyr::select(-Mercadoria.ANTT)

# stations: project to Sirgas 2000 polyconic projectionand drop Z coordinate
stations <- st_transform(stations, crs(GEO_MUN_SOY)) %>% st_zm()

# add state codes & names to stations
stations <- stations %>% 
  left_join(dplyr::select(SOY_MUN,c(co_mun, nm_mun, co_state, nm_state)), 
            by = c("CodigoMuni" = "co_mun"))

# extract stations with soy movement
# NOTE: some station names appear mutliple times, but in different states. Thus the filtering is applied on the station names in conjunction with the state 
stations_orig <- filter(stations, 
                        paste(NomeEstaca,nm_state) %in% paste(cargo_rail$orig,cargo_rail$orig_state)) #a <- right_join(stations, unique(dplyr::select(cargo_rail, c(Origem, NA.))), by = c("NomeEstaca" = "Origem", "co_state" = "NA."))
stations_dest <- filter(stations, 
                        paste(NomeEstaca,nm_state) %in% paste(cargo_rail$dest,cargo_rail$dest_state))

# add station codes to cargo movement
cargo_rail <- left_join(cargo_rail, st_drop_geometry(stations)[,c(3:4,16)], 
                        by = c("orig" = "NomeEstaca", "orig_state" = "nm_state")) %>% 
  rename(co_orig = CodigoTres) %>% relocate(co_orig, .after = orig)
cargo_rail <- left_join(cargo_rail, st_drop_geometry(stations)[,c(3:4,16)], 
                        by = c("dest" = "NomeEstaca", "dest_state" = "nm_state")) %>% 
  rename(co_dest = CodigoTres) %>% relocate(co_dest, .after = dest)


# rasterize rail lines:

# add value for rasterization
rail$value <- 1
# project to Sirgas 2000 polyconic
rail <- st_transform(rail, crs(GEO_MUN_SOY))
# add buffer around lines and check if all stations are covered (i.e. they fall within the buffer of any line)
rail_buff <- st_buffer(rail, 100) 
stations_orig <- stations_orig %>% mutate(intersection = st_intersects(stations_orig,rail_buff))
stations_dest <- stations_dest %>% mutate(intersection = st_intersects(stations_dest,rail_buff))
# write buffered rail lines to file for rasterization
st_write(rail_buff, dsn = "results/intermediate/rail.gpkg", driver = "GPKG", delete_dsn = TRUE)
# rasterize from file to file with resolution of 5000m
src <- "results/intermediate/rail.gpkg"
gdal_utils('rasterize', src, "results/intermediate/rail_rasterized.tif", 
           options = c("-tr", "5000", "5000", "-a", "value", "-te", ext, "-a_nodata", "NA", "-at"))
rail_rast <- raster("results/intermediate/rail_rasterized.tif")

# check if all stations are covered by railway pixels (i.e. they are in a location where raster == 1)
raster::extract(rail_rast, stations_orig)
raster::extract(rail_rast, stations_dest)



## water ---------------------------------------------------------------------------------------------

# join main cargo table with info on containerized cargo
cargo_water <- left_join(cargo_water, cargo_water_cont, by = c("IDCarga"))
# for containerized cargo, the true commodity code is contained in "CDMercadoriaConteinerizada"  
# --> add column with harmonized commodity code
cargo_water <- cargo_water %>% 
  mutate(co_product = ifelse(Carga.Geral.Acondicionamento == "Conteinerizada", 
                             CDMercadoriaConteinerizada, CDMercadoria), 
         .before = CDMercadoria)
# add volume column containing gross weight (VLPesoCargaBruta) for bulk cargo and net weight for container cargo (VLPesoCargaConteinerizada)
cargo_water <- cargo_water %>% 
  mutate(weight = ifelse(Carga.Geral.Acondicionamento == "Conteinerizada", 
                         VLPesoCargaConteinerizada, VLPesoCargaBruta))
# NOTE: results show that interior soy transports do not use containers (they seem to be only used for export shipments)

# keep only interior soy movements within Brazil
cargo_water <- filter(cargo_water, co_product %in% c(1201,1507,2304)) %>%
  filter(Tipo.Navegação %in% c("Interior")) %>% #"Cabotagem" #NOTE: cabotage (only small volumes) is not included for now
  filter(substr(Origem,1,2) == "BR") %>% # removing movements that originate or arrive outside of Brazil
  filter(substr(Destino,1,2) == "BR")

# remove duplicates
# NOTE: not 100% sure if these really are duplicates or the exact same volume transported repeatedly between same ports
cargo_water_dup <- get_dupes(cargo_water, c(Origem, Destino, co_product, weight))
cargo_water <-  distinct(cargo_water, Origem, Destino, co_product, weight ,.keep_all = TRUE)

#ports: add full MU code (ports only contain first 6 digits, which are also unique)
co_mun <- st_drop_geometry(GEO_MUN_SOY)$co_mun
co_mun <- data.frame(co_mun, co_mun_6 = substr(co_mun, 1,6))
ports <- ports %>% 
  st_transform(crs(GEO_MUN_SOY)) %>%
  mutate(co_mun_6 = substr(idcidade, 3, 8)) %>%
  left_join(co_mun, by = "co_mun_6") %>% 
  dplyr::select(-co_mun_6)

# extract ports that had soy movement in 2013
ports_orig <- filter(ports, cdi_tuaria %in% cargo_water$Origem)
ports_dest <- filter(ports, cdi_tuaria %in% cargo_water$Destino)

# check which relevant ports are not contained in the geo file
unique(cargo_water$Origem)[!unique(cargo_water$Origem) %in% ports_orig$cdi_tuaria]
unique(cargo_water$Destino)[!unique(cargo_water$Destino) %in% ports_dest$cdi_tuaria]
# NOTE: these missing ports where then geocoded manually in QGIS

# merge ports with manually geocoded missing ones
ports_add <- st_read("data/old/geo/ANTAQ/ip_add.gpkg", stringsAsFactors = FALSE)
ports_add <- rename(ports_add, geometry = geom) %>% st_set_geometry("geometry")
ports <- rbind(ports, ports_add)
ports_orig <- filter(ports, cdi_tuaria %in% cargo_water$Origem)
ports_dest <- filter(ports, cdi_tuaria %in% cargo_water$Destino)

# add product names to transport volumes
cargo_water <- cargo_water %>% 
  mutate(product = ifelse(co_product == "1201", 
                          "bean", 
                          ifelse(co_product == "1507", "oil", "cake"))) %>%
  relocate(product, .after = co_product)

# rasterize waterways
water$value <- 1
water <- st_transform(water, crs(GEO_MUN_SOY))
st_write(water, dsn = "results/intermediate/water.gpkg", driver = "GPKG", delete_dsn = TRUE)

# rasterize from file to file with resolution of 5000m
src <- "results/intermediate/water.gpkg"
gdal_utils('rasterize', src, "results/intermediate/water_rasterized.tif", options = c("-tr", "5000", "5000", "-a", "value", "-te", ext, "-a_nodata", "NA", "-at"))
water_rast <- raster("results/intermediate/water_rasterized.tif")

# check if all ports fall into a certain buffer around waterway lines
water_buff <- st_buffer(water, 3000) # NOTE: consider merging lines with IBGE waterway polygons instead of using a large buffer
ports_orig <- ports_orig %>% mutate(intersection = st_intersects(ports_orig,water_buff))
ports_dest <- ports_dest %>% mutate(intersection = st_intersects(ports_dest,water_buff))

# check if all ports are covered by waterway pixels
raster::extract(water_rast, ports_orig)
raster::extract(water_rast, ports_dest)


# compute shortest paths (least cost paths) with gDistance -----------------------

## road --------------------------

# compute least cost paths 
# - between MU capitals, 
# - from MU capitals to origin rail/water terminals
# - from destination rail/water terminals to MU capitals 

# create transition matrix based on cost raster
# NOTE: the transition function is a important factor determining how road type translates into a weight for crossing a pixel!
# if speed is 80, the weight will be 1 and thus the real distance
# --> include this into sensitivity analysis
transition_osm <- transition(x = osm2014_rast, 
                             transitionFunction = function(x){
                               mean(sqrt(x/80))}, directions=8)

#transition_conduct <- transition(x = osm2014conduct_rast, 
#                                 transitionFunction = function(x){
#                                   mean(x)}, directions=8)
#--> equivalent! --> we don't need the conductance raster itself!

# geoCorrect to obtain unbiased distances (see gDistance documentation)
transition_corr_osm <- geoCorrection(transition_osm, type = "c")
#transition_corr_conduct <- geoCorrection(transition_conduct, type = "c")

transition_corr <- transition_corr_osm

# compute matrix of least-cost distances

# TODO: this is time-comsuming, consider parallelizing!

#ncores <- detectCores() - 1
#clust <- makeCluster(ncores)
#clusterExport(cl = clust, c("transition_corr", "MUN_capitals", "stations_orig", "ports_orig", "stations_dest", "ports_dest"))

# between MU capitals
road_dist_MUN <- costDistance(transition_corr, st_coordinates(MUN_capitals))

# from MU capitals to origin stations
road_dist_MUN_stat <- costDistance(transition_corr, 
                                   st_coordinates(MUN_capitals), 
                                   st_coordinates(stations_orig) )

# from MU capitals to origin ports
road_dist_MUN_port <- costDistance(transition_corr, 
                                   st_coordinates(MUN_capitals), 
                                   st_coordinates(ports_orig) )

# from MU capitals to destination stations
road_dist_stat_MUN <- costDistance(transition_corr, 
                                   st_coordinates(stations_dest), 
                                   st_coordinates(MUN_capitals) )

# from MU capitals to destination ports
road_dist_port_MUN <- costDistance(transition_corr, 
                                   st_coordinates(ports_dest), 
                                   st_coordinates(MUN_capitals) )

# change type to normal matrix
road_dist_MUN <- as.matrix(road_dist_MUN)
road_dist_MUN_stat <- as.matrix(road_dist_MUN_stat)
road_dist_MUN_port <- as.matrix(road_dist_MUN_port)
road_dist_stat_MUN <- as.matrix(road_dist_stat_MUN)
road_dist_port_MUN <- as.matrix(road_dist_port_MUN)
# add dimnames
dimnames(road_dist_MUN) <- list(SOY_MUN$co_mun, SOY_MUN$co_mun)
dimnames(road_dist_MUN_stat) <- list(SOY_MUN$co_mun, stations_orig$CodigoTres)
dimnames(road_dist_MUN_port) <- list(SOY_MUN$co_mun, ports_orig$cdi_tuaria)
dimnames(road_dist_stat_MUN) <- list(stations_dest$CodigoTres, SOY_MUN$co_mun)
dimnames(road_dist_port_MUN) <- list(ports_dest$cdi_tuaria, SOY_MUN$co_mun)

#stopCluster(clust)

# check an exemplary pair of MUs
A <- MUN_capitals[5310,]
B <- MUN_capitals[3810,]
AtoB <- shortestPath(transition_corr_osm, as_Spatial(A), as_Spatial(B), output = "SpatialLines")
(cost_AtoB <- costDistance(transition_corr_osm, as_Spatial(MUN_capitals[c(5310,3810),])))
# for reference: suggested route on google maps has 4018 km 
# view on map
m1 <- mapview(osm2014_rast, maxpixels =  1000000) #, st_as_sf(AtoB)
m2 <- mapview(AtoB, color = 'cyan') 
m3 <- mapview(list(A,B), zcol = "nm_mun", col.regions = list("yellow", "green"))
m1+m2+m3+mapview(AtoB, color = 'cyan')


## rail ------------------------

# compute rail distances between stations
transition_rail <- transition(x = rail_rast, 
                              transitionFunction = function(x){mean(x)}, directions=8)
transition_rail_corr <- geoCorrection(transition_rail, type = "c")
rail_dist <- costDistance(transition_rail_corr, 
                          st_coordinates(stations_orig), 
                          st_coordinates(stations_dest))
rail_dist<- as.matrix(rail_dist)
dimnames(rail_dist) <- list(stations_orig$CodigoTres, stations_dest$CodigoTres)


## put movements into a list of separate wide-format matrices for each product

# aggregate flows to annual volumes
cargo_rail_agg <- cargo_rail %>% group_by(co_orig, co_dest, product) %>% 
  summarise(volume = sum(TU, na.rm = TRUE), .groups = "drop")
product <- c("bean", "oil", "cake")
cargo_templ <- data.frame(
  orig = rep(stations_orig$CodigoTres, each = nrow(stations_dest), times = length(product)),
  dest = rep(stations_dest$CodigoTres, times = nrow(stations_orig) * length(product)),
  product = rep(product, each = nrow(stations_dest) * nrow(stations_orig)))

cargo_rail_long  <- left_join(cargo_templ, cargo_rail_agg, 
                              by = c("orig" = "co_orig", "dest" = "co_dest", "product" = "product")) %>% 
  replace_na(list(volume = 0))

cargo_rail_wide <- sapply(product, function(x){
  filter(cargo_rail_long, product == x) %>% 
    dplyr::select(!product) %>% 
    pivot_wider(names_from = dest, values_from = volume) %>% 
    column_to_rownames("orig") #%>% as("Matrix")
}, USE.NAMES = TRUE, simplify = FALSE)

#cargo_rail_arr <- abind(cargo_rail_wide, along=3)

# sum across products
cargo_rail_wide_agg <- Reduce('+', cargo_rail_wide)
#check if transport distance is finite for every pair of ports with positive movement
all(is.finite(rail_dist[cargo_rail_wide_agg>0]))



## water -----------------------

# compute water distances between ports
transition_water <- transition(x = water_rast, 
                               transitionFunction = function(x){mean(x)}, directions=8)
transition_water_corr <- geoCorrection(transition_water, type = "c")
water_dist <- costDistance(transition_water_corr, 
                           st_coordinates(ports_orig), 
                           st_coordinates(ports_dest))
water_dist <- as.matrix(water_dist)
dimnames(water_dist) <- list(ports_orig$cdi_tuaria, 
                             ports_dest$cdi_tuaria)

# check if all ports with cargo movement between them have finite costs
cargo_water_agg <- cargo_water %>% group_by(Origem, Destino, product) %>% 
  summarise(volume = sum(VLPesoCargaBruta, na.rm = TRUE), .groups = "drop")

# put movements into a list of separate wide-format matrices for each product
cargo_templ <- data.frame(
  orig = rep(ports_orig$cdi_tuaria, each = nrow(ports_dest), times = length(product)),
  dest = rep(ports_dest$cdi_tuaria, times = nrow(ports_orig) * length(product)),
  product = rep(product, each = nrow(ports_dest) * nrow(ports_orig)))

cargo_water_long  <- left_join(cargo_templ, cargo_water_agg, 
                               by = c("orig" = "Origem", "dest" = "Destino", "product" = "product")) %>% 
  replace_na(list(volume = 0))

cargo_water_wide <- sapply(product, function(x){
  filter(cargo_water_long, product == x) %>% 
    dplyr::select(!product) %>% 
    pivot_wider(names_from = dest, values_from = volume) %>% 
    column_to_rownames("orig") #%>% as("Matrix")
}, USE.NAMES = TRUE, simplify = FALSE)

#cargo_water_arr <- abind(cargo_water_wide, along=3)

# sum across products
cargo_water_wide_agg <- Reduce('+', cargo_water_wide)
#check if transport distance is finite for every pair of ports with positive movement
all(is.finite(water_dist[cargo_water_wide_agg>0]))


# # generate cost matrices out of distance matrices ---------------------------------------------------
# 
# NOTE: THIS IS NOW MOVED TO THE SENSITIVITY ANALYSIS
# TODO: these are the crucial parameters for sensitivity analysis, besides the maxspeed weight above
# 
# ## using cost values from Góes & Lopes (2018)
# c_road <- 0.1624
# c_rail_short <- 0.0792 # < 1000 km
# c_rail_long <- 0.0614 # > 1000 km
# c_water <- 0.027
# m_switch <- 2.22 # intermodal cargo transfer markup (for switching modes)
# 
# 
# ## road ----
# 
# road_cost_MUN <- c_road * road_dist_MUN / 1000
# road_cost_MUN_stat <- c_road * road_dist_MUN_stat / 1000 + m_switch # adding switching cost 
# road_cost_MUN_port <- c_road * road_dist_MUN_port / 1000 + m_switch
# road_cost_stat_MUN <- c_road * road_dist_stat_MUN / 1000 + m_switch
# road_cost_port_MUN <- c_road * road_dist_port_MUN / 1000 + m_switch
# 
# ## rail ----
# 
# rail_cost <- rail_dist
# rail_cost[rail_dist < 1000000] <- rail_dist[rail_dist < 1000000] * c_rail_short / 1000
# rail_cost[rail_dist >= 1000000] <- rail_dist[rail_dist >= 1000000] * c_rail_long / 1000
# 
# ## water ----
# 
# water_cost <- water_dist * c_water / 1000


# check modal split according to rail/water data ----------------------------------------
cargo_rail_total  <- group_by(cargo_rail, product) %>% 
  summarise(TU = sum(TU, na.rm = TRUE)) # sum(cargo_rail$TU[cargo_rail$product == "Soja"])
cargo_water_total <- group_by(cargo_water, product) %>% 
  summarise(TU = sum(VLPesoCargaBruta, na.rm = TRUE))  # sum(cargo_water$VLPesoCargaBruta[cargo_water$CDMercadoria == 1201])
modal_volumes <- data.frame(road = rep(NA,3), 
                            rail = cargo_rail_total$TU, 
                            water = cargo_water_total$TU, 
                            row.names = c("bean", "cake", "oil"))# c("road" = sum(SOY_MUN$prod_bean)-cargo_rail_total-cargo_water_total, "rail" = cargo_rail_total, "water" = cargo_water_total)
prod <- c(sum(SOY_MUN$prod_bean), sum(SOY_MUN$prod_cake), sum(SOY_MUN$prod_oil))
modal_volumes$road <- prod-rowSums(modal_volumes, na.rm = TRUE)
modal_split <- modal_volumes/prod


# write results ------------------------------------------------------------------------

if(write){
  # geodata
  save(ports_dest, ports_orig, ports, file = "results/intermediate/ports.Rdata")
  save(stations_dest, stations_orig, stations, file = "results/intermediate/stations.Rdata")
  save(cargo_water_long, cargo_rail_long, file = "results/intermediate/cargo_long.Rdata")
  
  # distance matrices
  save(road_dist_MUN, 
       road_dist_MUN_stat, 
       road_dist_MUN_port,
       road_dist_stat_MUN, 
       road_dist_port_MUN, 
       water_dist,
       rail_dist,
       file = "results/intermediate/dist_matrices.Rdata")
  
  #saveRDS(road_dist_MUN, file = "results/intermediate/road_dist_MUN.RDS")
  #saveRDS(road_dist_MUN_stat, file = "results/intermediate/road_dist_MUN_stat.RDS")
  #saveRDS(road_dist_MUN_port, file = "results/intermediate/road_dist_MUN_port.RDS")
  #saveRDS(road_dist_stat_MUN, file = "results/intermediate/road_dist_stat_MUN.RDS")
  #saveRDS(road_dist_port_MUN, file = "results/intermediate/road_dist_port_MUN.RDS")
  #saveRDS(water_dist, file = "results/intermediate/water_dist.RDS")
  #saveRDS(rail_dist, file = "results/intermediate/rail_dist.RDS")
  
  # cost matrices
  #save(road_cost_MUN, 
  #     road_cost_MUN_stat, 
  #     road_cost_MUN_port,
  #     road_cost_stat_MUN, 
  #     road_cost_port_MUN, 
  #     water_cost,
  #     rail_cost,
  #     file = "results/intermediate/cost_matrices.Rdata")
  
  #saveRDS(road_cost_MUN, file = "results/intermediate/road_cost_MUN.RDS")
  #saveRDS(road_cost_MUN_stat, file = "results/intermediate/road_cost_MUN_stat.RDS")
  #saveRDS(road_cost_MUN_port, file = "results/intermediate/road_cost_MUN_port.RDS")
  #saveRDS(road_cost_stat_MUN, file = "results/intermediate/road_cost_stat_MUN.RDS")
  #saveRDS(road_cost_port_MUN, file = "results/intermediate/road_cost_port_MUN.RDS")
  #saveRDS(water_cost, file = "results/intermediate/water_cost.RDS")
  #saveRDS(rail_cost, file = "results/intermediate/rail_cost.RDS")
}

# clear environment
rm(list = ls())
gc()

##### Computation of transport cost matrices for truck, train and ship based on logistic networks #######

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

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
# xlsx is only needed for the legacy RailCargo xls fallback; loaded lazily there
library(abind)
library(janitor)

# should results be written to file?
write = TRUE

# output directory ------------------------------------------------------------
out_dir <- paste0("data/generated/outputs/06_", YEAR)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# load data -------------------------------------------------------------------

# MU polygons
SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
GEO_MUN_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/GEO_MUN_SOY_fin.rds"))

# OSM roads
osm2014 <- st_read("data/geo/OSM_logistic_network/gis_osm_roads_free_1.shp", stringsAsFactors = FALSE)

# DNIT waterway lines data
water <- st_read("data/geo/DNIT_logistic_network/Hidrovias.shp", stringsAsFactors = FALSE)
# ANTAQ ports and cargo data
ports <- st_read("data/geo/ANTAQ/IP.shp", stringsAsFactors = FALSE, options = "ENCODING=WINDOWS-1252")
# year-parameterized cargo files; ANTAQ cargo files exist here only for 2017-2022.
# For other years fall back to Stefan's 2013 ANTAQ data (the version he used).
.antaq_cargo <- paste0("data/geo/ANTAQ/", YEAR, "Carga.txt")
.antaq_cont  <- paste0("data/geo/ANTAQ/", YEAR, "Carga_Conteinerizada.txt")
if (!file.exists(.antaq_cargo)) {
  # fallback chain: Stefan's 2013 download (his original design), else the nearest
  # year among the ANTAQ files on disk (2017-2022; ANTAQ's server has been down,
  # blocking re-download of <=2016 - see WHAT_IS_MISSING.md item 4)
  .have <- as.integer(gsub("Carga\\.txt$", "", basename(Sys.glob("data/geo/ANTAQ/[0-9][0-9][0-9][0-9]Carga.txt"))))
  if (file.exists("data/geo/ANTAQ/2013Carga.txt")) {
    .fb <- 2013
  } else if (length(.have) > 0) {
    .fb <- .have[which.min(abs(.have - YEAR))]
  } else {
    stop("No ANTAQ cargo for YEAR=", YEAR, " and no fallback files present.")
  }
  message("[06] ANTAQ cargo: no ", YEAR, " file; using ", .fb, " as proxy for water cargo/capacities")
  .antaq_cargo <- paste0("data/geo/ANTAQ/", .fb, "Carga.txt")
  .antaq_cont  <- paste0("data/geo/ANTAQ/", .fb, "Carga_Conteinerizada.txt")
}
cargo_water <- read.csv2(.antaq_cargo, encoding = "UTF-8", stringsAsFactors = FALSE)
cargo_water_cont <- read.csv2(.antaq_cont, encoding = "UTF-8", stringsAsFactors = FALSE)

# ANTT rail lines, stations and cargo data
rail <-  st_read("data/geo/ANTT/Linhas.shp", stringsAsFactors = FALSE)
stations <- st_read("data/geo/ANTT/Estacoes.shp", stringsAsFactors = FALSE)
# stations_man (train_stations_soy.gpkg) was loaded here but never used - dropped.
# Rail cargo: raw ANTT OD CSVs (data/geo/ANTT/RailCargo_od/, 2006-2023) replace
# Stefan's compiled xls. Reshaped to the xls sheet layout the code below expects;
# monthly rows are fine (aggregated by the group_by+sum further down).
.rail_csv <- paste0("data/geo/ANTT/RailCargo_od/producao_origem_destino_", YEAR, ".csv")
if (file.exists(.rail_csv)) {
  .cr <- read.csv2(.rail_csv, fileEncoding = "latin1", stringsAsFactors = FALSE,
                   colClasses = "character")
  # Brazilian number format: "." thousands separator, "," decimal
  .num <- function(x) as.numeric(gsub(",", ".", gsub(".", "", x, fixed = TRUE), fixed = TRUE))
  cargo_rail <- data.frame(Mercadoria.ANTT = .cr$Mercadoria_ANTT,
                           Origem  = .cr$Estacao_Origem, "NA."   = .cr$UF_Origem,
                           Destino = .cr$Estacao_Destino, "NA..1" = .cr$UF_Destino,
                           TU = .num(.cr$TU), TKU = .num(.cr$TKU),
                           check.names = FALSE, stringsAsFactors = FALSE)
  rm(.cr)
} else {
  # legacy fallback: Stefan's compiled xls (one sheet per year), if present
  cargo_rail <- xlsx::read.xlsx("data/geo/RailCargo_2006-21_ANTT.xls", sheetName = as.character(YEAR))
}

# MU capitals (year-invariant; step 05 does not copy them per year - use base/)
.mc <- paste0("data/generated/outputs/05_", YEAR, "/MUN_capitals.rds")
if (!file.exists(.mc)) .mc <- "data/generated/base/MUN_capitals.rds"
MUN_capitals <- readRDS(.mc)
# align capitals 1:1 with SOY_MUN rows - the base capitals file carries two extra
# non-municipality IBGE water-body codes (4300001/4300002), and the road distance
# matrix dimnames below assume identical row order
MUN_capitals <- MUN_capitals[match(SOY_MUN$co_mun, MUN_capitals$co_mun), ]
if (anyNA(MUN_capitals$co_mun)) {
  .drop <- SOY_MUN$co_mun[is.na(MUN_capitals$co_mun)]
  message("[06] dropping municipality(ies) without a capital point: ", paste(.drop, collapse = ", "))
  .keep <- !is.na(MUN_capitals$co_mun)
  SOY_MUN <- SOY_MUN[.keep, ]
  MUN_capitals <- MUN_capitals[.keep, ]
}
stopifnot(identical(as.character(MUN_capitals$co_mun), as.character(SOY_MUN$co_mun)))


# create distance rasters for all modes --------------------------------------------

## road ----------------------------------------------------------------------------

## prepare data for rasterization

# create blank raster with desired resolution and extent of Brazil
# NOTE: resolution of 5 km is chosen for now to keep computational requirements manageable
rast_temp <- raster(ext = extent(GEO_MUN_SOY), resolution = 5000, crs = 5880)
writeRaster(rast_temp, file.path(out_dir, "rast_temp.tif"), overwrite = TRUE, format = "GTiff")

# create raster covering Brazilian territory
# using fasterize, which is much faster than rasterize but only works for polygons
Brazil_rast <- fasterize(GEO_MUN_SOY, rast_temp, field = NULL)
Brazil_rast <- buffer(Brazil_rast, width = 5000, doEdge = TRUE)
# buffer around Fernando do Noronha to connect it to the mainland
# (necessary to avoid non-connected MUs later)
fdn_buffer <- st_buffer(filter(GEO_MUN_SOY, co_mun == 2605459), dist = 400000)
fdn_buffer_rast <- fasterize(fdn_buffer, Brazil_rast, field = NULL)
Brazil_rast[is.na(Brazil_rast) & fdn_buffer_rast == 1] <- 1

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
# add MU and state code to OSM
osm2014$mun <- osm_mun
osm2014$state <- as.numeric(substr(as.character(osm_mun), 1, 2))
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

  osm2014 <- left_join(osm2014, maxspeed_mun_ref, by = c("fclass", "mun", "ref"))
  osm2014 <- left_join(osm2014, maxspeed_mun, by = c("fclass", "mun"))
  osm2014 <- left_join(osm2014, maxspeed_state, by = c("fclass", "state"))
  osm2014 <- left_join(osm2014, maxspeed_BRA, by = c("fclass"))
  osm2014 <- mutate(osm2014, maxspeed_fin = coalesce(maxspeed, maxspeed_mun_ref, maxspeed_mun, maxspeed_state, maxspeed_BRA))

} else {

  # 2. use value of closest road of same road type
  osm_byclass <- sapply(unique(osm2014$fclass), function(x){
    filter(osm2014, !is.na(maxspeed) & fclass == x)}, simplify = F, USE.NAMES = T)
  nn <- lapply(osm_byclass, function(x){
    st_nearest_feature(osm2014, x)})
  nn_maxspeed <- sapply(names(nn), function(x){
      maxspeed <- osm_byclass[[x]]$maxspeed[nn[[x]]]
      df = data.frame(fclass = x, osm_id = osm2014$osm_id, maxspeed_nn = maxspeed)
      return(df)}, simplify = F, USE.NAMES = T) %>%
    bind_rows()
  osm2014 <- left_join(osm2014, nn_maxspeed, by = c("osm_id", "fclass"))
  osm2014 <- mutate(osm2014, maxspeed_fin = coalesce(maxspeed, maxspeed_nn))

  osm2014 <- mutate(osm2014,
                    conduct = maxspeed_fin/80,
                    conduct_sqrt = sqrt(maxspeed_fin/80))
}


## rasterize OSM data with now filled speed values

# free the large nn/join intermediates before the GDAL writes - GDAL segfaults
# (instead of erroring) when memory runs out mid-write on the 295k-feature layer
rm(list = intersect(c("osm_byclass", "nn", "nn_maxspeed", "osm_att", "osm_mun",
                      "maxspeed_BRA", "maxspeed_state", "maxspeed_mun", "maxspeed_mun_ref"),
                    ls()))
invisible(gc())

# write to file - only the rasterization attribute: the gpkg exists solely to feed
# gdal_utils rasterize below (writing the full OSM attribute table is also wasteful)
osm2014 <- arrange(osm2014, maxspeed_fin)
# write via terra::writeVector - sf's CPL_write_ogr segfaults intermittently on
# this 295k-feature layer (memory-pressure dependent; crashed 2019 & 2014 runs)
terra::writeVector(terra::vect(dplyr::select(osm2014, osm_id, maxspeed_fin)),
                   file.path(out_dir, "osm2014.gpkg"),
                   filetype = "GPKG", overwrite = TRUE)
osm2014conduct <- arrange(osm2014, conduct_sqrt)
terra::writeVector(terra::vect(dplyr::select(osm2014conduct, osm_id, conduct_sqrt)),
                   file.path(out_dir, "osm2014conduct.gpkg"),
                   filetype = "GPKG", overwrite = TRUE)


# define file source and target extent for rasterization
ext <- as.character(st_bbox(GEO_MUN_SOY))
src <- file.path(out_dir, "osm2014.gpkg")
gdal_utils('rasterize', src, file.path(out_dir, "osm2014_rasterized.tif"),
           options = c("-tr", "5000", "5000", "-a", "maxspeed_fin", "-te", ext, "-a_nodata", "NA", "-at"))
src <- file.path(out_dir, "osm2014conduct.gpkg")
gdal_utils('rasterize', src, file.path(out_dir, "osm2014conduct_rasterized.tif"),
           options = c("-tr", "5000", "5000", "-a", "conduct_sqrt", "-te", ext, "-a_nodata", "NA", "-at"))

osm2014_rast <- raster(file.path(out_dir, "osm2014_rasterized.tif"))
osm2014_rast[is.na(osm2014_rast) & Brazil_rast == 1] <- 10

osm2014conduct_rast <- raster(file.path(out_dir, "osm2014conduct_rasterized.tif"))
osm2014conduct_rast[is.na(osm2014conduct_rast) & Brazil_rast == 1] <- sqrt(10/80)

# mapview(osm2014_rast, maxpixels = 20841183)  # interactive check, skip in batch runs



## rail --------------------------------------------------------------------------------

# cargo: extract soy movements
cargo_rail <- filter(cargo_rail, Mercadoria.ANTT %in% c("Soja", "Farelo de Soja", "Óleo Vegetal"))

# aggregate rail cargo to annual values
cargo_rail <- group_by(cargo_rail, Mercadoria.ANTT, Origem, NA., Destino, NA..1) %>%
  summarise(TU = sum(TU, na.rm = TRUE), TKU = sum(TKU, na.rm = TRUE), .groups = "drop")
cargo_rail <- cargo_rail %>% rename(orig = Origem, dest = Destino, orig_state = NA., dest_state = NA..1) %>%
      mutate(product = ifelse(Mercadoria.ANTT == "Soja",
                              "bean",
                              ifelse(Mercadoria.ANTT == "Farelo de Soja", "cake", "oil"))) %>%
      relocate(product, .before = orig) %>% dplyr::select(-Mercadoria.ANTT)

stations <- st_transform(stations, crs(GEO_MUN_SOY)) %>% st_zm()

stations <- stations %>%
  left_join(dplyr::select(SOY_MUN,c(co_mun, nm_mun, co_state, nm_state)),
            by = c("CodigoMuni" = "co_mun"))

stations_orig <- filter(stations,
                        paste(NomeEstaca,nm_state) %in% paste(cargo_rail$orig,cargo_rail$orig_state))
stations_dest <- filter(stations,
                        paste(NomeEstaca,nm_state) %in% paste(cargo_rail$dest,cargo_rail$dest_state))

cargo_rail <- left_join(cargo_rail, st_drop_geometry(stations)[, c("NomeEstaca", "CodigoTres", "nm_state")],
                        by = c("orig" = "NomeEstaca", "orig_state" = "nm_state")) %>%
  rename(co_orig = CodigoTres) %>% relocate(co_orig, .after = orig)
cargo_rail <- left_join(cargo_rail, st_drop_geometry(stations)[, c("NomeEstaca", "CodigoTres", "nm_state")],
                        by = c("dest" = "NomeEstaca", "dest_state" = "nm_state")) %>%
  rename(co_dest = CodigoTres) %>% relocate(co_dest, .after = dest)


# rasterize rail lines:
rail$value <- 1
rail <- st_transform(rail, crs(GEO_MUN_SOY))
rail_buff <- st_buffer(rail, 100)
stations_orig <- stations_orig %>% mutate(intersection = st_intersects(stations_orig,rail_buff))
stations_dest <- stations_dest %>% mutate(intersection = st_intersects(stations_dest,rail_buff))
st_write(rail_buff, dsn = file.path(out_dir, "rail.gpkg"), driver = "GPKG", delete_dsn = TRUE)
src <- file.path(out_dir, "rail.gpkg")
gdal_utils('rasterize', src, file.path(out_dir, "rail_rasterized.tif"),
           options = c("-tr", "5000", "5000", "-a", "value", "-te", ext, "-a_nodata", "NA", "-at"))
rail_rast <- raster(file.path(out_dir, "rail_rasterized.tif"))

raster::extract(rail_rast, stations_orig)
raster::extract(rail_rast, stations_dest)



## water ---------------------------------------------------------------------------------------------

cargo_water <- left_join(cargo_water, cargo_water_cont, by = c("IDCarga"))
cargo_water <- cargo_water %>%
  mutate(co_product = ifelse(Carga.Geral.Acondicionamento == "Conteinerizada",
                             CDMercadoriaConteinerizada, CDMercadoria),
         .before = CDMercadoria)
cargo_water <- cargo_water %>%
  mutate(weight = ifelse(Carga.Geral.Acondicionamento == "Conteinerizada",
                         VLPesoCargaConteinerizada, VLPesoCargaBruta))

cargo_water <- filter(cargo_water, co_product %in% c(1201,1507,2304)) %>%
  filter(Tipo.Navegação %in% c("Interior")) %>%
  filter(substr(Origem,1,2) == "BR") %>%
  filter(substr(Destino,1,2) == "BR")

cargo_water_dup <- get_dupes(cargo_water, c(Origem, Destino, co_product, weight))
cargo_water <-  distinct(cargo_water, Origem, Destino, co_product, weight ,.keep_all = TRUE)

co_mun <- st_drop_geometry(GEO_MUN_SOY)$co_mun
co_mun <- data.frame(co_mun, co_mun_6 = substr(co_mun, 1,6))
ports <- ports %>%
  st_transform(crs(GEO_MUN_SOY)) %>%
  mutate(co_mun_6 = substr(idcidade, 3, 8)) %>%
  left_join(co_mun, by = "co_mun_6") %>%
  dplyr::select(-co_mun_6)

ports_orig <- filter(ports, cdi_tuaria %in% cargo_water$Origem)
ports_dest <- filter(ports, cdi_tuaria %in% cargo_water$Destino)

unique(cargo_water$Origem)[!unique(cargo_water$Origem) %in% ports_orig$cdi_tuaria]
unique(cargo_water$Destino)[!unique(cargo_water$Destino) %in% ports_dest$cdi_tuaria]

ports_add <- st_read("data/geo/ANTAQ/ip_add.gpkg", stringsAsFactors = FALSE)
ports_add <- rename(ports_add, geometry = geom) %>% st_set_geometry("geometry")
ports <- rbind(ports, ports_add)
ports_orig <- filter(ports, cdi_tuaria %in% cargo_water$Origem)
ports_dest <- filter(ports, cdi_tuaria %in% cargo_water$Destino)

cargo_water <- cargo_water %>%
  mutate(product = ifelse(co_product == "1201",
                          "bean",
                          ifelse(co_product == "1507", "oil", "cake"))) %>%
  relocate(product, .after = co_product)

water$value <- 1
water <- st_transform(water, crs(GEO_MUN_SOY))
st_write(water, dsn = file.path(out_dir, "water.gpkg"), driver = "GPKG", delete_dsn = TRUE)

src <- file.path(out_dir, "water.gpkg")
gdal_utils('rasterize', src, file.path(out_dir, "water_rasterized.tif"), options = c("-tr", "5000", "5000", "-a", "value", "-te", ext, "-a_nodata", "NA", "-at"))
water_rast <- raster(file.path(out_dir, "water_rasterized.tif"))

water_buff <- st_buffer(water, 3000)
ports_orig <- ports_orig %>% mutate(intersection = st_intersects(ports_orig,water_buff))
ports_dest <- ports_dest %>% mutate(intersection = st_intersects(ports_dest,water_buff))

raster::extract(water_rast, ports_orig)
raster::extract(water_rast, ports_dest)

# snap ports that miss the 5-km water raster onto the nearest water pixel centre -
# otherwise their water distances are infinite and their observed cargo (e.g.
# BRPA005 Ponta da Montanha, 5% of 2019 interior tonnage) silently drops out
.water_xy <- raster::xyFromCell(water_rast, which(!is.na(raster::values(water_rast))))
.snap_to_water <- function(p) {
  .off <- which(is.na(raster::extract(water_rast, p)))
  for (i in .off) {
    .xy <- st_coordinates(st_geometry(p)[i])
    .d2 <- (.water_xy[, 1] - .xy[1])^2 + (.water_xy[, 2] - .xy[2])^2
    message(sprintf("[06] snapping port %s (%s) %.1f km onto the water raster",
                    p$cdi_tuaria[i], p$nome[i], sqrt(min(.d2)) / 1000))
    st_geometry(p)[i] <- st_sfc(st_point(.water_xy[which.min(.d2), ]), crs = st_crs(p))
  }
  p
}
ports_orig <- .snap_to_water(ports_orig)
ports_dest <- .snap_to_water(ports_dest)


# compute shortest paths (least cost paths) with gDistance -----------------------

## road --------------------------

transition_osm <- transition(x = osm2014_rast,
                             transitionFunction = function(x){
                               mean(sqrt(x/80))}, directions=8)

transition_corr_osm <- geoCorrection(transition_osm, type = "c")

transition_corr <- transition_corr_osm

# between MU capitals
road_dist_MUN <- costDistance(transition_corr, st_coordinates(MUN_capitals))

road_dist_MUN_stat <- costDistance(transition_corr,
                                   st_coordinates(MUN_capitals),
                                   st_coordinates(stations_orig) )

road_dist_MUN_port <- costDistance(transition_corr,
                                   st_coordinates(MUN_capitals),
                                   st_coordinates(ports_orig) )

road_dist_stat_MUN <- costDistance(transition_corr,
                                   st_coordinates(stations_dest),
                                   st_coordinates(MUN_capitals) )

road_dist_port_MUN <- costDistance(transition_corr,
                                   st_coordinates(ports_dest),
                                   st_coordinates(MUN_capitals) )

road_dist_MUN <- as.matrix(road_dist_MUN)
road_dist_MUN_stat <- as.matrix(road_dist_MUN_stat)
road_dist_MUN_port <- as.matrix(road_dist_MUN_port)
road_dist_stat_MUN <- as.matrix(road_dist_stat_MUN)
road_dist_port_MUN <- as.matrix(road_dist_port_MUN)
dimnames(road_dist_MUN) <- list(SOY_MUN$co_mun, SOY_MUN$co_mun)
dimnames(road_dist_MUN_stat) <- list(SOY_MUN$co_mun, stations_orig$CodigoTres)
dimnames(road_dist_MUN_port) <- list(SOY_MUN$co_mun, ports_orig$cdi_tuaria)
dimnames(road_dist_stat_MUN) <- list(stations_dest$CodigoTres, SOY_MUN$co_mun)
dimnames(road_dist_port_MUN) <- list(ports_dest$cdi_tuaria, SOY_MUN$co_mun)

# check an exemplary pair of MUs (interactive; skip in batch runs)
# A <- MUN_capitals[5310,]
# B <- MUN_capitals[3810,]
# AtoB <- shortestPath(transition_corr_osm, as_Spatial(A), as_Spatial(B), output = "SpatialLines")
# (cost_AtoB <- costDistance(transition_corr_osm, as_Spatial(MUN_capitals[c(5310,3810),])))
# m1 <- mapview(osm2014_rast, maxpixels =  1000000)
# m2 <- mapview(AtoB, color = 'cyan')
# m3 <- mapview(list(A,B), zcol = "nm_mun", col.regions = list("yellow", "green"))
# m1+m2+m3+mapview(AtoB, color = 'cyan')


## rail ------------------------

transition_rail <- transition(x = rail_rast,
                              transitionFunction = function(x){mean(x)}, directions=8)
transition_rail_corr <- geoCorrection(transition_rail, type = "c")
rail_dist <- costDistance(transition_rail_corr,
                          st_coordinates(stations_orig),
                          st_coordinates(stations_dest))
rail_dist<- as.matrix(rail_dist)
dimnames(rail_dist) <- list(stations_orig$CodigoTres, stations_dest$CodigoTres)


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
    column_to_rownames("orig")
}, USE.NAMES = TRUE, simplify = FALSE)

cargo_rail_wide_agg <- Reduce('+', cargo_rail_wide)
all(is.finite(rail_dist[cargo_rail_wide_agg>0]))



## water -----------------------

transition_water <- transition(x = water_rast,
                               transitionFunction = function(x){mean(x)}, directions=8)
transition_water_corr <- geoCorrection(transition_water, type = "c")
water_dist <- costDistance(transition_water_corr,
                           st_coordinates(ports_orig),
                           st_coordinates(ports_dest))
water_dist <- as.matrix(water_dist)
dimnames(water_dist) <- list(ports_orig$cdi_tuaria,
                             ports_dest$cdi_tuaria)

cargo_water_agg <- cargo_water %>% group_by(Origem, Destino, product) %>%
  summarise(volume = sum(VLPesoCargaBruta, na.rm = TRUE), .groups = "drop")

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
    column_to_rownames("orig")
}, USE.NAMES = TRUE, simplify = FALSE)

cargo_water_wide_agg <- Reduce('+', cargo_water_wide)
all(is.finite(water_dist[cargo_water_wide_agg>0]))


# check modal split according to rail/water data ----------------------------------------
cargo_rail_total  <- group_by(cargo_rail, product) %>%
  summarise(TU = sum(TU, na.rm = TRUE))
cargo_water_total <- group_by(cargo_water, product) %>%
  summarise(TU = sum(VLPesoCargaBruta, na.rm = TRUE))
# match by product name - some years move only 2 of the 3 products by a mode
# (e.g. no soy oil by rail in 2020), which breaks positional recycling
.mprods <- c("bean", "cake", "oil")
modal_volumes <- data.frame(road = rep(NA, 3),
                            rail = cargo_rail_total$TU[match(.mprods, cargo_rail_total$product)],
                            water = cargo_water_total$TU[match(.mprods, cargo_water_total$product)],
                            row.names = .mprods)
modal_volumes$rail[is.na(modal_volumes$rail)] <- 0
modal_volumes$water[is.na(modal_volumes$water)] <- 0
prod <- c(sum(SOY_MUN$prod_bean), sum(SOY_MUN$prod_cake), sum(SOY_MUN$prod_oil))
modal_volumes$road <- prod-rowSums(modal_volumes, na.rm = TRUE)
modal_split <- modal_volumes/prod


# write results ------------------------------------------------------------------------

if(write){
  save(ports_dest, ports_orig, ports, file = file.path(out_dir, "ports.Rdata"))
  save(stations_dest, stations_orig, stations, file = file.path(out_dir, "stations.Rdata"))
  save(cargo_water_long, cargo_rail_long, file = file.path(out_dir, "cargo_long.Rdata"))

  save(road_dist_MUN,
       road_dist_MUN_stat,
       road_dist_MUN_port,
       road_dist_stat_MUN,
       road_dist_port_MUN,
       water_dist,
       rail_dist,
       file = file.path(out_dir, "dist_matrices.Rdata"))
}

# clear environment
rm(list = ls())
gc()

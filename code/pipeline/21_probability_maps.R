# FABIO MRIO / land-use footprint stage (steps 13-21). Year-parameterized
# fork of the matching archive/code_old_stefan/ script. Needs the FABIO v2 +
# EXIOBASE backends (data/fabio/v2, data/exiobase, data/generated/fabio; see DATA.md).
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
if (!dir.exists("/mnt/nfs_fineprint") &&
    length(list.files("data/generated/fabio")) == 0 &&
    length(list.files("data/fabio/v2/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See DATA.md.", call. = FALSE)
}

library(Matrix)
library(data.table)
library(sf)
library(dplyr)
library(tidyr)
library(raster)
library(fasterize)
library(mapview)
library(gdalUtilities)
library(parallel)
library(ggplot2)
library(rasterVis)
library(viridis)

# load function library
source("code/pipeline/00_function_library.R")

# raster spills full-tile intermediates to uncompressed temp files that live
# until the session ends; 85 tiles x 17 targets overflows the disk. Give each
# worker its own tmpdir, dropped right after the tile is written, and cap the
# worker count (each holds a full 30m tile in RAM).
MC_CORES <- 4  # 6 workers OOM-killed a forked child on the 16GB laptop; each holds a full 30m tile
# mclapply swallows worker errors and returns try-error objects; fail loudly instead
stop_on_worker_error <- function(res) {
  bad <- Filter(function(z) inherits(z, "try-error"), res)
  if (length(bad)) stop("burn_rast worker failed: ", as.character(bad[[1]]), call. = FALSE)
  res
}
burn_rast_tmpsafe <- function(x, ...) {
  tdir <- file.path(tempdir(), paste0("rtmp_", x, "_", Sys.getpid()))
  dir.create(tdir, showWarnings = FALSE)
  raster::rasterOptions(tmpdir = tdir)
  out <- burn_rast(...)
  unlink(tdir, recursive = TRUE)
  out
}

# prepare footprint results ----------------------------------

regions <- fread("data/fabio/v2/inst/regions_full.csv")
items <-  fread("data/fabio/v2/inst/items_full.csv")

# load production footprints
P_mass  <- readRDS(paste0("data/generated/footprints/", YEAR, "_P_mass.rds"))
P_value <- readRDS(paste0("data/generated/footprints/", YEAR, "_P_value.rds"))

# bind 
P_mass <-  cbind(P_mass$A_country,  P_mass$B_country,  P_mass$A_product,  P_mass$B_product,  
                 "total_food" = rowSums(P_mass$A_product),  
                 "total_nonfood" = rowSums(P_mass$B_product),  P_mass$A_product_country)
P_value <- cbind(P_value$A_country, P_value$B_country, P_value$A_product, P_value$B_product, 
                 "total_food" = rowSums(P_value$A_product), 
                 "total_nonfood" = rowSums(P_value$B_product), P_value$A_product_country)


# load MU polygons and project to WGS84
GEO_MUN_SOY <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/GEO_MUN_SOY_fin.rds")) %>% st_transform(crs = 4326)
GEO_states <- st_read("data/geo/GADM_boundaries/gadm36_BRA_1.shp", stringsAsFactors = FALSE) %>% st_transform(crs = 4326)


# S3 method: makes is.finite() work on the data.frames below (base errors on lists)
is.finite.data.frame <- function(obj){
  sapply(obj,FUN = function(x) (is.finite(x)))
}

# join production footprints for soybeans with MU polygons
P_mun_mass <- P_mass[as.numeric(sub("_.*", "", rownames(P_mass)))>1000 & sub(".*_", "", rownames(P_mass)) == "c021",]
P_mun_mass <- as.data.frame(as.matrix(P_mun_mass))
P_mun_value <- P_value[as.numeric(sub("_.*", "", rownames(P_value)))>1000 & sub(".*_", "", rownames(P_value)) == "c021",]
P_mun_value <- as.data.frame(as.matrix(P_mun_value))

# transform into probabilities (do not round yet)
P_mun_mass <- P_mun_mass/GEO_MUN_SOY$prod_bean # make sure they sum up to one!
P_mun_mass[!is.finite(P_mun_mass)] <- 0
P_mun_mass <- P_mun_mass*100 # round(P_mun_mass*100)
P_mun_value <- P_mun_value/GEO_MUN_SOY$prod_bean # make sure they sum up to one!
P_mun_value[!is.finite(P_mun_value)] <- 0
P_mun_value <- P_mun_value*100 # round(P_mun_value*100)

# change column names to ISO codes
#colnames(P_mun_mass) <- regions$iso3c[match(colnames(P_mun_mass), regions$code)]

# join with polygons
P_mun_mass <- mutate(P_mun_mass, co_mun = as.numeric(sub("_.*", "", rownames(P_mun_mass)))) %>% relocate(co_mun)
GEO_MUN_P_mass <- dplyr::select(GEO_MUN_SOY, c(co_mun:nm_state, prod_bean)) %>%
  left_join(P_mun_mass, by = "co_mun") # or simply to cbind, as rows already math (but this is more safe)

P_mun_value <- mutate(P_mun_value, co_mun = as.numeric(sub("_.*", "", rownames(P_mun_value)))) %>% relocate(co_mun)
GEO_MUN_P_value <- dplyr::select(GEO_MUN_SOY, c(co_mun:nm_state, prod_bean)) %>%
  left_join(P_mun_value, by = "co_mun") # or simply to cbind, as rows already math (but this is more safe)


# prepare land-use tiles --------------------------------------

# this uses the burn_rast function from the function library

# load tiles in a list
tile_names = list.files("data/geo/mb_tiles/",pattern="^.*.tif$")
if (length(tile_names) == 0) {
  stop("[step 21] No MapBiomas soy land-use tiles found in data/geo/mb_tiles/. ",
       "These 30m tiles must be downloaded from Google Earth Engine (see README / ",
       "DATA.md). The municipal footprints (step 20) are complete; only the ",
       "grid-level refinement in this step is blocked.", call. = FALSE)
}
tile_paths = paste0("data/geo/mb_tiles/",tile_names)
tiles <- lapply(tile_paths, raster)
names(tiles) <- tile_names

# test for one tile
# prob_tile1 <- burn_rast(rast = tiles[[1]], poly = GEO_MUN_SOY, value = "co_state", class = 1, file = "prob_tile1.tif")
# mapview(prob_tile1)

# Destination-group maps: the SAME five groups as all other figures
# (see code/prep/prep_map_allyears.R and code/analysis/figstyle.py):
# China | EU-27 | Rest of Asia | Rest of world | Brazil (domestic).
# These five (value allocation) plus total_food/total_nonfood below are the
# ONLY probability maps we produce. Single small countries (DEU, ESP, ...)
# are pointless here: their per-municipality shares are <0.5% everywhere and
# round to an empty map at the integer-percent resolution of the tiles.
reg_tbl <- fread("data/fabio/v2/inst/regions_full.csv")
eu27    <- reg_tbl$iso3c[reg_tbl$EU27 == TRUE]
cont    <- setNames(reg_tbl$continent, reg_tbl$iso3c)
grp_of  <- function(iso) ifelse(iso == "BRA", "Brazil-domestic",
    ifelse(iso == "CHN", "China",
    ifelse(iso %in% eu27, "EU-27",
    ifelse(!is.na(cont[iso]) & cont[iso] == "ASI", "Rest-of-Asia", "Rest-of-world"))))

for (grp in c("China", "EU-27", "Rest-of-Asia", "Rest-of-world", "Brazil-domestic")) {
    for(alloc in c("value")) { # "mass",

      geo <- if(alloc == "mass") GEO_MUN_P_mass else GEO_MUN_P_value

      # group probability = food + nonfood country columns summed over members
      dat    <- st_drop_geometry(geo)
      f_cols <- grep("^[A-Z]{3}_food$",    names(dat), value = TRUE)
      n_cols <- grep("^[A-Z]{3}_nonfood$", names(dat), value = TRUE)
      sel_f  <- f_cols[grp_of(sub("_food$",    "", f_cols)) == grp]
      sel_n  <- n_cols[grp_of(sub("_nonfood$", "", n_cols)) == grp]
      geo$grp_prob <- round(rowSums(dat[, sel_f, drop = FALSE]) +
                            rowSums(dat[, sel_n, drop = FALSE]))

      # create directory
      dir <- paste0("results/mb_tiles/",YEAR,"_",grp,"_",alloc)
      ifelse(!dir.exists(dir), dir.create(dir, recursive = TRUE), "Folder exists already")
      target <- "grp_prob"
      
      if(length(dir(dir,all.files=FALSE)) == 0) {
        
        # apply to tile list 
        system.time(
          prob_tiles <- mclapply(names(tiles), function(x) {
            burn_rast_tmpsafe(x, rast = tiles[[x]],
                      poly = geo,
                      value = target, class = 1, zeroes = FALSE,
                      file = paste0(dir,"/",x))
          }, mc.cores = MC_CORES)
        )
        prob_tiles <- stop_on_worker_error(prob_tiles)

        # build a vrt
        gdalUtilities::gdalbuildvrt(gdalfile = sapply(prob_tiles, filename), output.vrt = paste0(dir,"/prob.vrt"))
        prob_vrt <- raster(paste0(dir,"/prob.vrt"))
        #mapview(prob_vrt, na.color = "transparent")
        
        
        # resample: directly build a vrt from high-res tiles with desired resolution:
        gdalUtilities::gdalbuildvrt(gdalfile = sapply(prob_tiles, filename), 
                                    output.vrt = paste0(dir, "/prob_agg.vrt"),
                                    r = "nearest", # TODO: what resampling method?
                                    tr = res(prob_tiles[[1]])*16)
        
      }
      
      prob_agg_vrt <- raster(paste0(dir,"/prob_agg.vrt"))
      #mapview(prob_agg_vrt, na.color = "transparent")# plot
      
      
      # plot -----------------------------------------
      
      # reshape raster into data frame (see function library)
      prob_dat <- gplot_data(prob_agg_vrt, maxpixels = ncell(prob_agg_vrt)) %>% dplyr::filter(!is.na(value))
      
      (prob_map <- ggplot() +
          geom_sf(data = GEO_states, fill = "transparent", color = "darkgrey", size = 0.4) + # "gray19", "lightgrey"
          geom_tile(data = dplyr::filter(prob_dat, !is.na(value) & value > 0), 
                    aes(x = x, y = y, fill = value) ) +
          #scale_fill_gradient("Land use\nprobability",
          #                    low = 'yellow', high = 'blue',
          #                    na.value = NA) +
          scale_fill_viridis(direction = -1)+ #limits = c(1,80)
          coord_sf(datum = sf::st_crs(prob_agg_vrt)) +
          labs(fill = "probability", title = paste(grp, "consumption: land-use probability,", alloc, "allocation")) + 
          theme_void()+
          theme(plot.title = element_text(hjust = 0.5, size = 10), 
                plot.margin = margin(t = -0.0, r = -0.2, b = -0.1, l = -0.2, "cm"),
                legend.margin=margin(0,0,0,0), 
                legend.box.margin=margin(t=0,r=0,b= 0,l=-60))
        #coord_quickmap()
      )
      
      ggsave(filename = paste0("results/maps/probability_maps/",YEAR,"_prob_map_",grp,"_",alloc,".png"), prob_map, width = 12, height = 10, units = "cm", scale = 2)
      
      
      # for selected state
      state = "MT"
      GEO_state <- filter(GEO_states, HASC_1 == paste0("BR.", state))
      prob_state <- crop(prob_agg_vrt, extent(GEO_state))
      #rast_temp_state[] <- NA
      rast_temp_state <- fasterize(GEO_state, prob_state)
      prob_state[is.na(rast_temp_state)] <- NA
      prob_dat_state <- gplot_data(prob_state, maxpixels = ncell(prob_state)) %>% dplyr::filter(!is.na(value))
      
      (prob_map_state <- ggplot() +
          geom_sf(data = GEO_state, fill = "transparent", color = "darkgrey", size = 0.4) + # "gray19", "lightgrey"
          geom_tile(data = dplyr::filter(prob_dat_state, !is.na(value) & value > 0), 
                    aes(x = x, y = y, fill = value) ) +
          #scale_fill_gradient("Land use\nprobability",
          #                    low = 'yellow', high = 'blue',
          #                    na.value = NA) +
          scale_fill_viridis(direction = -1)+ #limits = c(1,80)
          coord_sf(datum = sf::st_crs(prob_agg_vrt)) +
          labs(fill = "probability", title = paste(grp, "consumption: land-use probability,", alloc, "allocation")) + 
          theme_void()+
          theme(plot.title = element_text(hjust = 0.5, size = 10), 
                plot.margin = margin(t = -0.0, r = -0, b = -0.1, l = -0.2, "cm"),
                legend.margin=margin(0,0,0,0), 
                legend.box.margin=margin(t=0,r=0,b= 0,l=0))
        #coord_quickmap()
      )
      
      
      ggsave(filename = paste0("results/maps/probability_maps/",YEAR,"_prob_map_state_",grp,"_",alloc,".png"), prob_map_state, width = 12, height = 10, units = "cm", scale = 2)


    }
}



# or by product

for (prod in c("total_food", "total_nonfood")) { # c110/c114/c116/c117/c118 dropped: codes are FABIO v1 numbering, in v2 they hit Butter/Mutton/Poultry/OtherMeat/Offals - remap before reusing
  for(alloc in c("value")){ # "mass",
    
    # or: select product
    # prod <- "c101"
    
    geo <- if(alloc == "mass") GEO_MUN_P_mass else GEO_MUN_P_value
    
    # create directory
    dir <- paste0("results/mb_tiles/",YEAR,"_",prod,"_",alloc)
    ifelse(!dir.exists(dir), dir.create(dir, recursive = TRUE), "Folder exists already")
    target <- prod
    
    if(length(dir(dir,all.files=FALSE)) == 0) {
      
      # apply to tile list
      system.time(
        prob_tiles <- mclapply(names(tiles), function(x) {
          burn_rast_tmpsafe(x, rast = tiles[[x]],
                    poly = geo,
                    value = target, class = 1, zeroes = FALSE,
                    file = paste0(dir,"/",x))
        }, mc.cores = MC_CORES)
      )
      prob_tiles <- stop_on_worker_error(prob_tiles)

      # build a vrt
      gdalUtilities::gdalbuildvrt(gdalfile = sapply(prob_tiles, filename), output.vrt = paste0(dir,"/prob.vrt"))
      prob_vrt <- raster(paste0(dir,"/prob.vrt"))
      #mapview(prob_vrt, na.color = "transparent")
      
      
      # resample: directly build a vrt from high-res tiles with desired resolution:
      gdalUtilities::gdalbuildvrt(gdalfile = sapply(prob_tiles, filename), 
                                  output.vrt = paste0(dir, "/prob_agg.vrt"),
                                  r = "nearest", # TODO: what resampling method?
                                  tr = res(prob_tiles[[1]])*16)
      
    }
    
    prob_agg_vrt <- raster(paste0(dir,"/prob_agg.vrt"))
    #mapview(prob_agg_vrt, na.color = "transparent")# plot
    
    
    # plot -----------------------------------------
    
    prob_dat <- gplot_data(prob_agg_vrt, maxpixels = ncell(prob_agg_vrt)) %>% dplyr::filter(!is.na(value))
    
    # plot
    (prob_map <- ggplot() +
        geom_sf(data = GEO_states, fill = "transparent", color = "darkgrey", size = 0.4) + # gray19 lightgrey
        geom_tile(data = dplyr::filter(prob_dat, !is.na(value)), 
                  aes(x = x, y = y, fill = value) ) +
        #scale_fill_gradient("Land use\nprobability",
        #                    low = 'yellow', high = 'blue',
        #                    na.value = NA) +
        scale_fill_viridis(direction = -1, limits = c(1,80))+
        coord_sf(datum = sf::st_crs(prob_agg_vrt)) +
        labs(fill = "probability", title = paste(ifelse(substr(target,1,1)=="c",items$item[items$comm_code  == target],target), "consumption: land-use probability,", alloc, "allocation")) + 
        theme_void()+
        theme(plot.title = element_text(hjust = 0.5, size = 10), 
              plot.margin = margin(t = -0.0, r = -0.2, b = -0.1, l = -0.2, "cm"),
              legend.margin=margin(0,0,0,0), 
              legend.box.margin=margin(t=0,r=0,b= 0,l=-60))
      #coord_quickmap()
    )
    
    ggsave(filename = paste0("results/maps/probability_maps/",YEAR,"_prob_map_",target,"_",alloc,".png"), prob_map, width = 12, height = 10, units = "cm", scale = 2)
    
    
  }
}

rm(list = ls())
gc()

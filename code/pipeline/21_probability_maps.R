# ============================================================================
# REPRODUCTION PORT — FABIO MRIO / land-use footprint backend (steps 13-21).
# Year-parameterized continuation of steps 00-12. Minimal-delta fork of the
# matching archive/code_old_stefan/ script.
#
# REQUIRES WU/fineprint FABIO + EXIOBASE data that is NOT present on this
# machine (see DATA.md):
#   - data/generated/fabio/*                     (FABIO MRIO matrices)
#   - archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/*   (concordances / tidy data)
#   - /mnt/nfs_fineprint/tmp/{exiobase,fabio}/*      (EXIOBASE + FABIO v2, NFS)
# These stages cannot run here without that infrastructure.
# ============================================================================
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
# Fail fast with a clear message if none of the FABIO data is available.
if (!dir.exists("/mnt/nfs_fineprint") &&
    length(list.files("data/generated/fabio")) == 0 &&
    length(list.files("data/fabio/v2/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See DATA.md.", call. = FALSE)
}
# NOTE: year-keyed file paths below are parameterized via YEAR, but full
# year-extension is unvalidated until FABIO data is available to run against.

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


# helper function (add to library)
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

for (reg in c("DEU", "CHN", "ESP")) {  # 
  for(type in c("meat-dairy-eggs")) { #"food", "nonfood" #"meat", "meat_dairy", 
    for(alloc in c("mass")) { # "value", 
      
      # # select final demand region
      # reg <- "CHN"
      # # select food/nonfood
      # type <- "food"
      # # select allocation method
      # alloc <- "mass"
      # #or: select product
      # prod <- "c101"
      
      geo <- if(alloc == "mass") GEO_MUN_P_mass else GEO_MUN_P_value
      
      if(reg == "EU") {
        EU <- c("AUT", "BGR", "DNK", "FIN", "FRA", "DEU", "GRC", "HUN", "HRV", "IRL", "ITA", "MLT", "NLD", "CZE", "POL", "PRT", "ROU", "SVN", "SVK", "ESP", "SWE", "GBR", "BEL", "LUX", "LVA", "LTU", "EST", "CYP")
        names(geo)[sub("_.*", "", names(geo)) %in% EU] <- paste0("EU_", sub(".*_", "", names(geo)[sub("_.*", "", names(geo)) %in% EU]))
        mat <- as.matrix(st_drop_geometry(geo)[,which(names(st_drop_geometry(geo)) =="ARM_food"):ncol(st_drop_geometry(geo))])
        sum_mat <- as(sapply(unique(colnames(mat)),"==",colnames(mat)), "Matrix")*1
        mat <- mat %*% sum_mat
        geo <- bind_cols(geo[,1:(which(names(geo) =="ARM_food")-1)], as.data.frame(as.matrix(mat)))
      }
      
      # round to intergers
      geo <- mutate(geo, across(ARM_food:last_col(), round))
      
      
      # create directory
      dir <- paste0("results/mb_tiles/",YEAR,"_",reg,"_",type,"_",alloc)
      ifelse(!dir.exists(dir), dir.create(dir, recursive = TRUE), "Folder exists already")
      target <- paste0(reg,"_",type)
      
      if(length(dir(dir,all.files=FALSE)) == 0) {
        
        # apply to tile list 
        system.time(
          prob_tiles <- mclapply(names(tiles), function(x) {
            burn_rast(rast = tiles[[x]], 
                      poly = geo, 
                      value = target, class = 1, zeroes = FALSE,
                      file = paste0(dir,"/",x))
          }, mc.cores = 12)
        )
        
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
          labs(fill = "probability", title = paste(reg, type, "consumption: land-use probability,", alloc, "allocation")) + 
          theme_void()+
          theme(plot.title = element_text(hjust = 0.5, size = 10), 
                plot.margin = margin(t = -0.0, r = -0.2, b = -0.1, l = -0.2, "cm"),
                legend.margin=margin(0,0,0,0), 
                legend.box.margin=margin(t=0,r=0,b= 0,l=-60))
        #coord_quickmap()
      )
      
      ggsave(filename = paste0("results/maps/probability_maps/",YEAR,"_prob_map_",reg,"_",type,"_",alloc,".png"), prob_map, width = 12, height = 10, units = "cm", scale = 2)
      
      
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
          labs(fill = "probability", title = paste(reg, type, "consumption: land-use probability,", alloc, "allocation")) + 
          theme_void()+
          theme(plot.title = element_text(hjust = 0.5, size = 10), 
                plot.margin = margin(t = -0.0, r = -0, b = -0.1, l = -0.2, "cm"),
                legend.margin=margin(0,0,0,0), 
                legend.box.margin=margin(t=0,r=0,b= 0,l=0))
        #coord_quickmap()
      )
      
      
      ggsave(filename = paste0("results/maps/probability_maps/",YEAR,"_prob_map_state_",reg,"_",type,"_",alloc,".png"), prob_map_state, width = 12, height = 10, units = "cm", scale = 2)
      
      
    }
  }
}



# or by product

for (prod in c("c110", "c114", "c116", "c117", "c118", "total_food", "total_nonfood")) { # 
  for(alloc in c("mass", "value")){
    
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
          burn_rast(rast = tiles[[x]], 
                    poly = geo, 
                    value = target, class = 1, zeroes = FALSE,
                    file = paste0(dir,"/",x))
        }, mc.cores = 12)
      )
      
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

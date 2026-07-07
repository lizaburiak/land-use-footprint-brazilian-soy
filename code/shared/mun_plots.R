# ============================================================================
# Commodity-balance maps — per-municipality choropleths of every CBS item
# (production / imports / exports / processing / feed / food / seed / other /
# stock) for bean, oil and cake, assembled into patchwork lattices; plus a
# shortest-path example map. Interactive/manual helper.
# Inputs : data/generated/base/{GEO_MUN_SOY_fin,SOY_MUN_fin}.rds,
#          data/geo/GADM_boundaries/gadm36_BRA_1.shp
# Outputs (when write = TRUE): results/maps/commodity_balance_maps/
#          map_cbs_{all,bean,oil,cake}.png and results/maps/path_example.png
# ============================================================================
######## comparative graphs of municipality soy data #####

library(ggplot2)
library(viridis)
library(mapview)
library(tmap)
library(sf)
library(leafsync)
library(patchwork)

write = TRUE

# load data
GEO_MUN_SOY <- readRDS("data/generated/base/GEO_MUN_SOY_fin.rds")
GEO_states <- st_read("data/geo/GADM_boundaries/gadm36_BRA_1.shp", stringsAsFactors = FALSE)
SOY_MUN <- readRDS("data/generated/base/SOY_MUN_fin.rds")


# plot data ------------------------

plot_funct <- function(variable, title = NA, unit = NA, lowcol = "transparent", highcol = "darkgreen", ...){
  thesubset <- GEO_MUN_SOY[pull(SOY_MUN, variable)>0,]
  thedata <- st_drop_geometry(thesubset)
  theplot <- ggplot(thesubset, aes(fill = pull(thedata, variable)), size = 0.4) +
                labs(title = ifelse(!is.na(title), title, variable))+
                geom_sf(color = "transparent")+            
                # scale_fill_viridis(direction = -1, na.value = "transparent", name = paste(unit)) + 
                scale_fill_gradient(low = lowcol, high = highcol, 
                                    na.value = "transparent", 
                                    #breaks = quantile(pull(thedata, variable)),
                                    #trans = "boxcox",
                                    name = paste(unit)) + 
                #scale_fill_steps(n.breaks = 10, nice.breaks = TRUE) +
                geom_sf(data = GEO_states, fill = "transparent", color = "grey", size = 0.1)+
                theme_void()+ # or minimal
                theme(plot.title = element_text(hjust = 0.5), plot.margin = margin(t = -0.0, r = -0.2, b = -0.1, l = -0.5, "cm"),
                      legend.margin=margin(0,0,0,0), legend.box.margin=margin(t=0,r=0,b= 0,l=-40))
  return(theplot)
}


g_prod_bean <- plot_funct(variable = "prod_bean", title = "Soybean production", unit = "tons",  lowcol = "grey95", highcol = "darkgreen")
g_prod_oil  <- plot_funct(variable = "prod_oil", title = "Soy oil  production", unit = "tons",  lowcol = "grey95", highcol = "darkgreen")
g_prod_cake <- plot_funct(variable = "prod_cake", title = "Soy cake production", unit = "tons", lowcol = "grey95", highcol = "darkgreen")

g_exp_bean <- plot_funct(variable = "exp_bean", title = "Soy bean exports", unit = "tons", lowcol = "grey95", highcol = "darkblue")
g_exp_oil <-  plot_funct(variable = "exp_oil", title = "Soy oil exports", unit = "tons", lowcol = "grey95",   highcol = "darkblue")
g_exp_cake <- plot_funct(variable = "exp_cake", title = "Soy cake exports", unit = "tons",  lowcol = "grey95", highcol = "darkblue")

g_imp_bean <- plot_funct(variable = "imp_bean", title = "Soy bean imports", unit = "tons", lowcol = "grey95", highcol = "purple4")
g_imp_oil  <- plot_funct(variable = "imp_oil",  title =  "Soy oil imports", unit = "tons", lowcol = "grey95", highcol = "purple4")
g_imp_cake <- plot_funct(variable = "imp_cake", title = "Soy cake imports", unit = "tons", lowcol = "grey95", highcol = "purple4")

g_food_bean <- plot_funct(variable = "food_bean", title = "Soy bean food use", unit = "tons", lowcol = "grey95", highcol = "darkorange")
g_food_oil  <- plot_funct(variable = "food_oil",  title =  "Soy oil food use", unit = "tons", lowcol = "grey95", highcol = "darkorange")

g_proc_bean <-  plot_funct(variable = "proc_bean", title = "Soy bean processing use", unit = "tons", lowcol = "grey95", highcol = "deeppink")
g_feed_bean <-  plot_funct(variable = "feed_bean",  title =  "Soy bean feed use",     unit = "tons", lowcol = "grey95", highcol = "firebrick4")
g_feed_cake <-  plot_funct(variable = "feed_cake",  title =  "Soy cake feed use",     unit = "tons", lowcol = "grey95", highcol = "firebrick4")

g_seed_bean  <-  plot_funct(variable = "seed_bean",  title =  "Soy bean seed use",          unit = "tons", lowcol = "grey95", highcol = "darkgreen")
g_other_oil  <-  plot_funct(variable = "other_oil",  title =  "Soy oil other use",          unit = "tons", lowcol = "grey95", highcol = "tan4")
g_stock_bean <-  plot_funct(variable = "stock_bean",  title =  "Soy bean storage addition", unit = "tons", lowcol = "grey95", highcol = "darkgreen")

#g_proc_cap <- plot_funct(variable = "proc_cap", title = "Processing capacity \n (tons/day)")
#g_ref_cap  <- plot_funct(variable = "ref_cap", title = "Refining capacity \n (tons/day)")
#g_bot_cap  <- plot_funct(variable = "bot_cap", title = "Bottling capacity \n (tons/day)")
#g_cattle   <- plot_funct(variable = "cattle", title = "Cattle (units)", trans = "log")
#g_pig      <- plot_funct(variable = "pig", title = "Pigs (units)", trans = "log")
#g_poultry  <- plot_funct(variable = "poultry", title = "Poultry (units)", trans = "log")
#g_sheep    <- plot_funct(variable = "sheep", title = "Sheep (units)", trans = "log")
#g_pop      <- plot_funct(variable = "population", title = "Population", trans = "log")


# create lattices with patchwork ----------------

#comparison <- (g_prod | g_exp_tot | g_exp_bean | g_exp_oil | g_exp_cake ) / (g_proc | g_refbot | g_proc_cap | g_ref_cap | g_bot_cap) / (g_cattle | g_pig | g_poultry | g_sheep | g_pop)
comparison <- (g_prod_bean | g_prod_oil | g_prod_cake | g_exp_bean | g_exp_oil | g_exp_cake ) / 
              (g_imp_bean  | g_imp_oil  | g_imp_cake  | g_food_bean| g_food_oil| g_seed_bean) / 
              (g_feed_bean | g_feed_cake| g_other_oil | g_stock_bean) 

comparison_bean <- (g_prod_bean | g_imp_bean )/ 
                    (g_exp_bean | g_proc_bean)/ 
                    (g_food_bean| g_feed_bean)#/
                   #(g_seed_bean | g_stock_bean) #+ plot_layout(ncol = 2)
comparison_oil  <- (g_prod_oil  | g_imp_oil  )/
                    (g_exp_oil  | g_food_oil) /
                    (g_other_oil | plot_spacer())# + plot_layout(ncol = 2, nrow = 3)
comparison_cake <- (g_prod_cake | g_imp_cake) / 
                   (g_exp_cake | g_feed_cake) /
                   (plot_spacer() | plot_spacer())#  + plot_layout(ncol = 2)

if(write){
  ggsave(plot = comparison, filename = "results/maps/commodity_balance_maps/map_cbs_all.png", device = "png", width = 15.02, height = 23.77, units = "cm", scale = 1.5)
  ggsave(plot = comparison_bean, filename = "results/maps/commodity_balance_maps/map_cbs_bean.png", device = "png",  width = 15.02, height = 23.77, units = "cm", scale = 1.5)
  ggsave(plot = comparison_oil , filename = "results/maps/commodity_balance_maps/map_cbs_oil.png", device = "png", width = 15.02, height = 23.77, units = "cm", scale = 1.5)
  ggsave(plot = comparison_cake, filename = "results/maps/commodity_balance_maps/map_cbs_cake.png", device = "png", width = 15.02, height = 23.77, units = "cm", scale = 1.5)
}

# plot with mapview (ool, but very heavy: only manageable for individual layers)

#mapviewOptions(platform = "mapdeck", fgb = TRUE)
#m_prod <- mapview(GEO_MUN_SOY, zcol = "prod_t", map.types = "CartoDB.Positron") 
#m_exp_t <- mapview(GEO_MUN_SOY, zcol = "ex_tot_t", map.types = "CartoDB.Positron")
#m_proc_fac <- mapview(GEO_MUN_SOY, zcol = "proc_total", map.types = "CartoDB.Positron")
#m_refbot_fac <- mapview(GEO_MUN_SOY, zcol = "ref_total", map.types = "CartoDB.Positron")
#sync(m_prod, m_exp_t, m_proc_fac, m_refbot_fac)


### shortest path plot
#osm2014_rast[is.na(osm2014_rast)] <- 10
network_dat <- gplot_data(osm2014_rast, maxpixels = ncell(osm2014_rast))# %>% dplyr::filter(!is.na(value))
AtoB_sf <- st_as_sf(AtoB)

(path_map <- ggplot() +
    geom_tile(data = dplyr::filter(network_dat, !is.na(value)), 
              aes(x = x, y = y, fill = value) ) +
    geom_sf(data = AtoB_sf, fill = "transparent", color = "cyan", size = 1.2) + # gray19 lightgrey
    #scale_fill_gradient("Land use\nprobability",
    #                    low = 'yellow', high = 'blue',
    #                    na.value = NA) +
    geom_sf(data = A, fill = "yellow", color = "yellow", size = 4) +
    geom_sf_label(data = rbind(A,B), aes(label = nm_mun), nudge_y = c(150000,-150000), size = 4) + #, -50000)
    geom_sf(data = B, fill = "green", color = "green", size = 4) +
    scale_fill_viridis(direction = 1, option = "magma")+
    coord_sf(datum = sf::st_crs(osm2014_rast)) +
    labs(fill = "maxspeed") + 
    theme_void()+
    theme(plot.title = element_text(hjust = 0.5, size = 10), 
          plot.margin = margin(t = -0.0, r = -0.2, b = -0.1, l = -0.2, "cm"),
          legend.margin=margin(0,0,0,0), 
          legend.box.margin=margin(t=0,r=0,b= 0,l=-60))
  #coord_quickmap()
)

if(write){
  ggsave(plot = path_map, filename = "results/maps/path_example.png", device = "png", width = 12, height = 10, units = "cm", scale = 2)
}
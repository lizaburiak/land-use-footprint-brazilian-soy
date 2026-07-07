# ============================================================================
# Transport-flow maps — origin→destination soy movements across Brazil.
# Draws municipal excess-supply choropleths with flow segments on top (one map
# per product: bean/oil/cake), plus a bootstrap-sensitivity variant coloured by
# the flow CV. Interactive/manual helper — run line by line after the pipeline.
# Inputs : data/generated/base/{flows_mu_comp,SOY_MUN_fin,GEO_MUN_SOY_fin,
#          MUN_capitals}.rds, data/geo/GADM_boundaries/gadm36_BRA_1.shp
# Outputs: flow-map PNGs (e.g. flows_bean.png) in the working directory.
# ============================================================================

library(dplyr)
library(sf)
library(ggplot2)
library(ggthemes)
library(viridis)
library(ggforce)

flows <-readRDS("data/generated/base/flows_mu_comp.rds") #readRDS("data/generated/base/transport_flows.rds")
SOY_MUN <- readRDS("data/generated/base/SOY_MUN_fin.rds")
GEO_MUN_SOY <- readRDS("data/generated/base/GEO_MUN_SOY_fin.rds")
MUN_capitals <- readRDS("data/generated/base/MUN_capitals.rds")
states <- st_read("data/geo/GADM_boundaries/gadm36_BRA_1.shp")

# drop geometries and prepare for plot
MUN_capitals_df <- st_drop_geometry(MUN_capitals)

# add coordinates of origins and destinations
flows <- flows %>% left_join(MUN_capitals_df[,c(1,3:4)], by = c("co_orig" = "co_mun")) %>% rename("orig_lon" = "LONG", "orig_lat" = "LAT")
flows <- flows %>% left_join(MUN_capitals_df[,c(1,3:4)], by = c("co_dest" = "co_mun")) %>% rename("dest_lon" = "LONG", "dest_lat" = "LAT")

# summarize modes and create separate frames for each product
#flows <- flows %>% group_by(co_orig,co_dest,product,orig_lon,orig_lat,dest_lon,dest_lat) %>% summarise(value = sum(value, na.rm = T), .groups = "drop")
flows_bean <- filter(flows, product == "bean")
flows_oil <- filter(flows, product == "oil")
flows_cake <- filter(flows, product == "cake")

# check aggregate flow data
flows_agg <- group_by(flows, co_orig, product) %>% summarise(across(euclid:mean, sum), .groups = "drop")
flows_agg_wide <- pivot_wider(flows_agg, id_cols = c(co_orig), names_from = product, values_from = c(euclid, mean))
flows_agg_wide[is.na(flows_agg_wide)] <- 0
flows_agg <- flows_agg %>% mutate(diff_euclid_mean = euclid - mean)

SOY_MUN_flows <- SOY_MUN %>% dplyr::select(c(co_mun:nm_state, starts_with("excess_supply"))) %>% left_join(flows_agg_wide, by = c("co_mun" = "co_orig"))

# plot with ggplot

# general plots by product

prod_flow_plots <- lapply(list(bean = flows_bean, oil = flows_oil, cake = flows_cake), function(flow){

ggplot(data = states) +
  geom_sf(color = "grey", fill= "transparent", size = 0.1)+
  geom_sf(data = GEO_MUN_SOY[GEO_MUN_SOY$excess_supply_bean>0,], aes(fill = excess_supply_bean), color = "transparent", size = 0.01)+
  scale_fill_viridis(direction = -1, option = "D", na.value = "transparent", name = "Excess soybean supply \n in tons")+
  #scale_fill_gradient(low = "white", high = "darkgreen", na.value = "transparent", name = "Excess soybean supply")+
  #The next line tells ggplot that we wish to plot line segments. The "alpha=" is line transparency and used below
  geom_segment(data = flow[which(flow$value>1000),], aes(x=orig_lon, y=orig_lat, xend=dest_lon, yend=dest_lat, alpha=value), col="darkblue")+
  #geom_link(data = flows_bean[which(flows_bean$value>10),], aes(x=orig_lon, y=orig_lat, xend=dest_lon, yend=dest_lat, alpha=value, colour = stat(index)), lineend = "round")+
  #scale_colour_gradient(low = "red", high = "green") +
  #Here is the magic bit that sets line transparency - essential to make the plot readable
  scale_alpha_continuous(range = c(0.1, 0.45), guide = "none")+
  #Set black background, ditch axes and fix aspect ratio
  #theme(panel.background = element_rect(fill='transparent',colour='transparent'))+quiet+coord_equal()+
  #theme(axis.text = element_blank(),
  #      axis.text.y = element_blank(),
  #      axis.ticks = element_blank(),
  #      rect = element_blank(),
  #      panel.background = element_rect(fill='darkgrey',colour='darkgrey'))+
  theme_map()+
  #theme(legend.position = "none")+
  coord_sf(crs = st_crs("+init=epsg:4326"))

ggsave(filename = "flows_bean.png")

})

#flow <- flows_oil
#
#ggplot(data = states) +
#  geom_sf(color = "grey", fill= "transparent", size = 0.1)+
#  geom_sf(data = GEO_MUN_SOY[GEO_MUN_SOY$excess_supply_oil>0,], aes(fill = excess_supply_oil), color = "transparent", size = 0.01)+
#  scale_fill_viridis(direction = -1, option = "A", na.value = "transparent", name = "Excess soy oil supply \n in tons")+
#  #scale_fill_gradient(low = "white", high = "darkgreen", na.value = "transparent", name = "Excess soybean supply")+
#  #The next line tells ggplot that we wish to plot line segments. The "alpha=" is line transparency and used below
#  geom_segment(data = flow[which(flow$value>1000),], aes(x=orig_lon, y=orig_lat, xend=dest_lon, yend=dest_lat, alpha=value), col="firebrick")+
#  #scale_colour_gradient(low = "red", high = "green") +
#  #Here is the magic bit that sets line transparency - essential to make the plot readable
#  scale_alpha_continuous(range = c(0.05, 0.45), guide = "none")+
#  #Set black background, ditch axes and fix aspect ratio
#  #theme(panel.background = element_rect(fill='transparent',colour='transparent'))+quiet+coord_equal()+
#  #theme(axis.text = element_blank(),
#  #      axis.text.y = element_blank(),
#  #      axis.ticks = element_blank(),
#  #      rect = element_blank(),
#  #      panel.background = element_rect(fill='darkgrey',colour='darkgrey'))+
#  theme_map()+
#  #theme(legend.position = "none")+
#  coord_sf(crs = st_crs("+init=epsg:4326"))
#
#ggsave(filename = "flows_oil.png")
#
#
#flow <- flows_cake
#
#ggplot(data = states) +
#  geom_sf(color = "grey", fill= "transparent", size = 0.1)+
#  geom_sf(data = GEO_MUN_SOY[GEO_MUN_SOY$excess_supply_cake>0,], aes(fill = excess_supply_cake), color = "transparent", size = 0.01)+
#  scale_fill_viridis(direction = -1, option = "C", na.value = "transparent", name = "Excess soy cake supply \n in tons")+
#  #scale_fill_gradient(low = "white", high = "darkgreen", na.value = "transparent", name = "Excess soybean supply")+
#  #The next line tells ggplot that we wish to plot line segments. The "alpha=" is line transparency and used below
#  geom_segment(data = flow[which(flow$value>1000),], aes(x=orig_lon, y=orig_lat, xend=dest_lon, yend=dest_lat, alpha=value), col="purple4")+
#  #geom_link(data = flows_bean[which(flows_bean$value>10),], aes(x=orig_lon, y=orig_lat, xend=dest_lon, yend=dest_lat, alpha=value, colour = stat(index)), lineend = "round")+
#  #scale_colour_gradient(low = "red", high = "green") +
#  #Here is the magic bit that sets line transparency - essential to make the plot readable
#  scale_alpha_continuous(range = c(0.05, 0.45), guide = "none")+
#  #Set black background, ditch axes and fix aspect ratio
#  #theme(panel.background = element_rect(fill='transparent',colour='transparent'))+quiet+coord_equal()+
#  #theme(axis.text = element_blank(),
#  #      axis.text.y = element_blank(),
#  #      axis.ticks = element_blank(),
#  #      rect = element_blank(),
#  #      panel.background = element_rect(fill='darkgrey',colour='darkgrey'))+
#  theme_map()+
#  #theme(legend.position = "none")+
#  coord_sf(crs = st_crs("+init=epsg:4326"))
#
#ggsave(filename = "flows_cake.png")


# compare simulation mean with cv
flow <- flows_bean

flow_list <- list(bean = flows_bean, oil = flows_oil, cake = flows_cake)

prod_sensi_plots <- lapply(c("bean", "oil", "cake"), function(prod){

  flow <- flow_list[[prod]]  
  ggplot(data = states) +
    geom_sf(color = "grey", fill= "transparent", size = 0.1)+
    geom_sf(data = GEO_MUN_SOY[SOY_MUN[paste0("excess_supply_",prod)]>0,], aes(fill = !! sym(paste0("excess_supply_", prod))), color = "transparent", size = 0.01, alpha = 0.9)+
    #scale_fill_viridis(direction = -1, option = "D", na.value = "transparent", name = "Excess soybean supply \n in tons")+
    scale_fill_gradient(na.value = "transparent", low = "transparent", high = "darkgrey",  guide = "none") +
    #The next line tells ggplot that we wish to plot line segments. The "alpha=" is line transparency and used below
    geom_segment(data = flow[which(flow$mean > 0),], aes(x=orig_lon, y=orig_lat, xend=dest_lon, yend=dest_lat, alpha=mean, color = cv),
               arrow = arrow(length = unit(0.005, "npc"), type = "closed"))+
    #Here is the magic bit that sets line transparency - essential to make the plot readable
    scale_alpha_continuous(range = c(0.01, 0.4), guide = "none")+
    #scale_size_continuous(range = c(0.08, 1.3))+
    #scale_color_viridis(option = "plasma") + 
    scale_color_gradient(low = "#481567FF", high = "firebrick1") + 
    #Set black background, ditch axes and fix aspect ratio
    #theme(panel.background = element_rect(fill='transparent',colour='transparent'))+quiet+coord_equal()+
    #theme(axis.text = element_blank(),
    #      axis.text.y = element_blank(),
    #      axis.ticks = element_blank(),
    #      rect = element_blank(),
    #      panel.background = element_rect(fill='darkgrey',colour='darkgrey'))+
    theme_map()+
    labs(fill = "excess supply") + 
    #theme(legend.position = "none")+
    theme(legend.position = "bottom") +
    coord_sf(crs = st_crs("+init=epsg:4326"))
  
  #ggsave(filename = paste0("flowmap_sensi_",prod,".png"))
  
})

wrap_plots(prod_sensi_plots, guides = "collect") + theme(legend.position = "bottom")


# general MU level plots

plot_funct <- function(variable, title,...){
  thesubset <- GEO_MUN_SOY[pull(SOY_MUN, variable)>0,]#GEO_MUN_SOY[!is.na(GEO_MUN_SOY[,paste0(variable)])[,1],]
  thedata <- st_drop_geometry(thesubset)
  theplot <- ggplot(thesubset, aes(fill = pull(thedata, variable)), size = 0.01) +
    geom_sf(color = "transparent")+            
    scale_fill_viridis(direction = -1, na.value = "transparent", name = paste(title), ...) + 
    #scale_fill_gradient(low = "white", high = "firebrick")+
    geom_sf(data = states, fill = "transparent", color = "grey", size = 0.1)+
    theme_void() # or minimal
  return(theplot)
}

plot_funct(variable = "excess_supply_cake", title = "Excess soy cake supply in tons")
# ggsave(filename = "excess_supply_cake.png")

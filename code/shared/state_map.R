# ============================================================================
# Reference map of Brazil's states grouped into the five macroregions
# (North / Northeast / Southeast / South / Center-West), with hand-tuned state
# labels. Interactive helper for the paper's overview figure.
# Input  : data/generated/base/GEO_MUN_SOY_fin.rds
# Output : results/maps/state_map.png
# ============================================================================
### create nice paper plot of territorial division of brazil

library(ggplot2)
library(dplyr)
library(ggsci)

GEO_MUN_SOY <- readRDS("data/generated/base/GEO_MUN_SOY_fin.rds")

GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(co_reg = as.numeric(substr(as.character(co_state),1,1)), .after = nm_state)
regions <- c("North", "Northeast", "Southeast", "South", "Center-West")

GEO_MUN_SOY <- GEO_MUN_SOY %>% mutate(nm_reg = regions[co_reg],.after = co_reg)

GEO_MUN <- select(GEO_MUN_SOY, co_mun:nm_reg)

GEO_STATE <- GEO_MUN %>% group_by(across(co_state:nm_reg)) %>% summarise()

GEO_STATE <- GEO_STATE %>% mutate(co_nm_state = paste(co_state, nm_state), co_nm_reg = paste(co_reg, nm_reg))
#GEO_STATE <- aggregate(GEO_MUN, c("co_state", "nm_state", "co_reg", "nm_reg"), FUN = first())


(regions_plot <- ggplot(GEO_STATE, aes(fill = co_nm_reg)) +
  #scale_fill_npg() +
  scale_fill_manual(values=c("#E64B35FF", "#4DBBD5FF", "#00A087FF", "#3C5488FF", "#FFC844FF")) +
  geom_sf(color = "white") +  
  geom_sf_text(data = filter(GEO_STATE, !nm_state %in% c("RN", "PB", "PE", "AL", "SE", "DF", "ES", "RJ", "SC")), 
               aes(label = co_nm_state), size = 3, fontface = "bold",
               nudge_x = c(0,0,0,0,0,0,0,0,"PI" = -110000,0,"BA" = 100000,100000,100000,0,0,0,0,10000),
               nudge_y = c(0,35000,0,0,0,0,0,0,"PI"= -140000, 10000,"BA" = 150000,0,0,0,"RS" = 100000,0,0,-10000)) +  
  ggrepel::geom_text_repel(
    data = filter(GEO_STATE, nm_state %in% c("RN", "PB", "PE", "AL", "SE", "DF","ES", "RJ", "SC")),
    aes(label = co_nm_state, geometry = geom),
    size = 3,
    fontface = "bold",
    stat = "sf_coordinates",
    min.segment.length = 0.1,
    max.overlaps = 100,
    nudge_x = c(450000, 480000, 680000, 350000,350000, 350000, 350000, 350000, 350000),
    nudge_y = c(0, 0, 0, 0,0, 0, 0, 0, -100000)
  ) +
  #geom_sf(data = GEO_states, fill = "transparent", color = "grey", size = 0.1)+
  theme_void()+ # or minimal
  theme(plot.title = element_text(hjust = 0.5), plot.margin = margin(0.5, 1, 0.5, 1, "cm"),
        legend.text=element_text(size=10, face = "bold"),
        legend.title=element_text(size=12, face = "bold"))+
  labs(fill="Macroregion")
)

ggsave("results/maps/state_map.png", regions_plot, bg = "transparent", width = 2500, height = 2000, units = "px")

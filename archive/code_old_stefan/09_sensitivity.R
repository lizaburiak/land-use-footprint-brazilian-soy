library(parallel)
library(MASS)
library(ggplot2)
library(viridis)
library(ggsci)
library(purrr)
library(patchwork)
library(tidyr)
library(ggpointdensity)


#### sensitivity analysis of multimodal model results #####

# load function library
source("code/old/00_function_library.R")

write = TRUE

options(scipen = 999999)

# sensitivity of total cost to each input parameter

product <- c("bean", "oil", "cake")
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
co_mun <- SOY_MUN$co_mun

# load inter-municipality flows
flows_euclid <- readRDS("results/intermediate/flows_euclid.rds")
bs_files <- list.files("./results/outputs/gams/bs_res", pattern="*.rds", full.names=F)
flows_bs <- lapply(bs_files, function(file){
  readRDS(paste0("./results/outputs/gams/bs_res/", file))
})
names(flows_bs) <- gsub(".rds","",bs_files)
flows_lst <- c(flows_euclid, flows_bs)
flows_mu <- reduce(flows_lst, merge, by = c("co_orig", "co_dest", "product"), all = TRUE) 
names(flows_mu) <- c(names(flows_mu)[1:3], names(flows_lst))
flows_mu[is.na(flows_mu)] <- 0
rm(flows_bs,flows_lst)

# # load MU-to-importer flows
# source_to_export_list <- readRDS("results/intermediate/source_to_export_list.rds")
# flows_full <- reduce(source_to_export_list, merge, by = c("from_code", "to_code", "item_code"), all = TRUE) 
# names(flows_full) <- c(names(flows_full)[1:3], names(source_to_export_list))
# rm(source_to_export_list)

# trase-level flows
comp_list <- readRDS("results/intermediate/comp_list.rds")
flows_trase <- comp_list$mun
rm(comp_list)


# for inter-municipality flows ------------------------------------------------------------------

# create ci / cv
flows_bs <- flows_mu[,which(colnames(flows_mu) == "00001"):ncol(flows_mu)]
flows_mu <- dplyr::select(flows_mu, c(co_orig:euclid))
flows_mu <- flows_mu %>% mutate(mean = apply(as.matrix(flows_bs), 1, mean),
                                min = apply(as.matrix(flows_bs), 1, min),
                                max = apply(as.matrix(flows_bs), 1, max),
                                sd = apply(as.matrix(flows_bs), 1, sd),
                                .after = euclid) %>%
                            mutate(cv = sd/mean,
                                   .after = max) %>%
                           replace_na(list(cv = 0))

flows_mu_p <- filter(flows_mu, mean > 0)

flows_mu_p$density <- get_density(flows_mu_p$mean, flows_mu_p$cv, n = 100, h = c(1000, 0.5))
#flows_mu$col <- densCols(flows_mu$mean, flows_mu$cv, colramp = colorRampPalette(rev(rainbow(10, end = 4/6))), nbin = 128*16)

# ggplot(flows_mu_p, aes(x=mean, y = cv))+ #,color = density
#  geom_pointdensity(alpha = 0.4, adjust = 1) + 
#  #geom_point(alpha = 0.4)+
#  scale_color_viridis(discrete  = FALSE, guide = guide_colourbar(barheight = unit(10, "cm")))+ #trans = "pseudo_log"
#  labs(y = "coefficient of variation", x=  "mean (tons)") +
#  theme_minimal() +
#  facet_wrap( ~ product)
# 
# ggplot(flows_mu_p, aes(x=mean, y = cv, color = density))+ #,color = density
#  #geom_pointdensity(alpha = 0.4, adjust = 0.01) + 
#  geom_point(alpha = 0.4)+
#  #scale_color_identity()+
#  scale_color_viridis(discrete  = FALSE,  guide = guide_colourbar(barheight = unit(10, "cm")))+ #trans = "pseudo_log"
#  labs(y = "coefficient of variation", x = "mean (tons)") +
#  theme_minimal() +
#  facet_wrap( ~ product)

scatter_mu <- ggplot(flows_mu_p, aes(x=mean, y = cv, fill = product))+ #,color = density
  geom_point(alpha = 0.25, shape = 21, stroke = 0, size = 2)+
  scale_color_lancet()+
  labs(y = "coefficient of variation", x = "mean (tons)", fill = "") +
  theme_minimal() +
  theme(legend.position = "bottom")

dens_cv <- ggplot(flows_mu_p, aes(x = cv, fill = product)) + 
  geom_density(alpha = 0.5, bw = 0.5) + # bw = 0.01
  scale_color_lancet()+
  theme_void() + 
  theme(legend.position = "none") + 
  coord_flip()

dens_mean <- ggplot(flows_mu_p, aes(x = mean, fill = product)) + 
  geom_density(alpha = 0.5, bw = 5000) + # bw = 0.01
  scale_color_lancet()+
  theme_void() + 
  theme(legend.position = "none") 

(sensi_mu <- dens_mean + plot_spacer() + scatter_mu + dens_cv + 
  plot_layout(ncol = 2, nrow = 2, widths = c(4, 0.8), heights = c(1, 4)))

if (write){
  ggsave(filename = "results/figures/sensi_mu.png", height = 5, width = 7, units = "in", sensi_mu, bg = "white")
  saveRDS(flows_mu, file = "results/intermediate/flows_mu_comp.rds")
} 


# cumulative flows ordered by CV
flows_mu_cum <- flows_mu_p %>% group_by(product) %>% arrange(cv) %>% mutate(cummean = cumsum(mean)) %>% mutate(cummean_rel = cummean/max(cummean) )

cumplot_mu <- ggplot(flows_mu_cum, aes(x=cummean_rel, y = cv, color = product))+ #,color = density
  geom_line(alpha = 1)+
  #scale_color_viridis(discrete  = FALSE, guide = guide_colourbar(barheight = unit(10, "cm")))+ #trans = "pseudo_log"
  #scale_color_lancet()+
  labs(y = "coefficient of variation", x = "cumulative sum of means (in % of total)") +
  theme_minimal() +
  geom_hline(yintercept=1,linetype=2, color = "grey", size = 0.5)+
  theme(legend.position = "bottom")

if (write) ggsave(filename = "results/figures/sensi_cum_mu.png", height = 5, width = 6, units = "in", cumplot_mu, bg = "white")




# # municipality-to-importer flows ------------------------------------------------------------------------------------
# flows_bs_full <- flows_full[,which(colnames(flows_full) == "00001"):ncol(flows_full)]
# flows_full <- dplyr::select(flows_full, c(from_code:euclid))
# flows_full <- flows_full %>% mutate(mean = apply(as.matrix(flows_bs_full), 1, mean),
#                                     min = apply(as.matrix(flows_bs_full), 1, min),
#                                     max = apply(as.matrix(flows_bs_full), 1, max),
#                                     sd = apply(as.matrix(flows_bs_full), 1, sd),
#                                     .after = euclid) %>%
#   mutate(cv = sd/mean,
#          .after = max) %>%
#   replace_na(list(cv = 0))
# 
# flows_full_p <- filter(flows_full, mean >0)
# 
# flows_full_p$density <- get_density(flows_full_p$mean, flows_full_p$cv, n = 100)
# 
# 
# scatter_imp <- ggplot(flows_full_p, aes(x=mean, y = cv))+
#   geom_pointdensity(alpha = 0.4) + # shape = 1
#   scale_color_viridis(discrete = FALSE)+
#   labs(y = "coefficient of variation",x = "mean (tons)") +
#   theme_minimal() +
#   facet_wrap( ~ item_code)
# 
# scatter_imp <- ggplot(flows_full_p, aes(x=mean, y = cv))+
#   geom_point(alpha = 0.4, color = "darkblue") + # shape = 1
#   #scale_color_viridis(discrete = FALSE)+
#   labs(y = "coefficient of variation", x = "mean (tons)") +
#   theme_minimal() +
#   facet_wrap( ~ item_code)
# 



# trase-level flows ------------------------------------------------------------------------------------

flows_trase_p <- filter(flows_trase, mean > 0)
flows_trase_p$density <-  get_density(flows_trase_p$mean, flows_trase_p$cv, n = 128*16, h = c(10000, 0.5))
flows_trase_p$product <- "bean equivalents"

scatter_trase <- ggplot(flows_trase_p, aes(x=mean, y = cv, fill = product))+ # color = density
  #geom_pointdensity(alpha = 0.4) + # shape = 1
  #geom_point(alpha = 0.3, color = "#481567FF") +
  geom_point(alpha = 0.25, shape = 21, stroke = 0, size = 2)+
  scale_fill_lancet()+
  #geom_point(alpha = 0.4) +
  #scale_color_viridis(discrete = FALSE)+
  labs(y = "coefficient of variation", x = "mean (tons)", fill = "") +
  theme_minimal() +
  theme(legend.position = "bottom") 

dens_cv_trase <- ggplot(flows_trase_p, aes(x = cv, fill = product)) + 
  geom_density(alpha = 0.5, bw = 0.5) + # bw = 0.01 , fill = "#481567FF"
  scale_color_lancet()+
  theme_void() + 
  theme(legend.position = "none") + 
  coord_flip()

dens_mean_trase <- ggplot(flows_trase_p, aes(x = mean, fill = product)) + 
  geom_density(alpha = 0.5, bw = 5000) + # bw = 0.01 , fill = "#481567FF"
  scale_color_lancet()+
  theme_void() + 
  theme(legend.position = "none") 

(sensi_trase <- dens_mean_trase + plot_spacer() + scatter_trase + dens_cv_trase + 
  plot_layout(ncol = 2, nrow = 2, widths = c(4, 0.8), heights = c(1, 4)))

if (write) ggsave(filename = "results/figures/sensi_trase.png", sensi_trase, height = 5, width = 7, units = "in", bg = "white")


# cumulative flows ordered by CV
flows_trase_cum <- flows_trase_p %>% arrange(cv) %>% mutate(cummean = cumsum(mean)) %>% mutate(cummean_rel = cummean/max(cummean) )

cumplot_trase <- ggplot(flows_trase_cum, aes(x=cummean_rel, y = cv, color = product))+ #,color = density
  geom_line(alpha = 1)+
  #scale_color_viridis(discrete  = FALSE, guide = guide_colourbar(barheight = unit(10, "cm")))+ #trans = "pseudo_log"
  #scale_color_lancet()+
  labs(y = "coefficient of variation", x = "cumulative sum of means (in % of total)") +
  theme_minimal() +
  geom_hline(yintercept=1,linetype=2, color = "grey", size = 0.5)+
  theme(legend.position = "bottom") 

if (write) ggsave(filename = "results/figures/sensi_cum_trase.png", height = 5, width = 6, units = "in", cumplot_trase, bg = "white")



  
  

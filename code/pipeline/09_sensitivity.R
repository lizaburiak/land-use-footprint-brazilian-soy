
#### sensitivity analysis of multimodal model results #####

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(parallel)
library(MASS)
library(ggplot2)
library(viridis)
library(ggsci)
library(purrr)
library(patchwork)
library(tidyr)
library(ggpointdensity)


# load function library
source("code/pipeline/00_function_library.R")

write = TRUE

options(scipen = 999999)

out_dir <- paste0("data/generated/outputs/09_", YEAR)
fig_dir <- paste0("results/figures/sensitivity/", YEAR)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
bs_res_dir <- paste0("./data/generated/outputs/gams/bs_res_", YEAR)

product <- c("bean", "oil", "cake")
SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
co_mun <- SOY_MUN$co_mun

# load inter-municipality flows
flows_euclid <- readRDS(paste0("data/generated/outputs/07_", YEAR, "/flows_euclid.rds"))
bs_files <- list.files(bs_res_dir, pattern="*.rds", full.names=F)
flows_bs <- lapply(bs_files, function(file){
  readRDS(file.path(bs_res_dir, file))
})
names(flows_bs) <- gsub(".rds","",bs_files)
flows_lst <- c(flows_euclid, flows_bs)
flows_mu <- reduce(flows_lst, merge, by = c("co_orig", "co_dest", "product"), all = TRUE)
names(flows_mu) <- c(names(flows_mu)[1:3], names(flows_lst))
flows_mu[is.na(flows_mu)] <- 0
rm(flows_bs,flows_lst)

# trase-level flows (comp_list is created by step 10; expected at data/generated/outputs/10_{YEAR}/)
comp_list <- readRDS(paste0("data/generated/outputs/10_", YEAR, "/comp_list.rds"))
flows_trase <- comp_list$mun
rm(comp_list)


# for inter-municipality flows ------------------------------------------------------------------

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

scatter_mu <- ggplot(flows_mu_p, aes(x=mean, y = cv, fill = product))+
  geom_point(alpha = 0.25, shape = 21, stroke = 0, size = 2)+
  scale_color_lancet()+
  labs(y = "coefficient of variation", x = "mean (tons)", fill = "") +
  theme_minimal() +
  theme(legend.position = "bottom")

dens_cv <- ggplot(flows_mu_p, aes(x = cv, fill = product)) +
  geom_density(alpha = 0.5, bw = 0.5) +
  scale_color_lancet()+
  theme_void() +
  theme(legend.position = "none") +
  coord_flip()

dens_mean <- ggplot(flows_mu_p, aes(x = mean, fill = product)) +
  geom_density(alpha = 0.5, bw = 5000) +
  scale_color_lancet()+
  theme_void() +
  theme(legend.position = "none")

(sensi_mu <- dens_mean + plot_spacer() + scatter_mu + dens_cv +
  plot_layout(ncol = 2, nrow = 2, widths = c(4, 0.8), heights = c(1, 4)))

if (write){
  ggsave(filename = file.path(fig_dir, "sensi_mu.png"), height = 5, width = 7, units = "in", sensi_mu, bg = "white")
  saveRDS(flows_mu, file = file.path(out_dir, "flows_mu_comp.rds"))
}


flows_mu_cum <- flows_mu_p %>% group_by(product) %>% arrange(cv) %>% mutate(cummean = cumsum(mean)) %>% mutate(cummean_rel = cummean/max(cummean) )

cumplot_mu <- ggplot(flows_mu_cum, aes(x=cummean_rel, y = cv, color = product))+
  geom_line(alpha = 1)+
  labs(y = "coefficient of variation", x = "cumulative sum of means (in % of total)") +
  theme_minimal() +
  geom_hline(yintercept=1,linetype=2, color = "grey", size = 0.5)+
  theme(legend.position = "bottom")

if (write) ggsave(filename = file.path(fig_dir, "sensi_cum_mu.png"), height = 5, width = 6, units = "in", cumplot_mu, bg = "white")




# trase-level flows ------------------------------------------------------------------------------------

flows_trase_p <- filter(flows_trase, mean > 0)
flows_trase_p$density <-  get_density(flows_trase_p$mean, flows_trase_p$cv, n = 128*16, h = c(10000, 0.5))
flows_trase_p$product <- "bean equivalents"

scatter_trase <- ggplot(flows_trase_p, aes(x=mean, y = cv, fill = product))+
  geom_point(alpha = 0.25, shape = 21, stroke = 0, size = 2)+
  scale_fill_lancet()+
  labs(y = "coefficient of variation", x = "mean (tons)", fill = "") +
  theme_minimal() +
  theme(legend.position = "bottom")

dens_cv_trase <- ggplot(flows_trase_p, aes(x = cv, fill = product)) +
  geom_density(alpha = 0.5, bw = 0.5) +
  scale_color_lancet()+
  theme_void() +
  theme(legend.position = "none") +
  coord_flip()

dens_mean_trase <- ggplot(flows_trase_p, aes(x = mean, fill = product)) +
  geom_density(alpha = 0.5, bw = 5000) +
  scale_color_lancet()+
  theme_void() +
  theme(legend.position = "none")

(sensi_trase <- dens_mean_trase + plot_spacer() + scatter_trase + dens_cv_trase +
  plot_layout(ncol = 2, nrow = 2, widths = c(4, 0.8), heights = c(1, 4)))

if (write) ggsave(filename = file.path(fig_dir, "sensi_trase.png"), sensi_trase, height = 5, width = 7, units = "in", bg = "white")


flows_trase_cum <- flows_trase_p %>% arrange(cv) %>% mutate(cummean = cumsum(mean)) %>% mutate(cummean_rel = cummean/max(cummean) )

cumplot_trase <- ggplot(flows_trase_cum, aes(x=cummean_rel, y = cv, color = product))+
  geom_line(alpha = 1)+
  labs(y = "coefficient of variation", x = "cumulative sum of means (in % of total)") +
  theme_minimal() +
  geom_hline(yintercept=1,linetype=2, color = "grey", size = 0.5)+
  theme(legend.position = "bottom")

if (write) ggsave(filename = file.path(fig_dir, "sensi_cum_trase.png"), height = 5, width = 6, units = "in", cumplot_trase, bg = "white")

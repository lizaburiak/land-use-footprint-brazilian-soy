# ============================================================================
# Footprint dynamics plots - Brazilian soy production embodied in consumption.
# Metric: production tonnes (P_mass production footprint).
# Years: default 2010-2015 (clean prod_bean); pass a range via commandArgs.
# Origin = Brazilian municipal soybean rows ({co_mun}_c021).
# Outputs: results/figures/footprint_dynamics/{png,csv}
# ============================================================================
suppressMessages({
  library(Matrix); library(data.table); library(dplyr); library(tidyr)
  library(ggplot2); library(sf); library(viridis); library(scales); library(patchwork)
})

args <- commandArgs(trailingOnly = TRUE)
YEARS <- if (length(args) >= 2) seq(as.integer(args[1]), as.integer(args[2])) else 2010:2015

OUT <- Sys.getenv("FPD_OUT", "results/figures/footprint_dynamics")
dir.create(file.path(OUT, "csv"), recursive = TRUE, showWarnings = FALSE)

regions <- fread("data/fabio/v2/inst/regions_full.csv")
items   <- fread("data/fabio/v2/inst/items_full.csv")

# ---- lookups -------------------------------------------------------------
eu27 <- regions$iso3c[regions$EU27 == TRUE]
cont <- setNames(regions$continent, regions$iso3c)
region_group <- function(iso) {
  ifelse(iso == "BRA", "Brazil (domestic)",
  ifelse(iso == "CHN", "China",
  ifelse(iso %in% eu27, "EU-27",
  ifelse(!is.na(cont[iso]) & cont[iso] == "ASI", "Rest of Asia", "Rest of world"))))
}
# end-use buckets from FABIO comm_group
animal_grp <- c("Meat","Milk","Eggs","Live animals","Animal fats","Hides, skins, wool","Honey")
soy_grp    <- c("Oil crops","Vegetable oils","Oil cakes")
enduse_of_comm <- function(cc) {
  g <- items$comm_group[match(cc, items$comm_code)]
  ifelse(g %in% animal_grp, "Animal products (meat/dairy/eggs)",
  ifelse(g %in% soy_grp,    "Soybeans, meal & oil (commodity)", "Other food"))
}

# ---- per-year aggregation ------------------------------------------------
by_region <- list(); by_enduse <- list(); by_country <- list(); chn_mun <- list()
for (Y in YEARS) {
  f <- sprintf("data/generated/footprints/%d_P_mass.rds", Y)
  if (!file.exists(f)) { message("skip ", Y, " (no footprint)"); next }
  P <- readRDS(f)
  soy <- as.numeric(sub("_.*", "", rownames(P$A_country))) > 1000 &
         sub(".*_", "", rownames(P$A_country)) == "c021"

  # --- by destination country (food + nonfood), summed over soy origin rows ---
  food    <- Matrix::colSums(P$A_country[soy, , drop = FALSE])  # ISO_food
  nonfood <- Matrix::colSums(P$B_country[soy, , drop = FALSE])  # ISO_nonfood
  iso_f <- sub("_food$", "", names(food)); iso_n <- sub("_nonfood$", "", names(nonfood))
  ctry <- tapply(c(food, nonfood), c(iso_f, iso_n), sum)
  dt_c <- data.table(iso = names(ctry), t = as.numeric(ctry), year = Y)
  by_country[[as.character(Y)]] <- dt_c
  dt_c[, grp := region_group(iso)]
  by_region[[as.character(Y)]] <- dt_c[, .(t = sum(t)), by = .(year, grp)]

  # --- by end-use product (food side A_product + nonfood side B_product) ---
  ap <- Matrix::colSums(P$A_product[soy, , drop = FALSE])
  bp <- sum(Matrix::colSums(P$B_product[soy, , drop = FALSE]))
  de <- data.table(bucket = enduse_of_comm(names(ap)), t = as.numeric(ap))[, .(t = sum(t)), by = bucket]
  de <- rbind(de, data.table(bucket = "Non-food / industrial", t = bp))
  de[, year := Y]
  by_enduse[[as.character(Y)]] <- de

  # --- municipal soy embodied in China (for choropleth) ---
  chn <- P$A_country[soy, "CHN_food"] + P$B_country[soy, "CHN_nonfood"]
  chn_mun[[as.character(Y)]] <- data.table(
    co_mun = as.numeric(sub("_.*", "", rownames(P$A_country)[soy])),
    t_china = as.numeric(chn), year = Y)
  message("aggregated ", Y)
  rm(P); gc()
}

reg  <- rbindlist(by_region);  fwrite(reg,  file.path(OUT, "csv", "by_region.csv"))
endu <- rbindlist(by_enduse);  fwrite(endu, file.path(OUT, "csv", "by_enduse.csv"))
ctry <- rbindlist(by_country); fwrite(ctry, file.path(OUT, "csv", "by_country.csv"))

Mt <- function(x) x / 1e6
yr_breaks <- min(YEARS):max(YEARS)
theme_set(theme_minimal(base_size = 12))

# ---- PLOT 1: by destination region (stacked area) ------------------------
reg$grp <- factor(reg$grp, levels = c("China","EU-27","Rest of Asia","Rest of world","Brazil (domestic)"))
p1 <- ggplot(reg, aes(year, Mt(t), fill = grp)) +
  geom_area(alpha = .9, colour = "white", linewidth = .2) +
  scale_fill_manual(values = c("China"="#d1495b","EU-27"="#00798c","Rest of Asia"="#edae49",
                               "Rest of world"="#8d96a3","Brazil (domestic)"="#66a182")) +
  scale_x_continuous(breaks = yr_breaks) +
  labs(title = "Brazilian soy embodied in consumption, by destination",
       subtitle = "Production footprint (mass allocation)", x = NULL,
       y = "Million tonnes soybean equiv.", fill = NULL) +
  theme(legend.position = "bottom")
ggsave(file.path(OUT, "01_by_destination_region.png"), p1, width = 9, height = 6, dpi = 150)

# ---- PLOT 2: by end-use (stacked area) -----------------------------------
endu$bucket <- factor(endu$bucket, levels = c("Animal products (meat/dairy/eggs)",
  "Soybeans, meal & oil (commodity)","Other food","Non-food / industrial"))
p2 <- ggplot(endu, aes(year, Mt(t), fill = bucket)) +
  geom_area(alpha = .9, colour = "white", linewidth = .2) +
  scale_fill_manual(values = c("Animal products (meat/dairy/eggs)"="#a63603",
    "Soybeans, meal & oil (commodity)"="#e6550d","Other food"="#fd8d3c","Non-food / industrial"="#fdbe85")) +
  scale_x_continuous(breaks = yr_breaks) +
  labs(title = "Brazilian soy embodied in consumption, by end-use",
       subtitle = "Production footprint (mass allocation)", x = NULL,
       y = "Million tonnes soybean equiv.", fill = NULL) +
  theme(legend.position = "bottom") + guides(fill = guide_legend(nrow = 2))
ggsave(file.path(OUT, "02_by_enduse.png"), p2, width = 9, height = 6, dpi = 150)

# ---- PLOT 3: top importers + domestic share ------------------------------
ctry[, name := regions$name[match(iso, regions$iso3c)]]
top <- ctry[iso != "BRA", .(t = sum(t)), by = .(iso, name)][order(-t)][1:8]
lines <- ctry[iso %in% top$iso]
p3a <- ggplot(lines, aes(year, Mt(t), colour = reorder(name, -t))) +
  geom_line(linewidth = 1) + geom_point(size = 1.6) +
  scale_x_continuous(breaks = yr_breaks) + scale_colour_brewer(palette = "Set2") +
  labs(title = "Top importing destinations", x = NULL,
       y = "Million tonnes soybean equiv.", colour = NULL) +
  theme(legend.position = "right")
# domestic vs export share
ds <- ctry[, .(Domestic = sum(t[iso == "BRA"]), Exported = sum(t[iso != "BRA"])), by = year]
dsl <- melt(ds, id.vars = "year", variable.name = "dest", value.name = "t")
p3b <- ggplot(dsl, aes(year, Mt(t), fill = dest)) +
  geom_area(alpha = .9, colour = "white", linewidth = .2) +
  scale_fill_manual(values = c("Domestic"="#66a182","Exported"="#d1495b")) +
  scale_x_continuous(breaks = yr_breaks) +
  labs(title = "Domestic vs exported", x = NULL, y = "Million tonnes", fill = NULL) +
  theme(legend.position = "bottom")
ggsave(file.path(OUT, "03_top_importers_and_domestic.png"),
       p3a + p3b + plot_layout(widths = c(1.4, 1)), width = 12, height = 5.5, dpi = 150)

# ---- PLOT 4: choropleth small-multiples (soy embodied in China) ----------
geo <- readRDS(sprintf("data/generated/outputs/05_%d/GEO_MUN_SOY_fin.rds", max(YEARS))) %>%
  st_transform(4326) %>% dplyr::select(co_mun)
panel_years <- intersect(c(min(YEARS), round(median(YEARS)), max(YEARS)), YEARS)
cm <- rbindlist(chn_mun)[year %in% panel_years]
gj <- geo %>% left_join(cm, by = "co_mun")
gj$t_china[is.na(gj$t_china)] <- 0
states <- tryCatch(st_read("data/geo/GADM_boundaries/gadm36_BRA_1.shp", quiet = TRUE) %>%
                     st_transform(4326), error = function(e) NULL)
p4 <- ggplot(gj) +
  { if (!is.null(states)) geom_sf(data = states, fill = NA, colour = "grey80", linewidth = .2) } +
  geom_sf(aes(fill = t_china / 1e3), colour = NA) +
  scale_fill_viridis(option = "inferno", direction = -1, trans = "sqrt",
                     name = "1000 t to China", na.value = "grey95") +
  facet_wrap(~year, nrow = 1) +
  labs(title = "Brazilian soy embodied in China's consumption - municipal origin",
       subtitle = "Production footprint (mass), thousand tonnes") +
  theme_void(base_size = 11) + theme(legend.position = "right",
       plot.title = element_text(hjust = .5), plot.subtitle = element_text(hjust = .5))
ggsave(file.path(OUT, "04_china_choropleth.png"), p4, width = 13, height = 5.5, dpi = 150)

cat("\nDONE. Figures in", OUT, "\n"); print(list.files(OUT, pattern = "png$"))

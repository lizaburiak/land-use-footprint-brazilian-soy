# ============================================================================
# Extend map_data_allyears.csv back to 2001 (merge, don't regenerate: the
# 2010-2012 / 2014-2021 F_mass files are no longer on disk - their rows are
# taken from the existing CSV). Also writes map_data_2001_2022.csv (the
# 2001-vs-2022 pair for the comparison map).
# Output: results/plots_2001_2022/csv/{map_data_allyears.csv, map_data_2001_2022.csv}
# Usage : Rscript code/prep/prep_map_merge_pre2010.R
# ============================================================================
suppressMessages({library(Matrix); library(data.table)})

OUT <- "results/plots_2001_2022/csv"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

regions <- fread("data/fabio/v2/inst/regions_full.csv")
eu27 <- regions$iso3c[regions$EU27 == TRUE]
cont <- setNames(regions$continent, regions$iso3c)
grp_of <- function(iso) ifelse(iso == "BRA", "Brazil (domestic)",
  ifelse(iso == "CHN", "China",
  ifelse(iso %in% eu27, "EU-27",
  ifelse(!is.na(cont[iso]) & cont[iso] == "ASI", "Rest of Asia", "Rest of world"))))
LAYERS <- c("Total", "China", "EU-27", "Rest of Asia", "Rest of world")

layer_rows <- function(Y) {
  F <- readRDS(sprintf("data/generated/footprints/%d_F_mass.rds", Y))
  soy <- as.numeric(sub("_.*", "", rownames(F$A_country))) > 1000 &
         sub(".*_", "", rownames(F$A_country)) == "c021"
  mun <- as.numeric(sub("_.*", "", rownames(F$A_country)[soy]))
  food    <- F$A_country[soy, , drop = FALSE]
  nonfood <- F$B_country[soy, , drop = FALSE]
  grp_f <- grp_of(sub("_food$", "", colnames(food)))
  grp_n <- grp_of(sub("_nonfood$", "", colnames(nonfood)))
  rows <- lapply(LAYERS, function(L) {
    ha <- if (L == "Total")
      Matrix::rowSums(food) + Matrix::rowSums(nonfood)
    else
      Matrix::rowSums(food[, grp_f == L, drop = FALSE]) +
      Matrix::rowSums(nonfood[, grp_n == L, drop = FALSE])
    data.table(co_mun = mun, year = Y, layer = L, ha = as.numeric(ha))
  })
  message(sprintf("[merge-map] %d done", Y))
  rbindlist(rows)
}

new <- rbindlist(lapply(2001:2009, layer_rows))
old <- fread("results/maps/footprint_maps/map_data_allyears.csv")[year >= 2010]
all <- rbind(new, old)[order(year)]
all[, layer := factor(layer, levels = LAYERS)]
fwrite(all, file.path(OUT, "map_data_allyears.csv"))
cat("map_data_allyears:", paste(range(all$year), collapse = "-"), nrow(all), "rows\n")

pair <- all[year %in% c(2001, 2022)]
fwrite(pair, file.path(OUT, "map_data_2001_2022.csv"))
cat("map_data_2001_2022:", nrow(pair), "rows\n")

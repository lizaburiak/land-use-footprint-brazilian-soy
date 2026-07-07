# ============================================================================
# Prep data for the 2010-vs-2022 municipal land-footprint map (5 rows x 2 cols).
# Extracts, per Brazilian municipality, the soy LAND-use footprint (ha, F_mass)
# embodied in consumption, split into 5 layers:
#   Total | China | EU-27 | Rest of Asia | Rest of world
# (region groups follow the repo convention in plot_footprint_dynamics.R;
#  "Rest of world" EXCLUDES Brazil-domestic, so the 4 destination layers sum to
#  Total minus the Brazil-domestic share.)
# Writes a tidy CSV consumed by code/plot_map_2010_2022.py (geopandas).
# Usage: Rscript code/prep/prep_map_2010_2022.R   (years 2010 & 2022 hard-wired)
# ============================================================================
suppressMessages({library(Matrix); library(data.table)})

YEARS <- c(2010, 2022)
OUT   <- "results/maps/footprint_maps"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

regions <- fread("data/fabio/v2/inst/regions_full.csv")
eu27 <- regions$iso3c[regions$EU27 == TRUE]
cont <- setNames(regions$continent, regions$iso3c)
grp_of <- function(iso) ifelse(iso == "BRA", "Brazil (domestic)",
  ifelse(iso == "CHN", "China",
  ifelse(iso %in% eu27, "EU-27",
  ifelse(!is.na(cont[iso]) & cont[iso] == "ASI", "Rest of Asia", "Rest of world"))))

LAYERS <- c("Total", "China", "EU-27", "Rest of Asia", "Rest of world")

out <- list()
for (Y in YEARS) {
  f <- sprintf("data/generated/footprints/%d_F_mass.rds", Y)
  stopifnot(file.exists(f))
  F <- readRDS(f)
  soy <- as.numeric(sub("_.*", "", rownames(F$A_country))) > 1000 &
         sub(".*_", "", rownames(F$A_country)) == "c021"
  mun <- as.numeric(sub("_.*", "", rownames(F$A_country)[soy]))

  food    <- F$A_country[soy, , drop = FALSE]   # cols "{ISO}_food"
  nonfood <- F$B_country[soy, , drop = FALSE]    # cols "{ISO}_nonfood"
  grp_f <- grp_of(sub("_food$", "", colnames(food)))
  grp_n <- grp_of(sub("_nonfood$", "", colnames(nonfood)))

  for (L in LAYERS) {
    if (L == "Total") {
      ha <- Matrix::rowSums(food) + Matrix::rowSums(nonfood)
    } else {
      ha <- Matrix::rowSums(food[, grp_f == L, drop = FALSE]) +
            Matrix::rowSums(nonfood[, grp_n == L, drop = FALSE])
    }
    out[[paste(Y, L)]] <- data.table(co_mun = mun, year = Y, layer = L, ha = as.numeric(ha))
  }
  message(sprintf("[prep] %d: total footprint %.2f Mha across %d municipalities",
                  Y, sum(Matrix::rowSums(food) + Matrix::rowSums(nonfood)) / 1e6, length(mun)))
  rm(F); gc(verbose = FALSE)
}

dt <- rbindlist(out)
dt[, layer := factor(layer, levels = LAYERS)]
fwrite(dt, file.path(OUT, "map_data_2010_2022.csv"))

# quick layer totals (Mha) for sanity
cat("\nLayer totals (Mha):\n")
print(dcast(dt[, .(Mha = round(sum(ha) / 1e6, 2)), by = .(year, layer)],
            layer ~ year, value.var = "Mha"))
cat("\nwrote", file.path(OUT, "map_data_2010_2022.csv"), "\n")

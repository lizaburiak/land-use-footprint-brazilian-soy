# ============================================================================
# Per-municipality soy LAND-use footprint (ha, F_mass) for ALL years, by layer
#   Total | China | EU-27 | Rest of Asia | Rest of world
# -> tidy CSV consumed by code/animate_footprint.py to build year-by-year GIFs.
# Same extraction as prep_map_2010_2022.R, looped over every available year.
# Usage: Rscript code/prep/prep_map_allyears.R   (auto-detects years with F_mass)
# ============================================================================
suppressMessages({library(Matrix); library(data.table)})

OUT <- "results/maps/footprint_maps"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

fps   <- list.files("data/generated/footprints", pattern = "^[0-9]{4}_F_mass\\.rds$", full.names = TRUE)
YEARS <- sort(as.integer(sub(".*/([0-9]{4})_F_mass\\.rds$", "\\1", fps)))

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
  F <- readRDS(sprintf("data/generated/footprints/%d_F_mass.rds", Y))
  soy <- as.numeric(sub("_.*", "", rownames(F$A_country))) > 1000 &
         sub(".*_", "", rownames(F$A_country)) == "c021"
  mun <- as.numeric(sub("_.*", "", rownames(F$A_country)[soy]))
  food    <- F$A_country[soy, , drop = FALSE]
  nonfood <- F$B_country[soy, , drop = FALSE]
  grp_f <- grp_of(sub("_food$", "", colnames(food)))
  grp_n <- grp_of(sub("_nonfood$", "", colnames(nonfood)))
  for (L in LAYERS) {
    ha <- if (L == "Total")
      Matrix::rowSums(food) + Matrix::rowSums(nonfood)
    else
      Matrix::rowSums(food[, grp_f == L, drop = FALSE]) +
      Matrix::rowSums(nonfood[, grp_n == L, drop = FALSE])
    out[[paste(Y, L)]] <- data.table(co_mun = mun, year = Y, layer = L, ha = as.numeric(ha))
  }
  message(sprintf("[prep] %d done (%.1f Mha total)", Y, sum(Matrix::rowSums(food) + Matrix::rowSums(nonfood)) / 1e6))
  rm(F); gc(verbose = FALSE)
}

dt <- rbindlist(out)
dt[, layer := factor(layer, levels = LAYERS)]
fwrite(dt, file.path(OUT, "map_data_allyears.csv"))
cat("\nwrote", file.path(OUT, "map_data_allyears.csv"),
    "(", length(YEARS), "years:", min(YEARS), "-", max(YEARS), ")\n")

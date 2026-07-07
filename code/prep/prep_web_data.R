# ============================================================================
# Per-DESTINATION per-municipality soy land-use footprint (ha) -> small JSON files
# for the MapLibre web map. Geometry is loaded once client-side; selecting a
# destination fetches just that destination's tiny values file.
#
# Destinations written:
#   total ; regions (eu27, asia, row, bra-domestic) ; EVERY FABIO country (ISO3).
# Each file: {key,label,group,years:[...],vmax,data:{co_mun:[ha_per_year...]}} (ints, nonzero only)
# Plus index.json: ordered list for the dropdown.
#
# Output: web/data/<key>.json + web/data/index.json
# Usage : Rscript code/prep/prep_web_data.R
# ============================================================================
suppressMessages({library(Matrix); library(data.table); library(jsonlite); library(sf)})

OUT <- "web/data"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
fps   <- list.files("data/generated/footprints", pattern = "^[0-9]{4}_F_mass\\.rds$", full.names = TRUE)
YEARS <- sort(as.integer(sub(".*/([0-9]{4})_F_mass\\.rds$", "\\1", fps)))

regions <- fread("data/fabio/v2/inst/regions_full.csv")
nm   <- setNames(regions$name, regions$iso3c)
eu27 <- regions$iso3c[regions$EU27 == TRUE]
cont <- setNames(regions$continent, regions$iso3c)
region_of <- function(iso) ifelse(iso == "BRA", "r_bra",
  ifelse(iso == "CHN", "CHN",
  ifelse(iso %in% eu27, "r_eu27",
  ifelse(!is.na(cont[iso]) & cont[iso] == "ASI", "r_asia", "r_row"))))

# master municipality list = exactly the geometry's co_mun, so data aligns to the map
geo_mun <- as.character(sort(unique(as.integer(
  st_drop_geometry(st_read("data/generated/base/GEO_MUN_SOY.gpkg", quiet = TRUE))$co_mun))))

# discover the full country (ISO) set from the first footprint
F0 <- readRDS(sprintf("data/generated/footprints/%d_F_mass.rds", YEARS[1]))
isos <- sub("_food$", "", colnames(F0$A_country))                 # 186 FABIO countries
rm(F0); gc()
keys <- c("total", "r_eu27", "r_asia", "r_row", "r_bra", isos)    # CHN is among isos
acc  <- setNames(lapply(keys, function(k) matrix(0, length(geo_mun), length(YEARS),
                        dimnames = list(geo_mun, as.character(YEARS)))), keys)

for (yi in seq_along(YEARS)) {
  Y <- YEARS[yi]
  F <- readRDS(sprintf("data/generated/footprints/%d_F_mass.rds", Y))
  soy <- as.numeric(sub("_.*", "", rownames(F$A_country))) > 1000 &
         sub(".*_", "", rownames(F$A_country)) == "c021"
  mun <- as.character(as.numeric(sub("_.*", "", rownames(F$A_country)[soy])))
  ri  <- match(mun, geo_mun)                                       # rows into master order
  ok  <- !is.na(ri)                                                # drop muni codes absent from geometry
  if (any(!ok)) message(sprintf("[web] %d: %d footprint munis not in geometry, dropped", Y, sum(!ok)))
  ri  <- ri[ok]
  food    <- F$A_country[soy, , drop = FALSE][ok, , drop = FALSE]; iso_f <- sub("_food$", "", colnames(food))
  nonfood <- F$B_country[soy, , drop = FALSE][ok, , drop = FALSE]; iso_n <- sub("_nonfood$", "", colnames(nonfood))
  reg_f <- region_of(iso_f); reg_n <- region_of(iso_n)

  acc[["total"]][ri, yi] <- Matrix::rowSums(food) + Matrix::rowSums(nonfood)
  for (rk in c("r_eu27", "r_asia", "r_row", "r_bra")) {
    v <- numeric(length(ri))
    if (any(reg_f == rk)) v <- v + Matrix::rowSums(food[, reg_f == rk, drop = FALSE])
    if (any(reg_n == rk)) v <- v + Matrix::rowSums(nonfood[, reg_n == rk, drop = FALSE])
    acc[[rk]][ri, yi] <- v
  }
  for (k in seq_along(isos)) {
    iso <- isos[k]
    v <- as.numeric(food[, k])
    j <- match(iso, iso_n); if (!is.na(j)) v <- v + as.numeric(nonfood[, j])
    acc[[iso]][ri, yi] <- v
  }
  message(sprintf("[web] %d aggregated", Y)); rm(F); gc(verbose = FALSE)
}

# global vmax (95th pct of Total nonzero) for a shared colour scale
tot_nz <- acc[["total"]][acc[["total"]] > 0]
VMAX <- as.numeric(round(quantile(tot_nz, 0.95)))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a
label_of <- function(k) switch(k,
  total = "Total (all destinations)", r_eu27 = "EU-27 (region)",
  r_asia = "Rest of Asia (region)", r_row = "Rest of world (region)",
  r_bra = "Brazil — domestic", unname(nm[k]) %||% k)
group_of <- function(k) if (startsWith(k, "r_") || k == "total") "Region" else "Country"

idx <- list()
for (k in keys) {
  M <- round(acc[[k]]); keep <- which(rowSums(M) > 0)
  if (!length(keep)) next
  data <- setNames(lapply(keep, function(i) as.integer(M[i, ])), geo_mun[keep])
  write_json(list(key = k, label = label_of(k), group = group_of(k),
                  years = YEARS, vmax = VMAX, data = data),
             file.path(OUT, paste0(k, ".json")), auto_unbox = TRUE, digits = 0)
  idx[[length(idx) + 1]] <- list(key = k, label = label_of(k), group = group_of(k),
                                 total2022 = as.numeric(round(sum(M[, ncol(M)]) / 1e6, 2)))
}
# order: total, then regions, then countries by 2022 footprint desc
idx <- idx[order(match(sapply(idx, `[[`, "key"), c("total","r_eu27","r_asia","r_row","r_bra")),
                 -sapply(idx, function(x) x$total2022))]
write_json(list(years = YEARS, vmax = VMAX, destinations = idx),
           file.path(OUT, "index.json"), auto_unbox = TRUE, digits = 2)
cat(sprintf("\nwrote %d destination files + index.json (vmax=%.0f ha)\n", length(idx), VMAX))

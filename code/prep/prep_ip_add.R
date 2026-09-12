# Rebuild ip_add.gpkg - supplementary ANTAQ ports missing from IP.shp
#
# Stefan's original ip_add.gpkg (hand-geocoded in QGIS) is not recoverable
# (not in strsek/soyprint, not on Zenodo). This script reconstructs it for the
# soy ports that appear in the 2017-2022 ANTAQ cargo data but are absent from
# IP.shp (see code/analysis/check_missing_ports.R). Each terminal is placed on
# the DNIT waterway network (Hidrovias.shp): the point on the waterway inside
# the terminal's municipality that is nearest to the municipal seat. This
# guarantees the port rasterizes onto a water pixel in step 06.
#
# BR200 ("Terminais Interiores") is a non-geographic catch-all code and is
# not included - its flows are dropped.
#
# Output: data/geo/ANTAQ/ip_add.gpkg (EPSG:5880, layer geometry column "geom"),
# schema = IP.shp columns + co_mun, i.e. exactly what 06_transport_cost.R
# rbind()s after its co_mun join. Run from repo root:
#   Rscript code/prep/prep_ip_add.R

suppressMessages({
  library(sf)
  library(dplyr)
})

# --- inputs -------------------------------------------------------------------

GEO_MUN_SOY <- readRDS("data/generated/base/GEO_MUN_SOY_fin.rds")       # EPSG:5880
if (!inherits(GEO_MUN_SOY, "sf")) stop("GEO_MUN_SOY_fin.rds is not sf")
MUN_capitals <- readRDS("data/generated/base/MUN_capitals.rds")
ports <- st_read("data/geo/ANTAQ/IP.shp", quiet = TRUE,
                 options = "ENCODING=WINDOWS-1252", stringsAsFactors = FALSE)
water <- st_read("data/geo/DNIT_logistic_network/Hidrovias.shp", quiet = TRUE,
                 stringsAsFactors = FALSE) |>
  st_transform(st_crs(GEO_MUN_SOY)) |>
  st_geometry() |>
  st_union()

# --- terminals to reconstruct -------------------------------------------------
# identified from data/geo/ANTAQ/Instalacao_{Origem,Destino}.txt (name, river, UF)

# uf_code = first two digits of co_mun (IBGE state code) - encoding-safe match
targets <- tibble::tribble(
  ~cdi_tuaria, ~nome,                        ~nm_mun,       ~uf,  ~uf_code,
  "BRSP020",   "TNPM Anhembi",               "Anhembi",     "SP", "35",
  "BRSP021",   "TNPM Pederneiras",           "Pederneiras", "SP", "35",
  "BRAM076",   "Coari Pequi",                "Coari",       "AM", "13",
  "BRPHA",     "Porto de Prainha",           "Prainha",     "PA", "15",
  "BRRO016",   "TEPOVEL Porto Velho",        "Porto Velho", "RO", "11",
  "BRJUR",     "Porto de Juruti",            "Juruti",      "PA", "15"
)

# --- geocode: nearest waterway point to the municipal seat, within the MU ----

geocode_port <- function(nm, uf_code) {
  mun <- filter(GEO_MUN_SOY, toupper(nm_mun) == toupper(nm),
                substr(as.character(co_mun), 1, 2) == uf_code)
  if (nrow(mun) != 1) stop(sprintf("municipality lookup failed: %s/%s (n=%d)", nm, uf_code, nrow(mun)))
  seat <- MUN_capitals[MUN_capitals$co_mun == mun$co_mun, ]
  anchor <- if (nrow(seat) == 1) st_geometry(seat) else st_centroid(st_geometry(mun))
  w_mun <- st_intersection(water, st_geometry(mun))
  target_water <- if (length(w_mun) > 0 && !all(st_is_empty(w_mun))) w_mun else water
  pt <- st_nearest_points(anchor, target_water) |> st_cast("POINT")
  list(geometry = pt[2], co_mun = mun$co_mun, on_mun_water = length(w_mun) > 0 && !all(st_is_empty(w_mun)))
}

geo <- lapply(seq_len(nrow(targets)), function(i) geocode_port(targets$nm_mun[i], targets$uf_code[i]))
for (i in seq_along(geo)) {
  if (!geo[[i]]$on_mun_water)
    warning(sprintf("%s: no waterway inside municipality, snapped to nearest waterway overall",
                    targets$cdi_tuaria[i]))
}

# --- assemble with IP.shp schema + co_mun ------------------------------------

pts_5880 <- st_sfc(do.call(c, lapply(geo, `[[`, "geometry")), crs = st_crs(GEO_MUN_SOY))
pts_4674 <- st_transform(pts_5880, 4674)
coords <- st_coordinates(pts_4674)
co_mun <- vapply(geo, function(x) as.numeric(x$co_mun), numeric(1))

template <- st_drop_geometry(ports)[0, ]                      # 32 empty attribute cols
ports_add <- template[rep(NA_integer_, nrow(targets)), ]
rownames(ports_add) <- NULL
ports_add$cdi_tuaria <- targets$cdi_tuaria
ports_add$nome       <- targets$nome
ports_add$idcidade   <- paste0("BR", substr(as.character(co_mun), 1, 6))
ports_add$cidade     <- targets$nm_mun
ports_add$estado     <- targets$uf
ports_add$latitude   <- coords[, "Y"]
ports_add$longitude  <- coords[, "X"]
ports_add$fonte      <- "SOYPRINT reconstruction (prep_ip_add.R)"
ports_add$observacao <- "Rebuilt 2026-07-27: ANTAQ code from Instalacao_* tables; point = nearest DNIT waterway to municipal seat within municipality. Replaces Stefan's lost hand-geocoded ip_add.gpkg."
ports_add$co_mun     <- co_mun
ports_add <- st_sf(ports_add, geom = pts_5880)

stopifnot(identical(setdiff(names(ports_add), "geom"),
                    c(names(st_drop_geometry(ports)), "co_mun")))

st_write(ports_add, "data/geo/ANTAQ/ip_add.gpkg", driver = "GPKG",
         delete_dsn = TRUE, quiet = TRUE)
cat("written: data/geo/ANTAQ/ip_add.gpkg with", nrow(ports_add), "ports\n")

# --- verification (mimics 06_transport_cost.R) --------------------------------

# 1. rbind compatibility exactly as in step 06
co_mun_lut <- data.frame(co_mun = st_drop_geometry(GEO_MUN_SOY)$co_mun) |>
  mutate(co_mun_6 = substr(co_mun, 1, 6))
ports06 <- ports |>
  st_transform(st_crs(GEO_MUN_SOY)) |>
  mutate(co_mun_6 = substr(idcidade, 3, 8)) |>
  left_join(co_mun_lut, by = "co_mun_6") |>
  select(-co_mun_6)
padd <- st_read("data/geo/ANTAQ/ip_add.gpkg", stringsAsFactors = FALSE, quiet = TRUE)
padd <- rename(padd, geometry = geom) |> st_set_geometry("geometry")
ports_all <- rbind(ports06, padd)
cat("rbind check: OK,", nrow(ports_all), "ports total\n")

# 2. within 3 km of a waterway (step 06's buffer check)
d <- as.numeric(st_distance(padd, water))
cat("distance to waterway [m]:", paste(round(d, 1), collapse = ", "), "\n")
stopifnot(all(d < 3000))

# 3. lands on a 5 km water raster pixel (step 06's rasterization)
suppressMessages({library(raster)})
ext <- as.character(st_bbox(GEO_MUN_SOY))
tmp_gpkg <- file.path(tempdir(), "water_verify.gpkg")
tmp_tif  <- file.path(tempdir(), "water_verify.tif")
wsf <- st_sf(value = 1, geometry = water)
st_write(wsf, tmp_gpkg, driver = "GPKG", delete_dsn = TRUE, quiet = TRUE)
gdal_utils("rasterize", tmp_gpkg, tmp_tif,
           options = c("-tr", "5000", "5000", "-a", "value", "-te", ext,
                       "-a_nodata", "NA", "-at"))
water_rast <- raster(tmp_tif)
hit <- raster::extract(water_rast, padd)
cat("water raster pixel hit:", paste(hit, collapse = ", "), "\n")
stopifnot(all(!is.na(hit)))

cat("all checks passed\n")

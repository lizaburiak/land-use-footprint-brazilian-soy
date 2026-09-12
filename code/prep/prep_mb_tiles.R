# ============================================================================
# Build the MapBiomas soy land-use tiles that step 21 (21_probability_maps.R)
# expects in data/geo/mb_tiles/.
#
# Source: MapBiomas Collection 9 annual land-cover/land-use coverage raster
# (full Brazil, 30 m, EPSG:4326), downloaded from the public GCS bucket:
#   https://storage.googleapis.com/mapbiomas-public/initiatives/brasil/
#     collection_9/lclu/coverage/brasil_coverage_<YEAR>.tif
#
# step 21 calls burn_rast(..., class = 1): it expects tiles where soy pixels
# are coded 1 and everything else is NA. MapBiomas codes soybean as class 39,
# so we reclassify 39 -> 1 / else -> NA, then cut the country into a tile grid
# (mirrors the multi-tile GEE export the original toolkit produced).
#
# Usage: Rscript code/prep/prep_mb_tiles.R YEAR [NTILE_SIDE]
#   YEAR       year to build (must match the *_P_mass.rds footprint vintage)
#   NTILE_SIDE tiles per side of the grid (default 16 -> up to 256 tiles)
# ============================================================================
suppressMessages(library(terra))

args    <- commandArgs(trailingOnly = TRUE)
YEAR    <- suppressWarnings(as.integer(args[1])); if (is.na(YEAR)) YEAR <- 2022
NSIDE   <- suppressWarnings(as.integer(args[2])); if (is.na(NSIDE)) NSIDE <- 16
SOYCODE <- 39L

src <- sprintf("data/geo/_mb_staging/brasil_coverage_%d.tif", YEAR)
if (!file.exists(src)) stop("Coverage raster not found: ", src, call. = FALSE)

terraOptions(memfrac = 0.6, progress = 0)

message("[prep_mb_tiles] reclassifying soy (class ", SOYCODE, ") -> 1 for ", YEAR)
r   <- rast(src)
soy <- ifel(r == SOYCODE, 1L, NA)

soy_file <- sprintf("data/geo/_mb_staging/soy_%d.tif", YEAR)
writeRaster(soy, soy_file, datatype = "INT1U", overwrite = TRUE,
            gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=6"), NAflag = 0)

# tile grid: one template cell per output tile
tmpl <- rast(ext(soy), nrow = NSIDE, ncol = NSIDE, crs = crs(soy))

message("[prep_mb_tiles] cutting into up to ", NSIDE * NSIDE, " tiles")
soy <- rast(soy_file)
tiles <- makeTiles(soy, tmpl,
                   filename = sprintf("data/geo/mb_tiles/soy%d_.tif", YEAR),
                   datatype = "INT1U", na.rm = TRUE, overwrite = TRUE,
                   gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=6"))

message("[prep_mb_tiles] wrote ", length(tiles), " tiles to data/geo/mb_tiles/")

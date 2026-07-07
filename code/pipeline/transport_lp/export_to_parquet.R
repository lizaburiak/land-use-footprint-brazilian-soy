#!/usr/bin/env Rscript
# Export R step-05 + step-06 outputs to Apache Parquet for the Python LP loader.
#
# Eliminates the pyreadr/rpy2 dependency on the Python side. Writes one .parquet
# per logical table under data/generated/outputs/05_YYYY/parquet/ and data/generated/outputs/06_YYYY/parquet/.
#
# Distance matrices (which are dense 2D numerics in R) are exported as long
# format: from, to, distance (skipping NA / non-finite cells).
#
# Usage:
#   Rscript code/pipeline/transport_lp/export_to_parquet.R 2013
#   Rscript code/pipeline/transport_lp/export_to_parquet.R 2013 --force   # overwrite existing

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
})

args <- commandArgs(trailingOnly = TRUE)
YEAR <- suppressWarnings(as.integer(args[1]))
if (is.na(YEAR)) stop("YEAR required: Rscript export_to_parquet.R 2013")
FORCE <- "--force" %in% args

# Pick a parquet writer; arrow is preferred, nanoparquet is the lightweight fallback.
.writer <- NULL
if (requireNamespace("arrow", quietly = TRUE)) {
  .writer <- function(df, path) arrow::write_parquet(df, path)
  cat("[export] using arrow\n")
} else if (requireNamespace("nanoparquet", quietly = TRUE)) {
  .writer <- function(df, path) nanoparquet::write_parquet(df, path)
  cat("[export] using nanoparquet\n")
} else {
  stop("Install one of: arrow OR nanoparquet  (install.packages('arrow') recommended)")
}

write_pq <- function(df, path) {
  if (file.exists(path) && !FORCE) {
    cat("[export] skip (exists):", path, "\n")
    return(invisible(NULL))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .writer(as.data.frame(df), path)
  cat("[export] wrote ", path, " (", nrow(df), " rows)\n", sep="")
}

# A long-format conversion for 2D distance matrices: from, to, distance.
mat_to_long <- function(mat, from_name = "from", to_name = "to", val_name = "distance") {
  if (is.data.frame(mat)) mat <- as.matrix(mat)
  rn <- rownames(mat); cn <- colnames(mat)
  if (is.null(rn) || is.null(cn)) {
    stop("Matrix is missing row/column names — cannot reshape to long format.")
  }
  out <- expand.grid(.from = rn, .to = cn, stringsAsFactors = FALSE)
  out$.val <- as.vector(mat)  # column-major: matches expand.grid order
  out <- out[is.finite(out$.val) & out$.val >= 0, ]
  names(out) <- c(from_name, to_name, val_name)
  out
}

# ── data/generated/outputs/00_YYYY/MUN_capital_dist.rds → long parquet ──────────────────────
out00 <- file.path(paste0("data/generated/outputs/00_", YEAR), "parquet")
mun_dist_path <- paste0("data/generated/outputs/00_", YEAR, "/MUN_capital_dist.rds")
if (file.exists(mun_dist_path)) {
  d <- readRDS(mun_dist_path)
  long <- mat_to_long(d, from_name = "from", to_name = "to", val_name = "distance")
  long$from <- as.character(long$from); long$to <- as.character(long$to)
  write_pq(long, file.path(out00, "MUN_capital_dist_long.parquet"))
}

# ── data/generated/outputs/05_YYYY ──────────────────────────────────────────────────────────
out05 <- file.path(paste0("data/generated/outputs/05_", YEAR), "parquet")
dir.create(out05, recursive = TRUE, showWarnings = FALSE)

soy_mun_path <- paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds")
if (file.exists(soy_mun_path)) {
  soy_mun <- readRDS(soy_mun_path)
  if (inherits(soy_mun, "sf")) soy_mun <- sf::st_drop_geometry(soy_mun)
  # co_mun must be character so the Python loader sees uniform string IDs.
  soy_mun$co_mun <- as.character(soy_mun$co_mun)
  write_pq(soy_mun, file.path(out05, "SOY_MUN_fin.parquet"))
} else {
  cat("[export] WARN: ", soy_mun_path, " not found\n")
}

# ── data/generated/outputs/06_YYYY ──────────────────────────────────────────────────────────
src06 <- paste0("data/generated/outputs/06_", YEAR)
out06 <- file.path(src06, "parquet")
if (!dir.exists(src06)) {
  cat("[export] data/generated/outputs/06_", YEAR, " does not exist — step 06 not yet run.\n", sep="")
  cat("[export] Skipping step-06 export. Python smoke test can still run via make_fixture.py.\n")
  quit(save = "no", status = 0)
}
dir.create(out06, recursive = TRUE, showWarnings = FALSE)

# stations.Rdata → stations_orig, stations_dest
if (file.exists(file.path(src06, "stations.Rdata"))) {
  e <- new.env(); load(file.path(src06, "stations.Rdata"), envir = e)
  for (nm in ls(e)) {
    obj <- get(nm, envir = e)
    if (inherits(obj, "sf")) obj <- sf::st_drop_geometry(obj)
    write_pq(obj, file.path(out06, paste0(nm, ".parquet")))
  }
}
# ports.Rdata → ports_orig, ports_dest
if (file.exists(file.path(src06, "ports.Rdata"))) {
  e <- new.env(); load(file.path(src06, "ports.Rdata"), envir = e)
  for (nm in ls(e)) {
    obj <- get(nm, envir = e)
    if (inherits(obj, "sf")) obj <- sf::st_drop_geometry(obj)
    write_pq(obj, file.path(out06, paste0(nm, ".parquet")))
  }
}
# cargo_long.Rdata → cargo_rail_long, cargo_water_long
if (file.exists(file.path(src06, "cargo_long.Rdata"))) {
  e <- new.env(); load(file.path(src06, "cargo_long.Rdata"), envir = e)
  for (nm in ls(e)) {
    obj <- as.data.frame(get(nm, envir = e))
    obj$orig <- as.character(obj$orig); obj$dest <- as.character(obj$dest)
    obj$product <- as.character(obj$product)
    write_pq(obj, file.path(out06, paste0(nm, ".parquet")))
  }
}
# dist_matrices.Rdata → road_dist_MUN, road_dist_MUN_stat, ..., rail_dist, water_dist
if (file.exists(file.path(src06, "dist_matrices.Rdata"))) {
  e <- new.env(); load(file.path(src06, "dist_matrices.Rdata"), envir = e)
  for (nm in ls(e)) {
    obj <- get(nm, envir = e)
    long <- mat_to_long(obj, from_name = "from", to_name = "to", val_name = "distance")
    long$from <- as.character(long$from); long$to <- as.character(long$to)
    write_pq(long, file.path(out06, paste0(nm, "_long.parquet")))
  }
}

cat("[export] Done. Parquet under ", out05, " and ", out06, "\n", sep="")

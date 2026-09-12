#!/usr/bin/env Rscript
# Bridge for the Python port: dump R intermediate tables to parquet so the Python
# steps in code/python/ can read them without pyreadr (which won't build here).
# Drops sf geometry / list columns; preserves rownames as a `.rowname` column.
# Run: Rscript code/python/export_for_py.R [YEAR]   (default 2013)
suppressPackageStartupMessages(library(nanoparquet))
year <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(year)) year <- 2013

exp <- function(rds, pq) {
  if (!file.exists(rds)) { cat("skip (missing):", rds, "\n"); return(invisible()) }
  x <- as.data.frame(readRDS(rds))
  rn <- rownames(x)
  if (!is.null(rn) && !identical(rn, as.character(seq_len(nrow(x))))) x[[".rowname"]] <- rn
  drop <- vapply(x, function(c) inherits(c, "sfc") || is.list(c), logical(1))
  x <- x[, !drop, drop = FALSE]
  dir.create(dirname(pq), recursive = TRUE, showWarnings = FALSE)
  write_parquet(x, pq)
  cat(sprintf("wrote: %s (%d x %d)\n", pq, nrow(x), ncol(x)))
}

o <- function(s) sprintf("results/outputs/%s_%d", s, year)
# inputs the Python steps read
exp(file.path(o("00"), "CBS_SOY.rds"), file.path(o("00"), "parquet/CBS_SOY.parquet"))
for (st in c("00", "01", "02", "04")) {
  exp(sprintf("%s/SOY_MUN_%s.rds", o(st), st), sprintf("%s/parquet/SOY_MUN_%s.parquet", o(st), st))
}
exp(sprintf("%s/SOY_MUN_fin.rds", o("05")), sprintf("%s/parquet/SOY_MUN_fin.parquet", o("05")))
# R reference OUTPUTS for validating the Python ports (suffix _R so they don't clash)
exp(sprintf("%s/SOY_MUN_03.rds", o("03")), sprintf("%s/parquet/SOY_MUN_03_R.parquet", o("03")))
exp(sprintf("%s/FAO_consistency.rds", o("00")), sprintf("%s/parquet/FAO_consistency_R.parquet", o("00")))
for (nm in c("EXP_MUN_SOY", "IMP_MUN_SOY", "EXP_NAT_SOY", "IMP_NAT_SOY", "regions")) {
  exp(sprintf("%s/%s.rds", o("04"), nm), sprintf("%s/parquet/%s_R.parquet", o("04"), nm))
}

# ---- step 04 inputs: EXP/IMP MU (step 00) + FABIO BTD filtered to year + soy items ----
exp(file.path(o("00"), "EXP_MUN_SOY_00.rds"), file.path(o("00"), "parquet/EXP_MUN_SOY_00.parquet"))
exp(file.path(o("00"), "IMP_MUN_SOY_00.rds"), file.path(o("00"), "parquet/IMP_MUN_SOY_00.parquet"))
soy_items <- c(2555, 2571, 2590)
filt <- function(df) { df <- as.data.frame(df); df[df$year == year & df$item_code %in% soy_items, ] }
wf <- function(df, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  write_parquet(df, p); cat(sprintf("wrote: %s (%d x %d)\n", p, nrow(df), ncol(df))) }
.stefan <- "data/new/04/FABIO/btd_bal.rds"; .new <- "data/new/04/FABIO/new/btd_bal.RData"
if (year <= 2013 && file.exists(.stefan)) {
  btd_imp <- filt(readRDS(.stefan))
} else if (file.exists(.new)) {
  e <- new.env(); load(.new, envir = e); btd_imp <- filt(e$btd_bal)
} else btd_imp <- filt(readRDS(.stefan))
wf(btd_imp, file.path(o("04"), "parquet/btd_imp_soy.parquet"))
wf(filt(readRDS("data/new/04/FABIO/FABIO_exp/v1/btd_bal.rds")),   file.path(o("04"), "parquet/btd_exp_soy.parquet"))
wf(filt(readRDS("data/new/04/FABIO/FABIO_exp/pure/btd_bal.rds")), file.path(o("04"), "parquet/btd_exp_pure_soy.parquet"))

# ---- step 02 geo input: municipality polygons (WGS84) + livestock attrs → GeoPackage ----
suppressPackageStartupMessages(library(sf))
.g01 <- sprintf("%s/GEO_MUN_SOY_01.rds", o("01"))
if (file.exists(.g01)) {
  g01 <- st_transform(readRDS(.g01), 4326)
  keep <- intersect(c("co_mun", "co_state", "cattle", "cattle_milked", "pig",
                      "chicken", "chicken_layer", "buffalo"), names(g01))
  st_write(g01[, keep], sprintf("%s/GEO_MUN_SOY_01.gpkg", o("01")), append = FALSE, quiet = TRUE)
  cat(sprintf("wrote: %s/GEO_MUN_SOY_01.gpkg (%d polygons)\n", o("01"), nrow(g01)))
}

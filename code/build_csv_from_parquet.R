#!/usr/bin/env Rscript
# build_csv_from_parquet.R -- dump the release Parquet layer to CSV so that
# code/build_release_db.py --csv can load it on hosts without pyarrow.
#
# The VM's system Python is externally managed and has no pyarrow; R does have
# arrow. One CSV per table, hive `year=` partitions unpacked into a year column.
#
# Usage: Rscript code/build_csv_from_parquet.R [PARQUET_DIR] [CSV_DIR]

DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")
suppressPackageStartupMessages({library(arrow); library(dplyr)})

args <- commandArgs(trailingOnly = TRUE)
PQ  <- if (length(args) >= 1) args[1] else file.path(DATA_DIR, "generated/parquet")
CSV <- if (length(args) >= 2) args[2] else file.path(DATA_DIR, "generated/parquet_csv")
dir.create(CSV, showWarnings = FALSE, recursive = TRUE)

tables <- list.dirs(PQ, recursive = FALSE, full.names = FALSE)
for (tbl in tables) {
  root <- file.path(PQ, tbl)
  parts <- list.files(root, pattern = "^year=", full.names = TRUE)
  if (length(parts)) {
    d <- open_dataset(root, partitioning = "year") %>% collect()
    d$year <- as.integer(as.character(d$year))
  } else {
    f <- file.path(root, "part-0.parquet")
    if (!file.exists(f)) { cat(sprintf("  %-26s skipped (no part-0.parquet)\n", tbl)); next }
    d <- read_parquet(f)
  }
  out <- file.path(CSV, paste0(tbl, ".csv"))
  write.csv(d, out, row.names = FALSE, na = "")
  cat(sprintf("  %-26s %10s rows -> %s\n", tbl, format(nrow(d), big.mark = ","), basename(out)))
}
cat("CSV layer written to ", CSV, "\n", sep = "")

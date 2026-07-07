#!/usr/bin/env Rscript
# Convert a raw EXIOBASE 3 pxp folder (pymrio .txt layout) into the {Z,x,Y}.rds files that
# prep_exiobase_L.R expects:
#   Z.rds : numeric matrix 9800 x 9800
#   x.rds : data.frame(region, sector, indout)
#   Y.rds : numeric matrix 9800 x 343
# pymrio layout: Z/Y have 2 column-header rows + 1 index-name row = 3 rows before data, and
# 2 index columns (region, sector). x is a flat table with 1 header row. (9800 = 49 regions x
# 200 products; Y has 343 = 49 x 7 final-demand categories.)
# Usage: Rscript code/prep/prep_exiobase_rds.R <path-to-IOT_YYYY_pxp>
suppressPackageStartupMessages(library(data.table))

d <- commandArgs(trailingOnly = TRUE)[1]
stopifnot(!is.na(d), dir.exists(d))

# Z: skip 2 header rows, drop 2 index cols -> 9800 x 9800
Zdt <- fread(file.path(d, "Z.txt"), skip = 3, header = FALSE, showProgress = FALSE)
Z <- as.matrix(Zdt[, -(1:2)]); storage.mode(Z) <- "double"
stopifnot(nrow(Z) == ncol(Z))
saveRDS(Z, file.path(d, "Z.rds")); cat(sprintf("Z.rds: %d x %d\n", nrow(Z), ncol(Z)))

# Y: skip 2 header rows, drop 2 index cols -> 9800 x 343
Ydt <- fread(file.path(d, "Y.txt"), skip = 3, header = FALSE, showProgress = FALSE)
Y <- as.matrix(Ydt[, -(1:2)]); storage.mode(Y) <- "double"
saveRDS(Y, file.path(d, "Y.rds")); cat(sprintf("Y.rds: %d x %d\n", nrow(Y), ncol(Y)))

# x: nr_header=1, 2 index cols (region, sector) + value col(s). Keep the total-output column.
xdt <- fread(file.path(d, "x.txt"), skip = 1, header = FALSE, showProgress = FALSE)
xout <- data.frame(region = as.character(xdt[[1]]),
                   sector = as.character(xdt[[2]]),
                   indout = as.numeric(xdt[[ncol(xdt)]]),
                   stringsAsFactors = FALSE)
saveRDS(xout, file.path(d, "x.rds"))
cat(sprintf("x.rds: %d rows ; sum(indout)=%.4g\n", nrow(xout), sum(xout$indout)))

stopifnot(nrow(Z) == nrow(xout), nrow(Y) == nrow(xout))
cat("OK\n")

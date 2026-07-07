#!/usr/bin/env Rscript
# Compute the EXIOBASE Leontief inverse L = (I - A)^-1, with A = Z * diag(1/x), and
# repackage {Z, L, x, Y} into the per-year `.RData` files that steps 18-20 load()
# from .../exiobase/pxp/{YEAR}_{Z,L,x,Y}.RData (objects named Z / L / x / Y).
#
# Source: data/exiobase/pxp/IOT_{YEAR}_pxp/{Z,x,Y}.rds  (uploaded EXIOBASE 3 pxp).
# Note  : x = the `indout` (total output) column; A divides each Z column by it.
#         The 9800x9800 dense inverse needs ~2 GB RAM and ~1-2 min per year.
#
# Usage : Rscript code/prep/prep_exiobase_L.R [YEAR]            # default 2020
#         Rscript code/prep/prep_exiobase_L.R 2013
suppressPackageStartupMessages(library(Matrix))

year <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(year)) year <- 2020
d <- sprintf("data/exiobase/pxp/IOT_%d_pxp", year)
out <- "data/exiobase/pxp"
stopifnot(dir.exists(d))

Z <- as.matrix(readRDS(file.path(d, "Z.rds")))
xdf <- readRDS(file.path(d, "x.rds"))
x <- as.numeric(xdf$indout)
names(x) <- paste(xdf$region, xdf$sector, sep = "_")
Y <- as.matrix(readRDS(file.path(d, "Y.rds")))
dimnames(Z) <- list(names(x), names(x))   # label region_sector (was generic 1..N / V..)

# technical coefficients A = Z / x (column-wise); x==0 -> 0
A <- sweep(Z, 2, x, "/")
A[!is.finite(A)] <- 0

cat(sprintf("[exiobase L] %d: inverting (I - A), %d x %d ...\n", year, nrow(A), ncol(A)))
t0 <- Sys.time()
L <- solve(diag(nrow(A)) - A)
dimnames(L) <- dimnames(Z)
cat(sprintf("[exiobase L] done in %.1f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

save(Z, file = sprintf("%s/%d_Z.RData", out, year))
save(L, file = sprintf("%s/%d_L.RData", out, year))
save(x, file = sprintf("%s/%d_x.RData", out, year))
save(Y, file = sprintf("%s/%d_Y.RData", out, year))
cat(sprintf("[exiobase L] wrote %s/%d_{Z,L,x,Y}.RData\n", out, year))

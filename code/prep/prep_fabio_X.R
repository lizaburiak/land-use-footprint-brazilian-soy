#!/usr/bin/env Rscript
# Derive FABIO total output X from the balanced MRIO (x = rowSums(Z) + rowSums(Y)),
# since the uploaded FABIO v2 data has Z/Y/E but not X. X is what step 17 needs to
# build the Leontief inverse (A = Z / X; it does NOT use Y in the math).
#
# Output: data/fabio/v2/X.rds  — matrix [process x year], columns named by year
#         (the layout step 17 reads as X[, as.character(year)]).
#
# Usage: Rscript code/prep/prep_fabio_X.R
suppressPackageStartupMessages(library(Matrix))

ZF <- "data/fabio/v2/Z_mass_b.rds"
YF <- "data/fabio/v2/Y_b.rds"
stopifnot(file.exists(ZF), file.exists(YF))
Z <- readRDS(ZF)   # list by year, sparse 22263 x 22263
Y <- readRDS(YF)   # list by year, sparse 22263 x 905

years <- intersect(names(Z), names(Y))
X <- vapply(years, function(y) as.numeric(rowSums(Z[[y]]) + rowSums(Y[[y]])),
            numeric(nrow(Z[[years[1]]])))
rownames(X) <- rownames(Z[[years[1]]])
colnames(X) <- years

saveRDS(X, "data/fabio/v2/X.rds")
cat(sprintf("wrote data/fabio/v2/X.rds  [%d x %d]  years %s\n",
            nrow(X), ncol(X), paste(range(as.integer(years)), collapse = "-")))
cat(sprintf("  sanity: 2020 total output sum = %.3e\n", sum(X[, "2020"])))

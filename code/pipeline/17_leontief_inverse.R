# ============================================================================
# REPRODUCTION PORT — FABIO MRIO / land-use footprint backend (steps 13-21).
# Year-parameterized continuation of steps 00-12. Minimal-delta fork of the
# matching archive/code_old_stefan/ script.
#
# REQUIRES WU/fineprint FABIO + EXIOBASE data that is NOT present on this
# machine (see WHAT_IS_MISSING.md section 6):
#   - data/generated/fabio/*                     (FABIO MRIO matrices)
#   - archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/*   (concordances / tidy data)
#   - /mnt/nfs_fineprint/tmp/{exiobase,fabio}/*      (EXIOBASE + FABIO v2, NFS)
# These stages cannot run here without that infrastructure.
# ============================================================================
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
# Fail fast with a clear message if none of the FABIO data is available.
if (!dir.exists("/mnt/nfs_fineprint") &&
    length(list.files("data/generated/fabio")) == 0 &&
    length(list.files("archive/fabio_stefan/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See WHAT_IS_MISSING.md section 6.", call. = FALSE)
}
# NOTE: year-keyed file paths below are parameterized via YEAR, but full
# year-extension is unvalidated until FABIO data is available to run against.

### Leontief inverse ###

# what is changed:
# - calculation of A matrix made more efficient by sparse approach
# - inversion of matrix (solve) is done with sparse = TRUE to get output as sparse dgC matrix and improve speed

library(data.table)
library(Matrix)

write = TRUE

# Leontief inverse ---

prep_solve <- function(year, Z, Y, X,
                       adj_X = FALSE, adj_A = TRUE, adj_diag = FALSE,
                       adj_prod = TRUE, prod_cap = 0.9999) {

  if(adj_X) {X <- X + 1e-10}

  # A <- Matrix(0, nrow(Z), ncol(Z))
  # idx <- X != 0
  # idx <- c(1:nrow(A))[idx] # CHANGED index here
  # A[, idx] <- t(t(Z[, idx]) / X[idx])

  # CHANGED: use sparse matrix method here as well
  A <- Z
  A@x <- A@x / rep.int(X, diff(A@p))

  if(adj_A) {A[A < 0] <- 0}
  if(adj_diag) {diag(A)[diag(A) == 1] <- 1 - 1e-10}

  # Productiveness safeguard (2026-07): a column of A with sum >= 1 is non-productive
  # (intermediate use >= gross output), which makes I-A singular and drives (I-A)^-1
  # into large negative entries. The FABIO base is non-productive in ~3,600 columns
  # every year; the MRIO build normally absorbs this, but the 2020 build does not
  # (COVID-year base: outputs collapsed, use structure did not) -> ~3,200 non-productive
  # FABIO-country columns and 55k negative Leontief entries (the Philippines footprint
  # went net-negative as a result). Cap each offending column's sum just below 1 by
  # proportional down-scaling so the system is productive. Columns already productive
  # (colSum < prod_cap) are untouched, so productive-build years (2010-2019) are a no-op.
  if(adj_prod) {
    cs <- Matrix::colSums(A)
    bad <- which(cs >= prod_cap)
    if(length(bad) > 0) {
      d <- rep(1, ncol(A)); d[bad] <- prod_cap / cs[bad]
      A <- A %*% Matrix::Diagonal(x = d)
      cat(sprintf("[17] productiveness safeguard (%d): capped %d non-productive column(s) (max colSum %.1f -> %.4f)\n",
                  year, length(bad), max(cs), prod_cap))
    } else {
      cat(sprintf("[17] productiveness safeguard (%d): no non-productive columns (max colSum %.4f); no-op\n",
                  year, max(cs)))
    }
  }

  L <- .sparseDiagonal(nrow(A)) - A
  
  lu(L) # Computes LU decomposition and stores it in L
  
  L_inv <- solve(L, tol = .Machine[["double.eps"]], sparse = TRUE) # use sparse = TRUE!!!

  dimnames(L_inv) <- dimnames(Z)
  
  return(L_inv)
}

##
years <- YEAR
years_singular <- c(1986,1994,2002,2009)

Z_m <- readRDS("data/generated/fabio/Z_mass.rds")
Z_v <- readRDS("data/generated/fabio/Z_value.rds")
Y <- readRDS("data/generated/fabio/Y.rds")
X <- readRDS("data/generated/fabio/X.rds")


for(year in years){
  
  print(year)
  
  adjust <- ifelse(year %in% years_singular, TRUE, FALSE)
  
  L <- prep_solve(year = year, Z = Z_m[[as.character(year)]],
                  Y = Y[[as.character(year)]], X = X[, as.character(year)],
                  adj_diag = adjust)
  if (write) saveRDS(L, paste0("data/generated/fabio/", year, "_L_mass.rds"))
  
  L <- prep_solve(year = year, Z = Z_v[[as.character(year)]],
                  Y = Y[[as.character(year)]], X = X[, as.character(year)],
                  adj_diag = adjust)
  if (write) saveRDS(L, paste0("data/generated/fabio/", year, "_L_value.rds"))
  
}


rm(list = ls())
gc()

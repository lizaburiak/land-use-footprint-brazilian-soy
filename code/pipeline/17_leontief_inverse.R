# FABIO MRIO / land-use footprint stage (steps 13-21). Year-parameterized
# fork of the matching archive/code_old_stefan/ script. Needs the FABIO v2 +
# EXIOBASE backends (data/fabio/v2, data/exiobase, data/generated/fabio; see DATA.md).
# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR (e.g. isolated worker dirs).
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")

YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
if (!dir.exists("/mnt/nfs_fineprint") &&
    length(list.files(file.path(DATA_DIR, "generated/fabio"))) == 0 &&
    length(list.files("archive/fabio_stefan/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See DATA.md.", call. = FALSE)
}

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
                       adj_prod = FALSE, prod_cap = 0.9999) {

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

  # Column cap, OFF by default since 2026-10-06 (adj_prod = FALSE). It scaled every column of A
  # whose sum was >= prod_cap down to prod_cap, on the argument that such a column is
  # non-productive. That only holds when all rows share one unit. Here rows are head, thousand
  # head and tonnes, so column sums above 1 are normal: 430 birds or 11 pigs per tonne of meat,
  # 1.05 t of beans per tonne of oil plus cake. The cap hit 2,900-3,600 columns in EVERY year
  # (not only 2020, for which it was written), broke land conservation and removed 3.9-4.8 Mha
  # of Brazilian soy land per year from the footprint, including nearly all poultry before 2010
  # (birds are counted in head in the v1.1 inputs). Step 20 now checks the land identity instead.
  # Evidence: generated/diagnostics/2026-10-05_input_audit/REPORT_input_audit_2026-10-05.md.
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

Z_m <- readRDS(file.path(DATA_DIR, "generated/fabio/Z_mass.rds"))
Z_v <- readRDS(file.path(DATA_DIR, "generated/fabio/Z_value.rds"))
Y <- readRDS(file.path(DATA_DIR, "generated/fabio/Y.rds"))
X <- readRDS(file.path(DATA_DIR, "generated/fabio/X.rds"))


for(year in years){
  
  print(year)
  
  adjust <- ifelse(year %in% years_singular, TRUE, FALSE)
  
  L <- prep_solve(year = year, Z = Z_m[[as.character(year)]],
                  Y = Y[[as.character(year)]], X = X[, as.character(year)],
                  adj_diag = adjust)
  if (write) saveRDS(L, paste0(DATA_DIR, "/generated/fabio/", year, "_L_mass.rds"))
  
  L <- prep_solve(year = year, Z = Z_v[[as.character(year)]],
                  Y = Y[[as.character(year)]], X = X[, as.character(year)],
                  adj_diag = adjust)
  if (write) saveRDS(L, paste0(DATA_DIR, "/generated/fabio/", year, "_L_value.rds"))
  
}


rm(list = ls())
gc()

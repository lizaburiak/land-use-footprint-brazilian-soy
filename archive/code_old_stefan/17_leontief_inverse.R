### Leontief inverse ###

# what is changed:
# - calculation of A matrix made more efficient by sparse approach
# - inversion of matrix (solve) is done with sparse = TRUE to get output as sparse dgC matrix and improve speed

library(data.table)
library(Matrix)

write = TRUE

# Leontief inverse ---

prep_solve <- function(year, Z, Y, X,
                       adj_X = FALSE, adj_A = TRUE, adj_diag = FALSE) {
  
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
  
  L <- .sparseDiagonal(nrow(A)) - A
  
  lu(L) # Computes LU decomposition and stores it in L
  
  L_inv <- solve(L, tol = .Machine[["double.eps"]], sparse = TRUE) # use sparse = TRUE!!!

  dimnames(L_inv) <- dimnames(Z)
  
  return(L_inv)
}

##
years <- seq(2013, 2013)
years_singular <- c(1986,1994,2002,2009)

Z_m <- readRDS("results/intermediate/FABIO/Z_mass.rds")
Z_v <- readRDS("results/intermediate/FABIO/Z_value.rds")
Y <- readRDS("results/intermediate/FABIO/Y.rds")
X <- readRDS("results/intermediate/FABIO/X.rds")


for(year in years){
  
  print(year)
  
  adjust <- ifelse(year %in% years_singular, TRUE, FALSE)
  
  L <- prep_solve(year = year, Z = Z_m[[as.character(year)]],
                  Y = Y[[as.character(year)]], X = X[, as.character(year)],
                  adj_diag = adjust)
  if (write) saveRDS(L, paste0("results/intermediate/FABIO/", year, "_L_mass.rds"))
  
  L <- prep_solve(year = year, Z = Z_v[[as.character(year)]],
                  Y = Y[[as.character(year)]], X = X[, as.character(year)],
                  adj_diag = adjust)
  if (write) saveRDS(L, paste0("results/intermediate/FABIO/", year, "_L_value.rds"))
  
}


rm(list = ls())
gc()

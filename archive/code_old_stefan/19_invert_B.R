
#### invert the hybrid B quadrant #######

# Block matrix inversion:
# B^-1 = -(A - BD^-1C)^-1 BD^-1
# for C = 0 -->  B^-1 = -A^-1 BD^-1

library(Matrix)

write = TRUE

#year=2013
years <- 2013
#versions <- c("")#,"losses/","wood/")
#version="losses/"

for(year in years){
  print(year)
  
  if(year<1995){
    load(paste0("/mnt/nfs_fineprint/tmp/exiobase/pxp/1995_L.RData"))
    load(paste0("/mnt/nfs_fineprint/tmp/exiobase/pxp/1995_x.RData"))
  } else {
    load(paste0("/mnt/nfs_fineprint/tmp/exiobase/pxp/", year, "_x.RData"))
    load(paste0("/mnt/nfs_fineprint/tmp/exiobase/pxp/", year, "_L.RData"))
  }
  
  D_inv <- as(L, "sparseMatrix") # L
  rm(L); gc()
  
  B <- readRDS(paste0("results/intermediate/FABIO/B.rds"))[[paste(year)]]
  #B <- t(t(B)/x)
  #B[!is.finite(B)] <- 0
  B@x <- B@x / rep.int(x, diff(B@p))
  B[B<0] <- 0
  B <- 0-B
  
  A_inv <- readRDS(paste0("results/intermediate/FABIO/", year, "_L_mass.rds"))
  B_inv <- -A_inv %*% B %*% D_inv  
  # B_inv <- as(B_inv, "dgCMatrix") # if D_inv is not already spares (might be faster)?
  saveRDS(B_inv, paste0("results/intermediate/FABIO/", year, "_B_inv_mass.rds"))
  
  A_inv <- readRDS(paste0("results/intermediate/FABIO/",  year, "_L_value.rds"))
  B_inv <- -A_inv %*% B %*% D_inv
  # B_inv <- as(B_inv, "dgCMatrix")
  if (write) saveRDS(B_inv, paste0("results/intermediate/FABIO/", year, "_B_inv_value.rds"))
  
}

rm(list = ls())
gc()



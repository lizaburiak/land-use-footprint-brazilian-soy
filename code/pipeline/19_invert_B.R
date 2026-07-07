# ============================================================================
# REPRODUCTION PORT — FABIO MRIO / land-use footprint backend (steps 13-21).
# Year-parameterized continuation of steps 00-12. Minimal-delta fork of the
# matching archive/code_old_stefan/ script.
#
# REQUIRES WU/fineprint FABIO + EXIOBASE data that is NOT present on this
# machine (see DATA.md):
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
       "See DATA.md.", call. = FALSE)
}
# NOTE: year-keyed file paths below are parameterized via YEAR, but full
# year-extension is unvalidated until FABIO data is available to run against.


#### invert the hybrid B quadrant #######

# Block matrix inversion:
# B^-1 = -(A - BD^-1C)^-1 BD^-1
# for C = 0 -->  B^-1 = -A^-1 BD^-1

library(Matrix)

write = TRUE

#year=2013
years <- YEAR
#versions <- c("")#,"losses/","wood/")
#version="losses/"

for(year in years){
  print(year)
  
  if(year<1995){
    load(paste0("data/exiobase/pxp/1995_L.RData"))
    load(paste0("data/exiobase/pxp/1995_x.RData"))
  } else {
    load(paste0("data/exiobase/pxp/", year, "_x.RData"))
    load(paste0("data/exiobase/pxp/", year, "_L.RData"))
  }
  
  D_inv <- as(L, "sparseMatrix") # L
  rm(L); gc()
  
  B <- readRDS(paste0("data/generated/fabio/B.rds"))[[paste(year)]]
  #B <- t(t(B)/x)
  #B[!is.finite(B)] <- 0
  B@x <- B@x / rep.int(x, diff(B@p))
  B[B<0] <- 0
  B <- 0-B
  
  A_inv <- readRDS(paste0("data/generated/fabio/", year, "_L_mass.rds"))
  B_inv <- -A_inv %*% B %*% D_inv  
  # B_inv <- as(B_inv, "dgCMatrix") # if D_inv is not already spares (might be faster)?
  saveRDS(B_inv, paste0("data/generated/fabio/", year, "_B_inv_mass.rds"))
  
  A_inv <- readRDS(paste0("data/generated/fabio/",  year, "_L_value.rds"))
  B_inv <- -A_inv %*% B %*% D_inv
  # B_inv <- as(B_inv, "dgCMatrix")
  if (write) saveRDS(B_inv, paste0("data/generated/fabio/", year, "_B_inv_value.rds"))
  
}

rm(list = ls())
gc()



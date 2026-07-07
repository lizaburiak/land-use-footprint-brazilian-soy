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

## create hybrid MRIO using Exiobase

library(Matrix)
library(parallel)
library(data.table)

write = TRUE

#Matrices necessary
sup <- read.csv("data/fabio/v2/hybrid/fabio-exio_sup.csv") 
use <- read.csv("data/fabio/v2/hybrid/fabio-exio_use.csv")
conc <- read.csv("data/fabio/v2/hybrid/fabio-exio_conc.csv")

cbs <- readRDS("data/generated/fabio/cbs_final.rds")
areas_full <- (unique(cbs[,.(area_code, area)])) # sort could be avoided by using setkey before saving cbs_final!

conc <- conc[conc$FAO_code %in% areas_full$area_code,]
conc$FABIO_code <- 1:nrow(conc)
# Move NAs to extra column to drop, allocate at some point
conc$EXIOBASE_code[is.na(conc$EXIOBASE_code)] <- 50

# extend for MUs
areas_mun <- areas_full[area_code > 1000,]
# MUs have Exiobase counterpart in Brazil
areas_mun[,`:=`(ISO = NA, EXIOBASE = NA, EXIOBASE_code = 34, FABIO_code = nrow(conc)+(1:nrow(areas_mun))) ]
setnames(areas_mun, c("area", "area_code"), c("Country", "FAO_code"))
conc <- rbind(conc, areas_mun)

as_matrix <- function(x) {
  y <- as.matrix(x[5:ncol(x)])
  y_rowSums <- rowSums(y, na.rm = TRUE)
  if(!all(x[["Total"]] == y_rowSums)) stop()
  y[is.na(y)] <- 0
  #dimnames(y) <- NULL
  rownames(y) <- as.character(x$Com.Code)
  Matrix(y)
}
Sup <- as_matrix(sup)
Use <- as_matrix(use)
Cou_NA <- sparseMatrix(i = conc$FABIO_code, j = conc$EXIOBASE_code) * 1
dimnames(Cou_NA) <- list(conc$FAO_code, sort(unique(conc$EXIOBASE_code)))
Cou <- Cou_NA[, 1:49] # Remove 50th column of countries missing in EXIOBASE


# Function to create the hybrid part for a certain year
hybridise <- function(year, Sup, Use, Cou, Y_all) {
  
  require(Matrix) # Necessary for forked processes
  
  # Read EXIOBASE Z and FABIO Y
  Y <- Y_all[[as.character(year)]]
  if(year<1995){
    load(paste0("data/exiobase/pxp/1995_Z.RData"))
  } else {
    load(paste0("data/exiobase/pxp/", year, "_Z.RData"))
  }
  
  # Calculate Tech matrices for the 49 EXIO countries
  # --> national parts of Z matrix
  Tec <- vector("list", 49)
  for(i in 1:49) {
    tmp <- Matrix(0, nrow = 200, ncol = 200)
    for(j in 1:49)
      tmp <- tmp + Z[(1 + 200 * (j - 1)):(200 * j), 
                     (1 + 200 * (i - 1)):(200 * i)]
    Tec[[i]] <- tmp 
  }
  
  # Get the columns of Y containing the other use category to allocate
  Oth <- Y[, grep("other$", colnames(Y))]
  colnames(Oth) <- sub("_.*", "", colnames(Oth)) # use country names below
  
  
  # Match FABIO countries with EXIOBASE countries and restructure the Other use matrix
  ## NOTE: what about the other use of MU oil in other countries? Should be included in trade linking of Y with supply shares!
  Oth_exio <- Oth %*% Cou[colnames(Oth),]# use character indexing instead of Cou[1:ncol(Oth),]
  comms <- sub(".*_", "", rownames(Oth_exio))
  nprod <- length(unique(comms))# nrow(Oth) / 189 # 192
  
  # Create matrix for sector matching
  T <- vector("list", 49)
  for(i in 1:49) {
    T[[i]] <- Sup[1:nprod,] %*% Tec[[i]] * Use[1:nprod,]
    T[[i]] <- T[[i]] / rowSums(T[[i]])
    T[[i]][is.na(T[[i]])] <- 0
    rownames(T[[i]]) <- unique(comms)
  }
  
  # Compute the hybrid part from Oth and T
  B <- Matrix(0, nrow = nrow(Y), ncol = 49 * 200, sparse = TRUE) # nrow = 192 * nprod
  for(i in 1:49) {
    B[, (1 + 200 * (i - 1)):(200 * i)] <-
      T[[i]][comms,] * Oth_exio[, i] # do.call(rbind, replicate(192, T[[i]], simplify = FALSE))
  }
  
  # TODO: why is is sum(B) < sum(Oth_exio)
  # use in 50 region?
  # products without supply or use in Exiobase (fooder crops, grazing, live animals)?
  #sum(B)
  #sum(Oth_exio[as.numeric(sub("_.*","", rownames(Oth_exio)))>1000,])
  #sum(B[as.numeric(sub("_.*","", rownames(B)))>1000,])
  

  # ADDED: remove use allocated to B from the Y matrix!
  
  # aggregate B by using country
  sum_mat <- Diagonal(49)[rep(1:49, each = 200),]
  B_country <- B %*% sum_mat
  # compute residual to original other use by country (non-allocated other use)
  Oth_resid <- Oth_exio - B_country
  Oth_resid[Oth_resid < 0] <- 0 # just clear some very small negatives
  
  # version of FABIO other use excluding countries without counterpart in Exiobase
  Oth_no50 <- Oth[,colnames(Oth) %in% conc$FAO_code[conc$EXIOBASE_code != 50]]
  # mapping of FABIO sectors to Exiobase sectors
  fabio_to_exio <- conc$EXIOBASE_code[match(as.numeric(colnames(Oth_no50)), conc$FAO_code)]
  # compute shares to split residuals according to countries original share in aggregate Oth_exio
  Oth_shares <- Oth_no50/Oth_exio[,fabio_to_exio]
  Oth_shares[is.na(Oth_shares)] <- 0
  # split residuals back into FABIO format according to shares
  Oth_resid_alloc <- Oth_shares * Oth_resid[,fabio_to_exio]
  # replace original Oth with residuals
  Oth_new <- Oth
  Oth_new[, colnames(Oth_resid_alloc)] <- Oth_resid_alloc
  # replace Oth in full Y table
  Y[, grep("other$", colnames(Y))] <- Oth_new
  
  # alternative option (same result):
  # Oth_no50 <- Oth[,colnames(Oth) %in% conc$FAO_code[conc$EXIOBASE_code != 50]]
  # fabio_to_exio <- conc$EXIOBASE_code[match(as.numeric(colnames(Oth_no50)), conc$FAO_code)]
  # Oth_shares <- Oth_no50/Oth_exio[,fabio_to_exio]
  # Oth_shares[is.na(Oth_shares)] <- 0
  # # split
  # Oth_resid_alloc <- Oth_shares * Oth_resid[,fabio_to_exio]
  # # replace original Oth with residuals
  # Oth_new <- Oth
  # Oth_new[, colnames(Oth_resid_alloc)] <- Oth_resid_alloc
  
  # check sums: does allocated + unallocated Other use correspond to original Other use?
  all.equal(sum(Oth),   sum(B) + sum(Oth_new))
  all.equal(rowSums(Oth), rowSums(B) + rowSums(Oth_new))

  # TODO: why does B have these weird colnames?
  dimnames(B) <- list(rownames(Y), colnames(Z))
  rm(Z)
  return(list("B" = B, "Y" = Y))
}



# Execute -----------------------------------------------------------------

# Select fabio version or run loop

Y_all <- readRDS("data/generated/fabio/Y.rds")
  
# Setup to process in parallel
#  n_cores <- parallel::detectCores() - 2
#  cl <- parallel::makeCluster(n_cores)
  
# Years to calculate hybridised FABIO for
years <- YEAR
  
#output <- mclapply(cl, years, hybridise, Sup, Use, Cou, Y_all, mc.cores = detectCores())
output <- lapply(years, hybridise, Sup, Use, Cou, Y_all)
names(output) <- years

B <- lapply(output, `[[`, "B")
Y_hybrid <- lapply(output, `[[`, "Y")

if (write) {
  saveRDS(B,"data/generated/fabio/B.rds")
  saveRDS(Y_hybrid,"data/generated/fabio/Y_hybrid.rds")
}


rm(Y_all, output, B, Y_hybrid)
gc()
  

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
    length(list.files("data/fabio/v2/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See DATA.md.", call. = FALSE)
}
# NOTE: year-keyed file paths below are parameterized via YEAR, but full
# year-extension is unvalidated until FABIO data is available to run against.

### MRIO ###

# what is changed:
# - calculation of transformation matrix made more efficient by sparse approach
# - re-balancing changed to use character indexing and (optionally) to re-balance according to cbs production values

library(Matrix)

write = TRUE

# MRIO Table ---

mr_sup_m <- readRDS("data/generated/fabio/mr_sup_mass.rds")
mr_sup_v <- readRDS("data/generated/fabio/mr_sup_value.rds")
mr_use <- readRDS("data/generated/fabio/mr_use.rds")

# check for conformity
all.equal(rownames(mr_sup_m[[as.character(YEAR)]]), colnames(mr_use[[as.character(YEAR)]]))
all.equal(colnames(mr_sup_m[[as.character(YEAR)]]), rownames(mr_use[[as.character(YEAR)]]))

# Mass
trans_m <- lapply(mr_sup_m, function(sup) {
  # NB: a dense as.matrix(x / rowSums(x)) is not feasible for a matrix this large,
  # so we rescale via sparse-matrix indexing instead:
  #out <- as.matrix(x / rowSums(x))
  # --> make use of sparse matrix indexing: see https://stackoverflow.com/questions/39284774/column-rescaling-for-a-very-large-sparse-matrix-in-r
  # option 1:
  #out_t <- t(x)
  #out_t@x <- out_t@x / rep.int(colSums(out_t), diff(out_t@p))
  #out <- t(out_t)
  # option 2:
  out <- sup
  out@x <- out@x / rowSums(out)[(out@i+1)]
  ## TODO: double-check
   
  #out[!is.finite(out)] <- 0 # See Issue #75
  #return(as(out, "Matrix"))
  if(sum(is.na(out))) stop("NAs contained")
  return(out)
})

Z_m <- mapply(function(x, y) {
  x %*% y
}, x = mr_use, y = trans_m)

#Z_m <- lapply(Z_m, round)


# Value
trans_v <- lapply(mr_sup_v, function(x) {
  #out <- as.matrix(x / rowSums(x))
  #out[!is.finite(out)] <- 0 # See Issue #75
  
  out <- x
  out@x <- out@x / rowSums(out)[(out@i+1)]
  
  #return(as(out, "Matrix"))
  if(sum(is.na(out))) stop("NAs contained")
  return(out)
})

Z_v <- mapply(function(x, y) {
  x %*% y
}, x = mr_use, y = trans_v)

#Z_v <- lapply(Z_v, round)



# Rebalance row sums in Z and Y -----------------------------------------

library(data.table)
regions <- fread("data/fabio/v2/inst/regions_full.csv")
regions <- regions[cbs==TRUE]
items <- fread("data/fabio/v2/inst/items_full.csv")
nrcom <- nrow(items)
Y <- readRDS("data/generated/fabio/mr_use_fd.rds")
Y_orig <- readRDS("data/generated/fabio/mr_use_fd.rds")

# compute total use of each commodity by using country in mr_use and Z
agg_country <- function(mat){
  proc_countries <- as.numeric(sub("_.*", "", colnames(mat)))
  proc_countries[proc_countries > 1000] <- 21
  sum_mat <- as(sapply(unique(proc_countries),"==",proc_countries), "Matrix")*1
  dimnames(sum_mat) <- list(proc_countries, unique(proc_countries))
  mat_agg <- mat %*% sum_mat
}
mr_use_country <- lapply(mr_use, agg_country)
Z_m_country <- lapply(Z_m, agg_country)

# compute difference (i.e. lost inputs in Z)
use_diff <- Map(function(x,y){x-y}, mr_use_country, Z_m_country)

# add use_diff to Y balancing item of the respective using country
Y <- Map(function(y, diff){
  y[,paste0(colnames(diff),"_balancing")] <- 
    y[,paste0(colnames(diff),"_balancing")] + diff
  return(y)
  }, Y, use_diff)


# Rebalance remaining imbalances in row sums for each year
## CHANGED: to character indexing and optional balancing via original cbs supply by item
for(i in seq_along(Z_m)){

  X <- rowSums(Z_m[[i]]) + rowSums(Y[[i]])
  X_sup <- colSums(mr_sup_m[[i]])
  #X_use <- rowSums(mr_use[[i]]) + rowSums(Y_orig[[i]]) # Y already contains added balancing! --> use sup and deduct 
  bal <- X_sup - X
  #bal_use <- X_use - X
  

 # # or option 1 (standard)
 # #for(j in which(X < 0)){
 # for(j in names(which(X < 0))){
 #   #reg <- j %/% nrcom + 1 
 #   reg <- as.numeric(sub("_.*", "",j))
 #   reg <- ifelse(reg < 1000, reg, 21)
 #   #Y[[i]][j, paste0(regions[reg, code], "_balancing")] <-
 #   #  Y[[i]][j, paste0(regions[reg, code], "_balancing")] - X[j]
 #   Y[[i]][j, paste0(reg, "_balancing")] <-
 #     Y[[i]][j, paste0(reg, "_balancing")] - X[j]
 # }
  
  # or option 2: balance so total output matches supply
  #for(j in which(X < 0)){
  for(j in names(which(bal != 0))){
    #reg <- j %/% nrcom + 1 
    reg <- as.numeric(sub("_.*", "",j))
    reg <- ifelse(reg < 1000, reg, 21)
    #Y[[i]][j, paste0(regions[reg, code], "_balancing")] <-
    #  Y[[i]][j, paste0(regions[reg, code], "_balancing")] - X[j]
    Y[[i]][j, paste0(reg, "_balancing")] <-
      Y[[i]][j, paste0(reg, "_balancing")] + bal[j]
  }
  
  # check balance:
  all.equal(rowSums(Z_m[[i]]) + rowSums(Y[[i]]), X_sup)

}

# NOTE: why is balancing item adjusted with Z_m and not Z_v? --> rowSums are identical

# optional: round everything up to 8 digits
# Z_m <- lapply(Z_m, round, digits = 8)
# Z_v <- lapply(Z_v, round, digits = 8)
# Y <- lapply(Y, round, digits = 8)

# Derive total output X ---------------------------------------------

X <- mapply(function(x, y) {
  rowSums(x) + rowSums(y)
}, x = Z_m, y = Y)



# Store X, Y, Z variables
if (write){
  saveRDS(Z_m, "data/generated/fabio/Z_mass.rds")
  saveRDS(Z_v, "data/generated/fabio/Z_value.rds")
  saveRDS(Y, "data/generated/fabio/Y.rds")
  saveRDS(X, "data/generated/fabio/X.rds")
}



# # redistribute balancing over all uses proportionally ---------------------------------------------
# ###### NOT NEEDED ######
# 
# regions <- fread("data/fabio/v2/inst/regions_full.csv")
# regions <- regions[cbs==TRUE]
# items <- fread("data/fabio/v2/inst/items_full.csv")
# nrcom <- nrow(items)
# nrreg <- nrow(regions)
# nrfd <- ncol(Y[[1]])/nrreg
# i=28
# for(i in seq_along(Z_m)){
#   reg=1
#   for(reg in seq_len(nrow(regions))){
#     z_range <- (nrcom*(reg-1)+1):(nrcom*reg)
#     y_range <- (nrfd*(reg-1)+1):(nrfd*reg)
#     Z_sum <- rowSums(Z_m[[i]][, z_range])
#     Y_sum <- rowSums(Y[[i]][, y_range])
#     balancing <- as.vector(Y[[i]][, grepl("balancing", colnames(Y[[i]]))][, reg])
#     balancing <- balancing / as.vector(Z_sum + Y_sum - balancing)
#     balancing[!is.finite(balancing)] <- 0
#     Z_m[[i]][, z_range] <- Z_m[[i]][, z_range] * (1 + balancing)
#     Z_v[[i]][, z_range] <- Z_v[[i]][, z_range] * (1 + balancing)
#     Y[[i]][, y_range] <- Y[[i]][, y_range] * (1 + balancing)
#   }
# }

#saveRDS(Z_m, "/mnt/nfs_fineprint/tmp/fabio/v2/Z_mass_b.rds")
#saveRDS(Z_v, "/mnt/nfs_fineprint/tmp/fabio/v2/Z_value_b.rds")
#saveRDS(Y, "/mnt/nfs_fineprint/tmp/fabio/v2/Y_b.rds")


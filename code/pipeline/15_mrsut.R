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
    length(list.files("data/fabio/v2/inst")) == 0) {
  stop("[FABIO stage] FABIO/EXIOBASE data not available locally. This step needs ",
       "WU/fineprint's FABIO+EXIOBASE infrastructure (data/generated/fabio/, ",
       "archive/fabio_stefan/{inst,tidy,FABIO_hybrid}/, /mnt/nfs_fineprint/...). ",
       "See WHAT_IS_MISSING.md section 6.", call. = FALSE)
}
# NOTE: year-keyed file paths below are parameterized via YEAR, but full
# year-extension is unvalidated until FABIO data is available to run against.

### multi-regional supply and use tables

# what is changed:
# - now uses correct re-export-free btd
# - Brazilian municipalities are added only for the relevant processes
# - matrix indexing is now done by row/column names (character), as country-process/item structure is not regular any more
# - final demand: separate handling of negative stock_additions (= withdrawals) in supply shares, always assigning them to domestic source (supply share = 1)
# - in final mr_use/mr_use_fd table, municipal livestock processes and final demand use of soy is aggregated to national pendants
# - some efficiency fixes necessary due to now larger tables
# - remove rounding to avoid rounding errors
# - calculations are restricted to 2013
# - the whole process ensures that supply/use by origin-specific commodity conform with cbs numbers and remain balanced


library(data.table)
library(Matrix)
source("code/shared/fabio_tidy_functions.R")

write = TRUE

regions <- fread("data/fabio/v2/inst/regions_full.csv")
items <- fread("data/fabio/v2/inst/items_full.csv")

sup <- readRDS("data/generated/fabio/sup_final.rds")
cbs <- readRDS("data/generated/fabio/cbs_final.rds")
btd <- readRDS(paste0("data/generated/outputs/12_", YEAR, "/btd_final.rds"))

use <- readRDS("data/generated/fabio/use_final.rds")
use_fd <- readRDS("data/generated/fabio/use_fd_final.rds")

years <- YEAR
areas <- sort(unique(cbs$area_code)) # sort could be avoided by using setkey before saving cbs_final!
processes <- sort(unique(use$proc_code))
commodities <- sort(unique(use$comm_code))

# areas without Brazilian municipalities
areas_w <- areas[areas < 1000]
# areas without Brazil but with Brazilian municipalities
areas_soy <- areas[areas != 21]
# soybean and non-soybean commodities
commodities_soy <- unique(use$comm_code[grepl("Soyabean", use$item)])
commodities_w <- commodities[!commodities %in% commodities_soy]
# soybean processes
processes_soy <- unique(sup$proc_code[grepl("Soyabean", sup$item)])
processes_w <- processes[!processes %in% processes_soy]
# processes relevant for municipalities as users (including besides soy processes the livestock husbandry processes)
processes_mun_use <- sort(unique(use$proc_code[use$area_code > 1000]))


# Supply --------------------------------------------

# Template to always get full tables
template <- data.table(expand.grid(
  proc_code = processes, comm_code = commodities, stringsAsFactors = FALSE))
setkey(template, proc_code, comm_code)

# List with block-diagonal supply matrices, per year
mr_sup_mass <- lapply(years, function(x) {
  
  matrices <- lapply(areas, function(y, sup_y) {
    
    # Get supply for area y and merge with the template
    sup_x <- sup_y[area_code == y, .(proc_code, comm_code, production)]
    out <- if(nrow(sup_x) == 0) {
      template[, .(proc_code, comm_code, production = 0)]
    } else {merge(template, sup_x, all.x = TRUE)}
    ## CHANGED: for MUs, use only soy item commodities and processes
    # for municipalities as suppliers, only the three soybean commodities, which are produced in two processes, are relevant
    if(y > 1000) out <- out[comm_code %in% commodities_soy & proc_code %in% processes_soy,] # out[comm_code %in% commodities_soy & proc_code %in% processes_soy,]
    ## CHANGED: for Brazil, remove soy item commodities and processes 
    # for Brazil as a supplier, we take out the production of soybean products
    if(y == 21) out <- out[!(comm_code %in% commodities_soy) & !(proc_code %in% processes_soy),]
    
    # Cast the datatable to convert into a matrix
    out <- tryCatch(data.table::dcast(out, proc_code ~ comm_code,
                                      value.var = "production", fun.aggregate = sum, na.rm = TRUE, fill = 0),
                    error = function(e) {stop("Issue at ", x, "-", y, ": ", e)})

    
    # Return a (sparse) matrix of supply for region y and year x
    ## CHANGED: add area code as prefix to names
    return(Matrix(data.matrix(out[, c(-1)]), sparse = TRUE,
                  dimnames = list(paste0(y,"_",out$proc_code), paste0(y,"_",colnames(out)[-1]))))
    #return(Matrix(data.matrix(out[, c(-1)]), sparse = TRUE,
    #              dimnames = list(out$proc_code, colnames(out)[-1])))
    
  }, sup_y = sup[year == x, .(area_code, proc_code, comm_code, production)])
  
  # Return a block-diagonal matrix with all countries for year x
  # CHANGED: make sure that the bdiag item has named rows/columns
  mr_sup <- bdiag(matrices)
  colnames(mr_sup)  <- do.call(c, lapply(matrices, colnames))
  rownames(mr_sup) <- do.call(c, lapply(matrices, rownames))
  return(mr_sup)
  
})

# Convert to monetary values
sup[!is.na(price) & is.finite(price), value := production * price]
# If no price available, keep physical quantities
sup[is.na(price) | !is.finite(price), value := production]

# List with block-diagonal supply matrices in value, per year
mr_sup_value <- lapply(years, function(x) {
  
  matrices <- lapply(areas, function(y, sup_y) {
    # Get supply for area y and merge with the template
    sup_x <- sup_y[area_code == y, .(proc_code, comm_code, value)]
    out <- if(nrow(sup_x) == 0) {
      template[, .(proc_code, comm_code, value = 0)]
    } else {merge(template, sup_x, all.x = TRUE)}
    ## CHANGED: for MUs, use only soy item commodities and processes 
    if(y > 1000) out <- out[comm_code %in% commodities_soy & proc_code %in% processes_soy,] # out[comm_code %in% commodities_soy & proc_code %in% processes_soy,]
    ## CHANGED: for Brazil, remove soy item commodities and processes
    if(y == 21) out <- out[!(comm_code %in% commodities_soy) & !(proc_code %in% processes_soy),]
    
    # Cast the datatable to convert into a matrix
    out <- tryCatch(data.table::dcast(out, proc_code ~ comm_code,
                                      value.var = "value", fun.aggregate = sum, na.rm = TRUE, fill = 0),
                    error = function(e) {stop("Issue at ", x, "-", y, ": ", e)})
    
    ## CHANGED: add area code as prefix to names
    return(Matrix(data.matrix(out[, c(-1)]), sparse = TRUE,
                  dimnames = list(paste0(y,"_",out$proc_code), paste0(y,"_",colnames(out)[-1]))))
    
  }, sup_y = sup[year == x, .(area_code, proc_code, comm_code, value)])
  
  # Return a block-diagonal matrix with all countries for year x
  # CHANGED: make sure that the bdiag item has named rows/columns
  mr_sup <- bdiag(matrices)
  colnames(mr_sup)  <- do.call(c, lapply(matrices, colnames))
  rownames(mr_sup) <- do.call(c, lapply(matrices, rownames))
  return(mr_sup)
})

names(mr_sup_mass) <- names(mr_sup_value) <- years

if (write){
  saveRDS(mr_sup_mass, "data/generated/fabio/mr_sup_mass.rds")
  saveRDS(mr_sup_value, "data/generated/fabio/mr_sup_value.rds")
}

rm(sup)

# Bilateral supply shares ---------------------------------------

# Template to always get full tables
## CHANGED: modify to contain soy trade on MUN basis
template <- data.table(expand.grid(
  from_code = areas_w, to_code = areas_w,
  comm_code = commodities_w, stringsAsFactors = FALSE))
# append soy trade including MUs instead of Brazil as a whole
# TODO: make sure soy imports in MUs are also correctly in the btd 
template_soy <- data.table(expand.grid(
  from_code = areas_soy, to_code = areas_soy,
  comm_code = commodities_soy, stringsAsFactors = FALSE))
template <- rbind(template, template_soy)
setkey(template, from_code, comm_code, to_code)
rm(template_soy)

# Yearly list of BTD in matrix format
# Note that btd_final includes not only re-export adjusted bilateral trade flows,
# but also domestic production for domestic use, i.e. it gives the sources
# (domestic and imported) of each country's domestic use of any item.
btd_cast <- lapply(years, function(x, btd_x) {
  # Cast to convert to matrix
  out <- data.table::dcast(merge(template,
                                 btd_x[year == x, .(from_code, to_code, comm_code, value)],
                                 by = c("from_code", "to_code", "comm_code"), all.x = TRUE),
                           from_code + comm_code ~ to_code,
                           value.var = "value", fun.aggregate = sum, na.rm = TRUE, fill = 0)
  
  return(Matrix(data.matrix(out[, c(-1, -2)]), sparse = TRUE,
                dimnames = list(paste0(out$from_code, "_", out$comm_code), # CHANGED: "-" to "_"
                                colnames(out)[c(-1, -2)])))
  
}, btd_x = btd[, .(year, from_code, to_code, comm_code, value)])

names(btd_cast) <- years

rm(btd, template )
if (write) saveRDS(btd_cast, "data/generated/fabio/btd_cast.rds")

# Get commodities and their positions from total supply for domestic use
comms <- gsub("(^[0-9]+)_(c[0-9]+)", "\\2", rownames(btd_cast[[1]])) # CHANGED: "-" to "_"
## CHANGED: the comms for soy appear 188 + n(MUN) times, while all others appear 189 times
# account for this irregular structure
#is <- as.numeric(vapply(unique(comms), function(x) {which(comms == x)},
#  numeric(length(unique(areas)))))
comm_inds <- sapply(unique(comms), function(x) {which(comms == x)})
is <- do.call(c,comm_inds)
#is <- as.numeric(sapply(unique(comms)[1:10], function(x) {which(comms == x)}))
#js <- rep(seq(unique(comms)), each = length(unique(areas)))
js <- rep(seq(unique(comms)), times = sapply(comm_inds, length))
# Matrix used to aggregate over commodities
agg <- Matrix::sparseMatrix(i = is, j = js, dimnames = list(dimnames(btd_cast[[1]])[[1]], unique(comms)))

# Build supply shares, per year
supply_shares <- lapply(btd_cast, function(x, agg, js) {
  # x_agg <- colSums(crossprod(x, agg)) # Aggregate total supply (all countries)
  x_agg <- crossprod(x, agg) # Aggregate total supply (per country) across all sources --> (domestic + imported amount of each good available in each country)
  denom <- t(x_agg) # data.table(as.matrix(t(x_agg)))
  # Calculate shares (per country)
  ## CHANGED: ensure correct repeat of denom by indexing
  #out <- as.matrix(x / as.matrix(denom[rep(seq(length(commodities)), length(unique(cbs$area_code))), ]))
  denom <- denom[match(comms, dimnames(x_agg)[[2]]), ] # [rep(seq(length(commodities)), times = sapply(comm_inds, length)), ]
  rm(x_agg)
  #out <- x / as(denom[rep(seq(length(commodities)), times = sapply(comm_inds, length)), ], "Matrix") # length(unique(cbs$area_code))
  out <- x/denom 
  out[!is.finite(out)] <- 0 # See Issue #75

  # source is domestic, where no sources given in btd_final --> for grazing!
  # CHANGED: adapt by using named indexing!

  #for(i in 1:length(areas_w)){
  #  out[nrow(items)*(i-1)+62, i] <- 1
  #}

  for(i in areas_w){
    out[paste0(i,"_c062"), as.character(i)] <- 1
  }

  return(as(out, "dgCMatrix"))
  #return(out)
}, agg = agg, js = js)

if (write) saveRDS(supply_shares, "data/generated/fabio/supply_shares.rds")
rm(agg)
gc()


# Use ------------------------------------------------------

# Template to always get full tables
# CHANGED: restrict to relevant processes for municipalities (soy, livestock) and Brazil (all except soy)
template <- data.table(expand.grid(
  area_code = areas_w[areas_w != 21], proc_code = processes, comm_code = commodities,
  stringsAsFactors = FALSE))
# for BRA
template_bra <- data.table(expand.grid(
  area_code = 21, proc_code = processes_w, comm_code = commodities,
  stringsAsFactors = FALSE))
# for municipalities as users, the relevant processes are the two soybean processes + all livestock processes using soy as feed
template_mun <- data.table(expand.grid(
  area_code = areas[areas > 1000], proc_code = processes_mun_use, comm_code = commodities,
  stringsAsFactors = FALSE))
template <- rbind(template, template_bra, template_mun)
setkey(template, area_code, proc_code, comm_code)
rm(template_bra, template_mun)

# List with use matrices, per year
use_cast <- lapply(years, function(x, use_x) {
  # Cast use to convert to a matrix
  out <- data.table::dcast(merge(template[, .(area_code, proc_code, comm_code)],
                                 use_x[year == x, .(area_code, proc_code, comm_code, use)],
                                 by = c("area_code", "proc_code", "comm_code"), all.x = TRUE),
                           comm_code ~ area_code + proc_code,
                           value.var = "use", fun.aggregate = sum, na.rm = TRUE, fill = 0)
  
  return(Matrix(data.matrix(out[, c(-1)]), sparse = TRUE,
                dimnames = list(out$comm_code, colnames(out)[-1])))
  
}, use_x = use[, .(year, area_code, proc_code, comm_code, use)])
names(use_cast) <- years
rm(use, template)

# Apply supply shares to the use matrix
mr_use <- mapply(function(x, y) {
  # Repeat use values, then adapted according to shares
  #mr_x <- x[rep(seq_along(commodities), length(areas)), ]
  ## CHANGED: adapt to new structure 
  # make sure that the origin of commodities in the rows conforms with the supply mr_sup matrix
  mr_x <- x[match(comms, rownames(x)), ] #match(comms, dimnames(x)[[1]])
  rownames(mr_x) <- rownames(y)
  
  #n_proc <- length(processes)
  
  areas_proc <- as.numeric(sub("_.*", "", colnames(mr_x)))
  y_proc <- y[,match(areas_proc, colnames(y))]
  
  ## CHANGED: The for loop is inefficient for >5000 areas!!!
  #for(j in seq_along(areas)) { # Per country j
  #  mr_x[, seq(1 + (j - 1) * n_proc, j * n_proc)] <-
  #    mr_x[, seq(1 + (j - 1) * n_proc, j * n_proc)] * y[, j]
  #}
  
  mr_x <- mr_x*y_proc
  
  
  return(mr_x)
}, use_cast, supply_shares)

names(mr_use) <- years


# Final Demand ---

## CHANGED: final use needs to be distributed across sources differently than inter-industry use:
# the supply shares derived from the re-export-free btd do not apply to negative stock_addition 
# these are fully sourced from the domestic stocks stemming from previous years
# thus, take out negative additions from general split and add them for each country only to the domestic origin

# Template to always get full tables
template <- data.table(expand.grid(
  area_code = areas_w, comm_code = commodities_w,
  variable = c("food", "other", "losses", "stock_addition", "stock_withdrawal", "balancing", "unspecified"),
  stringsAsFactors = FALSE))
template_soy <- data.table(expand.grid(
  area_code = areas_soy, comm_code = commodities_soy,
  variable = c("food", "other", "losses", "stock_addition", "stock_withdrawal", "balancing", "unspecified"),
  stringsAsFactors = FALSE))
template <- rbind(template, template_soy)
rm(template_soy)
setkey(template, area_code, comm_code, variable)

# split stock addition to positive (addition) and negative part (withdrawal)
use_fd[,`:=`(stock_withdrawal = ifelse(stock_addition < 0, stock_addition, 0),
          stock_addition = ifelse(stock_addition >= 0, stock_addition, 0))] 

use_fd <- melt(use_fd[, .(year, area_code, comm_code,
                          food, other, losses, stock_addition, stock_withdrawal, balancing, unspecified)],
               id.vars = c("year", "area_code", "comm_code"))


# List with final use matrices, per year
use_fd_cast <- lapply(years, function(x, use_fd_x) {
  # Cast final use to convert to a matrix
  out <- data.table::dcast(merge(template[, .(area_code, comm_code, variable)],
                                 use_fd_x[year == x, .(area_code, comm_code, variable, value)],
                                 by = c("area_code", "comm_code", "variable"), all.x = TRUE),
                           comm_code ~ area_code + variable,
                           value.var = "value", fun.aggregate = sum, na.rm = TRUE, fill = 0)
  
  Matrix(data.matrix(out[, -1]), sparse = TRUE,
         dimnames = list(out$comm_code, colnames(out)[-1]))
}, use_fd[, .(year, area_code, comm_code, variable, value)])


# Apply supply shares to the final use matrix
mr_use_fd <- mapply(function(x, y) {
  
  # CHANGED: adapt to new structure:
  #mr_x <- x[rep(seq_along(commodities), length(areas)), ]
  mr_x <- x[match(comms, rownames(x)), ] 
  rownames(mr_x) <- rownames(y)

  # n_var <- length(unique(use_fd[,variable]))
  # for(j in seq_along(areas)) { # Could do this vectorised
  #   mr_x[, seq(1 + (j - 1) * n_var, j * n_var)] <-
  #     mr_x[, seq(1 + (j - 1) * n_var, j * n_var)] * y[, j]
  # }
  
  areas_fd <- as.numeric(sub("_.*", "", colnames(mr_x)))
  y_fd <- y[,match(areas_fd, colnames(y))]
  colnames(y_fd) <- colnames(x)
  # CHANGED: for stock withdrawals, allocate everything to domestic commodity
  d <- Diagonal(length(unique(areas_fd)))
  dimnames(d) <- list(unique(areas_fd), unique(areas_fd))
  areas_comm <- as.numeric(sub("_.*", "", rownames(y_fd)))
  y_fd[,grepl("stock_withdrawal", colnames(y_fd))] <- d[match(areas_comm, rownames(d)),]
  # allocate
  mr_x <- mr_x * y_fd
  
  return(mr_x)
}, use_fd_cast, supply_shares)

names(mr_use_fd) <- years
#rm(supply_shares)


## CHANGED: aggregate municipalities to national processes where detail is not needed

# use: add soy use of municipal livestock processes to national pendants

# create a summation matrix: dimensions ncol(mr_use) * ncol(target mr_use)
processes_live <- processes_mun_use[processes_mun_use != processes_soy]
areas_mun <- unique(areas[areas>1000])
proc_live_mun <- apply(expand.grid(areas_mun, processes_live), 1, paste, collapse="_")
# option 1:
# sum_mat <- Diagonal(n = ncol(mr_use[[1]]))
# dimnames(sum_mat) <- list(colnames(mr_use[[1]]), colnames(mr_use[[1]]))
# sum_mat <- sum_mat[,!colnames(sum_mat) %in% proc_live_mun]
# #proc_live_bra_mat <- match(paste0(21,"_",processes_live))
# for(p in processes_live) {
#   sum_mat[paste0(areas_mun,"_",p),paste0("21_",p)] <- 1
# }
# option 2 (slightly faster):
processes_all <- colnames(mr_use[[1]])
processes_fin <- processes_all[!processes_all %in% proc_live_mun]
sum_mat <- Diagonal(length(processes_fin))
dimnames(sum_mat) <- list(processes_fin,processes_fin)
processes_fin_long <- processes_all
processes_fin_long[processes_fin_long %in% proc_live_mun] <- paste0("21_",sub(".*?_", "", processes_fin_long[processes_fin_long %in% proc_live_mun]))
sum_mat <- sum_mat[processes_fin_long,]

# aggregate Brazilian national and municipal processes
mr_use <- lapply(mr_use, function(x){x %*% sum_mat})

# check conformity of dimensions with supply table
dim(mr_use[[1]]) == rev(dim(mr_sup_mass[[1]]))
all.equal(rownames(mr_sup_mass[[1]]), colnames(mr_use[[1]]))
all.equal(colnames(mr_sup_mass[[1]]), rownames(mr_use[[1]]))


# final demand use: re-aggregate stock_addition and stock_withdrawal
fd_uses <- colnames(mr_use_fd[[1]]) 
fd_uses_fin <- gsub("_withdrawal", "_addition", fd_uses)
fd_uses_unique <- unique(fd_uses_fin)
sum_mat_fd <- Diagonal(length(fd_uses_unique))
dimnames(sum_mat_fd) <- list(fd_uses_unique, fd_uses_unique)
sum_mat_fd <- sum_mat_fd[fd_uses_fin,]
# aggregate stock_addition and stock_withdrawal
mr_use_fd <- lapply(mr_use_fd, function(x){x %*% sum_mat_fd})

# final demand use: aggregate municipal final demand for soy products to national pendants
fd_uses <- colnames(mr_use_fd[[1]]) 
fd_uses_fin <- ifelse(gsub("_.*", "", fd_uses ) %in% as.character(areas_mun), paste0("21_",sub(".*?_", "", fd_uses ) ), fd_uses)
fd_uses_unique <- unique(fd_uses_fin)
#mr_use_fd1 <- lapply(mr_use_fd, function(x){as(t(rowsum(t(as.matrix(x)),group = fd_uses_fin, reorder = FALSE)),"Matrix")})
sum_mat_fd <- Diagonal(length(fd_uses_unique))
dimnames(sum_mat_fd) <- list(fd_uses_unique, fd_uses_unique)
sum_mat_fd <- sum_mat_fd[fd_uses_fin,]
# aggregate Brazilian national and municipal processes
mr_use_fd <- lapply(mr_use_fd, function(x){x %*% sum_mat_fd})

# CHANGED: avoid rounding
#mr_use_fd <- lapply(mr_use_fd, round)

if (write) {
  saveRDS(mr_use, "data/generated/fabio/mr_use.rds")
  saveRDS(mr_use_fd, "data/generated/fabio/mr_use_fd.rds")
}

rm(list = ls())
gc()


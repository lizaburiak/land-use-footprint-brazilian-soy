####### simple transport optimization within R, using the transport package #######

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(transport)
library(openxlsx)
library(dplyr)
library(abind)

write = TRUE

out_dir <- paste0("data/generated/outputs/07_", YEAR)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# load data
# Note: MUN_capital_dist.rds is produced by step 00 (code/pipeline/00_data_preperation.R),
# not by step 06. Reading from data/generated/outputs/00_{YEAR}/ instead of data/generated/outputs/05_{YEAR}/.
SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
MUN_capital_dist <- readRDS(paste0("data/generated/outputs/00_", YEAR, "/MUN_capital_dist.rds"))
# Subset distance matrix to municipalities present in SOY_MUN (step 00 may include a
# few extras that get filtered out by step 05; transport package requires dim match).
.mun <- as.character(SOY_MUN$co_mun)
# Drop non-geographic placeholder municipalities (e.g. COMEX code 9300000,
# "unknown municipality") that have no entry in the distance matrix — they
# cannot be transport nodes. Keep SOY_MUN and the cost matrix aligned.
.in_dist <- .mun %in% rownames(MUN_capital_dist)
if (any(!.in_dist)) {
  message("[07] dropping ", sum(!.in_dist), " non-geographic municipality(ies) absent from the ",
          "distance matrix: ", paste(.mun[!.in_dist], collapse = ", "))
  SOY_MUN <- SOY_MUN[.in_dist, , drop = FALSE]
  .mun <- .mun[.in_dist]
}
MUN_capital_dist <- MUN_capital_dist[.mun, .mun]


# specify distance type: we only use Euclidean here, but any other cost/distance type could also be used
dist <- list(euclid = MUN_capital_dist)

flows <- lapply(dist, function(d){
  MUN_dist <- d
  class(MUN_dist) <- "numeric"

  product <- c("bean", "oil", "cake")

  MUN_transport <- sapply(product, function(x){
    # transport() with full-length a/b returns from/to indices into the FULL a/b vectors
    # (1..nrow(SOY_MUN)). Stefan's original `suppliers[sol$from]` was a bug — `suppliers`
    # is a filtered subset (positive supply only), so indices > length(suppliers) returned NA.
    # Map directly through SOY_MUN$co_mun instead.
    a <- pull(SOY_MUN, paste0("excess_supply_", x))
    b <- pull(SOY_MUN, paste0("excess_use_", x))
    a[is.na(a)] <- 0; b[is.na(b)] <- 0   # defensive: NA excess = no excess
    .empty <- data.frame(co_orig = numeric(0), co_dest = numeric(0),
                         product = character(0), value = numeric(0))
    # Some products have no inter-municipal flow in a given year (e.g. oil fully
    # consumed locally) -> sum(a) or sum(b) is 0 and transport() returns an empty
    # plan. Skip cleanly instead of erroring on the 0-row assignment.
    if (sum(a) <= 0 || sum(b) <= 0) {
      cat("total cost ", x, ":  0 (no inter-municipal flow)\n")
      return(.empty)
    }
    # Dropping non-geographic nodes above can leave a tiny supply/demand mismatch
    # (e.g. the 9300000 "unknown" demand). transport() needs sum(a)==sum(b), so
    # scale the larger side down to match. The residual is negligible (<0.1%).
    if (!isTRUE(all.equal(sum(a), sum(b)))) {
      if (sum(a) > sum(b)) a <- a * (sum(b) / sum(a)) else b <- b * (sum(a) / sum(b))
    }
    solve <- transport(a = a, b = b, costm = MUN_dist, method = "networkflow", fullreturn=TRUE, threads=4)
    cat("total cost ", x, ": ", solve$cost, "\n")
    sol <- solve$default
    if (nrow(sol) == 0) return(.empty)
    sol$co_orig <- SOY_MUN$co_mun[sol$from]
    sol$co_dest <- SOY_MUN$co_mun[sol$to]
    sol$product <- x
    sol <- sol[,c("co_orig", "co_dest", "product", "mass")]
    names(sol)[4] <- "value"
    return(sol)
    },
    simplify = FALSE, USE.NAMES = TRUE)

  flows <- abind(MUN_transport, along = 1, force.array = FALSE)
  return(flows)
})


if (write){
  saveRDS(flows, file = file.path(out_dir, "flows_euclid.rds"))
}

rm(list = ls())

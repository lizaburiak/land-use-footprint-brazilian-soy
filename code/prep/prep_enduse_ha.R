# ============================================================================
# Land-use footprint (ha) of Brazilian soy by END-USE bucket x year, from F_mass.
#   Animal products (meat/dairy/eggs) | Soybeans, meal & oil (commodity) |
#   Other food | Non-food / industrial
# Mirrors the end-use logic in plot_footprint_dynamics.R but on F_mass (land, ha).
# Output: results/figures/footprint_dynamics/csv/by_enduse_ha.csv  (year,bucket,ha)
# Usage : Rscript code/prep/prep_enduse_ha.R
# ============================================================================
suppressMessages({library(Matrix); library(data.table)})

OUT <- "results/figures/footprint_dynamics/csv"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
fps   <- list.files("data/generated/footprints", pattern = "^[0-9]{4}_F_mass\\.rds$", full.names = TRUE)
YEARS <- sort(as.integer(sub(".*/([0-9]{4})_F_mass\\.rds$", "\\1", fps)))
items <- fread("data/fabio/v2/inst/items_full.csv")

animal_grp <- c("Meat","Milk","Eggs","Live animals","Animal fats","Hides, skins, wool","Honey")
soy_grp    <- c("Oil crops","Vegetable oils","Oil cakes")
enduse_of_comm <- function(cc) {
  g <- items$comm_group[match(cc, items$comm_code)]
  ifelse(g %in% animal_grp, "Animal products (meat/dairy/eggs)",
  ifelse(g %in% soy_grp,    "Soybeans, meal & oil (commodity)", "Other food"))
}

out <- list()
for (Y in YEARS) {
  F <- readRDS(sprintf("data/generated/footprints/%d_F_mass.rds", Y))
  soy <- as.numeric(sub("_.*", "", rownames(F$A_product))) > 1000 &
         sub(".*_", "", rownames(F$A_product)) == "c021"
  ap <- Matrix::colSums(F$A_product[soy, , drop = FALSE])     # land by consumer product (food)
  bp <- sum(Matrix::colSums(F$B_product[soy, , drop = FALSE]))# nonfood land (industrial)
  de <- data.table(bucket = enduse_of_comm(names(ap)), ha = as.numeric(ap))[, .(ha = sum(ha)), by = bucket]
  de <- rbind(de, data.table(bucket = "Non-food / industrial", ha = bp))[, year := Y]
  out[[as.character(Y)]] <- de
  message(sprintf("[enduse] %d: %.2f Mha total", Y, sum(de$ha)/1e6)); rm(F); gc(verbose = FALSE)
}
fwrite(rbindlist(out), file.path(OUT, "by_enduse_ha.csv"))
cat("\nwrote", file.path(OUT, "by_enduse_ha.csv"), "\n")

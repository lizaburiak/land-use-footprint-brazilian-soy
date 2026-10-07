# Per-municipality land balance for one year, from the files steps 16-20 leave behind
# (generated/fabio/{X,Y_hybrid,Z_mass,<Y>_L_mass}.rds, footprints/<Y>_F_mass.rds and
# <Y>_scaled_columns.csv, outputs/05_<Y>/SOY_MUN_fin.rds). Writes footprints/<Y>_land_balance_mun.csv
# and stops if the identity does not close per municipality or does not sum to the national
# identity of step 20 (<Y>_land_identity.csv). Step 20 runs the same code (code/shared/land_balance.R);
# this script exists so a year can be (re)checked without re-running step 20.
#
# Usage (repo or worker root, SOYPRINT_DATA_DIR pointing at the data root): Rscript code/prep/land_balance_mun.R YYYY
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")
YEAR <- as.integer(commandArgs(trailingOnly = TRUE)[1]); stopifnot(!is.na(YEAR))
suppressMessages({library(Matrix); library(data.table)})
source("code/shared/land_balance.R")
G <- file.path(DATA_DIR, "generated/fabio"); FP <- file.path(DATA_DIR, "generated/footprints"); Yc <- as.character(YEAR)
X <- readRDS(file.path(G, "X.rds")); x <- as.vector(if (is.matrix(X) && Yc %in% colnames(X)) X[, Yc] else X)
YA <- readRDS(file.path(G, "Y_hybrid.rds")); if (is.list(YA)) YA <- YA[[Yc]]
L <- readRDS(file.path(G, paste0(YEAR, "_L_mass.rds"))); rn <- rownames(YA)
soy_mun <- as.data.table(readRDS(file.path(DATA_DIR, sprintf("generated/outputs/05_%d/SOY_MUN_fin.rds", YEAR))))
si <- match(paste0(soy_mun$co_mun, "_c021"), rn); ok <- !is.na(si); si <- si[ok]; harv <- as.numeric(soy_mun$area_harv)[ok]; co_mun <- soy_mun$co_mun[ok]
l <- harv / x[si]; l[!is.finite(l) | abs(x[si]) < 1e-6] <- 0
Fm <- readRDS(file.path(FP, paste0(YEAR, "_F_mass.rds"))); stopifnot(identical(rownames(Fm$A_country), rn))
sc <- read.csv(file.path(FP, paste0(YEAR, "_scaled_columns.csv")), stringsAsFactors = FALSE); sc <- sc[sc$allocation == "mass", , drop = FALSE]
Zs <- NULL
if (nrow(sc)) { Z <- readRDS(file.path(G, "Z_mass.rds")); if (is.list(Z)) Z <- Z[[Yc]]; Zs <- Z[, match(sc$column, rownames(Z)), drop = FALSE]; Zs@x[Zs@x < 0] <- 0; rm(Z) }
d <- land_balance_mun(co_mun, harv, l, L[si, , drop = FALSE],
                      Matrix::rowSums(Fm$A_country[si, , drop = FALSE]), Matrix::rowSums(Fm$B_country[si, , drop = FALSE]),
                      Matrix::rowSums(YA[, grepl("_stock_addition$", colnames(YA)), drop = FALSE]),
                      Matrix::rowSums(YA[, grepl("_balancing$", colnames(YA)), drop = FALSE]), Zs, sc$scale)
check_land_balance_mun(d, YEAR)
nat <- read.csv(file.path(FP, paste0(YEAR, "_land_identity.csv")))
tot <- colSums(d[, c("harvested_ha", "footprint_food_ha", "footprint_nonfood_ha", "stock_change_dropped_ha", "balancing_dropped_ha", "nonproductive_lost_ha")])
ref <- c(nat$harvested_ha, nat$kept_food_ha, nat$kept_nonfood_ha, nat$stock_addition_ha, nat$balancing_ha, nat$nonproductive_lost_ha)
if (any(abs(tot - ref) > 1e-6 * nat$harvested_ha))
  stop(sprintf("[land balance] %d: municipal totals differ from the national identity: %s", YEAR,
               paste(sprintf("%s %.1f vs %.1f", names(tot), tot, ref), collapse = "; ")), call. = FALSE)
cat(sprintf("[land balance] %d: municipal totals equal the national identity (largest difference %.3f ha)\n", YEAR, max(abs(tot - ref))))
fwrite(d[d$harvested_ha > 0, ], file.path(FP, paste0(YEAR, "_land_balance_mun.csv")))

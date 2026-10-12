# Validate step 20 footprint outputs for one year.
# Usage: Rscript logs/fabio_probe/scripts/validate_footprints.R <YEAR>
# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR (e.g. isolated worker dirs).
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")

suppressMessages({library(data.table); library(Matrix)})
Y <- as.integer(commandArgs(trailingOnly = TRUE)[1]); if (is.na(Y)) Y <- 2013
dir <- file.path(DATA_DIR, "generated/footprints")
vals <- function(m) if (is(m, "Matrix")) m@x else as.vector(m)
flag <- character()
note <- function(ok, msg) { cat(if (ok) "  [ok]   " else "  [FLAG] ", msg, "\n", sep = ""); if (!ok) flag <<- c(flag, msg) }

cat("== files\n")
f <- file.path(dir, sprintf("%d_%s.rds", Y, c("P_mass", "P_value", "F_mass", "F_value")))
print(data.table(file = normalizePath(f, mustWork = FALSE), bytes = file.size(f)))
if (any(is.na(file.size(f)) | file.size(f) == 0)) stop("missing or empty footprint file")

X <- readRDS(file.path(DATA_DIR, "generated/fabio/X.rds"))[, as.character(Y)]
soy <- as.data.table(readRDS(sprintf(file.path(DATA_DIR, "generated/outputs/05_%d/SOY_MUN_fin.rds"), Y)))
items <- fread(file.path(DATA_DIR, "fabio/v2/inst/items_full.csv"))
harv <- sum(soy$area_harv)
cat(sprintf("municipal harvested soy area (SOY_MUN_fin): %.3f Mha, %d munis with area > 0\n",
            harv / 1e6, soy[area_harv > 0, .N]))

for (alloc in c("mass", "value")) {
  cat("\n==========", alloc, "allocation ==========\n")
  Fl <- readRDS(file.path(dir, sprintf("%d_F_%s.rds", Y, alloc)))
  Pl <- readRDS(file.path(dir, sprintf("%d_P_%s.rds", Y, alloc)))
  for (k in names(Fl)) {
    v <- vals(Fl[[k]])
    cat(sprintf("  F$%-15s %-10s %6d x %-5d sum %.5g | non-finite %d | negative cells %d (sum %.4g)\n",
                k, class(Fl[[k]])[1], nrow(Fl[[k]]), ncol(Fl[[k]]), sum(v[is.finite(v)]),
                sum(!is.finite(v)), sum(v < 0, na.rm = TRUE), sum(v[v < 0], na.rm = TRUE)))
    note(all(is.finite(v)), sprintf("%s F$%s has no NA/Inf", alloc, k))
  }
  FA <- Fl$A_country; FB <- Fl$B_country; PA <- Pl$A_country; PB <- Pl$B_country
  rn <- rownames(FA); area <- as.numeric(sub("_.*", "", rn)); comm <- sub(".*_", "", rn)
  note(identical(rn, names(X)) || identical(rn, rownames(readRDS(file.path(DATA_DIR, "generated/fabio/X.rds")))),
       sprintf("%s: footprint rows align with X", alloc))
  mun <- area > 1000

  # land: rows of all F tables sum to the same total (country vs product split)
  tot_c <- sum(FA) + sum(FB); tot_p <- sum(Fl$A_product) + sum(Fl$B_product)
  note(abs(tot_c / tot_p - 1) < 1e-6, sprintf("%s: country split total == product split total (%.6g vs %.6g)", alloc, tot_c, tot_p))

  # Brazilian municipal soy land
  lm <- rowSums(FA[mun, , drop = FALSE]) + rowSums(FB[mun, , drop = FALSE])
  cat(sprintf("  Brazil municipal soy land footprint (A food + B nonfood): %.3f Mha = %.1f%% of harvested area\n",
              sum(lm) / 1e6, 100 * sum(lm) / harv))
  cat(sprintf("    of which A (food/FABIO) %.3f Mha, B (nonfood/EXIOBASE) %.3f Mha; land on non-c021 municipal rows: %.4g\n",
              sum(FA[mun, ]) / 1e6, sum(FB[mun, ]) / 1e6, sum(lm[comm[mun] != "c021"])))
  note(sum(lm) <= harv * 1.001, sprintf("%s: municipal footprint <= harvested area", alloc))
  # output coverage per municipal soybean row: (L y)_i / x_i
  # |X| < 1e-6 t is floating-point residue (step 20 zeroes land per tonne there)
  cat(sprintf("    municipal rows with 0 < |X| < 1e-6 t (residue, excluded): %d, land on them %.4g ha\n",
              sum(mun & abs(X) > 0 & abs(X) < 1e-6), sum(rowSums(FA[mun & abs(X) < 1e-6, , drop = FALSE]))))
  i21 <- which(mun & comm == "c021" & X >= 1e-6)
  cov <- (rowSums(PA[i21, , drop = FALSE]) + rowSums(PB[i21, , drop = FALSE])) / X[i21]
  cat("    municipal c021 rows: output explained by kept final demand (quantiles):\n"); print(round(quantile(cov, c(0, .01, .1, .5, .9, .99, 1)), 4))
  note(all(cov > -1e-6 & cov < 1.001), sprintf("%s: municipal coverage within [0, 1] (min %.4f, max %.4f, n>1.001: %d)",
                                                alloc, min(cov), max(cov), sum(cov >= 1.001)))

  # global land coverage: implied land = l * X with l = F/P per row
  l <- rowSums(FA) / rowSums(PA); l[!is.finite(l)] <- 0
  cat(sprintf("  global footprint %.1f Mha vs implied land (l*X) %.1f Mha -> %.1f%%\n",
              tot_c / 1e6, sum(l * X) / 1e6, 100 * tot_c / sum(l * X)))

  # destinations of Brazilian soy land
  dA <- colSums(FA[mun, , drop = FALSE]); dB <- colSums(FB[mun, , drop = FALSE])
  d <- rbind(data.table(iso = sub("_food$", "", names(dA)), part = "A", ha = dA),
             data.table(iso = sub("_nonfood$", "", names(dB)), part = "B", ha = dB))
  d <- dcast(d, iso ~ part, value.var = "ha", fun.aggregate = sum, fill = 0)[, tot := A + B][order(-tot)]
  d[, share_pct := round(100 * tot / sum(tot), 2)]
  cat("  top consumers of Brazilian municipal soy land (ha):\n"); print(head(d[, .(iso, A = round(A), B = round(B), tot = round(tot), share_pct)], 15))
  cat(sprintf("  countries/regions with negative totals: %d (%s)\n", d[tot < 0, .N], paste(head(d[tot < 0, iso], 8), collapse = ",")))
  note(d[tot < -1, .N] == 0, sprintf("%s: no consumer with negative Brazilian soy land", alloc))

  # products
  pA <- colSums(Fl$A_product[mun, , drop = FALSE])
  pA <- data.table(comm_code = names(pA), ha = pA)[items, item := i.item, on = "comm_code"][order(-ha)]
  cat("  top food products (A_product) by Brazilian soy land:\n"); print(head(pA[, .(comm_code, item, ha = round(ha), pct = round(100 * ha / sum(ha), 1))], 10))
  pB <- colSums(Fl$B_product[mun, , drop = FALSE]); pB <- sort(pB, decreasing = TRUE)
  cat("  top nonfood EXIOBASE products (B_product):\n"); print(round(head(pB, 8)))

  # product groups by consumer country
  pc <- Fl$A_prod_country; g <- sub("^[^_]+_", "", colnames(pc))
  gs <- tapply(colSums(pc[mun, , drop = FALSE]), g, sum)
  cat("  A_prod_country groups, Brazilian soy land (ha):\n"); print(round(gs))
  if (all(c("meat", "dairy", "meat-dairy") %in% names(gs)))
    note(abs(gs[["meat-dairy"]] - gs[["meat"]] - gs[["dairy"]]) <= 1e-6 * max(1, gs[["meat-dairy"]]),
         sprintf("%s: meat-dairy == meat + dairy", alloc))
  rm(Fl, Pl, FA, FB, PA, PB); invisible(gc())
}
cat("\n========== step 13 supply vs cbs production (v1.1 item-code regression check) ==========\n")
sup <- readRDS(file.path(DATA_DIR, "generated/fabio/sup.rds")); cbs <- readRDS(file.path(DATA_DIR, "generated/fabio/cbs_final.rds"))
chk <- c("c081", "c089", "c090", "c109", "c113")
sc <- merge(sup[year == Y & comm_code %in% chk, .(sup_t = sum(production, na.rm = TRUE)), by = .(comm_code, item)],
            cbs[year == Y & comm_code %in% chk, .(cbs_t = sum(production, na.rm = TRUE)), by = comm_code], by = "comm_code")
sc[, ratio := round(sup_t / cbs_t, 4)]; print(sc)
for (k in seq_len(nrow(sc)))
  note(isTRUE(abs(sc$ratio[k] - 1) < 0.01), sprintf("supply of %s (%s) matches cbs production (ratio %s)", sc$comm_code[k], sc$item[k], sc$ratio[k]))

cat("\n== summary:", if (length(flag)) paste(length(flag), "FLAG(s):", paste(flag, collapse = " | ")) else "all checks ok", "\n")

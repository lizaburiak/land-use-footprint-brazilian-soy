# Compile the cross-year multimode vs Euclidean vs TRASE comparison from the
# per-year benchmark tables (results/tables/benchmarks/<year>/pearson_global.csv
# and rmsle_global.csv) into one panel CSV. Run from repo root.

years <- 2010:2022
antaq_real <- 2017:2022   # years with real ANTAQ water cargo; others proxied with 2017

rows <- list()
for (y in years) {
  f <- sprintf("results/tables/benchmarks/%d/pearson_global.csv", y)
  fr <- sprintf("results/tables/benchmarks/%d/rmsle_global.csv", y)
  if (!file.exists(f)) { message("skip ", y, " (no benchmarks)"); next }
  pe <- read.csv(f, check.names = FALSE)
  # significance stars are embedded in the pearson values - strip to numeric
  num <- function(x) as.numeric(gsub("[*]", "", x))
  rm_ <- if (file.exists(fr)) read.csv(fr, check.names = FALSE) else NULL
  for (i in seq_len(nrow(pe))) {
    rows[[length(rows) + 1]] <- data.frame(
      year = y,
      weighting = pe$weighting[i],
      pearson_multimode = num(pe$multimode[i]),
      pearson_euclid = num(pe$euclid[i]),
      pearson_downscale = num(pe$downscale[i]),
      delta_multimode_minus_euclid = round(num(pe$multimode[i]) - num(pe$euclid[i]), 4),
      rmsle_multimode = if (!is.null(rm_)) rm_$multimode[i] else NA,
      rmsle_euclid = if (!is.null(rm_)) rm_$euclid[i] else NA,
      water_cargo = ifelse(y %in% antaq_real, "real", "proxied_2017"),
      # 2021: multimode LP infeasible (no solve), so its benchmark table is the
      # Euclidean-only fallback - the multimode column just mirrors euclid there
      note = ifelse(y == 2021, "NO multimode solve (LP infeasible) - multimode col = euclid fallback", "")
    )
  }
}
panel <- do.call(rbind, rows)
out <- "results/tables/benchmarks/multimode_vs_euclid_panel_2010-2022.csv"
write.csv(panel, out, row.names = FALSE)
cat("wrote", out, "with", nrow(panel), "rows for years:",
    paste(unique(panel$year), collapse = ", "), "\n")

# ============================================================================
# Extract municipality x destination flow pairs (Trase vs Euclidean model, t)
# from the step-10 benchmark comparison, all available years, for the rocket
# plot. Keeps only pairs where at least one side is nonzero.
# Output: results/plots_2001_2022/csv/rocket_pairs.csv (year, co_mun, to_code, trase, euclid)
# Usage : Rscript code/prep/prep_rocket_pairs.R
# ============================================================================
suppressMessages(library(data.table))
OUT <- "results/plots_2001_2022/csv"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

years <- Filter(function(y) file.exists(sprintf("data/generated/outputs/10_%d/comp_list.rds", y)), 2004:2022)
res <- lapply(years, function(y) {
  m <- readRDS(sprintf("data/generated/outputs/10_%d/comp_list.rds", y))$mun
  m <- m[trase > 0 | euclid > 0, .(year = y, co_mun, to_code, trase, euclid)]
  message(sprintf("[rocket] %d: %d nonzero pairs", y, nrow(m)))
  m
})
dt <- rbindlist(res)
fwrite(dt, file.path(OUT, "rocket_pairs.csv"))
cat("wrote", file.path(OUT, "rocket_pairs.csv"), "-", nrow(dt), "rows,",
    length(years), "years:", min(years), "-", max(years), "\n")

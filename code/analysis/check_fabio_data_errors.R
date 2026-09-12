# ============================================================================
# CHECK: extreme technical coefficients in the FABIO v2 (mass) data
# ----------------------------------------------------------------------------
# For the input-output model to solve, the Leontief inverse L = (I - A)^-1 must
# exist and be non-negative, which needs the economy to be "productive"
# (spectral radius rho(A) < 1), with A = Z * diag(x)^-1 (Z = intermediate use,
# x = gross output).
#
# NOTE: a single column with colSum(A) > 1 (intermediate USE > OUTPUT) is NOT by
# itself an error in a MASS table -- it is normal for processing/livestock:
#   crushing  ~5 t soybeans -> ~1 t oil (+cake)      -> colSum(A) ~ 5
#   slaughter ~16 t live pigs -> ~11 t pigmeat        -> colSum(A) ~ 1.5
# What is NOT physical is an EXTREME ratio (thousands to millions), which here is
# driven by a NEAR-ZERO recorded OUTPUT despite very large inputs -- e.g. Japan
# pigmeat: output = 10 t but 16,100,238 t of live pigs go in (ratio 1.6e6). Such
# cells make rho(A) blow up and give the Leontief inverse large NEGATIVE entries
# (-> negative land footprints downstream, e.g. the Philippines 2020).
#
# This script reads ONLY the FABIO v2 base files (no pipeline / municipal build),
# reports per year the columns with use > output, flags the EXTREME ones
# (ratio >= THRESH), and writes the full list to CSV so the outputs can be checked
# against source. Whether the tiny outputs are a data error or an accounting
# convention is the question for the FABIO build.
#
# INPUT  (pass a different path as arg 1 if your FABIO v2 lives elsewhere):
#   <V2>/X.rds            gross output, matrix [process x year]
#   <V2>/Z_mass_b.rds     intermediate use (mass), list keyed by year
#   <V2>/inst/items_full.csv   commodity labels
# OUTPUT:
#   results/fabio_data_check/fabio_extreme_coefficients.csv
#
# RUN:  Rscript code/analysis/check_fabio_data_errors.R  [path/to/fabio/v2]
# ============================================================================
suppressMessages({library(Matrix); library(data.table)})

THRESH <- 100   # colSum(A) >= THRESH  =>  "extreme" (well beyond crushing/slaughter)

# Resolve paths independent of the working directory: use the path passed as an
# argument, else walk up from the current dir to find the repo root that contains
# data/fabio/v2 (so it runs from the repo root, docs/, or anywhere inside).
.arg <- commandArgs(TRUE)[1]
if (!is.na(.arg) && nzchar(.arg)) {
  V2 <- .arg; ROOT <- getwd()
} else {
  ROOT <- NA_character_; d <- normalizePath(getwd())
  for (i in 1:8) {
    if (dir.exists(file.path(d, "data/fabio/v2"))) { ROOT <- d; break }
    p <- dirname(d); if (p == d) break; d <- p
  }
  if (is.na(ROOT)) stop("Could not find 'data/fabio/v2'. Run setwd() to the repo root, ",
                        "or pass the FABIO v2 path as an argument.", call. = FALSE)
  V2 <- file.path(ROOT, "data/fabio/v2")
}
stopifnot(dir.exists(V2))
OUT <- file.path(ROOT, "results/fabio_data_check")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
cat("repo root:", ROOT, "\nFABIO v2 :", V2, "\n\n")

X     <- readRDS(file.path(V2, "X.rds"))         # [process x year]
Zb    <- readRDS(file.path(V2, "Z_mass_b.rds"))  # list: year -> sparse [process x process]
items <- fread(file.path(V2, "inst/items_full.csv"))
item_of <- function(cc) items$item[match(cc, items$comm_code)]   # names are "<ISO3>_<comm>"

years <- intersect(colnames(X), names(Zb))
TOL   <- 1e-6

cat("=================================================================\n")
cat(" FABIO v2 check - technical coefficients colSum(A) = use / output\n")
cat(" (use > output is normal for crush/slaughter; EXTREME ratios are not)\n")
cat("=================================================================\n\n")
cat(sprintf("%-6s %14s %16s %14s\n", "year", "use>output", paste0("EXTREME(>=", THRESH, ")"), "max ratio"))
cat(strrep("-", 54), "\n")

flagged <- list()
for (y in years) {
  Z <- Zb[[y]]; xv <- X[, y]
  A <- Z; A@x <- A@x / rep.int(xv, diff(A@p))    # A = Z * diag(x)^-1
  A[A < 0] <- 0
  cs <- Matrix::colSums(A); cs[!is.finite(cs)] <- 0   # x==0 columns undefined, skip
  gt1 <- which(xv > TOL & cs >= 1)                    # use > output (mostly legitimate)
  ext <- which(xv > TOL & cs >= THRESH)               # physically implausible tail
  cat(sprintf("%-6s %14d %16d %14.0f\n", y, length(gt1), length(ext),
              if (length(gt1)) max(cs[gt1]) else 0))
  if (length(ext))
    flagged[[y]] <- data.table(
      year = as.integer(y),
      region = sub("_.*", "", colnames(A)[ext]),
      commodity = item_of(sub(".*_", "", colnames(A)[ext])),
      output_t = round(xv[ext]),
      intermediate_use_t = round(cs[ext] * xv[ext]),
      use_over_output = round(cs[ext], 1))
}

DT <- rbindlist(flagged)
setorder(DT, -use_over_output)
fwrite(DT, file.path(OUT, "fabio_extreme_coefficients.csv"))

cat(sprintf("\nEXTREME cells (ratio >= %d) across %d years: %d  (unique region x commodity: %d)\n",
            THRESH, length(years), nrow(DT), uniqueN(DT[, .(region, commodity)])))
cat("Full list written to:", file.path(OUT, "fabio_extreme_coefficients.csv"), "\n\n")

cat("Worst 20 - note the near-zero OUTPUT against millions of tonnes of input:\n")
print(head(DT, 20), row.names = FALSE)

cat("\nReading: e.g. Japan Pigmeat consumes ~16,000,000 t of live pigs but records\n")
cat("~10 t of pigmeat OUTPUT (ratio 1.6e6). The large input is order-plausible for a\n")
cat("slaughter flow; the near-zero output is not -- it should be millions of tonnes.\n")
cat("That is what makes rho(A) exceed 1 and the Leontief inverse go negative.\n\n")
cat("QUESTIONS for the FABIO build:\n")
cat("  1) Why is the gross output (x) near-zero for these high-throughput processes\n")
cat("     -- data error, or is the output booked to another commodity/flow?\n")
cat("  2) How is the inverse meant to stay productive (rho(A) < 1) given these cells?\n")
cat("  3) Are the recent vintages (2020-2023) as balanced as 2010-2019?\n")

####### Split the net municipal stock change of step 05 into FAO stock variation, losses and residual #######
#
# Labels only. Step 05 books everything that closes the national soy balance as `stock_addition`
# (05_balancing.R:36-41). From 2019 that net is FAO stock variation plus FAO Losses plus FAO Residuals,
# because the 10-row FAO workbooks read in step 00 carry neither losses nor residuals. This script
# splits the net into the three parts for the release; the model is unchanged.
#
# Writes ONLY generated/outputs/05_<Y>/STOCK_DECOMP_MUN.rds (read only by code/build_release_parquet.R).
# No pipeline step reads it, so every existing output stays byte-identical.
#
# Per product (bean, oil, cake):
#   net       = the municipal stock_* columns of SOY_MUN_fin (their sum is step 05's national net)
#   stock     = the workbook's FAO Stock Variation, sign-normalised to "addition" with the workbook's own
#               domestic-supply identity (FAO flipped its convention in 2014)
#   losses    = FAOSTAT FBS "Losses" (raw/00/FAO_CBS/_faostat_fbs_bulk.csv); a use missing from the workbook
#   residual  = net - stock - losses; set beside FAOSTAT "Residuals" in the log
# The split is used only when the bulk file is the same FAO vintage as the workbook (production, trade and
# stock variation agree) and reports nonzero losses or residuals. Otherwise the whole net stays `stock`.
# Each national component is allocated to municipalities in proportion to the municipality's net row,
# so the three parts sum to the net row exactly.
#
# Usage: Rscript code/pipeline/05b_stock_decomposition.R YEAR

DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)
suppressPackageStartupMessages(library(data.table))

out_dir <- paste0(DATA_DIR, "/generated/outputs/05_", YEAR)
SOY_MUN <- as.data.table(readRDS(file.path(out_dir, "SOY_MUN_fin.rds")))
CBS00   <- readRDS(paste0(DATA_DIR, "/generated/outputs/00_", YEAR, "/CBS_SOY.rds"))

# FAOSTAT FBS bulk, Brazil soybeans and soybean oil (the FBS has no soybean cake item)
fbs <- fread(file.path(DATA_DIR, "raw/00/FAO_CBS/_faostat_fbs_bulk.csv"),
             select = c("Area", "Item", "Element", "Year", "Value"), encoding = "UTF-8")
fbs <- fbs[Area == "Brazil" & Year == YEAR & Item %in% c("Soyabeans", "Soyabean Oil")]
fbs[, product := c(Soyabeans = "bean", `Soyabean Oil` = "oil")[Item]]
fb <- function(p, el) { v <- fbs[product == p & Element == el, Value]; if (length(v)) 1000 * sum(v) else NA_real_ }

near <- function(a, b) !is.na(a) && !is.na(b) && abs(a - b) <= max(1000, 1e-3 * abs(b))

res <- list(); summ <- list()
for (p in c("bean", "oil", "cake")) {
  net_mun <- SOY_MUN[[paste0("stock_", p)]]; net_mun[is.na(net_mun)] <- 0
  net <- sum(net_mun)
  x <- CBS00[p, ]; sv <- x$stock_withdrawal                       # workbook Stock Variation, as read
  base <- x$production - x$export + x$import
  sv_add <- if (sv == 0) 0 else if (abs(base + sv - x$domestic_supply) <= abs(base - sv - x$domestic_supply)) -sv else sv
  same_vintage <- p != "cake" && near(x$production, fb(p, "Production")) && near(x$export, fb(p, "Export quantity")) &&
                  near(x$import, fb(p, "Import quantity")) && near(sv, fb(p, "Stock Variation"))
  fao_loss <- if (p == "cake") NA_real_ else fb(p, "Losses"); fao_res <- if (p == "cake") NA_real_ else fb(p, "Residuals")
  split <- same_vintage && ((!is.na(fao_loss) && fao_loss != 0) || (!is.na(fao_res) && fao_res != 0))
  comp <- if (split) {
    l <- ifelse(is.na(fao_loss), 0, fao_loss); c(stock = sv_add, losses = l, residual = net - sv_add - l)
  } else c(stock = net)
  if (split && abs(net) < 0.01 * sum(abs(comp))) {
    stop(sprintf("[05b] %d %s: national net %.0f t is near zero while its components are not (%s); proportional split unstable.",
                 YEAR, p, net, paste(sprintf("%s %.0f", names(comp), comp), collapse = ", ")), call. = FALSE)
  }
  shares <- if (net != 0) comp / net else c(stock = 1, comp[-1] * 0)
  for (k in names(comp)) res[[length(res) + 1L]] <- data.table(co_mun = SOY_MUN$co_mun, product = p, component = k,
                                                               tonnes = net_mun * shares[[k]], net_row = net_mun)
  summ[[p]] <- data.table(year = YEAR, product = p, net = net, stock = comp[["stock"]],
                          losses = if (split) comp[["losses"]] else 0, residual = if (split) comp[["residual"]] else 0,
                          fao_stock_variation_workbook = sv, stock_sign_normalised = sv_add,
                          fao_losses = fao_loss, fao_residuals = fao_res, same_vintage = same_vintage, split = split)
}
dec <- rbindlist(res)
chk <- dec[, .(d = abs(sum(tonnes) - net_row[1])), by = .(co_mun, product)][, max(d)]
if (chk > 1e-6) stop(sprintf("[05b] %d: components do not sum to the net row (max %.3g t)", YEAR, chk), call. = FALSE)
dec[, net_row := NULL]
saveRDS(as.data.frame(dec), file.path(out_dir, "STOCK_DECOMP_MUN.rds"))
S <- rbindlist(summ); S[, max_mun_sum_diff := chk]
print(S)
fwrite(S, file.path(out_dir, "STOCK_DECOMP_NATIONAL.csv"))
message(sprintf("[05b] %d: wrote STOCK_DECOMP_MUN.rds (%d rows), max |sum(components) - net| per municipality = %.3g t",
                YEAR, nrow(dec), chk))

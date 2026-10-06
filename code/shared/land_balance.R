# Land balance of municipal soy land, per municipality (mass allocation).
#
# For every municipality m with harvested soy area:
#   harvested_ha = footprint_food_ha + footprint_nonfood_ha      (kept final demand)
#                  + stock_change_dropped_ha                     (signed; negative = its buyers drew down stocks)
#                  + balancing_dropped_ha
#                  + nonproductive_lost_ha                       (columns scaled in step 17, same-item rule)
# The identity closes per row because the Leontief system conserves each row's output. A
# municipality's footprint therefore exceeds its harvested area exactly when the stock and
# balancing terms of its destinations are negative.
#
# Arguments (all restricted to / aligned with the municipal soybean rows, in the same order):
#   co_mun, harv        municipality codes and harvested area (ha)
#   l                   land per unit of output (ha/t) of those rows
#   L_s                 the rows of the mass Leontief inverse for those rows (n_mun x n_proc)
#   kept_food, kept_nonfood   row sums of F_mass$A_country and F_mass$B_country for those rows
#   y_stock, y_bal      final demand dropped in step 20, summed by row of the system (length n_proc)
#   Zpos_scaled, scale  the (non-negative) columns of Z scaled in step 17 and their scaling factors
land_balance_mun <- function(co_mun, harv, l, L_s, kept_food, kept_nonfood, y_stock, y_bal,
                             Zpos_scaled = NULL, scale = numeric()) {
  lost <- if (length(scale)) l * as.vector(L_s %*% (Zpos_scaled %*% (1 - scale))) else rep(0, length(co_mun))
  d <- data.frame(co_mun = as.integer(co_mun),
                  harvested_ha            = as.numeric(harv),
                  footprint_food_ha       = as.numeric(kept_food),
                  footprint_nonfood_ha    = as.numeric(kept_nonfood),
                  stock_change_dropped_ha = l * as.vector(L_s %*% y_stock),
                  balancing_dropped_ha    = l * as.vector(L_s %*% y_bal),
                  nonproductive_lost_ha   = as.numeric(lost))
  d$residual_ha <- d$harvested_ha - (d$footprint_food_ha + d$footprint_nonfood_ha + d$stock_change_dropped_ha +
                                     d$balancing_dropped_ha + d$nonproductive_lost_ha)
  d$traced_share <- ifelse(d$harvested_ha > 0, (d$footprint_food_ha + d$footprint_nonfood_ha) / d$harvested_ha, NA_real_)
  d
}

# Stop unless the identity closes for every municipality within `tol` of its harvested area.
check_land_balance_mun <- function(d, year, tol = 1e-4) {
  d <- d[d$harvested_ha > 0, ]
  rel <- abs(d$residual_ha) / d$harvested_ha
  cat(sprintf("[land balance] %d: %d municipalities, largest residual %.2e of harvested area; %d above 1.0, max traced share %.3f\n",
              year, nrow(d), max(rel), sum(d$traced_share > 1.001), max(d$traced_share)))
  if (any(rel > tol)) {
    w <- which.max(rel)
    stop(sprintf("[land balance] %d: the identity does not close for %d municipalit(y/ies); worst %d (residual %.1f ha of %.1f ha harvested).",
                 year, sum(rel > tol), d$co_mun[w], d$residual_ha[w], d$harvested_ha[w]), call. = FALSE)
  }
  invisible(TRUE)
}

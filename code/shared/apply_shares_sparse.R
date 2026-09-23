# Multiply a use matrix by supply shares without building the two large replicated
# intermediates. Equivalent to the original step 15 code
#
#   mr_x <- x[match(comms, rownames(x)), ]            # use rows copied once per origin
#   y_k  <- y[, match(col_area, colnames(y))]         # share columns copied once per use column
#   (optional) y_k[, own_cols] <- 1 where origin area == column area, else 0
#   mr_x * y_k
#
# but it only touches the nonzero cells of x: each nonzero (commodity r, column j) is
# paired with the nonzero shares of commodity r into the area of column j.
#
# x        : dgCMatrix, commodities (rownames = comm_code) x use columns
# y        : dgCMatrix, "origin_comm" rows x destination areas (colnames = area codes)
# comms    : comm_code of each row of y
# col_area : numeric area code of each column of x
# own_cols : column indices of x that are sourced only domestically
#            (step 15's stock_withdrawal rule); NULL for none
apply_shares_sparse <- function(x, y, comms, col_area, own_cols = NULL) {
  rn   <- match(comms, rownames(x))
  kcol <- match(col_area, as.numeric(colnames(y)))

  xt <- as.data.table(summary(x)); setnames(xt, c("r", "cj", "v"))
  xt <- xt[v != 0]
  yt <- as.data.table(summary(y)); setnames(yt, c("i", "kk", "s"))
  yt[, r := rn[i]]
  yt <- yt[!is.na(r) & s != 0]

  own <- NULL
  if (length(own_cols)) {
    own <- xt[cj %in% own_cols]
    xt  <- xt[!cj %in% own_cols]
  }

  xt[, kk := kcol[cj]]
  pr <- yt[xt, on = .(r, kk), nomatch = 0L, allow.cartesian = TRUE,
           .(i, j = cj, val = v * s)]

  if (!is.null(own) && nrow(own)) {
    # share is 1 for the row of the same commodity whose origin is the column's own area
    row_area <- as.numeric(sub("_.*", "", rownames(y)))
    ri <- data.table(i = seq_along(rn), r = rn, a = row_area)[!is.na(r)]
    own[, a := col_area[cj]]
    pr <- rbind(pr, ri[own, on = .(r, a), nomatch = 0L, .(i, j = cj, val = v)])
  }

  pr <- pr[val != 0]
  sparseMatrix(i = pr$i, j = pr$j, x = pr$val, dims = c(nrow(y), ncol(x)),
               dimnames = list(rownames(y), colnames(x)))
}

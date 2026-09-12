# ============================================================================
# FABIO tidy helpers - small data.table / matrix utilities for reshaping the
# FABIO supply-use and MRIO tables. Sourced by pipeline steps 12, 14 and 15.
# Provides: dt_replace, na_sum, replace_RoW, split_tcf.
# (Adapted from the fineprint-global/fabio helper library; unused helpers from
#  the original library were removed 2026-08 - see git history.)
# ============================================================================

# Replace values where `fun` applies
dt_replace <- function(x, fun = is.na, value = 0,
  cols = seq_len(ncol(x)), verbose = TRUE) {

  n_replaced <- 0
  for(col in cols) {
    fun_applied <- fun(x[[col]])
    if(verbose) {n_replaced <- n_replaced + sum(fun_applied, na.rm = TRUE)}
    set(x, i = which(fun_applied), j = col, value)
  }
  if(verbose) {
    cat("Replaced ", n_replaced, " values where `", deparse(substitute(fun)),
      "` (applies to columns ", paste0("'", cols, "'", collapse = ", "),
      ") with ", value, ".\n", sep = "")
  }
  return(x)
}


# Recursive sum over vectors with NA, returns NA if all values are NA
na_sum <- function(..., rowwise = TRUE) {
  dots <- list(...)
  if(length(dots) == 1) { # Base
    ifelse(all(is.na(dots[[1]])), NA_real_, sum(dots[[1]], na.rm = TRUE))
  } else { # Recurse
    if(rowwise) {
      x <- do.call(cbind, dots)
      return(apply(x, 1, na_sum))
    }
    return(na_sum(vapply(dots, na_sum, double(1L))))
  }
}


# Replace RoW values
replace_RoW <- function(x, cols = "area_code", codes) {

  name_cols <- gsub("(.*)_code", "\\1", cols)
  n_replaced <- 0
  for(i in seq_along(cols)) {
    fun_applied <- !x[[cols[i]]] %in% codes
    n_replaced <- n_replaced + sum(fun_applied, na.rm = TRUE)
    set(x, i = which(fun_applied), j = cols[i], 999)
    set(x, i = which(fun_applied), j = name_cols[i], "RoW")
  }
  cat("Aggregated ", n_replaced, " areas in columns ",
    paste0("'", c(cols, name_cols), "'", collapse = ", "),
    " to 999 / RoW.\n", sep = "")
  return(x)
}


# Split processing use over processes
split_tcf <- function(y, z, C, cap = TRUE) {
  Z <- diag(z)
  X <- C %*% Z
  x <- rowSums(X)
  exists <- x != 0 # exists kicks 0 potential outputs
  if(!any(exists)) {return(NA)}
  P <- ((X[exists, ] / x[exists]) * y[exists]) / C[exists,]
  P[is.na(P)] <- 0
  # P <- .sparseDiagonal(sum(exists), y[exists] / x[exists]) %*%
  #   (X[exists, ] / x[exists]) %*% Z
  if(cap) {
    cap <- rep(0, length(z))
    exists_inp <- z != 0
    if(class(P)!="numeric") {
      cap[exists_inp] <- colSums(P)[exists_inp] / z[exists_inp]
    } else {
      cap[exists_inp] <- P[exists_inp] / z[exists_inp]
    }
    cap[cap < 1] <- 1 # Don't want to scale up
    P <- P %*% diag(1 / cap)
  }
  out <- data.table(as.matrix(P))
  colnames(out) <- colnames(C)
  out[, item_code_proc := rownames(C)[exists]]
  out <- melt(out, id.vars = "item_code_proc", variable.name = "item_code",
    variable.factor = FALSE)
  out[, `:=`(item_code_proc = as.integer(item_code_proc),
    item_code = as.integer(item_code))]

  return(out)
}

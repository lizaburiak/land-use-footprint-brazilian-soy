### soyprint conservation checks ###
# assert_equal(): halt-on-failure equality check for mass-conservation
# invariants (municipal totals vs national CBS totals, matrix margins, herd
# partitions). Uses all.equal() rather than `==` so identities that hold in
# exact arithmetic pass under floating-point noise, and stop() rather than a
# printed TRUE/FALSE so a broken allocation halts the run instead of
# scrolling past in the log. Vectors are compared element-wise.
# warn_only = TRUE downgrades the failure to a loud warning; use it only for
# diagnostics with known, documented deviations (e.g. the step-02 chicken
# partition, where missing IBGE layer counts put NAs on the split side).
# No package dependencies on purpose: every pipeline step can source this.
assert_equal <- function(actual, target, label, tolerance = 1e-6, warn_only = FALSE) {
  chk <- all.equal(actual, target, tolerance = tolerance, check.attributes = FALSE)
  if (!isTRUE(chk)) {
    msg <- paste0("conservation check failed [", label, "]: ",
                  paste(chk, collapse = "; "))
    if (warn_only) warning(msg, call. = FALSE) else stop(msg, call. = FALSE)
  } else {
    cat("check ok [", label, "]\n", sep = "")
  }
  invisible(isTRUE(chk))
}

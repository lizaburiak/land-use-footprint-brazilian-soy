# Summarise the input-assumption sensitivity screen (code/analysis/sens_inputs.sh).
# Reads each variant's pearson_global.csv, extracts the model-vs-TRASE correlation
# (euclid + downscale paths), and reports the spread each assumption induces.
#
# Usage: Rscript code/analysis/sens_inputs_summary.R [YEAR]

suppressMessages({library(dplyr); library(tidyr)})
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2019L
ROOT <- sprintf("results/sensitivity/inputs_%d", YEAR)

# map variant name -> assumption group
group_of <- function(v) dplyr::case_when(
  v == "base"                    ~ "base",
  grepl("^crush_(prod|dir)", v)  ~ "1_crush_split",
  grepl("^gamma_", v)            ~ "1_crush_gamma",
  grepl("^feed_jit", v)          ~ "2_feed_rate",
  v == "feed_stateavg"           ~ "2_feed_shares",
  TRUE                           ~ "other")

num <- function(x) as.numeric(gsub("[*]", "", x))   # strip significance stars

vdirs <- list.dirs(ROOT, recursive = FALSE)
stopifnot(length(vdirs) > 0)

rows <- lapply(vdirs, function(d) {
  f <- file.path(d, "pearson_global.csv")
  if (!file.exists(f)) return(NULL)
  g <- read.csv(f, stringsAsFactors = FALSE, check.names = FALSE)
  names(g)[1] <- "weighting"
  data.frame(variant   = basename(d),
             weighting = g$weighting,
             euclid    = num(g$euclid),
             downscale = num(g$downscale),
             stringsAsFactors = FALSE)
})
tidy <- bind_rows(rows) %>% mutate(assumption = group_of(variant))
write.csv(tidy, file.path(ROOT, "tidy_correlations.csv"), row.names = FALSE)

base_val <- tidy %>% filter(variant == "base") %>%
  select(weighting, base_euclid = euclid, base_downscale = downscale)

# headline: the raw ("base" weighting) correlation, euclid path
cat(sprintf("\n=== Input-assumption sensitivity, %d ===\n", YEAR))
cat("Metric: Pearson r vs TRASE, weighting='base', euclid path (downscale in parens)\n\n")

hl <- tidy %>% filter(weighting == "base")
b_e <- hl$euclid[hl$variant == "base"]; b_d <- hl$downscale[hl$variant == "base"]
cat(sprintf("  base: euclid=%.4f  downscale=%.4f\n\n", b_e, b_d))

summ <- hl %>% filter(assumption != "base") %>% group_by(assumption) %>%
  summarise(n = dplyr::n(),
            euclid_min = min(euclid), euclid_med = median(euclid), euclid_max = max(euclid),
            euclid_spread = euclid_max - euclid_min,
            d_from_base_min = min(euclid) - b_e, d_from_base_max = max(euclid) - b_e,
            .groups = "drop") %>%
  arrange(desc(euclid_spread))

print(as.data.frame(summ), digits = 4, row.names = FALSE)
write.csv(summ, file.path(ROOT, "assumption_spread.csv"), row.names = FALSE)

cat("\nRanking by induced correlation spread (widest = most influential):\n")
for (i in seq_len(nrow(summ)))
  cat(sprintf("  %d. %-16s spread=%.4f  (r range %.4f..%.4f, %d runs)\n",
              i, summ$assumption[i], summ$euclid_spread[i],
              summ$euclid_min[i], summ$euclid_max[i], summ$n[i]))
cat(sprintf("\nWrote: %s/{tidy_correlations,assumption_spread}.csv\n", ROOT))

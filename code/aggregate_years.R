#!/usr/bin/env Rscript
# Aggregate per-year results from code/new pipeline into a multi-year summary table.
# Reads data/generated/outputs/05_YYYY/CBS_SOY_bal.rds and data/generated/outputs/10_YYYY/comp_list.rds.
# Writes:
#   results/tables/multi_year_summary.csv  — one row per year
#   results/tables/multi_year_per_dest.csv — long format, one row per year×destination
#   results/tables/multi_year_benchmarks.csv — per-year aggregate TRASE benchmarks
suppressPackageStartupMessages({
  library(dplyr)
  library(Metrics)
})

years <- 2013:2020
out_dir <- "results/tables"; dir.create(out_dir, showWarnings = FALSE)

summary_rows <- list()
per_dest_rows <- list()
benchmark_rows <- list()

for (y in years) {
  cbs_path <- sprintf("data/generated/outputs/05_%d/CBS_SOY_bal.rds", y)
  cmp_path <- sprintf("data/generated/outputs/10_%d/comp_list.rds", y)
  if (!file.exists(cbs_path)) { cat("[skip]", y, ": no CBS\n"); next }
  cbs <- readRDS(cbs_path)

  # National totals
  summary_rows[[as.character(y)]] <- data.frame(
    year = y,
    bean_production_Mt = cbs["bean","production"]/1e6,
    bean_export_Mt     = cbs["bean","export"]/1e6,
    bean_import_Mt     = cbs["bean","import"]/1e6,
    bean_processing_Mt = cbs["bean","processing"]/1e6,
    bean_feed_Mt       = cbs["bean","feed"]/1e6,
    bean_food_Mt       = cbs["bean","food"]/1e6,
    bean_seed_Mt       = cbs["bean","seed"]/1e6,
    oil_production_Mt  = cbs["oil","production"]/1e6,
    oil_export_Mt      = cbs["oil","export"]/1e6,
    oil_food_Mt        = cbs["oil","food"]/1e6,
    oil_other_Mt       = cbs["oil","other"]/1e6,
    cake_production_Mt = cbs["cake","production"]/1e6,
    cake_export_Mt     = cbs["cake","export"]/1e6,
    cake_feed_Mt       = cbs["cake","feed"]/1e6
  )

  if (!file.exists(cmp_path)) { cat("[skip benchmarks for]", y, ": no comp_list\n"); next }

  mun <- readRDS(cmp_path)$mun
  # Per-destination roll-up
  nat <- mun %>% group_by(to_code, to_name) %>%
    summarise(
      trase_kt     = sum(trase,          na.rm=TRUE)/1000,
      multimode_kt = sum(multimode_mean, na.rm=TRUE)/1000,
      euclid_kt    = sum(euclid,         na.rm=TRUE)/1000,
      downscale_kt = sum(downscale,      na.rm=TRUE)/1000,
      .groups = "drop"
    ) %>%
    mutate(year = y, .before = to_code) %>%
    arrange(desc(trase_kt))
  per_dest_rows[[as.character(y)]] <- nat

  # Aggregate benchmark metrics
  m <- mun %>% filter(trase > 0)
  by_d <- mun %>%
    group_by(to_code) %>%
    filter(sum(trase, na.rm=TRUE) > 0, n() >= 5,
           sd(trase, na.rm=TRUE) > 0, sd(euclid, na.rm=TRUE) > 0,
           sd(downscale, na.rm=TRUE) > 0) %>%
    summarise(
      r_eu  = cor(trase, euclid),
      r_ds  = cor(trase, downscale),
      rmse_eu = rmse(trase, euclid),
      rmse_ds = rmse(trase, downscale),
      .groups="drop")

  pool_r_eu <- if (nrow(m) > 1 && sd(m$euclid) > 0) cor(m$trase, m$euclid) else NA
  pool_r_ds <- if (nrow(m) > 1 && sd(m$downscale) > 0) cor(m$trase, m$downscale) else NA

  benchmark_rows[[as.character(y)]] <- data.frame(
    year = y,
    n_destinations    = nrow(by_d),
    n_flows_nonzero   = nrow(m),
    trase_total_Mt    = sum(mun$trase,          na.rm=TRUE)/1e6,
    euclid_total_Mt   = sum(mun$euclid,         na.rm=TRUE)/1e6,
    downscale_total_Mt= sum(mun$downscale,      na.rm=TRUE)/1e6,
    avg_r_euclid_dest = mean(by_d$r_eu, na.rm=TRUE),
    avg_r_downscale_dest = mean(by_d$r_ds, na.rm=TRUE),
    median_rmse_euclid = median(by_d$rmse_eu, na.rm=TRUE),
    median_rmse_downscale = median(by_d$rmse_ds, na.rm=TRUE),
    pool_r_euclid     = pool_r_eu,
    pool_r_downscale  = pool_r_ds
  )
  cat("[ok]", y, ":", nrow(nat), "destinations,", nrow(m), "non-zero flows, avg r_eu =", round(mean(by_d$r_eu, na.rm=TRUE), 3), "\n")
}

summary_df   <- do.call(rbind, summary_rows)
per_dest_df  <- do.call(rbind, per_dest_rows)
benchmark_df <- do.call(rbind, benchmark_rows)

write.csv(summary_df,   file.path(out_dir, "multi_year_summary.csv"),   row.names = FALSE)
write.csv(per_dest_df,  file.path(out_dir, "multi_year_per_dest.csv"),  row.names = FALSE)
write.csv(benchmark_df, file.path(out_dir, "multi_year_benchmarks.csv"), row.names = FALSE)

cat("\n=== summary ===\n"); print(summary_df, row.names = FALSE)
cat("\n=== benchmarks ===\n"); print(benchmark_df, row.names = FALSE)
cat("\nWrote three CSVs to results/tables/\n")

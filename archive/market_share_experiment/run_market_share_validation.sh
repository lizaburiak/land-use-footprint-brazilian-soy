#!/usr/bin/env bash
# Run end-to-end validation: 2013 with market_share allocation, compare vs equal
# baseline already in outputs/10_2013/. Writes side-by-side comparison.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. Stash baseline outputs (already computed under outputs/10_2013/ with equal alloc)
mkdir -p outputs_market_share/00_2013 outputs_market_share/01_2013 outputs_market_share/05_2013 outputs_market_share/10_2013

echo "=== Running 00_data_preparation.R with ALLOCATION_METHOD=market_share ==="
ALLOCATION_METHOD=market_share Rscript R/reproduction/00_data_preparation/00_data_preparation.R 2013 2>&1 | tail -30

# Copy the new outputs to a side directory
cp outputs/00_2013/SOY_MUN_00.rds outputs_market_share/00_2013/
cp outputs/00_2013/GEO_MUN_SOY_00.rds outputs_market_share/00_2013/ 2>/dev/null || true

echo ""
echo "=== Running 01_consumption_and_processing.R ==="
Rscript R/reproduction/01_consumption_and_processing.R 2013 2>&1 | tail -20

echo ""
echo "=== Running steps 02-11 ==="
for step in 02_livestock_systems 03_feed_use 04_trade_harmonization 05_balancing \
            06_transport_cost 07_transport_R 08_export_link_mean 10_create_benchmarks \
            11_analyse_benchmarks; do
  echo "--- $step ---"
  Rscript "R/reproduction/${step}.R" 2013 2>&1 | tail -10 || { echo "STEP FAILED: $step"; exit 1; }
done

echo ""
echo "=== Computing pooled and per-destination correlations ==="
Rscript /tmp/check_corr.R 2>&1 | tail -50

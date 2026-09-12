#!/bin/bash
# Run the full multimode transport chain for one year:
#   06 (cost matrices) -> parquet export -> HiGHS LP central solve -> 08 -> 10 -> 11
# Usage: bash code/run_multimode_year.sh YEAR
# Logs to logs/year_YEAR/, appends one status line per step to logs/multimode_runs.log

set -u
YEAR=$1
cd "$(dirname "$0")/.."
mkdir -p "logs/year_${YEAR}"
STATUS_LOG="logs/multimode_runs.log"

step () {
  local name=$1; shift
  local t0=$(date +%s)
  "$@" > "logs/year_${YEAR}/${name}.log" 2>&1
  local rc=$?
  local mins=$(( ($(date +%s) - t0) / 60 ))
  echo "$(date '+%F %T') ${YEAR} ${name} rc=${rc} (${mins} min)" >> "$STATUS_LOG"
  if [ $rc -ne 0 ]; then
    echo "$(date '+%F %T') ${YEAR} ABORTED at ${name}" >> "$STATUS_LOG"
    exit $rc
  fi
}

# skip step 06 if its outputs already exist (e.g. reruns)
if [ ! -f "data/generated/outputs/06_${YEAR}/dist_matrices.Rdata" ]; then
  step 06_transport_cost_mm  env R_MAX_VSIZE=100Gb Rscript code/pipeline/06_transport_cost.R "$YEAR"
else
  echo "$(date '+%F %T') ${YEAR} 06_transport_cost_mm skipped (exists)" >> "$STATUS_LOG"
fi
step export_parquet_mm     Rscript code/pipeline/transport_lp/export_to_parquet.R "$YEAR"
if [ ! -f "data/generated/outputs/gams/bs_res_${YEAR}/00000.rds" ]; then
  step solve_lp_mm           .venv/bin/python -u code/pipeline/transport_lp/solve_one.py "$YEAR" --threads 4
else
  echo "$(date '+%F %T') ${YEAR} solve_lp_mm skipped (exists)" >> "$STATUS_LOG"
fi
step 08_export_link_mean_mm Rscript code/pipeline/08_export_link_mean.R "$YEAR"
step 08_export_link_sep_mm  Rscript code/pipeline/08_export_link_sep.R "$YEAR"
step 10_create_benchmarks_mm Rscript code/pipeline/10_create_benchmarks.R "$YEAR"
step 11_analyse_benchmarks_mm Rscript code/pipeline/11_analyse_benchmarks.R "$YEAR"
echo "$(date '+%F %T') ${YEAR} COMPLETE" >> "$STATUS_LOG"

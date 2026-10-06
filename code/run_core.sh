#!/usr/bin/env bash
# Steps 00-11 for one year, inside an isolated worker dir created with FRESH=1 code/setup_worker.sh.
# Everything is written under the worker (data/generated/outputs/NN_<Y>); the data root is only read.
# Follow with code/run_fp.sh for steps 12-20.
#
# Usage (from the worker root): bash code/run_core.sh YYYY
set -u
Y="$1"; L=run_logs; mkdir -p $L
export SOYPRINT_DATA_DIR="$PWD/data"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 R_DATATABLE_NUM_THREADS=1
TSV=$L/core_steps.tsv; echo -e "step\texit\tseconds" > $TSV
step () {
  local name=$1 script=$2 t0=$(date +%s)
  echo "$(date +%T) [$Y] >>> $name"
  Rscript "$script" $Y > $L/$name.log 2>&1; local ec=$?
  echo -e "$name\t$ec\t$(( $(date +%s) - t0 ))" >> $TSV
  if [ $ec -ne 0 ]; then echo "$(date +%T) [$Y] !!! $name FAILED exit $ec"; tail -20 $L/$name.log; echo "RUN FAILED at $name"; exit $ec; fi
  echo "$(date +%T) [$Y] === $name OK"
}
step 00_data_preparation    code/pipeline/00_data_preparation/00_data_preparation.R
step 00_FAO                 code/pipeline/00_FAO_consitency_checks.R
step 01_consumption         code/pipeline/01_consumption_and_processing.R
step 02_livestock           code/pipeline/02_livestock_systems.R
step 03_feed                code/pipeline/03_feed_use.R
step 04_trade               code/pipeline/04_trade_harmonization.R
step 05_balancing           code/pipeline/05_balancing.R
step 05b_stock_decomp       code/pipeline/05b_stock_decomposition.R
step 07_transport_R         code/pipeline/07_transport_R.R
step 08_export_link_mean    code/pipeline/08_export_link_mean.R
step 08_export_link_sep     code/pipeline/08_export_link_sep.R
step 10_create_benchmarks   code/pipeline/10_create_benchmarks.R
step 11_analyse_benchmarks  code/pipeline/11_analyse_benchmarks.R
echo "CORE COMPLETE"

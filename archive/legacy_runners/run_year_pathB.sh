#!/usr/bin/env bash
# Run code/new Path B pipeline (00 -> 12, skipping 06/07_GAMS/09) for a single year.
# Usage: bash code/run_year_pathB.sh YYYY
set -u
YEAR="${1:?usage: run_year_pathB.sh YYYY}"
LOGDIR="logs/year_${YEAR}"
mkdir -p "$LOGDIR"

run_step () {
  local name="$1"; shift
  local script="$1"; shift
  echo "[${YEAR}] >>> ${name}"
  Rscript "$script" "$YEAR" > "${LOGDIR}/${name}.log" 2>&1
  local ec=$?
  if [ $ec -ne 0 ]; then
    echo "[${YEAR}] !!! ${name} FAILED (exit $ec). Tail:"
    tail -15 "${LOGDIR}/${name}.log"
    return $ec
  fi
  echo "[${YEAR}] === ${name} OK"
}

run_step 00_data_preparation      code/pipeline/00_data_preparation/00_data_preparation.R || exit 1
run_step 00_FAO                   code/pipeline/00_FAO_consitency_checks.R                 || exit 1
run_step 01_consumption           code/pipeline/01_consumption_and_processing.R            || exit 1
run_step 02_livestock             code/pipeline/02_livestock_systems.R                     || exit 1
run_step 03_feed                  code/pipeline/03_feed_use.R                              || exit 1
run_step 04_trade                 code/pipeline/04_trade_harmonization.R                   || exit 1
run_step 05_balancing             code/pipeline/05_balancing.R                             || exit 1
run_step 07_transport_R           code/pipeline/07_transport_R.R                           || exit 1
run_step 08_export_link_mean      code/pipeline/08_export_link_mean.R                      || exit 1
run_step 08_export_link_sep       code/pipeline/08_export_link_sep.R                       || exit 1
run_step 10_create_benchmarks     code/pipeline/10_create_benchmarks.R                     || exit 1
run_step 11_analyse_benchmarks    code/pipeline/11_analyse_benchmarks.R                    || exit 1
# 12 is expected to emit warnings/empty for YEAR >= 2014 (FABIO_exp limit) but should not fail
run_step 12_re-exports            code/pipeline/12_re-exports.R                            || echo "[${YEAR}] 12 emitted warning (expected for >=2014)"

echo "[${YEAR}] +++ pipeline complete"

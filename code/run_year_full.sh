#!/usr/bin/env bash
# Run the FULL reproduction pipeline (steps 00 -> 21) for a single year.
#
#   Core model (00-12, Euclidean "Path B"): fatal — stops the year on failure.
#   FABIO MRIO + footprints (13-21):        soft — they stop at a guard when the
#                                           FABIO/EXIOBASE data is absent (see
#                                           WHAT_IS_MISSING.md section 4); recorded
#                                           and skipped, not treated as a failure.
#
# Optional multimode transport (06, 07_GAMS, 09) is NOT run here — it needs the
# ANTAQ/ANTT data + a GAMS licence (or the Python transport_lp). See RUNBOOK.md.
#
# Usage: bash code/run_year_full.sh YYYY
set -u
cd "$(dirname "$0")/.."
# Footprint steps 15/17 build large MRIO matrices that blow past R's default 16 Gb
# vector-memory ceiling; raise it (as run_footprints.sh / run_from05.sh do).
export R_MAX_VSIZE="${R_MAX_VSIZE:-48Gb}"
YEAR="${1:?usage: run_year_full.sh YYYY}"
LOGDIR="logs/year_${YEAR}"
mkdir -p "$LOGDIR"

# fatal step: return non-zero stops the caller
run_step () {
  local name="$1"; shift
  local script="$1"; shift
  echo "[${YEAR}] >>> ${name}"
  Rscript "$script" "$YEAR" > "${LOGDIR}/${name}.log" 2>&1
  local ec=$?
  if [ $ec -ne 0 ]; then
    echo "[${YEAR}] !!! ${name} FAILED (exit $ec). Tail:"; tail -15 "${LOGDIR}/${name}.log"
    return $ec
  fi
  echo "[${YEAR}] === ${name} OK"
}

# soft step: never aborts the year; reports OK / SKIPPED / FAILED
run_step_soft () {
  local name="$1"; shift
  local script="$1"; shift
  echo "[${YEAR}] >>> ${name}"
  Rscript "$script" "$YEAR" > "${LOGDIR}/${name}.log" 2>&1
  local ec=$?
  if [ $ec -eq 0 ]; then echo "[${YEAR}] === ${name} OK"
  elif grep -q "FABIO stage" "${LOGDIR}/${name}.log"; then
    echo "[${YEAR}] ~~~ ${name} SKIPPED (FABIO/EXIOBASE data missing)"
  else
    echo "[${YEAR}] !!! ${name} FAILED (exit $ec). Tail:"; tail -8 "${LOGDIR}/${name}.log"
  fi
}

# ---- core model: steps 00-12 (Path B) ----
run_step 00_data_preparation   code/pipeline/00_data_preparation/00_data_preparation.R || exit 1
run_step 00_FAO                code/pipeline/00_FAO_consitency_checks.R                 || exit 1
run_step 01_consumption        code/pipeline/01_consumption_and_processing.R            || exit 1
run_step 02_livestock          code/pipeline/02_livestock_systems.R                     || exit 1
run_step 03_feed               code/pipeline/03_feed_use.R                              || exit 1
run_step 04_trade              code/pipeline/04_trade_harmonization.R                   || exit 1
run_step 05_balancing          code/pipeline/05_balancing.R                            || exit 1
run_step 07_transport_R        code/pipeline/07_transport_R.R                          || exit 1
run_step 08_export_link_mean   code/pipeline/08_export_link_mean.R                     || exit 1
run_step 08_export_link_sep    code/pipeline/08_export_link_sep.R                      || exit 1
# 10/11 self-skip when there is no TRASE data (years < 2004)
run_step 10_create_benchmarks  code/pipeline/10_create_benchmarks.R                    || exit 1
run_step 11_analyse_benchmarks code/pipeline/11_analyse_benchmarks.R                   || exit 1
run_step 12_re-exports         code/pipeline/12_re-exports.R                           || echo "[${YEAR}] 12 warning (expected >=2014)"

# ---- FABIO MRIO + land-use footprints: steps 13-21 (need FABIO/EXIOBASE data) ----
run_step_soft 13_supply            code/pipeline/13_supply.R
run_step_soft 14_use               code/pipeline/14_use.R
run_step_soft 15_mrsut             code/pipeline/15_mrsut.R
run_step_soft 16_mrio              code/pipeline/16_mrio.R
run_step_soft 17_leontief_inverse  code/pipeline/17_leontief_inverse.R
run_step_soft 18_hybridize_B       code/pipeline/18_hybridize_B_quadrant.R
run_step_soft 19_invert_B          code/pipeline/19_invert_B.R
run_step_soft 20_footprints        code/pipeline/20_footrpints.R
run_step_soft 21_probability_maps  code/pipeline/21_probability_maps.R

echo "[${YEAR}] +++ full pipeline complete (00-12 core; 13-21 as data allows)"

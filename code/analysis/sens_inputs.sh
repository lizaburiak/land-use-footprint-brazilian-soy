#!/usr/bin/env bash
# Input-assumption sensitivity screen (cheap chain, TRASE-correlation metric).
#
# Perturbs the two highest-leverage input assumptions and measures the effect on
# the model-vs-TRASE correlation, WITHOUT the transport LP (06) or the MRIO
# footprint chain (12-21). Steps 00 + 00_FAO are run once (no perturbation
# touches them); every variant then regenerates the FULL tail 01 -> 11 with only
# its own env set, so no variant ever reads another variant's perturbed output.
#
#   #1 crush location  : MC_CRUSH_SPLIT (step 01) + MC_CRUSHCAP_GAMMA (step 01)
#   #2 feed / livestock: MC_FEED_SYS_JITTER (step 03) + MC_FEED_SHARES (step 02)
#
# Usage: bash code/analysis/sens_inputs.sh [YEAR] [smoke]
#   YEAR   default 2019
#   smoke  if present, runs base + 1 crush + 1 feed variant only (machinery check)
#
# Output: results/sensitivity/inputs_<YEAR>/<variant>/pearson_global.csv (+ by_dest)
set -u
cd "$(dirname "$0")/../.."

YEAR="${1:-2019}"
MODE="${2:-full}"

# Screen tracks the Euclidean path only (transport dropped): make every step-08
# run ignore any stored GAMS bootstrap flows, which are stale under perturbed supply.
export SENS_EUCLID_ONLY=1
OUT="results/sensitivity/inputs_${YEAR}"
LOG="logs/sens_${YEAR}"
BENCH="results/tables/benchmarks/${YEAR}"
mkdir -p "$OUT" "$LOG"

# Full cheap chain, step 01 -> step 11 (steps 00 + 00_FAO run once, before any variant).
STEP_NAME=(01_consumption 02_livestock 03_feed 04_trade 05_balancing \
           07_transport_R 08_export_link_mean 08_export_link_sep \
           10_create_benchmarks 11_analyse_benchmarks)
STEP_FILE=(code/pipeline/01_consumption_and_processing.R \
           code/pipeline/02_livestock_systems.R \
           code/pipeline/03_feed_use.R \
           code/pipeline/04_trade_harmonization.R \
           code/pipeline/05_balancing.R \
           code/pipeline/07_transport_R.R \
           code/pipeline/08_export_link_mean.R \
           code/pipeline/08_export_link_sep.R \
           code/pipeline/10_create_benchmarks.R \
           code/pipeline/11_analyse_benchmarks.R)

# variant <name> [<env-assignments>...] : regenerate 01->11 with the given env,
# then harvest the correlation CSVs. No env == base. harvest="no" skips harvest
# (used for the final restore pass).
variant () {
  local name="$1"; shift
  local harvest="yes"
  if [ "$name" = "__restore__" ]; then harvest="no"; name="restore_base"; fi
  local vdir="$OUT/$name"; local vlog="$LOG/$name"
  # Resume mode: skip variants already harvested (a killed run leaves partial
  # disk state only for the variant it died in; completed ones are self-contained).
  if [ "${SENS_RESUME:-0}" = "1" ] && [ "$harvest" = "yes" ] && [ -s "$vdir/pearson_global.csv" ]; then
    echo "[$YEAR] === variant: $name  (resume: already harvested, skipping)"
    return 0
  fi
  mkdir -p "$vlog"; [ "$harvest" = "yes" ] && mkdir -p "$vdir"
  echo "[$YEAR] === variant: $name  (env: ${*:-none})"
  local i
  for ((i=0; i<${#STEP_NAME[@]}; i++)); do
    env "$@" Rscript "${STEP_FILE[$i]}" "$YEAR" > "$vlog/${STEP_NAME[$i]}.log" 2>&1
    if [ $? -ne 0 ]; then
      echo "[$YEAR] !!! $name FAILED at ${STEP_NAME[$i]}. Tail:"
      tail -12 "$vlog/${STEP_NAME[$i]}.log"; return 1
    fi
  done
  if [ "$harvest" = "yes" ]; then
    cp "$BENCH/pearson_global.csv"  "$vdir/" 2>/dev/null
    cp "$BENCH/pearson_by_dest.csv" "$vdir/" 2>/dev/null
    echo "[$YEAR]     harvested -> $vdir/pearson_global.csv"
  fi
}

# ---- steps 00 + 00_FAO once (unperturbed; shared by all variants) ----
echo "[$YEAR] === steps 00 + 00_FAO (once) ==="
mkdir -p "$LOG/base"
Rscript code/pipeline/00_data_preparation/00_data_preparation.R "$YEAR" > "$LOG/base/00_data_preparation.log" 2>&1 \
  || { echo "00 failed"; tail -12 "$LOG/base/00_data_preparation.log"; exit 1; }
Rscript code/pipeline/00_FAO_consitency_checks.R "$YEAR" > "$LOG/base/00_FAO.log" 2>&1 \
  || { echo "00_FAO failed"; exit 1; }

variant base || exit 1

if [ "$MODE" = "smoke" ]; then
  variant crush_dir_s01 MC_CRUSH_SPLIT=dirichlet MC_SPLIT_SEED=1 MC_SPLIT_ALPHA=2
  variant feed_jit_s01  MC_FEED_SYS_JITTER=0.3 MC_FEED_SEED=1
  variant __restore__
  echo "[$YEAR] +++ smoke run complete"; exit 0
fi

# ---- #1 crush location: within-state split + allocation sharpness ----
variant crush_prod MC_CRUSH_SPLIT=prod
for s in $(seq 1 10); do
  variant "crush_dir_s$(printf '%02d' "$s")" MC_CRUSH_SPLIT=dirichlet MC_SPLIT_SEED="$s" MC_SPLIT_ALPHA=1
done
variant gamma_0.5 MC_CRUSHCAP_GAMMA=0.5
variant gamma_2.0 MC_CRUSHCAP_GAMMA=2.0

# ---- #2 feed / livestock: relative-rate jitter + state-avg composition ----
for s in $(seq 1 10); do
  variant "feed_jit_s$(printf '%02d' "$s")" MC_FEED_SYS_JITTER=0.3 MC_FEED_SEED="$s"
done
variant feed_stateavg MC_FEED_SHARES=state_avg

# ---- restore canonical (base) outputs on disk ----
variant __restore__

echo "[$YEAR] +++ input-sensitivity screen complete -> $OUT"
echo "[$YEAR]     summarise with: Rscript code/analysis/sens_inputs_summary.R $YEAR"

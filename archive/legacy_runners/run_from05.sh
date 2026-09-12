#!/usr/bin/env bash
# Re-run Path B from step 05 (balancing) through the footprints (20), for the years passed as
# arguments. Used after the stock-withdrawal reallocation fix in 05_balancing.R: steps 00-04
# are unaffected by the stock allocation, so we start at 05 to save the heavy data-prep.
# Footprint steps 15/17 need the raised R vector-memory ceiling.
set -u
cd "$(dirname "$0")/.."
export R_MAX_VSIZE="${R_MAX_VSIZE:-48Gb}"

STEPS=(
  05_balancing 07_transport_R 08_export_link_mean 08_export_link_sep
  10_create_benchmarks 11_analyse_benchmarks 12_re-exports
  13_supply 14_use 15_mrsut 16_mrio 17_leontief_inverse
  18_hybridize_B_quadrant 19_invert_B 20_footrpints
)

for Y in "$@"; do
  echo "==================== YEAR ${Y} (05->20) ===================="
  LOG="logs/year_${Y}"; mkdir -p "$LOG"
  ok=1
  for s in "${STEPS[@]}"; do
    echo "[${Y}] >>> ${s}"
    Rscript "code/pipeline/${s}.R" "$Y" > "${LOG}/${s}.log" 2>&1
    ec=$?
    if [ $ec -ne 0 ]; then
      echo "[${Y}] !!! ${s} FAILED (exit $ec). Tail:"; tail -12 "${LOG}/${s}.log"; ok=0; break
    fi
    echo "[${Y}] === ${s} OK"
  done
  if [ $ok -eq 1 ] && [ -f "results/footprints/${Y}_P_mass.rds" ]; then
    echo "YEAR ${Y}: COMPLETE (05-20)"
  else
    echo "YEAR ${Y}: FAILED (see ${LOG})"
  fi
done
echo "all done=$(date)"

#!/usr/bin/env bash
# v1.1 seam cross-check runner (2010-2013 overlap window) -- V11-ONLY, SAFE.
#
# For each year it runs the footprint chain (steps 12-20) ONCE with
# SOYPRINT_FORCE_V11=1, stashes the resulting v1.1 footprints to
#   footprints/xcheck_<Y>/{P,F}_{mass,value}.v11.rds
# and then RESTORES the canonical footprints from the pristine v2 stash
#   footprints/xcheck_<Y>/*.v2.rds
# so the canonical on-disk v2 footprints are never left altered.
#
# It does not rebuild v2: the current code's fresh v2 build for
# 2010/2011 produced a degenerate F_mass (28-31 Jul incident) and, separately,
# the pristine 2010/2011 v2 are a PRE-June-filter method vintage that differs
# from the 2012/2013 v2 -- rebuilding is a decision to be made explicitly, not a
# side effect of the cross-check.
#
# FORCE=1 re-runs a year even if its v11 stash already exists (needed after the
# 28 Jul race, whose v11 stashes are suspect).
#
# !!! Refuses to start if a competing footprint chain (steps 12-20) is running
# (shared non-year-suffixed intermediates would be corrupted). Transport steps
# 06-11 are orthogonal and may run concurrently.
#
# Usage:
#   FORCE=1 bash code/run_xcheck_v11.sh 2010 2011      # force clean re-run
#   bash code/run_xcheck_v11.sh                        # 2010 2011 2012 (skip if stashed)
set -u
cd "$(dirname "$0")/.."
export R_MAX_VSIZE="${R_MAX_VSIZE:-48Gb}"
FORCE="${FORCE:-}"

YEARS=("$@")
[ ${#YEARS[@]} -eq 0 ] && YEARS=(2010 2011 2012)

FP="data/generated/footprints"
PARTS="P_mass P_value F_mass F_value"
CHAIN=(
  "12_re-exports:12_re-exports.R" "13_supply:13_supply.R" "14_use:14_use.R"
  "15_mrsut:15_mrsut.R" "16_mrio:16_mrio.R" "17_leontief_inverse:17_leontief_inverse.R"
  "18_hybridize_B:18_hybridize_B_quadrant.R" "19_invert_B:19_invert_B.R" "20_footprints:20_footrpints.R"
)
SUMMARY="logs/run_xcheck_v11_summary.txt"
mkdir -p logs
{ echo "run_xcheck_v11 (v11-only)  start=$(date)  years=${YEARS[*]}  FORCE=${FORCE:-0}"; echo "----------------------------------------"; } > "$SUMMARY"

COMPET=$(ps -ax -o command 2>/dev/null | grep -E "pipeline/(1[2-9]|20)_" | grep -v grep | grep -v run_xcheck_v11)
if [ -n "$COMPET" ]; then
  echo "ABORT: competing footprint chain running:"; echo "$COMPET"
  echo "ABORT: competing footprint chain" >> "$SUMMARY"; exit 1
fi

restore_v2_fp () { local Y="$1"; for f in $PARTS; do cp "$FP/xcheck_${Y}/${f}.v2.rds" "$FP/${Y}_${f}.rds"; done; }

for Y in "${YEARS[@]}"; do
  echo "==================== YEAR ${Y} (v1.1) ===================="
  LOGDIR="logs/xcheck_v11_${Y}"; mkdir -p "$LOGDIR" "$FP/xcheck_${Y}"

  miss=""; for f in $PARTS; do [ -f "$FP/xcheck_${Y}/${f}.v2.rds" ] || miss="$f"; done
  if [ -n "$miss" ]; then
    echo "YEAR ${Y}: BLOCKED (no pristine v2 stash ${miss})" | tee -a "$SUMMARY"; continue
  fi
  if [ -z "$FORCE" ] && [ -f "$FP/xcheck_${Y}/P_mass.v11.rds" ]; then
    echo "YEAR ${Y}: SKIP (v11 stashed; set FORCE=1 to redo)" | tee -a "$SUMMARY"; continue
  fi

  ok=1
  for step in "${CHAIN[@]}"; do
    name="${step%%:*}"; file="code/pipeline/${step##*:}"
    echo "[${Y}:v11] >>> ${name}"
    SOYPRINT_FORCE_V11=1 Rscript "$file" "$Y" > "${LOGDIR}/${name}.v11.log" 2>&1
    if [ $? -ne 0 ]; then
      echo "[${Y}:v11] !!! ${name} FAILED. Tail:"; tail -12 "${LOGDIR}/${name}.v11.log"; ok=0; break
    fi
    echo "[${Y}:v11] === ${name} OK"
  done

  if [ $ok -eq 1 ]; then
    for f in $PARTS; do mv "$FP/${Y}_${f}.rds" "$FP/xcheck_${Y}/${f}.v11.rds"; done
  fi
  restore_v2_fp "$Y"   # always put pristine v2 back as canonical

  # sanity: v11 footprint finite, non-zero, non-degenerate
  verdict="FAILED"
  if [ $ok -eq 1 ]; then
    verdict=$(Rscript -e '
      suppressMessages(library(Matrix)); x<-readRDS(commandArgs(TRUE)[1])
      f<-if(is.list(x)) x$A_product else x
      cat(if(any(is.na(f))||any(is.infinite(f))) "BAD(NA/Inf)" else
          if(sum(f)<=0) "BAD(nonpositive)" else
          if(max(abs(f))>1e15) "BAD(degenerate-magnitude)" else "SANE")
    ' "$FP/xcheck_${Y}/P_mass.v11.rds" 2>/dev/null)
  fi
  if ! cmp -s "$FP/${Y}_P_mass.rds" "$FP/xcheck_${Y}/P_mass.v2.rds"; then
    echo "YEAR ${Y}: v11 ${verdict} but RESTORE FAILED -- canonical != pristine v2, INSPECT" | tee -a "$SUMMARY"
  else
    echo "YEAR ${Y}: v11 ${verdict}; canonical v2 restored (pristine)" | tee -a "$SUMMARY"
  fi
done

echo "================== SUMMARY =================="; echo "done=$(date)" >> "$SUMMARY"; cat "$SUMMARY"

#!/usr/bin/env bash
# Runner: FABIO MRIO + municipal land-use footprints (steps 13-20) over a year range.
#
# SCOPE -----------------------------------------------------------------------
#   Runnable years = 2010-2020 only:
#     - FABIO v2 core (E/Z/Y) starts at 2010  -> excludes 2000-2009
#     - EXIOBASE pxp ends at 2020             -> excludes 2021-2023
#     - Path B outputs (05_Y, 12_Y) needed    -> present for 2000-2020
#   Step 21 (30m MapBiomas grid maps) is intentionally NOT run: it is blocked
#   for every year on (a) the MapBiomas soy tiles (data/geo/mb_tiles/, GEE
#   download) and (b) R packages fasterize / gdalUtilities / rasterVis.
#
# EXECUTION -------------------------------------------------------------------
#   Strictly sequential, both across years and across steps, to stay within
#   laptop RAM (the 22,263^2 sparse inverse in steps 17/19 peaked ~3.6 GB for
#   2017 on a 17 GB machine; do NOT parallelize years).
#   Steps 13-16 write SHARED, non-year-suffixed intermediates
#   (data/generated/fabio/{cbs_final,X,Y_hybrid,Z_mass,...}.rds) which are
#   overwritten each year. Therefore a year is run 13->20 contiguously and
#   individual FABIO steps are never skipped -- only a fully-finished year (its
#   year-suffixed footprints already exist) is skipped wholesale.
#
# Usage:
#   bash code/run_footprints.sh              # 2010..2020
#   bash code/run_footprints.sh 2010 2016    # subrange
#   bash code/run_footprints.sh 2015 2015    # single year
set -u
cd "$(dirname "$0")/.."

# Raise R's vector-memory ceiling. R defaults mem.maxVSize to physical RAM (16 GB
# here); step 15 (multi-regional SUT build) peaks ~17 GB and otherwise dies with
# "vector memory limit ... reached" -> empty matrices -> zero footprints. Allowing
# R to spill a couple GB into macOS virtual memory lets it complete.
export R_MAX_VSIZE="${R_MAX_VSIZE:-48Gb}"

START="${1:-2010}"
END="${2:-2020}"
SUMMARY="logs/run_footprints_summary.txt"
mkdir -p logs
{ echo "run_footprints  start=$(date)  years=${START}..${END}"; echo "----------------------------------------"; } > "$SUMMARY"

# fatal-within-year step: non-zero return aborts the current year (not the batch)
run_step () {
  local year="$1" name="$2" script="$3" logdir="$4"
  echo "[${year}] >>> ${name}"
  Rscript "$script" "$year" > "${logdir}/${name}.log" 2>&1
  local ec=$?
  if [ $ec -ne 0 ]; then
    echo "[${year}] !!! ${name} FAILED (exit $ec). Tail:"; tail -15 "${logdir}/${name}.log"
    return $ec
  fi
  echo "[${year}] === ${name} OK"
}

for Y in $(seq "$START" "$END"); do
  echo "==================== YEAR ${Y} ===================="
  LOGDIR="logs/footprints_${Y}"; mkdir -p "$LOGDIR"

  # already complete? (year-suffixed footprint = the deliverable)
  if [ -f "data/generated/footprints/${Y}_P_mass.rds" ]; then
    echo "[${Y}] footprints already present -> SKIP"
    echo "YEAR ${Y}: SKIP (already done)" | tee -a "$SUMMARY"; continue
  fi

  # prerequisite: Path B subnational output for this year
  if [ ! -f "data/generated/outputs/05_${Y}/GEO_MUN_SOY_fin.rds" ] || [ ! -f "data/generated/outputs/12_${Y}/btd_final.rds" ]; then
    echo "[${Y}] missing Path B output (05_${Y}/12_${Y}) -> cannot run"
    echo "YEAR ${Y}: BLOCKED (no Path B 05/12)" | tee -a "$SUMMARY"; continue
  fi

  # prerequisite: raw EXIOBASE pxp for this year
  if [ ! -d "data/exiobase/pxp/IOT_${Y}_pxp" ]; then
    echo "[${Y}] missing EXIOBASE pxp (IOT_${Y}_pxp) -> cannot run"
    echo "YEAR ${Y}: BLOCKED (no EXIOBASE pxp)" | tee -a "$SUMMARY"; continue
  fi

  # EXIOBASE Leontief inverse (year-suffixed output -> safe to skip if present)
  if [ ! -f "data/exiobase/pxp/${Y}_L.RData" ]; then
    run_step "$Y" "prep_exiobase_L" code/prep/prep_exiobase_L.R "$LOGDIR" \
      || { echo "YEAR ${Y}: FAILED at EXIOBASE prep" | tee -a "$SUMMARY"; continue; }
  else
    echo "[${Y}] EXIOBASE L present -> skip prep"
  fi

  # FABIO MRIO + footprints: steps 13-20, contiguous, never partially skipped
  ok=1
  for step in \
    "13_supply:13_supply.R" \
    "14_use:14_use.R" \
    "15_mrsut:15_mrsut.R" \
    "16_mrio:16_mrio.R" \
    "17_leontief_inverse:17_leontief_inverse.R" \
    "18_hybridize_B:18_hybridize_B_quadrant.R" \
    "19_invert_B:19_invert_B.R" \
    "20_footprints:20_footrpints.R" ; do
    name="${step%%:*}"; file="code/pipeline/${step##*:}"
    run_step "$Y" "$name" "$file" "$LOGDIR" || { ok=0; break; }
  done

  # verify the footprint is non-trivial: a degenerate MRIO (e.g. wrong-year inputs
  # -> empty supply/use -> identity Leontief inverse) writes an all-zero file while
  # every step still exits 0. Guard against that silent failure.
  nz=0
  if [ $ok -eq 1 ] && [ -f "data/generated/footprints/${Y}_P_mass.rds" ]; then
    nz=$(Rscript -e 'suppressMessages(library(Matrix)); p<-readRDS(commandArgs(TRUE)[1]); cat(as.integer(sum(p$A_product)>0))' "data/generated/footprints/${Y}_P_mass.rds" 2>/dev/null)
  fi
  if [ "$nz" = "1" ]; then
    echo "YEAR ${Y}: COMPLETE (13-20; footprints written, non-zero)" | tee -a "$SUMMARY"
  elif [ $ok -eq 1 ]; then
    echo "YEAR ${Y}: BAD OUTPUT (all-zero footprint -> degenerate MRIO; see ${LOGDIR})" | tee -a "$SUMMARY"
  else
    echo "YEAR ${Y}: FAILED (see ${LOGDIR})" | tee -a "$SUMMARY"
  fi
done

echo "================== SUMMARY ==================" | tee -a "$SUMMARY"
echo "NOTE: step 21 (30m MapBiomas grid maps) skipped for ALL years -- blocked on" | tee -a "$SUMMARY"
echo "      MapBiomas tiles + R pkgs fasterize/gdalUtilities/rasterVis." | tee -a "$SUMMARY"
echo "done=$(date)" >> "$SUMMARY"
echo; cat "$SUMMARY"

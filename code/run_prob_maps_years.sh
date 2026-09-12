#!/bin/bash
# ============================================================================
# Probability maps (step 21) for multiple years, sequentially.
# Per year: download MapBiomas Collection 9 coverage -> build soy tiles
# (prep_mb_tiles.R) -> run 21_probability_maps.R -> archive the tiles.
#
# data/geo/mb_tiles/ must contain ONLY the current year's tiles (step 21
# loads every .tif in there), so existing tiles are moved to
# data/geo/mb_tiles_<year>/ before each build.
#
# Usage: bash code/run_prob_maps_years.sh 2021 2020
# Waits for any already-running step-21 before starting.
# ============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1
GCS="https://storage.googleapis.com/mapbiomas-public/initiatives/brasil/collection_9/lclu/coverage"
LOG="logs/prob_maps_overnight.log"

echo "[driver] start $(date)" | tee -a "$LOG"

# wait for a running step-21 to finish (shared log/tile folder)
while pgrep -f "21_probability_maps.R" >/dev/null 2>&1; do sleep 120; done
echo "[driver] previous step-21 finished $(date)" | tee -a "$LOG"

for YEAR in "$@"; do
  echo "[driver] === $YEAR start $(date) ===" | tee -a "$LOG"
  mkdir -p "logs/year_${YEAR}" data/geo/_mb_staging

  # 1. coverage raster (keep a copy only in staging; it is re-downloadable)
  COV="data/geo/_mb_staging/brasil_coverage_${YEAR}.tif"
  if [ -f "data/geo/mapbiomas_coverage/brasil_coverage_${YEAR}.tif" ]; then
    cp "data/geo/mapbiomas_coverage/brasil_coverage_${YEAR}.tif" "$COV"
  elif [ ! -f "$COV" ]; then
    echo "[driver] $YEAR downloading coverage" | tee -a "$LOG"
    curl -fL --retry 3 -o "$COV.part" "$GCS/brasil_coverage_${YEAR}.tif" >> "$LOG" 2>&1 \
      && mv "$COV.part" "$COV" \
      || { echo "[driver] !!! $YEAR coverage download FAILED" | tee -a "$LOG"; continue; }
  fi

  # 2. move any existing tiles out (one year at a time in mb_tiles/)
  for f in data/geo/mb_tiles/*.tif; do
    [ -e "$f" ] || break
    ty=$(basename "$f" | sed 's/^soy\([0-9]\{4\}\)_.*/\1/')
    mkdir -p "data/geo/mb_tiles_${ty}"
    mv "$f" "data/geo/mb_tiles_${ty}/"
  done

  # 3. build this year's tiles
  echo "[driver] $YEAR building tiles" | tee -a "$LOG"
  Rscript code/prep/prep_mb_tiles.R "$YEAR" > "logs/year_${YEAR}/prep_mb_tiles.log" 2>&1 \
    || { echo "[driver] !!! $YEAR prep_mb_tiles FAILED (see logs/year_${YEAR}/prep_mb_tiles.log)" | tee -a "$LOG"; continue; }

  # 4. run step 21
  echo "[driver] $YEAR running step 21" | tee -a "$LOG"
  Rscript code/pipeline/21_probability_maps.R "$YEAR" > "logs/year_${YEAR}/21_probability_maps_groups.log" 2>&1 \
    && echo "[driver] $YEAR step 21 OK $(date)" | tee -a "$LOG" \
    || echo "[driver] !!! $YEAR step 21 FAILED (see logs/year_${YEAR}/21_probability_maps_groups.log)" | tee -a "$LOG"

  # 5. free staging space (~1.1GB per year)
  rm -f "data/geo/_mb_staging/brasil_coverage_${YEAR}.tif" "data/geo/_mb_staging/soy_${YEAR}.tif"
done

echo "[driver] all done $(date)" | tee -a "$LOG"

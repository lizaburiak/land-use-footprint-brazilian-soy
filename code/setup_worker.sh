#!/usr/bin/env bash
# Create an isolated worker dir for steps 12-20 of one year.
#
# Why a worker dir at all: steps 13-17 write YEAR-LESS files into generated/fabio/
# (Z_mass.rds, X.rds, Y.rds, ...), so two years sharing a directory silently overwrite
# each other. Steps 00-08 (+10) are reused from the data root via symlinks; only
# 12_<Y>, fabio/ and footprints/ are local to the worker.
#
# Usage: bash code/setup_worker.sh YYYY
#        then: cd <worker> && bash code/run_fp.sh YYYY
set -eu
Y="$1"
SRC="${SOYPRINT_DATA_DIR:-/mnt/bigdata/projects/soyprint}"
W="$SRC/generated/workers/fp$Y"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$W"/data/generated/{fabio,footprints,outputs} "$W"/run_logs "$W"/logs
rsync -a --delete "$REPO/code/" "$W/code/"
# run_fp.sh runs logs/fabio_probe/scripts/validate_footprints.R from the worker root
rsync -a "$REPO/logs/" "$W/logs/"

for d in exiobase fabio fabio_before_2010 geo new raw trase; do
  ln -sfn "$SRC/$d" "$W/data/$d"
done
for s in 00 01 02 03 04 05 07 08 10; do
  [ -d "$SRC/generated/outputs/${s}_$Y" ] && ln -sfn "$SRC/generated/outputs/${s}_$Y" "$W/data/generated/outputs/${s}_$Y"
done
echo "fp$Y ready at $W ($(ls "$W/data/generated/outputs" | wc -l) input symlinks)"

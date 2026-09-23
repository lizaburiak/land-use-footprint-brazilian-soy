#!/usr/bin/env bash
# Steps 12-20 + footprint validation for one year, inside an isolated worker dir.
# Steps 00-08 are reused from the data root via symlinks; only 12_<Y>, fabio/ and
# footprints/ are local. Create the worker with code/setup_worker.sh first.
#
# Usage (from the worker root): bash code/run_fp.sh YYYY
#
# Memory: step 15 peaks ~15.7 GB. HEAVY_SLOTS gates how many years may be in step 15
# at once via lock dirs under /locks (mount the shared workers/_locks there). Six years
# in parallel with HEAVY_SLOTS=3 peaked at 41 GB of 117 on the VM.
set -u
Y="$1"; L=run_logs; mkdir -p $L
export SOYPRINT_DATA_DIR="$PWD/data"
export R_MAX_VSIZE=48Gb OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 R_DATATABLE_NUM_THREADS=1
HEAVY_SLOTS="${HEAVY_SLOTS:-3}"
TSV=$L/steps.tsv; echo -e "step\texit\tseconds\tpeak_GB\twait_s" > $TSV
step () {
  local name=$1 script=$2 heavy=${3:-} slot="" waited=0 tw=$(date +%s)
  if [ -n "$heavy" ]; then
    while [ -z "$slot" ]; do
      for i in $(seq 1 $HEAVY_SLOTS); do
        if mkdir /locks/heavy.$i 2>/dev/null; then slot=/locks/heavy.$i; echo "$Y" > $slot/owner; break; fi
      done
      [ -z "$slot" ] && sleep 20
    done
    waited=$(( $(date +%s) - tw ))
  fi
  echo "$(date +%T) [$Y] >>> $name"
  local t0=$(date +%s) peak=0 cur
  Rscript "$script" $Y > $L/$name.log 2>&1 &
  local pid=$!
  while kill -0 $pid 2>/dev/null; do
    cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0); [ "$cur" -gt "$peak" ] && peak=$cur; sleep 2
  done
  wait $pid; local ec=$?
  [ -n "$slot" ] && rm -rf "$slot"
  awk -v n="$name" -v e=$ec -v s=$(( $(date +%s) - t0 )) -v p=$peak -v w=$waited \
      'BEGIN{printf "%s\t%d\t%d\t%.1f\t%d\n", n, e, s, p/1073741824, w}' >> $TSV
  if [ $ec -ne 0 ]; then echo "$(date +%T) [$Y] !!! $name FAILED exit $ec"; tail -20 $L/$name.log; echo "RUN FAILED at $name"; exit $ec; fi
  echo "$(date +%T) [$Y] === $name OK"
}
step 12_re-exports        code/pipeline/12_re-exports.R
step 13_supply            code/pipeline/13_supply.R
step 14_use               code/pipeline/14_use.R
step 15_mrsut             code/pipeline/15_mrsut.R heavy
step 16_mrio              code/pipeline/16_mrio.R
step 17_leontief_inverse  code/pipeline/17_leontief_inverse.R
step 18_hybridize_B       code/pipeline/18_hybridize_B_quadrant.R
step 19_invert_B          code/pipeline/19_invert_B.R
step 20_footprints        code/pipeline/20_footrpints.R
step validate_footprints  logs/fabio_probe/scripts/validate_footprints.R
echo "RUN COMPLETE"

#!/usr/bin/env bash
# Master runner: full pipeline (steps 00-21) for every year in a range.
#
# Runs code/run_year_full.sh per year, continues past a year that fails,
# and writes a pass/fail summary to logs/run_all_summary.txt.
#
# Usage:
#   bash code/run_all.sh                # default 2000..2020
#   bash code/run_all.sh 2004 2020      # custom range
#   bash code/run_all.sh 2013 2013      # single year
set -u
cd "$(dirname "$0")/.."
START="${1:-2000}"
END="${2:-2020}"
SUMMARY="logs/run_all_summary.txt"
mkdir -p logs
{
  echo "run_all  start=$(date)  years=${START}..${END}"
  echo "-------------------------------------------------"
} > "$SUMMARY"

for Y in $(seq "$START" "$END"); do
  echo "==================== YEAR ${Y} ===================="
  if bash code/run_year_full.sh "$Y"; then
    status="CORE 00-12 COMPLETE"
  else
    status="CORE FAILED (see logs/year_${Y})"
  fi
  # note how far 13-21 got, if at all
  fab=$(grep -hc "SKIPPED (FABIO" "logs/year_${Y}/"1*.log 2>/dev/null | head -1 || echo 0)
  echo "YEAR ${Y}: ${status}" | tee -a "$SUMMARY"
done

echo "================== SUMMARY ==================" | tee -a "$SUMMARY"
echo "done=$(date)" >> "$SUMMARY"
cat "$SUMMARY"

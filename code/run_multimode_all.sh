#\!/bin/bash
# Sequential multimode runs for 2010-2022 excluding 2019 (already done).
cd "$(dirname "$0")/.."
for Y in 2010 2011 2012 2013 2014 2015 2016 2017 2018 2020 2021 2022; do
  bash code/run_multimode_year.sh "$Y"
done
echo "$(date '+%F %T') ALL_YEARS_DONE" >> logs/multimode_runs.log

# Step-12 fix, re-runs, rebuild and Trase validation — report

From the data machine (VM), 30 September 2026. Reply to the laptop's go-ahead of 29 September.
Clock times are CEST; the logs are UTC (CEST − 2 h).

**Summary.** All five phases are done and every Phase D check passed. 2000 is back in the footprint
tables. The rebuilt release is at `/mnt/bigdata/projects/soyprint/generated/soyprint.sqlite`
(2,339,921,920 B; `meta_build` commit `fd1bf34`). The branch `release/12-table-db` has two new commits,
both pushed: `2fe3b78` and `fd1bf34`. `main` was not touched and no pull request was opened.

There is one deviation from the plan. The neutrality test used **2003 and 2008** instead of 2018,
because `footprint_provenance_2026-09-23/` holds step-12 outputs only for 2000–2004, 2007 and 2008.
Nothing from 2018 or any year after 2009 was archived. The user approved the substitution before
the run.

---

## Phase A. Housekeeping

- The evidence is in `/mnt/bigdata/projects/soyprint/generated/diagnostics/2026-09-29_step12_labels/`:
  `fp_vs_harv.csv` (3,432,138 B), `btd_vs_prod_2004.csv` (387,562 B), `probe_nodes_2004.csv` (373,864 B) and
  `README.md`, which describes each file and its columns.
  - The files were never in a scratchpad; they came from `generated/diag_2004_2026-09-29/`.
  - The originals and the probe scripts stay in that folder.
- `workers/fp2004` was renamed to `fp2004_prefix`. After Phase D passed, it was deleted (3,098,126,697 B).
- `results/reference/RESUME_NOTES.md` now marks Open item 1 and the 2026-09-23 ruling on 2000 as superseded,
  and points to the evidence folder.

## Phase B. The fix — commit `2fe3b78`, pushed

Changes in `code/pipeline/12_re-exports.R`:
1. `regions_soy` is now sorted by `CO_BTD` (`arrange(CO_BTD)`) before `regions_code_soy` is taken.
2. New guards: `stopifnot(!is.unsorted(regions_code), !is.unsorted(regions_code_soy), !anyDuplicated(regions_code), !anyDuplicated(regions_code_soy))`.
3. **`CO_BTD` is numeric.** Checked in `04_<Y>/regions.rds` and in `SOY_MUN_fin$co_mun` for 2000, 2003 and 2004.
   So `dense_rank()`, `merge()` and the sort all use numeric order.
4. A per-label conservation check now runs for every item's re-export matrix. It compares the matrix
   `rowSums` by label with the input flows summed by `from_code`, and halts if they differ by more than
   1e-6 relative.
   - It is tested on a synthetic case: it passes with sorted labels and trips with the unsorted order
     the bug produced.
   - It ran on all 7 step-12 runs today and never tripped.

Guard trips: none. The commit and the push succeeded (`a828e2e..2fe3b78`).

## Phase C. Runs (all from the clean committed tree)

1. **Neutrality:** step 12 alone for 2003 and 2008 in fresh workers, deleted afterwards. The logs are kept in
   `generated/workers/_neutrality_2026-09-30/`.
2. **Workers** 2000, 2004, 2013, 2014 and 2017 ran in parallel with `HEAVY_SLOTS=3`.
   - Each took 57–68 min, with a per-worker peak of 15.7–16.2 GB. The machine never dropped below
     88 GB available of 117.
   - The workers are kept in `generated/workers/fp{2000,2004,2013,2014,2017}/` (15.2 GB in total).
3. **Trase:** steps 10 and 11 for 2004–2022 in the data root, run one year after another alongside the workers.
   - All 38 steps exited 0. The logs are in `ROOT/logs/trase_2026-09-30_r2/`.
   - The first launch failed without writing anything: running as the host user gave a log permission
     error. The relaunch ran as container root, like the pipeline.
   - The 14 September state was archived first to `generated/archive/trase_benchmarks_2026-09-14/`:
     `outputs/10_2004..2022` (241,647,998 B), `results/tables/benchmarks` (881,187 B) and
     `results/maps/benchmark_maps` (202,665,699 B).

## Phase D. Acceptance checks — all passed

### Neutrality: passed

| Year | File | md5 now = archived |
|---|---|---|
| 2003 | btd_final.rds | `83373a1f…` = `83373a1f…` ✔ |
| 2003 | cbs_full.rds | `c15736f8…` = `c15736f8…` ✔ |
| 2008 | btd_final.rds | `3cf8b433…` = `3cf8b433…` ✔ |
| 2008 | cbs_full.rds | `15ad59e7…` = `15ad59e7…` ✔ |

### 2004 and 2000: municipal soy footprint against harvested area

Footprints are computed exactly as the release builder does it: municipal c021 rows of `A_country` and
`B_country`, cells ≥ 0.01 ha. Harvested area comes from `production`. The probe reproduces the known values
from before the fix (2004 max 567.7, 2003 max 1.196, 2005 max 1.039, 2000 traced 20.7%). On the rebuilt
SQLite it gives the same numbers as on the worker files.

| | 2004 before | 2004 after | 2000 before | 2000 after |
|---|---:|---:|---:|---:|
| max coverage (fp / harvest) | 567.7 (São José dos Quatro Marcos, MT) | **1.322** (Triunfo, RS) | 7,066 (Tupandi, RS) | **1.014** (Tesouro, MT) |
| municipalities > 1.10× | 54 (MT 17, GO 27, RS 8, MG 2) | **10 (RS 8, MG 2)** | 187 | **0** |
| share of national footprint above harvest | 14.64% | **0.14%** | 48.54% | **0.00%** |
| national footprint | 13.785 Mha | **15.996 Mha** | 2.825 Mha | **9.624 Mha** |
| traced share of harvested area | 64.0% | **74.3%** | 20.7% | **70.5%** |

- **2004:** as you predicted, the MT and GO offenders are gone and exactly the 8 RS and 2 MG residuals remain
  (up to 1.32×). Its max of 1.32 is above its neighbours (2003: 1.196; 2005: 1.039), but those 10
  municipalities hold 0.14% of the national footprint, the same share as 2003's excess.
- **2000:** traced 70.5%, against 72.9% in 2001, 71.6% in 2002 and 66.8% in 2003. 2000 passes at
  the 2001–2003 standard, so it is back in the footprint tables (Phase E).

### 2013, 2014 and 2017: municipal oil supply against use — consistent

The 65–68 municipalities are the ones with an oil stock drawdown in the shipped `domestic_use`: 65 (−1 kt)
in 2013, 65 (−148 kt) in 2014 and 68 (−40 kt) in 2017. The new step-12 `cbs_full` was compared with the
shipped fact tables, municipality by municipality:

- **Supply against use:** equal in every municipality, max |supply − use| ≤ 1.2e-10 t. No municipality
  has a `balancing` entry.
- **Stock drawdowns:** the chain has the same municipalities and tonnage as the fact tables (65/−1 kt,
  65/−148 kt, 68/−40 kt).
- **Production, food, other and stock:** 0 municipalities differ by more than 1 t.
- **Exports and imports:** 0 municipalities differ, once the chain's trade is read as foreign trade (the
  `trade` table) plus inter-municipal flows plus self-flows (step 08 `flows_mu`).

**Could not determine:** the old chain state for these three years. Its `cbs_full` was never archived,
so the "before" figure (inconsistent in 65–68 municipalities) is your number, not one reproduced here.
The rebuilt footprints move very little:

| Year | Old footprint | New footprint | Change |
|---|---:|---:|---:|
| 2013 | 22.0146 Mha | 22.0146 Mha | −40 ha |
| 2014 | 22.638 Mha | 22.644 Mha | +5.5 kha |
| 2017 | 25.922 Mha | 25.924 Mha | +1.2 kha |

### Every worker: all step exit codes 0

| Year | `validate_footprints` summary |
|---|---|
| 2000 | 1 FLAG: mass municipal coverage within [0, 1]: max 1.0144, 1 municipality > 1.001 |
| 2004 | 2 FLAGs: coverage, mass max 1.340 (26 municipalities > 1.001), value max 1.230 (8) |
| 2013, 2014, 2017 | all checks ok |

The coverage FLAG uses a strict ≤ 1.001 bound, and shipped years regularly trip it:

| Year | FLAG | Max |
|---|---|---:|
| 2001 | yes | 1.003 |
| 2002 | yes | 1.233 |
| 2003 | yes | 1.196 |
| 2005 | yes | 1.039 |
| 2006 | yes | 1.037 |
| 2009 | yes | 1.051 |
| 2007, 2008 | no (only clean years) | — |

No other check flagged anything in any worker. The validator's node-level coverage (1.34 for 2004) is a
different ratio from the harvest ratio in the table above (1.32).

### Trase: global Pearson and RMSE, 14 September against today

`multimode` / `base` weighting. "Max |ΔPearson|" and "max ΔRMSE" are taken over every weighting × method
cell in `pearson_global.csv` and `rmse_global.csv`.

| year | Pearson 09-14 | Pearson now | RMSE 09-14 | RMSE now | max \|ΔPearson\| | max ΔRMSE |
|---|---:|---:|---:|---:|---:|---:|
| 2004 | 0.4330 | 0.4507 | 4.901 | 5.053 | 0.026 | 6.5% |
| 2005 | 0.4778 | 0.4676 | 4.928 | 5.249 | 0.010 | **9.9%** |
| 2006 | 0.5544 | 0.5609 | 5.224 | 5.406 | 0.010 | 5.6% |
| 2007 | 0.5162 | 0.5291 | 5.476 | 5.703 | 0.021 | 5.1% |
| 2008 | 0.5908 | 0.5908 | 5.630 | 5.630 | 0 | 0 |
| 2009 | 0.6601 | 0.6600 | 5.197 | 5.331 | 0.016 | 3.9% |
| 2010 | 0.6027 | 0.6027 | 7.161 | 7.161 | 0 | 0 |
| 2011 | 0.7264 | 0.7264 | 6.099 | 6.099 | 0 | 0 |
| 2012 | 0.6817 | 0.6829 | 6.806 | 6.873 | 0.025 | 4.2% |
| 2013 | 0.6855 | 0.6855 | 7.101 | 7.101 | 0.0001 | 0 |
| 2014 | 0.6632 | 0.6630 | 6.968 | 6.968 | 0.0004 | 0.1% |
| 2015 | 0.7262 | 0.7262 | 6.752 | 6.752 | 0 | 0 |
| 2016 | 0.7277 | 0.7277 | 6.252 | 6.252 | 0 | 0 |
| 2017 | 0.7808 | 0.7807 | 7.001 | 7.000 | 0.0001 | 0 |
| 2018 | 0.6887 | 0.6952 | 9.517 | 9.724 | 0.018 | 2.2% |
| 2019 | 0.7173 | 0.7030 | 8.434 | 9.000 | **0.033** | **8.4%** |
| 2020 | 0.6873 | 0.6867 | 8.437 | 8.726 | 0.014 | 5.3% |
| 2021 | 0.6785 | 0.6733 | 8.537 | 8.751 | 0.025 | 5.4% |
| 2022 | 0.5819 | 0.5721 | 9.472 | 9.667 | 0.018 | 4.4% |

- **Threshold:** no year passes |ΔPearson| > 0.05 or ΔRMSE > 10%.
- **Largest moves:** 2019 (Pearson −0.014 on base, −0.033 in the worst cell; RMSE +8.4%) and 2005 (RMSE +9.9%).
- **Direction:** where anything changed, RMSE rose, so the Trase fit got slightly worse.
- **Unchanged years:** 2008, 2010, 2011, 2015 and 2016 are identical, and 2013, 2014 and 2017 are
  essentially identical.
- **Cause:** step 10/11 inputs from steps 00–08 changed after 14 September (the stock, pre-biodiesel oil
  and ES fixes). It has nothing to do with step 12, which these steps never read.
- **Stale:** step 11 writes only the CSVs. The `.tex` tables in `results/tables/benchmarks/<Y>/`
  (`pearson_dest.tex`, `rmse_dest.tex`, `export_summary_sorted.tex`) still date from 14 September.
  Whatever builds them was not run.

## Phase E. Release rebuild

1. **Archive:** the old release was moved to `generated/release_2026-09-23/`: `soyprint.sqlite`
   (2,285,445,120 B) and `parquet/` (176,021,748 B).
2. **Footprints:** the new `{F,P}_{mass,value}.rds` for the five years are in `generated/footprints/`, byte-
   identical to the workers' files. The 20 files they replaced were moved to
   `generated/archive/footprints_2026-09-23/` (3,667,228,981 B).
3. **2000 is back:** `FP_MIN_YEAR <- 2000L`, and the note beside it is rewritten with the real cause.
   The note records that the manuscript (`paper/data_section/data.tex:136`) still says the series
   starts in 2001. The manuscript was not edited.
4. **Municipality names** are taken from IBGE tables on disk (`raw/00/IBGE_municipalities/GEO_MUN_*_IBGE.csv`):
   - The three codes are now 2919553 **LUÍS EDUARDO MAGALHÃES (29, BA)**, 5104526 **IPIRANGA DO NORTE (51, MT)**
     and 5104542 **ITANHANGÁ (51, MT)**, as the 2005 and 2022 IBGE tables list them. The 2000 table lacks
     2919553.
   - The builder now skips the "0" placeholders, which come from `MUN_capitals` and the first `SOY_MUN_fin`
     occurrence. Any code still unnamed falls back to the IBGE tables, latest year first.
   - **Side effects:**
     - 4300001 and 4300002 remain unnamed: they appear in no IBGE table on disk, so no name was invented.
     - The COMEX undisclosed-origin placeholder code 9300000 now has an empty state (NA) instead of `0`/`"0"`.
   - Items 3 and 4 are one commit, **`fd1bf34`**, pushed (`2fe3b78..fd1bf34`).
5. **Rebuild** ran from `fd1bf34` on a clean tree. Logs are in `generated/rebuild_2026-09-30/`.
   - Parquet: exit 0, no warnings; `/mnt/bigdata/projects/soyprint/generated/parquet/`, 180,469,956 B.
   - SQLite: exit 0, "All 12 Figure 5 tables built, footprints included";
     `/mnt/bigdata/projects/soyprint/generated/soyprint.sqlite`, 2,339,921,920 B.
   - Referential integrity:
     - The builder's own integrity checks pass (exit 0 means no orphan FKs).
     - `pragma foreign_key_check` finds 0 violations.
     - `pragma quick_check`: `ok` (run in the background, 2026-09-30)
   - **Data dictionary validated against the Parquet, for the first time:**
     `build_data_dictionary.py --db … --parquet …` found 14 tables, 77 fields, 0 extra Parquet columns,
     "every field annotated, database and Parquet agree" (exit 0).
     `results/reference/data_dictionary.csv` has been regenerated (15,046 B); the previous copy is in
     `generated/rebuild_2026-09-30/data_dictionary_before.csv`.

**`meta_build`:** `built_at 2026-09-30T08:35:31+0000`, `git_commit fd1bf348d53e2bcf8a39cff7560e154f2977a28c`,
`git_branch release/12-table-db`, `sqlite_version 3.45.1`.

**Total rows:** 20,319,757 (23 September: 19,845,984; +473,773). The footprint series now covers 2000–2022.

### Row counts per table and year against the 23 September build (only changes listed)

| table | year | 2026-09-23 | 2026-09-30 | diff |
|---|---|---:|---:|---:|
| dim_commodity | all | 140 | 140 | 0 (every year identical) |
| dim_country | all | 265 | 265 | 0 (every year identical) |
| dim_municipality | all | 5,574 | 5,574 | 0 (every year identical) |
| dim_soy_product | all | 3 | 3 | 0 (every year identical) |
| domestic_use | all | 527,157 | 527,157 | 0 (every year identical) |
| export_attribution | all | 2,020,272 | 2,020,272 | 0 (every year identical) |
| footprint_animal_country | 2000 | 0 | 65,041 | +65,041 |
| footprint_animal_country | 2004 | 126,653 | 148,406 | +21,753 |
| footprint_country | 2000 | 0 | 192,887 | +192,887 |
| footprint_country | 2004 | 256,439 | 280,011 | +23,572 |
| footprint_country | 2013 | 310,412 | 310,411 | -1 |
| footprint_country | 2014 | 314,740 | 314,776 | +36 |
| footprint_country | 2017 | 337,787 | 337,792 | +5 |
| footprint_product | 2000 | 0 | 153,764 | +153,764 |
| footprint_product | 2004 | 192,141 | 208,772 | +16,631 |
| footprint_product | 2014 | 240,375 | 240,444 | +69 |
| footprint_product | 2017 | 278,965 | 278,978 | +13 |
| meta_build | all | 1 | 1 | 0 (every year identical) |
| meta_provenance | 2000 | 5 | 8 | +3 |
| production | all | 127,972 | 127,972 | 0 (every year identical) |
| trade | all | 45,145 | 45,145 | 0 (every year identical) |
| transport_flows | all | 833,398 | 833,398 | 0 (every year identical) |
| **total** | | 19,845,984 | 20,319,757 | +473,773 |

Every year not listed above is identical, and every non-footprint fact table is identical in every year.
The supply-chain fact tables are unaffected, as expected.

## Not done and left open

- **Commits:** none beyond these two. No PR (the laptop opens it). `main` is untouched. `paper/` is untouched.
- **Workers:** `fp2000`, `fp2004`, `fp2013`, `fp2014` and `fp2017` (15.2 GB, root-owned files) are kept until you
  accept the release. Deleting them needs a root container.
- **Backups:** kept, as the standing decision requires. Two new archives were added:
  `release_2026-09-23/` (2.46 GB) and `archive/footprints_2026-09-23/` (3.67 GB).
- **UNVERIFIED -- TODO:**
  - why steps 00/05 put the out-of-order "0"-named rows at the end of `SOY_MUN_fin` (open item 3 from
    29 September). The step-12 sort makes step 12 immune to it, and the builder no longer shows the "0"
    names, but the root cause upstream was not investigated.
  - the 8 RS and 2 MG 2004 residuals (1.11–1.32×) were not investigated.
- **Manuscript numbers to update:** 2000 footprint now exists, 2004 footprint (13.79 → 16.00 Mha), and the
  Trase metrics above.

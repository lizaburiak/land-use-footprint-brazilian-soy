> **UPDATE 2026-09-30 ~22:40 CEST: multimode pilot (2019) DONE in scratch `generated/workers/mm2019/` (1.7 GB); nothing running.**
> Report: `generated/diagnostics/2026-09-30_multimode_pilot/REPORT_multimode_pilot_2019.md`. Recommendation: not worth it as is (LP under-routes rail/water vs ANTT/ANTAQ; about 25 days for 23 years); pinned-euclid if forced.
> Proposed .gitignore change (results/* + !results/reference/) is not committed. The scratch root and ~/soyprint_mm_pilot/pylib can be deleted after the decision.

> **UPDATE 2026-09-30 ~18:45 CEST: stock relabel DONE.** Commit `d5522f1` is pushed (05b_stock_decomposition.R, a step-00 label guard, builder stock/losses/residual).
> Release: `generated/soyprint.sqlite` 2,342,920,192 B, meta_build `d5522f1`, 20,352,118 rows; FK 0, quick_check ok, dictionary agrees; every table except domestic_use is identical to bc8166b.
> The bc8166b release was moved to `generated/release_2026-09-30_bc8166b/`.
> Report: `generated/diagnostics/2026-09-30_stock_relabel/REPORT_stock_relabel_2026-09-30.md`.
> Coordinates come from IBGE Localidades 2010 (+7 hand-entered "Google Maps" points); no terms on disk.
> Next (laptop): the multimode transport run, in a separate briefing.

> **UPDATE 2026-09-30 ~15:15 CEST: step-18 go-ahead DONE (Phases A-F).** Report:
> `/mnt/bigdata/projects/soyprint/generated/diagnostics/2026-09-30_step18_rerun/REPORT_step18_fix_rebuild_stocks_2026-09-30.md`.
> - Release: `generated/soyprint.sqlite` 2,340,933,632 B, meta_build `bc8166b`, 20,332,587 rows; FK 0, quick_check ok, dictionary agrees.
>   The previous release is in `generated/release_2026-09-30/`; the replaced 2000-2009 footprints are in `generated/archive/footprints_2026-09-30/`.
> - Commit `bc8166b` (step-18 rows by name) is pushed to the branch only; no PR; main untouched.
> - All workers are deleted (their run logs are kept in `.../2026-09-30_step18_rerun/worker_run_logs/`). The 57 stale Trase .tex files are deleted (archived).
> - Phase A: transport is Euclidean only (no 06/bootstrap output exists; mean/multimode_mean == euclid).
> - Phase F: the stock series do not close. The Brazil 2019-22 "drawdowns" are mostly FAO Residuals; the 2002-04 foreign
>   "drawdowns" are step-12 trade-reconciliation residuals. The Technical Validation text was redrafted in the report.
> Open (laptop): PR; USDA PSD/CONAB stock series; step-00 FAO read by label + Losses/Residuals; the duplicate transport method.

> **UPDATE 2026-09-30 (CEST ~10:45): phases A-E of the laptop go-ahead are DONE; every Phase D check passed.**
> Full report: `results/reference/report_2026-09-30_step12_fix_rebuild.md`. Commits `2fe3b78` (step-12 fix) and
> `fd1bf34` (FP_MIN_YEAR 2000 + municipality names), both pushed to `origin/release/12-table-db`.
> New release: `/mnt/bigdata/projects/soyprint/generated/soyprint.sqlite` 2,339,921,920 B, meta_build fd1bf34,
> 20,319,757 rows, footprints 2000-2022. Old release moved to `generated/release_2026-09-23/`; replaced footprints in
> `generated/archive/footprints_2026-09-23/`; 09-14 Trase state in `generated/archive/trase_benchmarks_2026-09-14/`.
> Nothing running. Workers fp2000/2004/2013/2014/2017 (15.2 GB, root-owned) kept until the release is accepted.
> Open: PR (laptop); why steps 00/05 append unsorted "0" rows; 2004 RS/MG residuals; benchmark .tex files stale (09-14).
> The sections below are the 2026-09-29 state and are superseded where they conflict.

# Resume notes — SoyPrint (Liza's extension of Stefan's model)

Written 2026-09-29 17:25 CEST (handoff). Replaces the 2026-09-23 version.
`ROOT` = `/home/sortizgu/projects/SoyPrint/land-use-footprint-brazilian-soy` (VM; 117 GB RAM, 8 threads, no root).
`DATA` = `/mnt/bigdata/projects/soyprint` (NFS/GPFS).
Clock: VM, containers and every log are **UTC**; report times to the user in **CEST = UTC+2**.
The pipeline runs in Docker `my-r-env` (R 4.6.1). Run it as root with `-v DATA:DATA:ro -v <worker>:<worker> -v DATA/generated/workers/_locks:/locks -w <worker>`.

## 1. Stopped

2026-09-29: user paused after the 2004 diagnosis requested by the laptop Claude.
**Nothing is running**: no soy containers up and no Rscript processes. The fresh 2004 worker
finished cleanly (RUN COMPLETE, exit 0), so **no partial artefacts exist**. The release is
untouched: no code edits, no commits, no pushes.

## 2. State table

| Unit | State | Proof on disk (verified 2026-09-29) |
|---|---|---|
| Release SQLite | **done, but 2004 footprints are WRONG** (see Open item 1) | `DATA/generated/soyprint.sqlite` 2,285,445,120 B, `meta_build` commit 4ed1674 |
| Release Parquet | done, same caveat | `DATA/generated/parquet/` 176,021,748 B |
| Code on branch | unchanged | `release/12-table-db` at `a828e2e` == origin; `git status --short code/` empty; `main` 55fcc8c |
| **2004 diagnosis** | **done — root cause found** | `DATA/generated/diag_2004_2026-09-29/` (4.8 MB) + memory `step12-dimnames-mislabel.md` |
| Fresh 2004 worker (steps 12-20 + validate) | done, reproduces release exactly | `DATA/generated/workers/fp2004/` 3,098,126,697 B; `run_logs/steps.tsv` all exit 0; `2004_F_mass.rds` md5 `813e6f42…` == shipped; step-12 md5 == archive |
| Step-12 fix | **not started** (awaiting user) | `12_re-exports.R:187` unchanged |
| 2000 + 2004 re-run with fix | **not started** | — |
| 2013 / 2014 / 2017 re-runs (laptop's plan) | not started, laptop was holding them | this bug does NOT touch them (0 mislabelled codes) |
| Trase benchmark tables in ROOT | stale (2026-09-14) | `ROOT/results/tables/benchmarks/<Y>/` |

## 3. Artifacts built this session

- `/mnt/bigdata/projects/soyprint/generated/diag_2004_2026-09-29/` — 4.8 MB:
  - `fp_vs_harv.csv` 3,432,138 B — per year×municipality footprint vs harvested area (from the shipped SQLite, via `scan.py`)
  - `btd_vs_prod_2004.csv` 387,562 B — step-12 bean outflow vs production per municipality, 2004
  - `probe_nodes_2004.csv` 373,864 B — per municipal c021 node: X, kept/stock/balancing-driven output, coverage
  - probe scripts `probe*.R`, `cbs.R`, `scan.py` (run them with `docker run ... my-r-env Rscript <file>`)
- `/mnt/bigdata/projects/soyprint/generated/workers/fp2004/` — 3.1 GB — the fresh 2004 worker, with the year-less
  `data/generated/fabio/{X,Y,Y_hybrid,Z_mass,mr_use,...}.rds`, `2004_L_mass.rds`, `2004_B_inv_mass.rds`, footprints. The files are
  root-owned (the container ran as root). The laptop asked that **nothing be copied from it into the release**.

## 4. Open items

1. **SUPERSEDED 2026-09-30 — go-ahead received; fix being applied as a commit. Evidence: `/mnt/bigdata/projects/soyprint/generated/diagnostics/2026-09-29_step12_labels/`.** ROOT CAUSE (2004, very likely 2000): step 12 gives municipalities the wrong labels.** `12_re-exports.R:187` builds
   `sparseMatrix(i=dense_rank(from_code), j=dense_rank(to_code), dimnames=list(dims, dims))`.
   `dense_rank` is in sorted order, but `dims` is SOY_MUN rows in file order. In 2004 `SOY_MUN_fin` ends with
   5104526 and 5104542 (name/state "0", 0 t production), which mislabels 338 codes (5104526..5300108: the rest of MT, GO, DF).
   All 152 over-allocated municipalities carry exactly another municipality's production (13.41 Mt moved).
   Step 16 then closes those rows with a huge negative `21_balancing`, and step 20 drops it, so coverage reaches 567.7.
   2000: the last row is 2919553, which mislabels 3,454 codes, with 25.35 Mt of 32.73 Mt misplaced (not yet confirmed by a re-run).
   Every other year has 0 mislabelled codes.
   **Proposed fix (not applied):** sort `regions_soy` by `CO_BTD` before line 145, plus `stopifnot(!is.unsorted(dims))`.
   Then run steps 12-20 for 2000 and 2004 and rebuild the release (2000 can return: `FP_MIN_YEAR`).
   **Blocked on: user / laptop decision.**
2. The full diagnosis reply was given in chat on 2026-09-29. The user relays it to the laptop Claude.
   Its three answers: only 2000 and 2004 are affected; the cause is in the code (triggered by unsorted input rows);
   re-run steps 12-20 for 2000 and 2004, then the release layer.
3. UNVERIFIED -- TODO: why steps 00/05 append 5104526 and 5104542 (2004) and 2919553 (2000) at the end with state "0".
   `dim_municipality` also names these three codes "0".
4. UNVERIFIED -- TODO: whether steps 10/11 (Trase benchmarks) read step-12 output. If they do, 2000 and 2004 benchmarks are affected too.
5. 2004 RS (8) and MG (2) municipalities sit at 1.11-1.32x harvest (about 13 kha), outside the mislabelled range. Not investigated;
   they are the same size as the small overshoots in 2002/2003.
6. Not compared: the 2003/2005 dropped-demand totals at matrix level. Their matrices are gone, and only a 2004 worker was authorised.
7. Carried over: open the PR (user); send Liza the GEO_MUN_2000 data repair and `PROVENANCE_GEO_MUN_2000_repair.md` (user);
   backups of about 19.4 GB are kept until the release is accepted. The older list missed `soyprint_backup_2026-09-18.sqlite` (386 MB)
   and `parquet_backup_2026-09-18/` (30 MB). The v1.1/v2 comparability caveat still applies. Section 4 item 8 of the
   2026-09-23 notes (step 02 feedlot, step 01 seed, etc.) is still unverified.
8. `fp2004` worker (3.1 GB): keep or delete? That is the user's call.

## 5. Decisions made

- 2026-09-30 (user + laptop go-ahead): run phases A-E: commit + push the step-12 fix on the branch, re-run 2000/2004/2013/2014/2017, Trase 10/11 for 2004-2022, rebuild the release. The neutrality test uses 2003 + 2008, because no 2018 step-12 output was archived. `workers/fp2004` renamed `fp2004_prefix`.
- 2026-09-29 (resume check, user): **Hold** on the step-12 fix and the 2000/2004 re-runs until the laptop Claude or a co-author decides. State re-verified on the VM; nothing running.
- 2026-09-29 (user, via the laptop request): diagnosis only, with no changes to the release, commits, pushes or `paper/`. A fresh
  2004 worker was allowed and was run. The 2013/2014/2017 re-runs wait on this answer.
- Earlier decisions still in force: release is SQLite + Parquet; 0.01 ha threshold; 2000 excluded from the footprint
  tables until fixed; backups kept until the release is accepted; commits as `siwar149 <siwar@workmail.com>` on
  a branch only; step-12 orphan guard stays fatal.

## 6. Do not

- Never edit `paper/`. No DuckDB. No `pip install` on the host.
- Do not push to `main` or merge without the user; `origin` is a co-author's repo.
- Do not copy anything from `workers/fp2004` into the release.
- Do not make the step-12 conservation check non-halting or weaken the orphan guard.
- Do not allocate stock withdrawals by storage capacity.
- Do not run two years in one directory: use `code/setup_worker.sh <Y>` + `code/run_fp.sh <Y>`.
- Do not delete the backups before the release is accepted.
- Do not run `pragma quick_check` inline on the 2.3 GB DB (it takes 3-4 min); run it in the background.
- The 2026-09-23 "ruled out" list for 2000 is **SUPERSEDED (see `diagnostics/2026-09-29_step12_labels/`)**: its "step 12 is exactly clean for 2000" was wrong
  (step 12 conserves tonnes but scrambles labels).

## 7. Resume command

Nothing is running. Confirm state (takes about 2 s):
```bash
cd /home/sortizgu/projects/SoyPrint/land-use-footprint-brazilian-soy
git log --oneline -1; git status --short code/
ls -l /mnt/bigdata/projects/soyprint/generated/soyprint.sqlite
tail -3 /mnt/bigdata/projects/soyprint/generated/workers/fp2004/run_logs/steps.tsv
sed -n 187p code/pipeline/12_re-exports.R
```
Expect `a828e2e`, empty status, 2,285,445,120 B, `validate_footprints 0 ...`, and line 187 still using `dense_rank`.

Then ask the user **one** thing: apply the step-12 sort fix in the working tree (no commit) and run 2000 + 2004
workers in parallel (about 32 GB peak of 115 GB free, about 50 min)? If yes, do these in order:
1. Edit line ~145.
2. Delete or rename `workers/fp2004` first (setup_worker reuses the dir; its files are root-owned, so remove them with a root container).
3. Run `setup_worker.sh` + `run_fp.sh` for 2000 and 2004.
4. Check that coverage max is at most about 1.05 and the traced share is about 65-75%.
5. Confirm one unaffected year (e.g. 2001) is byte-identical under the fix.

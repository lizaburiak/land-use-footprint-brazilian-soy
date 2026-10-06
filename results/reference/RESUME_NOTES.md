# Resume notes — SoyPrint (Liza's extension of Stefan's model)

Written 2026-10-02 ~13:50 CEST (handoff). Replaces every earlier version: the old banners are in git history (this file
is tracked since `dbcfd77`).
- `ROOT` = `/home/sortizgu/projects/SoyPrint/land-use-footprint-brazilian-soy` (the VM: 117 GB RAM, 8 threads, no root).
- `DATA` = `/mnt/bigdata/projects/soyprint`.
- **Clock:** logs are UTC; report times to the user in CEST.
- **How the pipeline and builders run:** in Docker `my-r-env` (R 4.6.1, Python with pyarrow, SQLite 3.45.1), as root, with
  `-v DATA:DATA[:ro] -v ROOT:ROOT -w ROOT`.
- **git inside the container:** pass `-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'`.

## 0. IN PROGRESS 2026-10-06 (combined re-run) -- read this first

Briefing "Combined re-run: PAM, herds, no step-17 cap, cake exports from COMEX; rebuild, checks, figures"
(2026-10-06). Reports: `generated/diagnostics/2026-10-05_input_audit/REPORT_input_audit_2026-10-05.md` (why) and
`generated/diagnostics/2026-10-06_combined_rerun/` (this run).

**Decisions taken by the user (do not re-litigate):**

- **Step-17 column cap removed** (`adj_prod = FALSE`) for all years. 2020 is tested first.
- **Soybean cake balance rebuilt in step 00_FAO:** exports = COMEX heading 2304, production = 0.75 x beans processed,
  feed = production - exports. The cake column of `raw/00/FAO_CBS/CBS_SOY_<Y>_FAO.xlsx` is no longer used.
- **Soybean cake fed abroad stays at the feed point** (documentation only; `14_use.R` unchanged apart from a comment).
- **IBGE data as retrieved from SIDRA on 2026-10-05**, including the 2021 revision (Tangará da Serra).
- **2000-2013 FAOSTAT trade matrix** (one 2013 file): left as it is for this release.
- **Step 21** for 2022 only.
- **Non-productive columns (2026-10-06, after the 2020 test):** step 17 applies the same-item rule only (a column
  using 1 unit or more of its own item per unit of output is scaled to 0.9999). No general cap.
- **Traced share above 100% is accepted** in years with net stock withdrawals; stock additions and balancing stay
  dropped. The land identity has five terms and feeds the new release table `land_balance`.
- **Step-12 exception** for municipal flows with Brazil as partner stays (commit `2f46e78`; logged, stops above 100 t).
- The frozen `dbcfd77` release files stay; the new build goes to a new directory. Zenodo draft untouched.

**Raw inputs replaced on 2026-10-05 (originals archived beside them):**

- `raw/00/IBGE_production/Production_tabela1612_IBGE_2014..2024.csv` -> `_archive_shifted_2026-10-05/`
- `raw/00/IBGE_livestock/Livestock_2014..2025_tabela3939_IBGE.csv` -> `_archive_scrambled_2026-10-05/`

**State of the run:** see `generated/diagnostics/2026-10-06_combined_rerun/STATUS.md` (updated at every phase, with
PIDs, container names and log paths of anything running detached).

## 1. Stopped

**When and why:** 2026-10-02. The user paused after the Zenodo draft was filled; publishing waits on the code merge and the
EXIOBASE team.

**Nothing is running:** no soy containers, no drivers, no monitors. No partial artefacts.

## 2. State table (verified on disk 2026-10-02 13:45 CEST)

| unit | state | proof |
|---|---|---|
| Phase A commit (euclid-only transport, IBGE 2022 seats, `results/reference/` versioned) | done, pushed | `dbcfd77` on `origin/release/12-table-db` |
| BRA documentation fix (dictionary sidecar + regenerated dictionary + `code/db/README.md`) | done, pushed | `4f32df9` = `origin/release/12-table-db` HEAD |
| **Data freeze** = release built from `dbcfd77` + docs `4f32df9` | **done, accepted by laptop** | `DATA/generated/soyprint.sqlite` 2,153,979,904 B, md5 `d0d8d5514d1021c9833bd4dd2b8fbbc9`, meta_build `dbcfd77`, 18,925,285 rows; `DATA/generated/parquet/` 190 files, combined md5 `62de5161d772d5a970d6ad8cd497844a` |
| Phase B checks (vs d5522f1) | done, all passed | `DATA/generated/rebuild_2026-10-01_dbcfd77/compare_releases.log`, `quick_check.log` |
| Figure 10 regenerated (13/13 years × 20 optimal draws) | done | `DATA/generated/diagnostics/2026-10-01_fig10/fig_dest_weighted_v2.png`, `fig10_trase_2010_2022.csv` |
| Phase D clean-up | done | `DATA/generated/workers/` holds only `_locks`, `_neutrality_2026-09-30`; `~/soyprint_mm_pilot` and `~/soyprint_fig10` gone; `gdistance`, `igraph` kept in `~/R/x86_64-pc-linux-gnu-library/4.6` |
| Phase E (USDA PSD vs FAO stock path) | done | `DATA/generated/diagnostics/2026-10-01_fig10/phaseE/psd_vs_fao_2000_2022.csv` |
| Zenodo package | done | `DATA/generated/zenodo_v1/` (6 files, `MD5SUMS.txt` verifies) |
| **Zenodo upload to draft 23057008** | **done, NOT published** | `DATA/generated/diagnostics/2026-10-02_zenodo/verify.txt`: 6/6 size and md5 OK; `state unsubmitted`, metadata unchanged |
| Zenodo publish | **not started; must not happen** until the user says so | — |
| PR / merge to `main` | not started (user's call) | `main` untouched |

## 3. Artifacts built 2026-10-01 / 02

| path | size |
|---|---:|
| `/mnt/bigdata/projects/soyprint/generated/soyprint.sqlite` (the freeze) | 2,153,979,904 B |
| `/mnt/bigdata/projects/soyprint/generated/parquet/` | 177,063,835 B |
| `/mnt/bigdata/projects/soyprint/generated/release_2026-10-01_d5522f1/` (archived previous release: sqlite + parquet) | 2,524,233,403 B |
| `/mnt/bigdata/projects/soyprint/generated/rebuild_2026-10-01_dbcfd77/` (build logs, `compare_releases.py`/`.log`, `quick_check.log`) | 79,859 B |
| `/mnt/bigdata/projects/soyprint/generated/diagnostics/2026-10-01_fig10/` (`REPORT_freeze_fig10_2026-10-01.md`, Figure 10 PNG and CSV, drivers `run_fig10*.sh`, `fig10_build.py`, C.5 and BIG_COST scripts and logs, `kept_from_scratch/`, `phaseE/`) | 9,442,334 B |
| `/mnt/bigdata/projects/soyprint/generated/diagnostics/2026-10-02_bra_doc/` (`REPORT_bra_doc_fix_2026-10-02.md`, `bra_cells_2000_2022.*`, checksums before and after) | 28,856 B |
| `/mnt/bigdata/projects/soyprint/generated/diagnostics/2026-10-02_zenodo/` (`REPORT_zenodo_upload_2026-10-02.md`, `make_readme.py`, `upload.sh`/`.log`, API responses, `verify.txt`; no token in any file) | 24,866 B |
| `/mnt/bigdata/projects/soyprint/generated/zenodo_v1/soyprint.sqlite` | 2,153,979,904 B |
| `/mnt/bigdata/projects/soyprint/generated/zenodo_v1/soyprint_parquet.zip` | 176,271,407 B |
| `/mnt/bigdata/projects/soyprint/generated/zenodo_v1/data_dictionary.csv` | 16,803 B |
| `/mnt/bigdata/projects/soyprint/generated/zenodo_v1/README.md` | 5,845 B |
| `/mnt/bigdata/projects/soyprint/generated/zenodo_v1/LICENSE.txt` | 2,885 B |
| `/mnt/bigdata/projects/soyprint/generated/zenodo_v1/MD5SUMS.txt` | 249 B |

## 4. Open items

1. **Publish the Zenodo record 23057008.**
   - **Blocked on (user):** the code merge and confirmation from the EXIOBASE team.
   - **Still empty in the draft:** creators and description. Neither was asked for.
2. **`LICENSE.txt` "TO CONFIRM" items:** exact attribution wording for every source; the IBGE, COMEX, ABIOVE, ANP and
   GLEAM terms; the EXIOBASE terms.
   - **Who:** the user or co-authors.
   - **If it changes:** re-upload that file to the draft and update `MD5SUMS.txt`.
3. **README / CITATION placeholders:** `CITATION: <to be added>` and `PAPER: <to be added>` (user). Whether the GitHub repo
   in the README is public: UNVERIFIED -- TODO.
4. **Paper text no longer matches the regenerated Figure 10** (user; `paper/` is not editable by Claude):
   - `paper/overleaf/main.tex:705`: in 2018 Euclidean (0.702) no longer beats downscale (0.707).
   - `paper/overleaf/main.tex:715-716`: multimode is now within 0.032 of Euclidean, and 2013 is no longer the worst year.
5. **Optional:** a note on `trade.partner_iso3` BRA, 4 rows and 4 t, presumably the COMEX Manaus FTZ code. Offered, not
   asked for.
6. **Token hygiene (user):** revoke the token pasted in chat on 2026-10-02. Revoke or delete the one in `~/.zenodo_token`
   after publishing.
7. **Uncommitted:** this file (`results/reference/RESUME_NOTES.md`). Commit only if asked.
8. **Carried over, still unverified:**
   - why steps 00/05 append "0"-named rows (2919553 in 2000; 5104526 and 5104542 in 2004);
   - 2004 RS/MG municipalities at 1.11-1.32× harvest;
   - sending the GEO_MUN_2000 repair to Liza;
   - deleting the old backups and archives, now that the freeze is accepted. That is the user's call; see `DATA/generated/`
     `*_backup_*`, `release_2026-09-*`, `archive/`.

## 5. Decisions made (do not re-litigate)

- **Multimode is not in this release.** The release ships Euclidean transport only; the `method` column stays for a later
  multimodal version.
- **Figure 10:**
  - It stays in the paper, regenerated from the current build.
  - Its metric is the volume-weighted per-destination base Pearson r (`code/analysis/fig_dest_sets.py` @ `e12cca3`), not
    `pearson_global`.
- **Seat coordinates:** the seven hand-entered seats are fixed only in `dim_municipality`. The model and `MUN_capitals.rds`
  are unchanged, and the gap is documented.
- **BRA in `export_attribution`** is domestic use. Only the documentation was fixed; no rows were dropped and nothing was
  rebuilt.
- **Freeze:** `dbcfd77` + `4f32df9`.
- **Zenodo:**
  - one deposit with 6 files; the Parquet layer goes up as one zip, because of the 100-file limit;
  - the SQLite stays uncompressed;
  - the draft must never be published by Claude.
- **Earlier decisions still in force:**
  - SQLite + Parquet (no DuckDB file);
  - 0.01 ha footprint threshold;
  - footprints 2000-2022;
  - commits as `siwar149` on the branch only.

## 6. Do not

- Do not publish, edit the metadata of, or discard Zenodo draft 23057008.
- Do not modify `generated/soyprint.sqlite` or `generated/parquet/`: this is the freeze. Check the md5 values above before
  any packaging.
- Do not write, print or log a Zenodo token.
  - **Read it only inside commands**, from `~/.zenodo_token`:
    `-H @<(printf 'Authorization: Bearer %s\n' "$(< ~/.zenodo_token)")`.
  - Writing a chat-pasted token to a file is blocked by the permission classifier.
- Do not push to `main`, merge, or open a PR without the user. `origin` is a co-author's repo.
- Never edit `paper/`. No `pip install` into the host Python; use `--target` in a throwaway container. No DuckDB.
- Do not run more than 3 LP workers per container on this VM: 4 workers OOM-killed in 80 GiB.
- Do not allocate stock withdrawals by storage capacity. Do not weaken the step-12 orphan guard or the conservation checks.
- Do not run two years in one worker directory.

## 7. Resume command

Nothing is running. Confirm the freeze and the draft (about 1 minute; read-only):
```bash
cd /home/sortizgu/projects/SoyPrint/land-use-footprint-brazilian-soy
git log --oneline -1; git status --short code/      # expect 4f32df9, empty
md5sum /mnt/bigdata/projects/soyprint/generated/soyprint.sqlite   # expect d0d8d5514d1021c9833bd4dd2b8fbbc9
(cd /mnt/bigdata/projects/soyprint/generated/zenodo_v1 && md5sum -c MD5SUMS.txt)
```
Then ask the user which open item comes next. The usual next step is a laptop briefing on the LICENSE wording, the paper
text, or publishing. Do not publish without an explicit instruction.

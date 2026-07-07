# What is missing — data & dependency gaps

Status of the reproduction pipeline (`code/pipeline/`, steps 00–12) as of this audit.
Scope note: **Path B (default, Euclidean transport) has no missing data** — it runs for
2000–2020. Everything below is about the *optional* multimode path and the later steps.

## Quick summary

| # | Missing | Blocks | Severity | Re-obtainable? |
|---|---|---|---|---|
| 1 | `RailCargo_2006-21_ANTT.xls` | step 06 (multimode transport) | optional path | ✅ ANTT open data |
| 2 | `ip_add.gpkg` | step 06 | optional path | ❌ Stefan's hand-curated file |
| 3 | `train_stations_soy.gpkg` | step 06 | optional path | ❌ Stefan's hand-curated file |
| 4 | ANTAQ cargo for years ≤ 2016 (`2013Carga*.txt`) | step 06 for early years | optional path | ❌ Stefan's 2013 download |
| 5 | `pyreadr` (Python pkg) | `transport_lp` I/O | optional path | ✅ `pip install pyreadr` |
| 6 | FABIO export snapshot beyond 2013 | step 12 re-exports for ≥ 2014 | non-fatal | ❌ needs FABIO refresh |
| 7 | FABIO/EXIOBASE data for steps 13–21 | land-use footprints (any year) | blocked | ❌ WU/fineprint NFS, not public |

---

## 1. Path B (steps 00 → 12, Euclidean) — NOTHING MISSING ✅

Runs for **2000–2020** with the fallbacks now in place:
- Trade matrix (≤ 2012): falls back to Stefan's 2013 FAOSTAT file.
- Import trade (≤ 2013): uses Stefan's `btd_bal.rds` (covers 1986–2013); 2014+ uses the new
  `btd_bal.RData` (2010–2023).
- Periodic inputs (boundaries, POF, biodiesel): nearest available year ≤ target.

Command: `bash code/run_year_full.sh <YEAR>`

---

## 2. Multimode transport (step 06 → Python `transport_lp` / GAMS) — BLOCKED

The Python `transport_lp` reads `data/generated/outputs/06_YYYY/`, which is *generated* by step 06. Step 06
can't run because of missing inputs. Needed:

| File | Destination path | Source |
|---|---|---|
| `RailCargo_2006-21_ANTT.xls` | `data/geo/` | ANTT — https://dados.antt.gov.br/dataset/transporte-ferroviario-de-cargas-e-passageiros (compiled into one sheet per year) |
| `ip_add.gpkg` | `data/geo/ANTAQ/` | **Stefan's archive** — hand-curated supplementary ports, not downloadable |
| `train_stations_soy.gpkg` | `data/geo/ANTT/` | **Stefan's archive** — hand-curated soy rail stations, not downloadable |

Plus, ANTAQ waterway cargo for the target year:
- 2017–2020: ✅ already present (`{YEAR}Carga.txt` + `_Conteinerizada.txt`)
- ≤ 2016: ❌ need `2013Carga.txt` + `2013Carga_Conteinerizada.txt` in `data/geo/ANTAQ/` (Stefan's fallback, now wired in `06.R`)

Plus the Python dependency: `pip install pyreadr` (inside the venv).

**Best source for all of these: the original soyprint data archive** — wherever the rest of
`data/geo/` came from (Stefan directly, the WU / fineprint-global NFS store referenced in
`archive/code_old_stefan/16-20` as `/mnt/nfs_fineprint/...`, or the original repo). The two `.gpkg`
files exist *only* there.

**Is it worth it?** Path B (Euclidean) already reproduces Stefan's pooled correlation
(r ≈ 0.69 vs his 0.692), so the multimode's measured marginal benefit here is small. Pursue
these files only if the goal is specifically to run the multimode/Python transport.

---

## 3. Step 12 (re-exports) for YEAR ≥ 2014 — FIXED (was a crash, not "empty")

> **UPDATE 2026-06-23 — the real footprint-attribution bug was here, and it was the OIL re-export,
> not the bean.** The "soybean 2555 degenerate for 2018–2020" caveat below is **outdated**: 2555 now
> inverts exactly (TRUE/TRUE) every year. The bug that broke the footprint in **2016/2021/2022** was
> an **off-by-one for soybean OIL (2571)**: Brazil (`area_code 21`) leaked back into `cbs_ext` after
> the BTD-harmonization `full_join` (21 is absent from `regions_code_soy`), so the per-commodity
> `merge(..., all = TRUE)` appended a 5762nd row to a 5761-row matrix and the element-wise ops
> recycled — corrupting the entire oil re-export (`btd_final` BRA −2744 Mt) and producing negative
> Brazil footprints downstream (step 16 `balancing` slack → step 20). **Fixed** by re-asserting the
> area-21 soy exclusion after harmonization, switching the merge to `all.x = TRUE`, and adding a
> `stopifnot(nrow(data)==nrow(mat))` guard. See `docs/paper_plan.md §5.1`.

There are **two separate** post-2013 issues here; don't conflate them:

**(a) Step 12 crashed on a singular re-export inversion — now fixed.**
Earlier, `data/generated/outputs/12_{2014..2020}/` were *empty*. The cause was **not** missing data:
step 12 inverts a per-commodity re-export matrix `solve(I - mat)` (`12_re-exports.R`), and for
YEAR ≥ 2014 the two **soy commodities that carry the subnational municipal detail** —
**2590 (Soyabean Cake)** and **2555 (Soyabeans)** — produce a **singular** matrix on the newer
multi-year FABIO trade data (`LU factorization … out of memory or near-singular`). That aborted
the whole script *before* it saved anything, so the folder looked empty. Stefan only ran 2013,
where it inverts cleanly, so this was never exercised. **Fixed** with a robust inverter
(`invert_reex()`): sparse solve → dense solve → dense + a **diagonal ridge scaled to the matrix
magnitude** → Moore-Penrose pseudo-inverse (`MASS::ginv`) as the guaranteed last resort. Every
commodity that needs a fallback is logged. **2010–2020 now all produce** `btd_final.rds` /
`cbs_full.rds` / `reex.rds`.

⚠️ **Data-quality caveat (2018–2020):** for those years the **soybean (2555)** re-export matrix
is not merely near-singular but *numerically degenerate* — a near-zero `total_use` denominator
inflates its entries to ~1e15 and the balance target contains NAs. The fix lets the run complete
(huge scaled ridge, eps≈9e9) and **flags it**, but the soybean/cake re-export *values* for
2018–2020 should be treated as **unreliable** (all other commodities balance fine). This is a
data-quality signal about the post-2017 FABIO trade inputs, not a code bug. It does not affect
any current result (the only consumer, steps 13–21, is blocked on memory/FABIO data anyway);
revisit the soybean re-export treatment if/when 13–21 are run for ≥2018.

**(b) Step 04's FABIO *export* snapshot ends at 2013 — separate, still non-fatal.**
Stefan's `data/fabio/trade/FABIO_exp/{v1,pure}/btd_bal.rds` cover only **1986–2013**. For
YEAR ≥ 2014, `btd_exp`/`btd_exp_pure` are empty and step 04 emits a **warning** (not an error).
This affects the *export-comparison* tables, not step 12's re-export output. Fixing it needs
regenerated FABIO export tables for newer years (a FABIO-side task).

---

## 4. FABIO MRIO + land-use footprints (steps 13–21) — ported, blocked on data

These stages are now **ported to `code/pipeline/13–21`** (year-parameterized, with a
fail-fast guard). But they are **blocked on FABIO/EXIOBASE data that is entirely absent**
on this machine — every input is missing:

| Needed by 13–21 | Status |
|---|---|
| `data/generated/fabio/*` (MRIO matrices: `{Y}_L_mass.rds`, `{Y}_B_inv_*.rds`, `Z_*.rds`, `mr_sup/use*.rds`, …) | ❌ folder empty |
| `archive/fabio_stefan/inst/*` (`items_*.csv`, `tcf_*.csv`, `conc/conv_*.csv`, `regions_full.csv`, …) | ❌ folder empty |
| `archive/fabio_stefan/tidy/{live_tidy,prices_tidy}.rds` | ❌ folder missing |
| `archive/fabio_stefan/FABIO_hybrid/{fabio-exio_sup,use,conc}.csv` | ❌ folder missing |
| `archive/fabio_stefan/FABIO_exp/v1/btd_full.rds` | ❌ missing (only `btd_bal.rds`, `cbs_full.rds` present) |
| `/mnt/nfs_fineprint/tmp/exiobase/pxp/{Y}_{Z,L,x,Y}.RData`, `IO.codes`, `Y.codes` | ❌ NFS unreachable |
| `/mnt/nfs_fineprint/tmp/fabio/v2/{E,Y_b,Z_mass_b,Z_value_b}.rds` | ❌ NFS unreachable |

Running any of `code/pipeline/13–21` now stops immediately with a clear
`[FABIO stage] FABIO/EXIOBASE data not available locally …` message. To unblock, you need
**WU/fineprint's FABIO + EXIOBASE infrastructure** (the same NFS store referenced as
`/mnt/nfs_fineprint/...`) — this is institute data, not publicly downloadable.

**Caveat on year-extension:** the ports replace literal `2013` with `YEAR` in file paths and
list indexing, but this is **unvalidated** — it cannot be run until the FABIO data is present.
Treat 13–21 as "structurally ported, pending data + validation".

---

## 4b. TRASE benchmark data — 2004–2022 only

The TRASE composite (`data/trase/brazil_soy_v2_6_1_composite.csv`) covers **2004–2022**.
For **2000–2003** there is no TRASE data, so the benchmark steps **10 (create_benchmarks)
and 11 (analyse_benchmarks) are skipped** — the model outputs (steps 00–08, 12) are still
produced and valid, there is simply nothing to correlate against. This is a data gap, not a
failure; steps 10/11 now exit cleanly with a `[10]/[11] No TRASE data` message for these years.

## 4c. Early-year data quirks (handled in code, no action needed)

Discovered while running 2000–2012; all are now handled defensively so the pipeline completes:
- **Non-geographic COMEX municipality placeholders** (e.g. `9300000`, `4314530`) appear in
  some early years. They have no map location / NA livestock, so they are dropped from the
  transport (07) and benchmark (11) steps and excluded from feed scaling (03).
- **Products with no inter-municipal flow** in a given year (e.g. soy *oil* in 2000–2001 is
  consumed locally) now yield an empty flow table instead of crashing step 07.
- **ABIOVE plant-roster sheet names vary by year** — 2004 uses `geralproces` not the
  2003-style `unidproces`; 2007–2008 use `Geralproces`/`Geralrefin` (capitalised). Step 00
  now resolves the sheet name case/space-insensitively (fixed 2004, 2007, 2008).

These were code-robustness fixes (steps 00, 03, 07, 10, 11), not missing data.

## 4d. FABIO — trade data present, MRIO data absent (important distinction)

"FABIO" refers to two different datasets — only one is here:
- ✅ **FABIO *trade* data** (`data/fabio/trade/`: `btd_bal.rds` = Stefan's 1986–2013,
  `new/btd_bal.RData` = 2010–2023, `cbs_full`, regions, trade matrix) — **present**.
  Feeds steps 04 and 12, which run.
- ❌ **FABIO *MRIO* model** (`inst/` concordances, `tidy/`, `FABIO_hybrid/`, the L/B/Z
  matrices, EXIOBASE) — needed by steps 13–21, **absent everywhere** (searched the whole
  home folder). This is the large WU/fineprint dataset on `/mnt/nfs_fineprint`, separate from
  the trade data. See section 4 for the full list.

## 4e. FABIO / EXIOBASE — progress (uploaded data)

Now **present** (clearly-labeled homes):
- **EXIOBASE 3 pxp** (Z, Y, x, satellites), **2000–2020** → `data/exiobase/pxp/IOT_{YEAR}_pxp/`
- **FABIO v2 core** (E, Z_mass_b, Z_value_b, Y_b), 2010–2023 → `data/fabio/v2/`

Resolved since:
- ✅ **FABIO `X`** — `code/prep/prep_fabio_X.R` computes `X=rowSums(Z)+rowSums(Y)` → `data/fabio/v2/X.rds`.
  This is **exactly** how step 16 builds X (`16_mrio.R:151` `mapply(\(x,y) rowSums(x)+rowSums(y), Z_m, Y)`),
  so the derived X is the *correct* FABIO X — there is no separate file to source. (The 51% zero-output
  processes are normal — inactive country×commodity cells.) Step 17 tested 2020 and failed on
  `LU factorization … out of memory`: the blocker is **RAM for the 22,263² sparse inverse** (FABIO runs
  on servers), NOT the X.
- ✅ **EXIOBASE `L`** — `code/prep/prep_exiobase_L.R YEAR` → `data/exiobase/pxp/{YEAR}_{Z,L,x,Y}.RData`
  (2020 done; run per year as needed; ~11 s/year).
- ✅ **FABIO-hybrid concordances** — downloaded (v1.2) → `archive/fabio_stefan/FABIO_hybrid/`
  (`fabio-exio_{sup,use,conc}.csv`). Commodity dim (123) matches v2; **region map is 192 vs v2's
  181** — step 18 filters conc to the model regions, so it should reconcile (verify at runtime).

Still **missing / to do**:
1. **MapBiomas soy tiles** (30 m, Google Earth Engine) — step 21 only.
2. **Code wiring** (not data): bypass steps 13–16 (FABIO MRIO already supplied), repoint steps
   17–20 from `/mnt/nfs_fineprint/...` to `data/fabio/v2/`, `data/exiobase/pxp/`,
   `archive/fabio_stefan/FABIO_hybrid/`; and the FABIO region list (`inst/regions`) for the conc filter.

Code wiring (not data): steps 13–16 can be bypassed (their FABIO outputs are now supplied);
steps 17–20 repoint from `/mnt/nfs_fineprint/...` to `data/fabio/v2/` + `data/exiobase/pxp/`.

## 5. Minor / legacy data gaps

- `data/trase/trase_names.csv` — only used by the legacy Trase v2.5.1 benchmark branch; the
  default v2.6.1 path builds ISO codes inline and skips it. Not needed.
- `data/trase/BRAZIL_SOY_2.5.1_TRASE.csv` — legacy Trase, superseded by the present
  `brazil_soy_v2_6_1_composite.csv`.

---

## How to drop a file in (you can't "upload" through the agent)

Place the file on disk yourself, then it's usable. From this session you can run a `!`-prefixed
shell command, e.g.:
```
! cp ~/Downloads/RailCargo_2006-21_ANTT.xls "data/geo/"
! cp ~/Downloads/ip_add.gpkg "data/geo/ANTAQ/"
! cp ~/Downloads/train_stations_soy.gpkg "data/geo/ANTT/"
```
or just drag them into those folders in Finder.

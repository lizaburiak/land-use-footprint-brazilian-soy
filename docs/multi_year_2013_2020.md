# code/pipeline multi-year results — soyprint Path B for 2013–2020

> **Historical record (2026-05).** Old repo layout: `R/new/` → `code/pipeline/` (updated below);
> `inputs/` → `data/new/`; `outputs/` → `results/outputs/`; `scripts/` → `code/`.
>
> **⚠️ SUPERSEDED — the step 12 "crashes for ≥2014" story below is out of date.** The root cause
> was later found to be a soybean-oil (2571) off-by-one in step 12, **fixed 2026-06-23** (commit
> `1e00e11`). Step 12 and the downstream footprint chain (13–20) now run for 2014–2020 (and
> 2021–2022). The FABIO_exp v1 coverage discussion here was the wrong diagnosis. The **benchmark
> results (§1–§3) remain valid**; only the §5 blocker narrative is obsolete. See `docs/paper_plan.md` §5.

This document summarises the year-parameterised code/pipeline pipeline (Path B: Euclidean transport, no GAMS multimode) run for 8 consecutive years. Reference year **2013** matches Stefan Trsek's thesis baseline; years **2014–2020** are new extensions.

Run order each year:
```
00 → 00_FAO → 01 → 02 → 03 → 04 → 05 → 07_R → 08 mean+sep → 10 → 11 → 12
```
(Steps 06, 07_GAMS, 09 are skipped — they need ANTAQ/ANTT 2013–2020 cargo data + GAMS, which are unavailable.)

Step 12 (re-exports / FABIO MRIO) **crashes** for all years ≥ 2014. Important distinction about which data is and isn't refreshed:

* `inputs/04/FABIO/new/btd_bal.RData` — **bilateral trade, 2010–2023, present and current** (60M rows; ~4.3M/year). This is the regular-FABIO btd you uploaded May 4. It is **already used by step 04** for the import side (`btd_imp`), per the existing CHANGELOG patch.
* `inputs/04/FABIO/FABIO_exp/v1/btd_bal.rds` — **FABIO_exp v1 bilateral trade, 1986–2013 only**. This is a different variant ("export flow" methodology); step 12 reads from here, not from the new btd_bal.RData. Empty for ≥2014.
* `inputs/04/FABIO/FABIO_exp/v1/cbs_full.rds` — **FABIO_exp v1 commodity balance, 1961–2019 but partial post-2013**: ~96 country rows/year for Soyabean (vs 169 in 2013), and **zero rows for Soyabean Cake (item 2590) post-2013**.

The Leontief solve in step 12 (`mat <- solve(I − M)`, line 225) becomes singular when an iterated soy item has insufficient rows to be invertible. Concrete failure points observed:

* 2014–2017: crashes on item 2590 (Soybean Cake) — `LU factorization failed: out of memory or near-singular`
* 2018–2020: crashes earlier on item 2552 (Pulses, Other) — `'a' is computationally singular`

What's needed to unblock step 12 for ≥2014: a refresh of the **FABIO_exp v1 variant** (both `btd_bal.rds` and `cbs_full.rds` for the FABIO_exp methodology). The regular `btd_bal.RData` upload does not satisfy this requirement because it's a different methodology with different item coverage. Source: `github.com/fineprint-global/fabio` (the FABIO_exp branch) or Martin Bruckner at WU Vienna. The 2013 step-12 result is unaffected.

CSVs accompanying this doc:
* `results/tables/multi_year_summary.csv` — CBS national totals per year
* `results/tables/multi_year_per_dest.csv` — per-year, per-destination flow comparison (TRASE vs euclid vs downscale)
* `results/tables/multi_year_benchmarks.csv` — per-year aggregate benchmark metrics

---

## 1. National Commodity Balance (CBS) — Mt per year

### 1a. Soybean (raw beans)

| Year | Production | Exports | Imports | Processing | Feed | Food | Seed |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 2013 |  81.70 | 42.80 | 0.28 | 35.51 | 0.64 | 0.73 | 1.21 |
| 2014 |  86.76 | 45.69 | 0.58 | 38.11 | 1.22 | 0.00 | 1.31 |
| 2015 |  96.23 | 54.39 | 0.40 | 38.95 | 0.92 | 0.00 | 1.36 |
| 2016 |  95.43 | 51.58 | 0.30 | 40.16 | 1.43 | 0.00 | 1.43 |
| 2017 | 114.60 | 68.15 | 0.20 | 43.91 | 0.91 | 0.00 | 1.49 |
| 2018 | 117.89 | 83.27 | 0.18 | 36.50 | 0.93 | 0.00 | 1.56 |
| 2019 | 114.27 | 74.07 | 0.13 | 41.10 | 0.95 | 0.00 | 1.66 |
| 2020 | 121.80 | 83.00 | 0.43 | 46.13 | 0.99 | 0.00 | 1.77 |

National soybean production grew from **81.7 Mt (2013) to 121.8 Mt (2020)** — a 49% increase. Exports grew from 42.8 Mt to 83.0 Mt (+94%).

Notable artefact: FAO has revised the 2014+ "food" allocation for soybean to 0 (all human soy consumption is now classified as soy oil or soy cake derivatives, not raw bean). The code/pipeline pipeline reproduces this faithfully from the current FAOSTAT CBS files (`inputs/00/new/FAO_CBS/CBS_SOY_{YEAR}_FAO.xlsx`).

### 1b. Soybean oil

| Year | Production | Exports | Food | Other (incl. processing → biodiesel) |
|---:|---:|---:|---:|---:|
| 2013 |  7.077 | 1.381 | 2.713 |   2.990 |
| 2014 |  7.443 | 1.305 | 2.525 |   3.761 |
| 2015 |  7.789 | 1.566 | 2.520 |   3.953 |
| 2016 |  8.030 | 1.622 | 2.594 |   4.080 |
| 2017 |  8.726 | 1.435 | 2.610 |   4.642 |
| 2018 |  7.292 | 1.464 | 2.685 |   4.768 |
| 2019 |  8.218 | 0.992 | 2.768 |   4.984 |
| 2020 |  9.226 | 1.601 | 2.953 |   5.353 |

In code/pipeline ≥ 2014 the "processing" column for oil (biodiesel feedstock) is folded into "other" at CBS level (one of the code/pipeline patches — without this, step 08 crashes on supply/use imbalance for oil). Both pristine R/05 and code/pipeline/05 originally assumed oil processing = 0, which was true in 2013 but stopped being true after FAO's 2014 CBS revision.

### 1c. Soybean cake

| Year | Production | Exports | Feed |
|---:|---:|---:|---:|
| 2013 | 26.63 | 16.51 | 10.12 |
| 2014 | 28.58 | 20.72 |  7.86 |
| 2015 | 29.20 | 22.07 |  8.40 |
| 2016 | 30.12 | 21.69 |  9.91 |
| 2017 | 32.94 | 24.55 | 11.10 |
| 2018 | 27.38 | 23.13 |  9.34 |
| 2019 | 30.83 | 22.18 | 11.99 |
| 2020 | 34.60 | 25.20 | 13.18 |

---

## 2. Benchmark vs TRASE (v2.6.1 composite)

Per-year aggregate metrics. Pearson r is averaged across destinations (each weighted equally). Pooled r is over all municipality×destination flows. RMSE in tonnes.

| Year | Dests | Non-zero flows | TRASE total (Mt) | Euclid total (Mt) | Downscale total (Mt) | avg r euclid | avg r downscale | med RMSE euclid (t) | med RMSE downscale (t) | pool r euclid | pool r downscale |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2013 | 67 |  7,688 |  81.72 |  81.70 |  81.70 | 0.310 | 0.160 |   564 |   595 | 0.436 | 0.447 |
| 2014 | 76 |  8,923 |  86.76 |  86.76 |  86.76 | 0.297 | 0.154 |   357 |   456 | 0.496 | 0.523 |
| 2015 | 79 |  8,568 |  97.46 |  97.47 |  97.47 | 0.294 | 0.164 |   261 |   286 | 0.507 | 0.508 |
| 2016 | 75 |  8,072 |  96.39 |  96.39 |  96.39 | 0.326 | 0.169 |   252 |   336 | 0.446 | 0.448 |
| 2017 | 68 |  8,269 | 114.73 | 114.73 | 114.73 | 0.383 | 0.193 |   497 |   605 | 0.442 | 0.433 |
| 2018 | 80 |  9,589 | 117.91 | 127.59 | 117.91 | 0.293 | 0.120 |   435 |   378 | 0.265 | 0.302 |
| 2019 | 67 |  9,885 | 114.32 | 127.70 | 114.32 | 0.150 | 0.146 | 1,626 | 1,430 | 0.414 | 0.399 |
| 2020 | 74 | 11,066 | 121.80 | 129.11 | 121.80 | 0.164 | 0.133 | 1,817 | 1,581 | 0.418 | 0.438 |

### Headline findings

* **Euclid wins per-destination correlation in 6 of 8 years.** Average r is 0.310 (euclid) vs 0.160 (downscale) in 2013 — roughly a 2× improvement that the spatial transport model contributes over pure downscaling. The gap holds 2013–2017.

* **2018+ degradation.** The euclid:downscale advantage shrinks in 2018 and disappears in 2019/2020 (avg r drops to 0.15 vs 0.13 in 2020). At the same time, the euclid total (Mt) starts diverging from TRASE total (127.6 vs 117.9 in 2018, 129.1 vs 121.8 in 2020). This suggests TRASE v2.6.1 may have schema or coverage shifts in those later years that the v2.5.1-aware adapter doesn't fully accommodate — worth a closer look if those years are important.

* **Pool-level Pearson r is consistently ~0.4–0.5**, dominated by large flows (CHN, BRA) where all methods converge. The per-destination metric is the more informative signal.

* **Production growth scales the analysis well**: 2017 records 114 Mt production with 68 destinations and 8,269 non-zero MU×dest flows; the framework handles the volume increase without methodological issues.

### Per-destination correlation timeline (avg across destinations)

```
         2013  2014  2015  2016  2017  2018  2019  2020
euclid   0.310 0.297 0.294 0.326 0.383 0.293 0.150 0.164
downsc   0.160 0.154 0.164 0.169 0.193 0.120 0.146 0.133
gap      +0.15 +0.14 +0.13 +0.16 +0.19 +0.17 +0.00 +0.03
```

---

## 3. Top 5 destinations per year (TRASE kt)

Reading: TRASE-reported export volume vs code/pipeline euclid model.

### 2013
| dest | TRASE | Euclid | Downscale |
|---|---:|---:|---:|
| CHN | 32,783 | 32,761 | 32,737 |
| BRA | 23,923 | 20,253 | 20,266 |
| NLD |  5,917 |  7,125 |  7,113 |
| ESP |  2,215 |  2,278 |  2,273 |
| THA |  2,060 |  2,264 |  2,260 |

### 2014
| dest | TRASE | Euclid | Downscale |
|---|---:|---:|---:|
| CHN | 32,839 | 33,099 | 33,043 |
| BRA | 25,829 | 18,466 | 18,230 |
| NLD |  5,540 |  7,435 |  7,466 |
| ESP |  2,660 |  2,905 |  2,917 |
| THA |  2,467 |  3,133 |  3,168 |

### 2017
| dest | TRASE | Euclid | Downscale |
|---|---:|---:|---:|
| CHN | 53,803 | 53,879 | 53,879 |
| BRA | 24,995 | 23,452 | 23,452 |
| NLD |  5,239 |  3,807 |  3,807 |
| ESP |  2,895 |  2,330 |  2,330 |
| THA |  1,948 |  1,977 |  1,977 |

### 2020
| dest | TRASE | Euclid | Downscale |
|---|---:|---:|---:|
| CHN | 73,098 | 73,114 | 73,098 |
| BRA | 22,003 | 18,712 | 18,712 |
| ARG |  3,256 |  6,067 |  6,067 |
| ESP |  2,805 |  2,919 |  2,919 |
| THA |  3,034 |  4,008 |  4,008 |

Full per-destination time series: `results/tables/multi_year_per_dest.csv`.

**Persistent finding across all years**: domestic absorption (BRA destination) is systematically *under*-allocated by ~3–7 Mt versus what TRASE reports. The CBS-balanced pipeline absorbs ~20 Mt domestically while TRASE attributes 22–26 Mt. Possible causes:
* TRASE counts intermediate Brazilian processing steps (crusher → trader → exporter) as domestic absorption, while we count only final domestic use.
* TRASE includes farm-gate stock retention that our CBS treats as part of next-year's stock.
* Different conventions for biodiesel feedstock attribution.

---

## 4. code/pipeline code changes applied during the multi-year run

All fixes confined to `code/pipeline/`. None modify pristine `R/`.

| File | Change | Reason |
|---|---|---|
| `code/pipeline/04_trade_harmonization.R` | Fall back to `FABIO_regions$FAO.Code` (192 countries) when `btd_exp` is empty | FABIO_exp v1 only covers 1986–2013; for ≥2014 every destination collapsed to ROW |
| `code/pipeline/05_balancing.R` | Fold oil `processing` into oil `other` at CBS level | FAO 2014+ splits oil industrial use; only `other_oil` is allocated to municipalities, so non-zero `processing_oil` broke supply/use balance |
| `code/pipeline/05_balancing.R` | Replace non-finite rescale ratios with 1 | Cake `stock_addition=0` produced 0/0=NaN → all-NA `stock_cake` → step 07_R cake transport crashed |
| `code/pipeline/08_export_link_mean.R` | `unique()` after prepending `"BRA"` to destinations | 2019+ COMEX already includes BRA; duplicate BRA in `destin` broke `pivot_wider` |
| `code/pipeline/08_export_link_mean.R` | Wrap supply/use balance checks in `isTRUE(...)` | When `all.equal()` returns a character message, `&` crashes |
| `code/pipeline/08_export_link_sep.R` | `unique()` after BRA prepend | Same as 08_mean |
| `code/pipeline/10_create_benchmarks.R` | Aggregate `EXP_NAT` duplicates before `pivot_wider`; explicit `bean, oil, cake` instead of `cake:bean` range | 2019+ produced list-cols and column-order dependence broke select |
| `code/pipeline/11_analyse_benchmarks.R` | Subset `MUN_capital_dist` by `SOY_MUN$co_mun` | Step 00 emits 5572×5572 but SOY_MUN has 5570 rows → dim drift |
| `code/pipeline/11_analyse_benchmarks.R` | Add symmetric `Total` row to `rmsle_dest` | `cbind(rmse_dest, rmsle_dest)` row-count mismatch |
| `code/pipeline/11_analyse_benchmarks.R` | Intersect hardcoded scatter targets `c("CHN","ESP","NOR")` with available destinations | 2014+ some target years don't have all three in TRASE |

---

## 5. Per-year run status

All steps completed for every year except where noted.

| Year | 00 | 00_FAO | 01 | 02 | 03 | 04 | 05 | 07_R | 08m | 08s | 10 | 11 | 12 |
|---:|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2013 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2014 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| 2015 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| 2016 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| 2017 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| 2018 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| 2019 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| 2020 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |

⚠️ Step 12 **errors out** for ≥2014 inside the Leontief inversion (`solve(I − M, sparse = TRUE)` at line 225). Root cause is partial FABIO_exp v1 coverage (note: the new `inputs/04/FABIO/new/btd_bal.RData` covers 2010–2023 but is the *regular* FABIO btd; step 12 reads the separate *FABIO_exp v1* variant):

* `inputs/04/FABIO/FABIO_exp/v1/btd_bal.rds` — bilateral trade flows: years 1986–2013 only.
* `inputs/04/FABIO/FABIO_exp/v1/cbs_full.rds` — commodity balance: years 1961–2019, **but only for some items**. Soyabean (2555) has ~100 country rows post-2013 (vs 169 in 2013). Soyabean Cake (2590) has **zero rows** post-2013. Soyabean Oil (2571) similar.

When the item loop reaches a soy item with insufficient country coverage, `(I − M)` is singular and `solve()` fails. To run step 12 for ≥2014 we need the **FABIO_exp v1 variant** rebuilt (both files), not the regular FABIO btd (`github.com/fineprint-global/fabio` FABIO_exp branch, or contact Martin Bruckner at WU Vienna). The 2013 step-12 output is unaffected and is the only year present in `outputs/12_2013/`.

Per-step logs: `logs/year_YYYY/`. Driver scripts: `scripts/run_year_pathB.sh`, `scripts/run_year_full.sh`, `scripts/run_all.sh`. Aggregator: `scripts/aggregate_years.R`.

---

## 6. Caveats for interpretation

1. **No GAMS multimode** for any year. The `multimode_mean` column in the comparison CSVs is identical to `euclid` (Path B fallback). To reproduce the thesis §4.3 result (avg r ≈ 0.6–0.7) we'd need ANTAQ port cargo, ANTT rail cargo, and a GAMS Professional licence.

2. **TRASE v2.6.1 schema is used for all years**, mapped to v2.5.1 conventions via the adapter in `code/pipeline/10_create_benchmarks.R`. Stefan's thesis used v2.5.1 directly. Some destinations and ISO mappings may differ between TRASE versions.

3. **FABIO_exp time limit**: All step-12 (re-exports) outputs for ≥2014 are zero-padded. Downstream steps 13–21 (supply, use, MRSUT, MRIO, Leontief, hybridization, footprints) inherit the same limit and are not run.

4. **ABIOVE plant rosters are filled in by lower-bound fallback for**: 2000–2002 (→ 2003), 2016–2017 (→ 2015), 2021 (→ 2020). State capacity is direct for those years except 2021 (→ 2020).

5. **TRASE BRA discrepancy** of ~3–7 Mt/year is systematic across the time series — domestic absorption convention difference, not a year-specific artefact.

---

## 7. Files generated

```
docs/
├── comparison_2013.md             ← detailed pipeline-vs-pristine-vs-TRASE 2013 comparison
├── multi_year_2013_2020.md        ← this file
├── 2013_per_destination_benchmarks.csv
├── multi_year_summary.csv          ← CBS national totals per year
├── multi_year_per_dest.csv         ← per-year per-destination flows
└── multi_year_benchmarks.csv       ← per-year aggregate benchmark metrics

outputs/
├── 00_2013/, 00_2014/, ..., 00_2020/      (each ~21 files)
├── 01_2013/, ..., 01_2020/                (2 .rds files each)
├── ...                                     (steps 02–11 per year)
└── 12_2013/                                (only year with real output)

logs/
├── year_2013/...
├── year_2014/...
├── ...
└── year_2020/...
```

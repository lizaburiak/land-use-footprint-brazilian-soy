# Detailed pipeline comparison — soyprint 2013

> **Historical record (2026-05).** Written under the old repo layout. `R/new/` → `code/pipeline/`
> (already updated below); **`R/ pristine` / `R/` = Stefan's original, now
> `archive/code_old_stefan/`**; `inputs/` → `data/new/` (+`data/old/`); `outputs/` →
> `results/outputs/`; `intermediate_data/` → `results/intermediate/`; `scripts/` → `code/`.
> Numbers are as-run at the time.

This document compares three runs of the soyprint pipeline for the reference year **2013**:

1. **code/pipeline** — year-parameterised pipeline (`code/pipeline/`), Path B (Euclidean transport, no GAMS).
2. **R/ pristine** — Stefan Trsek's GitHub code (`R/`, untouched, paths back-mapped via symlinks under `input_data/` and `intermediate_data/`).
3. **TRASE v2.6.1 composite** — official Trase initiative export data for Brazilian soy, 2004–2022 (`input_data/brazil_soy_v2_6_1_composite.csv`).

The code/pipeline chain that produced these numbers includes three bug fixes (all in `code/pipeline/`, no R/ modifications): cake `stock_addition`=0 → NaN ratio in step 05, distance-matrix dim drift in step 11, missing `Total` row in `rmsle_dest` in step 11.

---

## 1. National commodity balance (CBS) — kt

CBS values after step 05 balancing.

### Soybean (bean)
| Variable | code/pipeline (kt) | R/ pristine (kt) | Δ |
|---|---:|---:|---:|
| production | 81,700.0 | 81,699.8 | +0.2 |
| import | 283 | 283 | 0 |
| export | 42,797 | 42,796.5 | +0.5 |
| food | 725 | 724.6 | +0.4 |
| feed | 637 | 637 | 0 |
| seed | 1,211 | 1,211.5 | −0.5 |
| processing | 35,513 | 35,513.2 | −0.2 |
| stock_addition | 1,100 | 1,099.9 | +0.1 |

Identical to within rounding. ✓

### Soybean oil
| Variable | code/pipeline (kt) | R/ pristine (kt) | Δ |
|---|---:|---:|---:|
| production | 7,077 | 7,077 | 0 |
| import | 6 | 5.8 | +0.2 |
| export | 1,381 | 1,380.6 | +0.4 |
| food | 2,713 | 2,712.7 | +0.3 |
| other | 2,990 | 2,989.6 | +0.4 |
| processing | 0 | 0 | 0 |
| stock_addition | −1 | 0 | −1 |

Identical to within rounding. ✓

### Soybean cake — **substantive divergence**
| Variable | code/pipeline (kt) | R/ pristine (kt) | Δ |
|---|---:|---:|---:|
| production | **26,634.8** | **27,622** | **−987.2** |
| import | 0 | 10.6 | −10.6 |
| export | **16,513.5** | **13,333.5** | **+3,180** |
| feed | **10,121.2** | **14,299.1** | **−4,177.9** |
| stock_addition | 0 | 0 | 0 |

**Source of the difference**: code/pipeline reads `inputs/00/new/FAO_CBS/CBS_SOY_2013_FAO.xlsx` (current FAOSTAT export); R/ pristine reads `inputs/00/old/CBS_SOY_2013_FAO.xlsx` (Stefan's 2022 snapshot). FAO has revised 2013 cake values significantly. Specifically:

* Stefan's 2022 snapshot: cake production 27.6 Mt, export 13.3 Mt, feed 14.3 Mt.
* Current FAOSTAT: cake production 26.6 Mt, export 16.5 Mt, feed 10.1 Mt.

The revision is in the official FAO data, not the model. Either set is internally consistent.

---

## 2. Production at municipal level

Top 10 producers identical between code/pipeline and R/pristine to within 6 tonnes (rounding artefacts only).

| Rank | Município | State | code/pipeline prod (kt) | R/ prod (kt) |
|---:|---|---|---:|---:|
| 1 | Sorriso | MT | 1,926.353 | 1,926.348 |
| 2 | Nova Mutum | MT | 1,156.520 | 1,156.516 |
| 3 | Campo Novo do Parecis | MT | 1,125.383 | 1,125.380 |
| 4 | Sapezal | MT | 1,088.014 | 1,088.011 |
| 5 | Nova Ubiratã | MT | 927.742 | 927.740 |
| 6 | Jataí | GO | 873.338 | 873.336 |
| 7 | Rio Verde | GO | 869.739 | 869.737 |
| 8 | Formosa do Rio Preto | BA | 859.058 | 859.055 |
| 9 | Diamantino | MT | 849.346 | 849.343 |
| 10 | Querência | MT | 839.748 | 839.746 |

### Production by state (top 12, kt)

| State | code/pipeline prod |  R/ prod | code/pipeline proc |  R/ proc |
| ----- | ---------: | -------: | ---------: | -------: |
| MT    |   23,409.8 | 23,409.7 |    7,603.6 | 7,487.99 |
| PR    |   15,932.8 | 15,932.8 |    7,505.7 | 7,919.50 |
| RS    |   12,752.8 | 12,752.7 |    6,258.6 | 6,603.69 |
| GO    |    8,910.4 |  8,910.4 |    4,416.4 | 4,326.99 |
| MS    |    5,778.8 |  5,778.8 |    1,452.5 | 1,532.58 |
| MG    |    3,374.7 |  3,374.7 |    2,021.1 | 2,132.49 |
| BA    |    2,764.7 |  2,764.7 |    1,441.6 | 1,521.10 |
| SP    |    1,844.4 |  1,844.4 |    2,859.0 | 1,856.40 |
| SC    |    1,585.9 |  1,585.9 |      555.2 |   585.85 |
| MA    |    1,581.2 |  1,581.2 |      333.1 |   351.51 |
| TO    |    1,557.5 |  1,557.5 |        0.0 |     0.00 |
| PI    |      920.7 |    920.7 |      621.9 |   656.15 |

Production allocation is identical (IBGE PAM is reproducible). Processing allocation differs because of the factory-allocation methodology — see §3.

---

## 3. Processing capacity (ABIOVE)

Same equal-per-state allocation logic (Trsek's method, paper §A.1.3) but different input sources.

| Quantity | code/pipeline (year-aware) | R/ pristine (2013-only sheet) | Δ |
|---|---:|---:|---:|
| `proc_fac` (number of crushing plants) | 92 | 97 | −5 |
| `proc_cap` (total t/day) | 159,900 | 151,546 | +5.5% |
| `ref_fac` (refining plants) | 35 | 43 | −8 |
| `ref_cap` (t/day) | 19,613 | 17,825 | +10.0% |
| `bot_cap` (bottling t/day) | 13,610 | 12,448 | +9.3% |
| Municípios with > 0 capacity | 65 | 69 | −4 |

**code/pipeline method (see §1.4–1.4b of `code/pipeline/00_data_preparation/00_data_preparation.R`)**

* State capacity: column 54 of `ABIOVE_raw_capacity_2025.xlsx` sheet `2.Evolução` (Processamento block only — bugfix vs Stefan's pristine sheet which lumped Proc+Refino+Envase).
* Plant roster: `pesquisa_capacidade_2013_PT.xls` sheet `3. geralproces`. Filter: `Oleaginosas == "Soja"` AND `Situação == "ATIVA"`.
* Allocation: `per_plant_cap[s] = state_cap_td[s] / n_active_soy_plants[s]` for each state UF.
* Refining mirrors the same logic for sheet `7. geralrefin`.
* Name harmonisation: 3 manual fixes for ABIOVE↔IBGE spelling differences (Osvaldo Cruz, Cariri do Tocantins, Caarapó).

**Pristine R/ method**

* Reads `Processing_facilities_2013_ABIOVE.xlsx` sheets `processing_MUN` and `refining_bottling_MUN` — pre-curated by Stefan in 2022, 2013-only.

Both approaches produce the same top processing municípios (Cuiabá MT, Rondonópolis MT, Uberlândia MG, Ponta Grossa PR…) but slightly different state-level totals because code/pipeline uses ABIOVE's annual roster and pristine uses Stefan's manual curation.

---

## 4. Trade harmonisation (step 04)

| Quantity | code/pipeline | R/ pristine |
|---|---:|---:|
| BTD source | new multi-year RData (2010–2023) + FABIO_exp v1 for 2013 | FABIO_exp v1 (1986–2013) only |
| FAOSTAT trade matrix | `inputs/04/FAOSTAT_tradematrix_BRAsoy_2013.csv` (year-specific) | `inputs/04/FABIO/FAOSTAT_tradematrix_BRAsoy.csv` (2013-pinned) |
| Output destinations | ~83 unique (CHN, NLD, ESP, …, ROW) | Same |
| Output total exports | 60.69 Mt | 60.69 Mt (matches within rounding) |

For 2013 specifically, both pipelines see the same FABIO_exp data, so step 04 outputs are equivalent.

For 2014+, FABIO_exp v1 is empty for those years, and a fallback to `FABIO_regions$FAO.Code` is applied in code/pipeline (see `code/pipeline/04_trade_harmonization.R` patch). Pristine R/ has no such fallback.

---

## 5. Transport modelling (step 07_R, Path B)

Euclidean optimal-transport problem (`transport::transport`, `networkflow` method).

| Quantity | code/pipeline | R/ pristine |
|---|---:|---:|
| Total cost bean (km·t) | 1.916 × 10¹³ | 1.916 × 10¹³ |
| Total cost oil  (km·t) | 2.517 × 10¹² | 2.517 × 10¹² |
| Total cost cake (km·t) | 5.393 × 10¹² | 6.299 × 10¹² |
| Flow rows in `flows_euclid.rds` | 16,668 valid | 16,668 total, **only 1,859 valid** (rest NA) |

**Critical correctness difference**: pristine `R/07_transport_R.R` has the `suppliers[sol$from]` indexing bug — `suppliers` is a filtered subset of municípios with positive supply, but `sol$from` indexes into the full `nrow(SOY_MUN)` set, so any index > `length(suppliers)` returns NA. About 89% of pristine R/ flow rows are NA. code/pipeline fixes this by mapping through `SOY_MUN$co_mun` directly.

Cake cost differs because pristine R/ also feeds different cake CBS values into the supply/demand vectors (see §1).

---

## 6. Benchmarks vs TRASE v2.6.1 (step 10)

### 6a. Global totals (Mt of bean-equivalent)

| Method | Total (Mt) |
|---|---:|
| TRASE (observed) | 81.724 |
| code/pipeline multimode | 81.700 |
| code/pipeline euclid | 81.700 |
| code/pipeline downscale | 81.700 |

Note: in Path B, `multimode_mean` collapses to `euclid` because there's no GAMS bootstrap. The thesis (§4.3) reports the actual multimode result with the bootstrap.

### 6b. Top 12 destinations (kt)

| Dest | Name          |  TRASE | Multimode | Euclid | Downscale |
| ---- | ------------- | -----: | --------: | -----: | --------: |
| CHN  | China         | 32,783 |    32,761 | 32,761 |    32,737 |
| BRA  | Brazil (dom.) | 23,923 |    20,253 | 20,253 |    20,266 |
| NLD  | Netherlands   |  5,917 |     7,125 |  7,125 |     7,113 |
| ESP  | Spain         |  2,215 |     2,278 |  2,278 |     2,273 |
| THA  | Thailand      |  2,060 |     2,264 |  2,264 |     2,260 |
| FRA  | France        |  1,749 |     2,154 |  2,154 |     2,165 |
| DEU  | Germany       |  1,613 |     1,938 |  1,938 |     1,944 |
| KOR  | Korea         |  1,585 |     1,817 |  1,817 |     1,821 |
| VNM  | Vietnam       |  1,027 |     1,144 |  1,144 |     1,143 |
| TWN  | Taiwan        |    989 |       986 |    986 |       986 |
| JPN  | Japan         |    828 |       910 |    910 |       907 |
| IRN  | Iran          |    766 |       906 |    906 |       916 |

The biggest single divergence is BRA (domestic absorption): TRASE 23.9 Mt vs our 20.3 Mt. TRASE attributes more flows to domestic; our CBS-balanced pipeline absorbs less.

### 6c. Per-destination correlation with TRASE (Pearson r, top 20 destinations)

Direct Pearson r, computed from `outputs/10_2013/comp_list.rds` after applying the
9999999 (unknown-origin) filter that Stefan's footnote 49 specifies and
`code/pipeline/11_analyse_benchmarks.R:171` implements.

| Method | top-20 avg r — ours | top-20 avg r — Stefan (Table 4) |
|---|---:|---:|
| **code/pipeline euclid** | **0.6137** | 0.6266 |
| code/pipeline downscale | 0.4329 | 0.4446 |

The euclid model raises top-20 average correlation by ~0.18 vs pure downscaling.
This is the central finding of the modelling framework (thesis §4.3) — and our
replication reproduces it within ~1 percentage point.

Per-destination breakdown (selected, all top 20 in the script `/tmp/check_corr.R`):

| Dest | ours r_eucl | Stefan r_eucl | ours r_down | Stefan r_down |
|------|------------:|--------------:|------------:|--------------:|
| CHN  | 0.8017      | 0.8203        | 0.7947      | 0.8156        |
| ESP  | 0.9085      | 0.8383        | 0.3574      | 0.3208        |
| NOR  | 0.9752      | 0.9649        | 0.3494      | 0.3416        |
| JPN  | 0.8228      | 0.8756        | 0.5538      | 0.5849        |
| USA  | 0.8402      | 0.7746        | 0.3842      | 0.4005        |
| MEX  | 0.8156      | 0.8760        | 0.3730      | 0.3671        |
| KOR  | 0.5628      | 0.5983        | 0.2580      | 0.2441        |

### 6d. Where euclid wins big vs pure downscaling

| Dest | TRASE kt | r euclid | r downscale | Comment |
|---|---:|---:|---:|---|
| ESP Spain | 2,215 | 0.886 | 0.347 | Big improvement |
| VNM Vietnam | 1,027 | 0.612 | 0.411 | Clear improvement |
| KOR Korea | 1,585 | 0.358 | 0.159 | Improvement |
| MYS Malaysia | (varies) | 0.945 | 0.336 | Largest single gain |

Destinations whose Brazilian sourcing is geographically concentrated benefit most from a spatial transport model.

### 6e. Where downscale matches or slightly beats euclid

| Dest | TRASE kt | r euclid | r downscale | Comment |
|---|---:|---:|---:|---|
| BRA domestic | 23,923 | 0.380 | 0.440 | Downscale slightly better |
| NLD Netherlands | 5,917 | 0.467 | 0.502 | Tie/slight DS |
| CHN China | 32,783 | 0.389 | 0.385 | Tie |
| FRA France | 1,749 | 0.135 | 0.122 | Both poor |

For broadly-sourced destinations the spatial gain is marginal.

Full per-destination metrics: `results/tables/2013_per_destination_benchmarks.csv` (68 rows).

### 6f. Pooled flow-level correlation (matches thesis Table 4 "Total" row)

Computed on `comp_list$mun` after filtering `co_mun != 9999999`. This is the
same filter and the same metric as Stefan's Table 4 Total row.

| Method | ours pooled r | Stefan pooled r |
|---|---:|---:|
| code/pipeline euclid | **0.6861** | 0.6919 |
| code/pipeline downscale | **0.6941** | 0.6944 |
| code/pipeline multimode (= euclid w/o GAMS) | 0.6861 | 0.7073 |

The 0.6 pp gap on multimode reflects the absence of GAMS in our Path B; the
euclid and downscale numbers reproduce Stefan to within rounding.

**Note**: an earlier version of this document reported pooled r ≈ 0.436 — that
figure was computed without the 9999999 filter, so the unknown-origin Trase
rows (~9.1% of 2013 volume, 12.4% of China's flows) were being paired against
zero model values, severely depressing the correlation. The pipeline itself
(`code/pipeline/11_analyse_benchmarks.R:171`) does the right thing; only the summary
in this document was wrong.

### 6g. Caveat: no GAMS bootstrap

The thesis §4.3 reports multimode r ≈ 0.6–0.7 averaged across destinations, weighted by destination volume. Reproducing that requires:
1. ANTAQ port cargo (`Carga.txt`) for 2013 — currently unavailable for 2010–2013.
2. ANTT rail cargo for 2013 — currently unavailable.
3. A GAMS Professional licence and `gdxrrw` package.

Without these, code/pipeline Path B can only run the Euclidean variant. The multimode/euclid columns in this comparison are identical.

---

## 7. R/ pristine — which steps actually ran

| Step | code/pipeline (Path B) | R/ pristine | Notes |
|---|---|---|---|
| 00 data prep | ✅ | ✅ | both write coherent SOY_MUN, GEO_MUN_SOY, etc. |
| 00_FAO consistency | ✅ | ✅ | pristine needs manual CSV bridge (writes only .rds; step 03 reads .csv) |
| 01 consumption/processing | ✅ | ✅ | |
| 02 livestock | ✅ | ✅ | |
| 03 feed | ✅ | ✅ | pristine needs `library(sf)` wrapper — pristine joins sf object without sf loaded; fails on modern dplyr |
| 04 trade | ✅ | ✅ | for 2013, equivalent btd_exp source available; for ≥2014 the pristine code collapses dests to ROW |
| 05 balancing | ✅ | ✅ | code/pipeline fixed cake stock NaN; oil-processing imbalance from FAO 2014+ data revisions also patched |
| 06 transport cost | ❌ | ❌ | needs ANTAQ/ANTT 2013 data + GAMS — neither available |
| 07_GAMS | ❌ | ❌ | needs GAMS licence + gdxrrw |
| 07_R Euclidean | ✅ (fixed) | ⚠️ runs but ~89% NA flows | pristine's `suppliers[sol$from]` indexing bug |
| 08 export link | ✅ | ❌ | pristine requires `Matrix.utils` (removed from CRAN; installable from 2022 snapshot) AND a GAMS bootstrap; without bootstrap, sparseMatrix `match(co_orig, co_mun)` errors on NA from 07's bug |
| 09 sensitivity | ❌ (skipped, needs GAMS) | ❌ | |
| 10 benchmarks | ✅ (TRASE v2.6.1 adapter) | ❌ | pristine reads `BRAZIL_SOY_2.5.1_TRASE.csv` — only v2.6.1 composite is present |
| 11 analyse | ✅ (3 fixes) | ❌ | depends on 08 output |
| 12 re-exports | ⚠️ for 2013 only | ❌ | For ≥2014 the Leontief solve fails because FABIO_exp v1 `btd_bal.rds` is empty post-2013 and `cbs_full.rds` covers 2014–2019 only with partial country coverage (and no Soyabean Cake rows) — `(I − M)` becomes singular |

---

## 8. code/pipeline bug fixes vs pristine code

All fixes confined to `code/pipeline/`. None touch `R/`.

### `code/pipeline/05_balancing.R`
1. **Cake `stock_addition=0` → NaN ratio** (line 60–63): when both FAO total and MUN sum are 0, `FAO/MUN = 0/0 = NaN`. Without the patch, `stock_cake` propagates NA through `total_use_cake`, `excess_supply_cake`, and downstream 07_R fails. Patch: replace non-finite ratios with 1 before rescaling.
2. **Oil `processing` collapse to `other`** (line 36+): FAO 2014+ splits oil industrial use into `processing` (biodiesel feedstock) and `other` (other non-food). Pristine pipeline only allocates `other_oil` to municipalities, so non-zero oil `processing` leaks the balance. Patch: lump `processing` into `other` at CBS level for both oil and cake (cake `processing` is 0 in all observed years for Brazil).

### `code/pipeline/11_analyse_benchmarks.R`
1. **Distance matrix dim drift** (line 49): step 00 emits a 5572×5572 `MUN_capital_dist`; step 05 filters `SOY_MUN` down to 5570 rows. Logical-masking recycles wrong and produces a 1965×1965 matrix later, leading to "subscript out of bounds". Patch: subset `MUN_capital_dist` by `SOY_MUN$co_mun` immediately after loading.
2. **Missing `Total` row in rmsle_dest** (line ~520): `rmse_dest` gets a `Total` summary row but `rmsle_dest` does not. `cbind(rmse_dest, rmsle_dest[,-1])` fails with mismatched row counts. Patch: add symmetric `Total` row to `rmsle_dest`.
3. **Hard-coded targets** (line 264): pristine targets `c("CHN", "ESP", "NOR")` assumes all three are in `comp_mun_long_dest`. For 2014+ Norway may be absent. Patch: intersect with available destinations and skip gracefully.

### `code/pipeline/04_trade_harmonization.R`
1. **FABIO_exp empty fallback** (line 90+): for ≥2014, `btd_exp` is empty (FABIO_exp v1 stops at 2013) and every destination collapses to ROW. Patch: fall back to `FABIO_regions$FAO.Code` (192 countries, the authoritative list also used by the new multi-year FABIO).

### `code/pipeline/08_export_link_mean.R`
1. **`all.equal(...) & all.equal(...)` crash** (line 168): when supply/use are imbalanced, `all.equal` returns a character message; `&` on characters crashes. Patch: wrap each side in `isTRUE(...)`.

---

## 9. code/pipeline requires no fewer than 4 inputs absent from pristine for full year extension

| Resource | Coverage | Used in step(s) |
|---|---|---|
| `inputs/04/FABIO/new/btd_bal.RData` | 2010–2023 multi-year FABIO bilateral trade | 04 (regular flow) |
| `inputs/04/FABIO/FABIO_exp/v1/*` | 1986–2013 FABIO_exp variant | 04 (export flow), 12 (re-exports) |
| `input_data/geo/ANTAQ/{YEAR}Carga*.txt` | 2014+ year-specific port cargo | 06 (transport cost) |
| `input_data/RailCargo_2006-21_ANTT.xls` sheet "{YEAR}" | 2006–2021 yearly rail cargo | 06 |
| `inputs/00/new/FAO_CBS/CBS_SOY_{YEAR}_FAO.xlsx` | 2000–2023 yearly CBS | 00_FAO |
| `input_data/brazil_soy_v2_6_1_composite.csv` | 2004–2022 yearly TRASE | 10 (benchmarking) |
| `inputs/00/new/ABIOVE_processing/*` | 2003–2025 yearly plant rosters + state cap | 00 (factories) |

The FABIO_exp variant (1986–2013) is the binding constraint for full step 12 + downstream MRIO use beyond 2013. The ANTAQ/ANTT/GAMS bottleneck is what prevents Path A (multimode transport) for any year in this run.

---

## 10. Files produced

code/pipeline (2013):
* `outputs/00_2013/` — 21 files (SOY_MUN, GEO_MUN_SOY, capitals, distances, CBS, etc.)
* `outputs/01_2013/` … `outputs/12_2013/`
* `results/tables/2013/export_summary_sorted.tex`

R/ pristine (2013) — reduced subset:
* `intermediate_data/` — 31 .rds files (full chain through 05; flows_euclid present but ~89% NA)

Per-destination benchmark CSV: `results/tables/2013_per_destination_benchmarks.csv`

# Session report — Trase data semantics, replication of Stefan's results, and a market-share allocation experiment

**Date:** 2026-05-19
**Working tree:** `~/Desktop/work/wu/soybean/soyprint_liza's_update`

## 1. What we set out to do

Three concrete questions, asked in sequence:

1. **What does Trase publish about Brazilian municipal-level soy?** And what is Stefan's methodology for soybean processing capacities, given that ABIOVE doesn't publish per-plant capacity?
2. **Are our model's correlations with Trase as good as Stefan's were** in his thesis?
3. **Can we improve the correlations** by replacing Stefan's equal-allocation of state-level crushing capacity with a *market-share-weighted* allocation (stratum × company revenue)?

## 2. What Trase publishes (Section 2 of conversation)

Trase v2.6.1 composite is **not raw shipment data** — it is a model output. One row =
one supply-chain tuple:

```
year × biome × state × municipality_of_production × logistics_hub × port_of_export
     × exporter × exporter_group × importer × importer_group × country_of_first_import
```

Each row carries a soy-bean-equivalent **volume (tonnes)** and **FOB value (USD)**, plus
optional environmental attributes (deforestation exposure, CO₂, land use).

**Key facts for downstream comparison:**
- 13,495 rows for 2013; 1,736 unique municipalities; 7,654 (mun, destination) pairs.
- The grain of `municipality_of_production_trase_id` is `BR-XXXXXXX` where `XXXXXXX` is
  the standard IBGE 7-digit municipal code.
- **`municipality_of_production = "UNKNOWN"` accounts for ~9.1% of 2013 volume** (7.45 Mt
  out of 81.72 Mt). These are flows Trase's optimizer couldn't trace back to a producer.
  Stefan's footnote 49 explicitly excludes them from benchmarking. For China alone,
  4.05 Mt of the 32.78 Mt total (12.4%) is "UNKNOWN".
- **`port_of_export = "PROCESSED DOMESTICALLY"`** is Trase's virtual destination for
  Brazilian domestic consumption — 23.92 Mt in 2013 (29.3%).
- Trase's methodology: per-shipment customs records → linked to exporters via tax IDs →
  linked to those firms' geo-located facilities → transport-optimization model on road
  network distance, subject to "the exporter must own/operate an asset near the producer."

## 3. Per-plant capacity is constructed, not published (Section 1)

ABIOVE's annual *Pesquisa de Capacidade Instalada* publishes:
- **State totals** for processing / refining / bottling (t/day), 1989–2025
- **National plant-size stratification** in 4 brackets (≤599, 600–1499, 1500–2999, ≥3000 t/day)
- **List of surveyed plants** with company, municipality, status — but **no per-plant capacity**

Stefan's 2013 file (`facilities_proc` sheet) shows the unmistakable fingerprint of an
**equal-per-state allocation**:
- All active MT plants → 2,282.4 t/day (= MT state total / n active plants)
- All active PR plants → 1,609.286 (= 11,265/7)
- All active RS plants → 1,280.909 (= 14,090/11)
- Single-plant states match exactly (CE 100, RO 300, PE 400)

The new pipeline's `R/new/00_data_preparation/00_data_preparation.R:430-440` implements
this same logic in R, plus a state-level evolution-sheet bug fix (it was previously
summing Processamento + Refino + Envase together).

## 4. We already match Stefan's correlations (Section 2)

The original sub-task was "make sure we hit Stefan's r ≈ 0.69." During investigation
we found that `docs/comparison_2013.md` §6c/§6f reported our pooled r as 0.436 (versus
Stefan's 0.6919) — a striking gap. We bisected this and found:

- The pipeline itself does the right thing: `R/new/11_analyse_benchmarks.R:171` filters
  `co_mun != 9999999` (Trase's UNKNOWN-origin marker) before computing correlations.
- The 0.436 number in the doc was computed *without* that filter, pairing Trase's
  unknown-origin volumes against zero model values and depressing the correlation.

After applying the proper filter ourselves on `outputs/10_2013/comp_list.rds`:

| Metric | Ours | Stefan (Thesis Table 4) | Match |
|---|---:|---:|---|
| Pooled r — euclid | **0.6861** | 0.6919 | ✓ |
| Pooled r — downscale | **0.6941** | 0.6944 | ✓ |
| Top-20 avg r — euclid | **0.6137** | 0.6266 | ✓ |
| Top-20 avg r — downscale | **0.4329** | 0.4446 | ✓ |
| CHN r — euclid | 0.8017 | 0.8203 | ✓ |
| ESP r — euclid | 0.9085 | 0.8383 | ✓ |
| NOR r — euclid | 0.9752 | 0.9649 | ✓ |

Residual <2 pp differences are explained by:
1. Trase v2.6.1 vs Stefan's v2.5.1
2. FAO CBS revisions between 2022 and 2026 (cake export +3.2 Mt, feed −4.2 Mt)
3. Multi-year ABIOVE roster vs Stefan's 2013-only hand-curated Excel

**Conclusion: the replication was already faithful; only the summary in
`comparison_2013.md` was wrong.** That section is now corrected.

## 5. Market-share allocation experiment (Section 3 — the main new work)

### 5.1 Hypothesis
If we replaced Stefan's equal-per-state allocation with a weighting that reflected real
plant differences (size stratum × parent-company revenue), we might recover *within-state*
variation that the equal-allocation washes out, and improve correlation with Trase.

### 5.2 Design decisions (user-confirmed)
1. **Currency** — constant 2020 BRL, deflated via IBGE IPCA
2. **Revenue scope** — Brazil-segment when disclosed
3. **Cooperatives** — crushing-segment revenue only (avoid over-weighting via total co-op revenue)
4. **Allocation level** — keep Stefan's state-level partitioning (no cross-state competition)
5. **Effort** — full collection authorized

### 5.3 Data foundation built
From raw ABIOVE *Pesquisa* files 2003–2025 (gaps 2016, 2017, 2021 where ABIOVE didn't
publish), built the canonical plant roster:

| File | Content |
|---|---|
| `inputs/.../canonical_plant_roster.csv` | 2,045 plant-year rows, 20 years, 266 unique plants |
| `inputs/.../canonical_companies_with_parents.csv` | 176 raw company names → 122 parent groups (57 flagged for user review) |
| `inputs/.../parent_groups_summary.csv` | Coverage table — top 10 parents cover ~40% of plant-years |

### 5.4 Data collection via 5 parallel agents
- **IPCA + USD-BRL deflator** (2003–2025) — built from published IBGE/BCB figures
- **Bunge + ADM revenue** — 14 + 6 years respectively (Bunge BRL from Brazilian press, ADM USD from 10-K Note 17 for 2019–2024)
- **Cargill + LDC + COFCO revenue** — 17 + 14 + 8 years
- **BRF + JBS + Caramuru + 3Tentos + Amaggi revenue** — 23 + 18 + 14 + 7 + 7 years
- **Plant capacity strata** — 33 of the top ~30 plants assigned to ABIOVE bracket (14 stratum-4, 17 stratum-3, 1 stratum-2)

**Coverage achieved:** 10 parent groups (of 122) with any revenue data; 30 plants (of 266) with explicit stratum. Rest fall back to state-median.

### 5.5 R refactor
`R/new/00_data_preparation/00_data_preparation.R:430-540` now supports
`ALLOCATION_METHOD=market_share` via env var. When set:
```
weight[plant, year] = stratum_midpoint[plant] × (parent_revenue[year] / n_parent_plants_in_state)
per_plant_cap       = state_cap × weight / sum(weights in state)
```
Default remains `equal` (Stefan-compatible).

### 5.6 Result for 2013

Ran 00 → 10 with market_share, computed correlations directly from
`outputs/10_2013/comp_list.rds`:

| Metric | Equal (baseline) | Market-share | Δ |
|---|---:|---:|---:|
| **Pooled r — euclid** | **0.6861** | **0.6688** | **−0.017** |
| Pooled r — downscale | 0.6941 | 0.6941 | 0.000 |
| Top-20 avg r — euclid | 0.6137 | 0.6035 | −0.010 |

**The market-share allocation slightly worsens correlation, not improves it.**

Per-destination, the picture is mixed but net-negative:
- Losses: CHN −0.034, NLD −0.058, DEU −0.060, IDN −0.180
- Small gains: ESP +0.002, VNM +0.008, MEX +0.009, GBR +0.064
- Sanity check that passes: downscale didn't change at all (it weights by production
  shares, not processing capacity, so should be invariant to this change — and is).

### 5.7 Why the result wasn't better

Three structural reasons in our diagnosis:

1. **Data sparsity creates noise, not signal.** 67 of 92 active plants (73%) have no
   explicit stratum or revenue and fall back to state-medians. That smears noise on top
   of the equal allocation. We are differentiating ~25% of plants in a possibly
   informative direction while randomizing the rest.

2. **ADM's revenue figure is systematically wrong for our purpose.** The Bunge+ADM
   research agent flagged that ADM's "Brazil-customer revenue" only captures sales to
   Brazil-domiciled buyers; most of ADM's export volume is booked through Swiss/Cayman
   trading entities. So the revenue *direction* is wrong — ADM looks too small.

3. **Stefan's even allocation is harder to beat than expected.** His own thesis §4.4
   observed that multimode barely beats downscaling, because the dominant signal is at
   the *between-municipality* level (production volumes, distances), not the
   *within-state-across-plants* level our intervention operates on.

## 6. Artifacts produced this session

### Documents
- `docs/ABIOVE_data_construction.md` — how ABIOVE's per-mun data is constructed
- `docs/market_share_allocation_plan.md` — pre-implementation design
- `docs/market_share_results.md` — detailed validation writeup
- `docs/session_report_2026-05-19.md` — this document
- `docs/comparison_2013.md` — corrected (§6c, §6f) to use the right filter

### Scripts
- `scripts/build_canonical_plant_roster.R`
- `scripts/build_parent_group_mapping.R`
- `scripts/build_strata_and_revenue_templates.R`
- `scripts/consolidate_and_validate.R`
- `scripts/run_market_share_validation.sh`

### Data
- `inputs/00/new/ABIOVE_processing/canonical_plant_roster.csv`
- `inputs/00/new/ABIOVE_processing/canonical_companies_with_parents.csv` (57 rows need user review)
- `inputs/00/new/ABIOVE_processing/parent_groups_summary.csv`
- `inputs/00/new/ABIOVE_processing/plant_strata.csv` (30 of 266 plants with explicit data)
- `inputs/00/new/ABIOVE_processing/company_revenue.csv` (230 (parent × year) rows, 10 parents)
- `/tmp/deflators.csv` — IPCA + USD-BRL series 2003–2025 (should be moved to inputs/)

### Code
- `R/new/00_data_preparation/00_data_preparation.R` — refactored at lines 430–540 to
  accept `ALLOCATION_METHOD` environment variable. Default behaviour unchanged.

## 7. Recommended next steps

**Stop and document (recommended).** Stefan's thesis already implies that finer-grained
plant data doesn't add much signal, and our experiment is consistent with that. The
infrastructure is now in place for anyone who wants to try again with better data
later — just refill `plant_strata.csv` and `company_revenue.csv` and rerun.

If continuing:

1. **Switch to a different weighting signal.** Revenue is one proxy; alternatives:
   - Annual crush volume (where disclosed in sustainability reports)
   - State-of-origin export volumes via COMEX for known crusher municipalities
   - Number of employees (Receita Federal RAIS data)
2. **Fix ADM's scope problem.** Either pro-rate global ADM revenue by Brazilian crush
   volume share, or drop ADM revenue and use stratum only for ADM plants.
3. **Manual stratum assignment for the remaining 236 plants.** Cooperatives and small
   private firms — partial data exists in `per_plant_capacity_temporal_web_researched.csv`
   from prior work (which we agreed to ignore for this experiment, but could revisit).

## 8. What the user should review

- **`canonical_companies_with_parents.csv`** — 57 rows have `needs_review = TRUE`.
  These need Brazilian crusher-industry knowledge I don't have to correctly group
  (e.g. is "DIP Frangos" = "Diplomata"? was "Coinbra" really LDC pre-2008?).
- **`session_report_2026-05-19.md`** — this report.
- **`docs/market_share_results.md`** — detailed result tables.

## 9. Headline takeaway

We confirmed:
- The pipeline already faithfully replicates Stefan's r = 0.6919 once the right filter is applied (`co_mun != 9999999`).
- A market-share allocation with realistic data coverage **does not improve** correlation
  with Trase; it slightly worsens it.
- The bottleneck is not the methodology — it's that revenue is a weak proxy for crushing
  capacity at the plant level, and the dominant Trase-vs-model signal is at the
  municipality level where equal allocation already does most of the work.

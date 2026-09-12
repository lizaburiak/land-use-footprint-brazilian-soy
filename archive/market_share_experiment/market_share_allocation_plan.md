# Market-share-based capacity allocation — implementation plan

## Goal

Replace the current **equal-per-state** allocation
```
per_plant_cap = state_cap[year] / n_active_soy_plants_in_state[year]
```
with a **market-share-weighted** allocation
```
weight[plant, year]   = stratum_midpoint[plant, year] × revenue_share[parent[plant], year, state]
per_plant_cap[p, y]   = state_cap[s, y] × weight[p, y] / sum(weights in state s, year y)
mun_cap[m, y]         = Σ per_plant_cap over plants in mun m
```

The goal is **higher correlation with Trase** than the equal-allocation baseline,
without using Trase itself as the weighting signal (which would be circular).

## Scope from the canonical roster

Built from raw ABIOVE `pesquisa_capacidade_YYYY` files (script:
`scripts/build_canonical_plant_roster.R`):

| Stat | Value |
|---|---:|
| Years covered | 20 (2003–2025, gaps in 2016, 2017, 2021 where ABIOVE didn't publish) |
| Plant-year rows | 2,045 |
| Active soy crushers (`Ativa` only) | 1,706 |
| Unique raw company names | 176 |
| Unique parent groups (after dedupe) | ~80–90 (140 in draft; expect convergence after review) |
| Unique municipalities | 131 |

Files produced:
- `inputs/00/new/ABIOVE_processing/canonical_plant_roster.csv` — all plant-years
- `inputs/00/new/ABIOVE_processing/canonical_companies_raw.csv` — 176 raw names
- `inputs/00/new/ABIOVE_processing/canonical_companies_with_parents.csv` — draft mapping (57 of 176 need manual review)
- `inputs/00/new/ABIOVE_processing/parent_groups_summary.csv` — coverage table

### Plant-year coverage by parent group (key for revenue scoping)

| Tier | Parents | Cumulative share of plant-years |
|---|---|---:|
| 1 — Multinationals + big domestic | Bunge, ADM, Cargill, LDC, COFCO, BRF, Amaggi, Caramuru, JBS | **~39%** |
| 2 — Mid-size private + co-ops | Granol, Brejeiro, Coamo, Camera, Comigo, Bianchini, Imcopa, Sina, Insol, Oleoplan, Cocamar, Coopavel, Cooperalfa, 3Tentos | **~70%** |
| 3 — Long tail | ~120 small/regional/defunct firms | 100% |

## Recommended tiered data-collection effort

Be pragmatic: **don't try to get revenue for all 140 parent groups**. Stop where
the marginal data-availability cost exceeds the marginal signal.

### Tier 1 (high-quality public data, ~40% of plant-years)
| Company | Revenue source | Coverage |
|---|---|---|
| ADM | SEC 10-K (Brazil segment in MD&A) | 2000–2025 |
| Bunge | SEC 10-K (Brazil South America segment) | 2000–2025 |
| Cargill | Cargill annual report (Brazil ops disclosed since 2010s) | 2010–2025 |
| LDC | LDC annual sustainability/financial report (since 2018) | 2018–2025 |
| COFCO Intl | COFCO Intl annual report | 2014–2025 |
| BRF | B3 listed, full Brazilian disclosures | 2009–2025 |
| JBS | B3 listed | 2007–2025 |
| Caramuru | B3 listed (CARA3) | 2007–2025 |
| 3Tentos | B3 listed (TTEN3) | 2021–2025 |
| Amaggi | Amaggi sustainability reports (revenue since ~2014) | 2014–2025 |

Effort: **4–6 hours** scraping ~10 documents per company.

### Tier 2 (Valor 1000 + sustainability reports, ~30% more)
- Valor 1000 Brazilian annual ranking — covers Granol, Bianchini, Coamo, Cocamar, Comigo, Camera, Imcopa, Sina, Oleoplan, Olfar, Olvego, Brejeiro… patchily.
- Effort: **6–10 hours** to pull and reconcile.

### Tier 3 (the long tail, ~30%)
- Skip revenue entirely. Use ABIOVE stratum only.
- For very small / defunct firms (Agrenco post-bankruptcy, Diplomata, Coinbra pre-LDC, Imcopa post-bankruptcy), assign a default stratum based on known plant size at exit.

**Total realistic effort: 10–16 hours** (vs naive 25 if collecting everything).

## Stratum assignment

ABIOVE's plant-size brackets (`4. estratific` sheet):

| Stratum | Range (t/day) | Midpoint to use as weight |
|---:|---|---:|
| 1 | ≤ 599 | 300 |
| 2 | 600 – 1,499 | 1,050 |
| 3 | 1,500 – 2,999 | 2,250 |
| 4 | ≥ 3,000 | 4,500 (or higher for known mega-plants) |

For 2013, we already have **actual per-plant capacities** in the 2013 ABIOVE
Excel (`facilities_proc` sheet). Assign strata directly from those (122 plants
covered). For ~30 plants with web-cited capacity values (already in
`per_plant_capacity_temporal_web_researched.csv` — but we agreed to ignore
that file), redo from primary sources.

For plants without any cited capacity, **default to the state-median stratum**
to avoid distorting allocation.

Effort: **3–5 hours** (most of 2013 is "free" from the existing file).

## Pre-implementation decisions you still need to make

1. **Currency / inflation** — revenue is multi-year. Use:
   - Nominal USD (simplest, but biased by FX)
   - Constant 2020 USD (deflated by US CPI; comparable across years)
   - Constant 2020 BRL (deflated by IPCA; matches local pricing)
   - **Recommendation: constant 2020 BRL** because the plants are domestic.

2. **Revenue scope when global ≠ Brazil**
   - For Bunge/ADM/Cargill/LDC/COFCO global revenues are public but Brazil-only
     segments aren't always broken out. Options:
     - Use global revenue (overstates these firms' weight)
     - Use Brazil-segment when disclosed, fall back to a Brazil share of global
     - Use Brazilian subsidiary financials from Receita Federal (CNPJ) — patchy
   - **Recommendation: Brazil-segment when disclosed; else `global × Brazil_share`
     using the firm's own disclosure of geographic mix.**

3. **Cooperative handling**
   - Coamo/Cocamar/Camera/Comigo report TOTAL co-op revenue including grain
     sales, ag inputs, ag credit, etc. Crushing is a fraction. Three options:
     - Use total co-op revenue (over-weights co-ops)
     - Use co-op's "Industrial / Esmagamento" segment if reported (Coamo does)
     - Estimate crushing revenue from their public crush volume × crush margin
   - **Recommendation: segment-when-disclosed, fall back to capacity × benchmark margin.**

4. **Allocation granularity — state or national?**
   - Current Trsek method allocates *within state*, so a Bunge plant in MT
     competes only with other MT plants for state MT capacity.
   - Alternative: allocate state capacity across plants by *national company size*
     (Bunge gets a bigger slice everywhere). This implicitly assumes companies
     run all plants near max utilization.
   - **Recommendation: keep state-level allocation** (closer to physical reality;
     interstate redistribution would mis-attribute capacity).

5. **Validation strategy**
   - Holdout test: for 2013, we have actual per-plant capacity from the ABIOVE
     Excel. Compare new allocation against this ground truth (the existing
     methodology achieved r = 0.686 on this test).
   - End-to-end test: rerun steps 00→11 for 2013, compare pooled Pearson r
     vs Stefan's 0.6919 baseline.

## Sequence of work

Once the decisions above are made:

1. **Manual review of `canonical_companies_with_parents.csv`** (57 rows flagged
   `needs_review = TRUE`). User edit. ~1 hour.
2. **Stratum assignment** for plants. Output: `plant_strata.csv` with
   columns `(parent_group, municipality, UF, year_range, stratum, source)`. ~3–5 hours.
3. **Revenue collection** for Tier 1 + Tier 2 companies. Output:
   `company_revenue.csv` with columns
   `(parent_group, year, revenue_constant_2020_BRL_million, source, scope)`. ~10–16 hours.
4. **Refactor `R/new/00_data_preparation/00_data_preparation.R`** to take an
   `allocation_method` argument (`equal` | `market_share`). When
   `market_share`, join the canonical roster against stratum + revenue files
   and compute weights. ~3 hours.
5. **Rerun 00 → 11 for 2013** (and a couple of other validation years like
   2018, 2022) to check correlation against Trase. ~2 hours run time.
6. **Compare correlations** in `docs/market_share_results.md`.

Total: **~20–28 hours** end-to-end.

## What I will NOT do without you confirming

- Send LAI requests to state environmental agencies.
- Email ABIOVE directly for private data.
- Use the `FINAL_*` derived files (you said ignore those).
- Spend more than ~30 min per Tier-3 company.

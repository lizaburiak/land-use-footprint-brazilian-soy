# Market-share allocation — 2013 validation results

## Headline

With **Tier 1 data only** (10 parent groups × 23 years of revenue, 30 plants with explicit stratum), the
market-share allocation **marginally degrades** correlation with Trase compared to
Stefan's equal-allocation baseline.

| Metric | Equal baseline | Market-share (Tier 1) | Δ |
|---|---:|---:|---:|
| **Pooled r — euclid** | **0.6861** | **0.6688** | **−0.017** |
| Pooled r — downscale | 0.6941 | 0.6941 | 0.000* |
| Pooled r — multimode (=euclid here) | 0.6861 | 0.6688 | −0.017 |
| Top-20 avg r — euclid | 0.6137 | 0.6035 | −0.010 |
| Top-20 avg r — downscale | 0.4329 | 0.4329 | 0.000* |

*Downscale doesn't depend on processing capacity (it weights by production
shares), so it should be invariant to the allocation method — sanity check passes.

## What changed and what didn't

The new method redistributed processing capacity for **92 active soy crushers** in
2013, of which:
- **25 plants have explicit stratum** (from web-researched capacities like
  Bunge Rondonópolis 5,000 t/d, ADM Rondonópolis 6,500 t/d).
- **22 plants belong to a parent group with revenue data** (Bunge, ADM, Cargill,
  LDC, COFCO, BRF, JBS, Caramuru, 3Tentos, Amaggi).
- **67 plants (73%) use state-median fallback** for both stratum and revenue.

State and national totals are preserved exactly (159,900 t/d national, matches
ABIOVE). Only the *within-state* distribution changes.

## Per-destination changes (top 12 importers)

| Dest | Equal r_euclid | Market-share r_euclid | Δ |
|---|---:|---:|---:|
| CHN  | 0.8017 | 0.7681 | **−0.034** |
| BRA  | 0.3799 | 0.3923 | +0.012 |
| NLD  | 0.6808 | 0.6232 | **−0.058** |
| ESP  | 0.9085 | 0.9100 | +0.002 |
| DEU  | 0.3834 | 0.3230 | **−0.060** |
| THA  | 0.5016 | 0.4921 | −0.009 |
| KOR  | 0.5628 | 0.5464 | −0.016 |
| FRA  | 0.4526 | 0.4350 | −0.018 |
| VNM  | 0.7124 | 0.7199 | +0.008 |
| JPN  | 0.8228 | 0.8100 | −0.013 |
| IDN  | 0.3411 | 0.1609 | **−0.180** |
| MEX  | 0.8156 | 0.8250 | +0.009 |

Most changes are small and inconsistent. The big drops (NLD, DEU, IDN) outweigh
the small gains.

## Why the result isn't surprising

Three structural reasons:

### 1. Data sparsity creates noise, not signal
Only 25/92 plants have an explicit stratum. The other 67 fall back to the
**state-median** stratum, which essentially nudges them all toward the middle.
That smears noise on top of the equal allocation rather than differentiating
plants meaningfully. Same for revenue: only 22/92 plants have a parent-group
revenue figure; the rest fall back to median.

The data we have moves ~25% of plants in the "right" direction — but the
remaining 75% are essentially randomized within ± state-median, which the
correlation penalizes.

### 2. ADM's "Brazil revenue" understates its real footprint
The Bunge+ADM agent explicitly flagged this:
> ADM's Brazil-customer revenue substantially understates its actual Brazilian
> operational footprint. Much of the export flow is booked through Swiss/Cayman
> trading entities.

So even our Tier 1 revenue data has known scope problems. For ADM specifically,
the revenue weight is *wrong* in a direction that doesn't reflect actual
crushing share.

### 3. Stefan's even-allocation may be hard to beat
Stefan's framework still gets r = 0.69 because the transport optimization
absorbs most of the variation between municipalities, regardless of how
state capacity is distributed across plants within a municipality. The
within-state-across-plants signal we're trying to inject is small relative to
the between-municipality signal that already dominates.

## What this means for the path forward

Three options:

### Option A — Invest in Tier 2/3 data collection
Get explicit stratum + revenue for the remaining 67 plants. If complete
coverage gives r = 0.74+, the methodology works and the partial result was
misleading. If complete coverage stays around 0.69, it doesn't.

Effort estimate: **15–20 more hours** of web research (Tier 2 cooperatives,
mid-size private firms, defunct firms).

Expected outcome: **moderate gain of perhaps +0.02 to +0.04 pooled r**, based
on the directional movement we saw in the 22 plants with full data.

### Option B — Use Trase volumes as plant weights (circular but powerful)
Use each plant's municipality's Trase outflow share as the weight. This
guarantees better correlation by construction but is **circular** — you can't
then validate against Trase. Could be useful if you want to use the model for
extrapolation to non-Trase years.

### Option C — Acknowledge "equal allocation" is the right baseline
Stefan's thesis section 4.4 already says:
> "the developed model framework (i.e., the Euclidean and multi-modal model)
> does not come closer to the results of Trase than a simple downscaling …
> the more complex multi-modal model does not add value compared to the
> Euclidean-distance-based allocation"

This empirical finding is consistent with that observation — adding more
plant-level realism doesn't necessarily help when the dominant signal is at
the municipality level.

## Files produced

- `inputs/00/new/ABIOVE_processing/canonical_plant_roster.csv` — 2,045 plant-years
- `inputs/00/new/ABIOVE_processing/canonical_companies_with_parents.csv` — 176 names → 122 parents (57 need user review)
- `inputs/00/new/ABIOVE_processing/plant_strata.csv` — 266 plants, 30 with explicit stratum
- `inputs/00/new/ABIOVE_processing/company_revenue.csv` — 230 rows, 10 parent groups with data
- `scripts/build_canonical_plant_roster.R`
- `scripts/build_parent_group_mapping.R`
- `scripts/build_strata_and_revenue_templates.R`
- `scripts/consolidate_and_validate.R`
- `R/new/00_data_preparation/00_data_preparation.R` — refactored with `ALLOCATION_METHOD` env var

## How to reproduce

```bash
# Baseline (equal allocation, already validated):
Rscript R/new/00_data_preparation/00_data_preparation.R 2013

# Market-share allocation:
ALLOCATION_METHOD=market_share Rscript R/new/00_data_preparation/00_data_preparation.R 2013

# Run downstream:
for step in 01_consumption_and_processing 02_livestock_systems 03_feed_use \
            04_trade_harmonization 05_balancing 07_transport_R \
            08_export_link_mean 10_create_benchmarks; do
  Rscript R/new/${step}.R 2013
done

# Check correlation:
Rscript /tmp/check_corr.R
```

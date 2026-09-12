# Archived: market-share allocation experiment

These scripts built a plant-level **market-share** weighting (size stratum × parent-company
revenue) to replace Stefan's equal-per-state crushing-capacity allocation in step 00.

**Outcome (2026-05-19):** the market-share allocation **did not improve** correlation with Trase
(it slightly worsened it) — revenue is a weak proxy for plant-level crushing capacity. See
`docs/session_report_2026-05-19.md` and `docs/market_share_results.md`. Archived rather than
deleted so the infrastructure can be revisited with a better weighting signal.

## Files
- `build_canonical_plant_roster.R` — ABIOVE *Pesquisa* files 2003–2025 → canonical plant roster
- `build_parent_group_mapping.R` — raw company names → parent groups
- `build_strata_and_revenue_templates.R` — plant size-stratum + revenue templates
- `consolidate_and_validate.R` — merges deflators + revenue + strata into final weights
- `run_market_share_validation.sh` — end-to-end driver (2013, market_share vs equal)

## Not runnable as-is
The driver and `consolidate_and_validate.R` read scratch files that no longer exist
(`/tmp/check_corr.R`, `/tmp/deflators.csv`, `/tmp/revenue_*.csv`, `/tmp/plant_strata_research.csv`).

## Still live (NOT archived)
The **generated outputs** these scripts produced are kept under
`inputs/00/new/ABIOVE_processing/` (`canonical_plant_roster.csv`, `company_revenue.csv`,
`plant_strata.csv`, …) and are read directly by
`R/reproduction/00_data_preparation/00_data_preparation.R` when run with
`ALLOCATION_METHOD=market_share`. So the experiment can still be reproduced from those CSVs
without re-running these builders.

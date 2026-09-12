# Multimode transport model — 2010–2022 results vs Euclidean vs TRASE

*Runs executed 2026-07-27 → 2026-07-29 on the laptop; written up 2026-08-04.*

## What was run

Stefan's intermodal (road/rail/water) min-cost-flow transport model, end-to-end and
year-parameterized, for **2010–2022** (2021 failed — see below):

1. `code/pipeline/06_transport_cost.R YEAR` — least-cost network distance matrices
   (OSM roads at 5 km resolution, ANTT rail, DNIT waterways; ~20–40 min/year).
2. `code/pipeline/transport_lp/solve_one.py YEAR` — the GAMS model ported to
   Pyomo+HiGHS, **central cost parameters only** (Góes & Lopes 2018), no bootstrap
   (one solve = 11 min–5.5 h on this machine; Stefan's 1000-iteration bootstrap is a
   server job).
3. `08_export_link_{mean,sep}.R` → `10_create_benchmarks.R` → `11_analyse_benchmarks.R`
   — link to COMEX exports and benchmark against TRASE (v2.6.1).

Orchestration: `code/run_multimode_year.sh` / `code/run_multimode_all.sh`
(resumable; per-step status in `logs/multimode_runs.log`).

## Headline result

**Multimode ≈ Euclidean.** Global pooled Pearson vs TRASE (base weighting):

| Year | Multimode | Euclid | Δ (mm−eu) | Water cargo |
|---|---|---|---|---|
| 2010 | 0.585 | 0.603 | −0.017 | proxied (2017) |
| 2011 | 0.697 | 0.726 | −0.029 | proxied |
| 2012 | 0.679 | 0.682 | −0.003 | proxied |
| 2013 | 0.646 | 0.686 | −0.040 | proxied |
| 2014 | 0.673 | 0.652 | +0.021 | proxied |
| 2015 | 0.717 | 0.726 | −0.009 | proxied |
| 2016 | 0.713 | 0.732 | −0.019 | proxied |
| 2017 | 0.771 | 0.785 | −0.014 | **real** |
| 2018 | 0.766 | 0.727 | +0.039 | **real** |
| 2019 | 0.728 | 0.723 | +0.005 | **real** |
| 2020 | 0.713 | 0.705 | +0.008 | **real** |
| 2021 | — | 0.681 | — | real (LP infeasible, no multimode solve) |
| 2022 | 0.597 | 0.588 | +0.010 | **real** |

Full panel (all weightings + RMSLE): `results/tables/benchmarks/multimode_vs_euclid_panel_2010-2022.csv`
(rebuild with `Rscript code/analysis/compile_multimode_panel.R`).
Per-year detail (per-destination Pearson, RMSE, scatter/maps): `results/tables/benchmarks/<year>/`,
`results/figures/correlation_scatter/<year>/`, `results/maps/benchmark_maps/<year>/`.

## Reading

1. **Straight-line distance is a very good approximation.** |Δ| ≤ 0.04 in every year;
   the Euclidean default of the pipeline (Path B) is empirically justified.
2. **Real vs proxied water cargo matters.** With real ANTAQ cargo (2017–2022),
   multimode beats Euclidean in 4 of 5 solved years (mean Δ ≈ +0.010); with 2017
   cargo proxied onto 2010–2016, it loses in 6 of 7 (mean Δ ≈ −0.014). Feeding the
   network model wrong-year infrastructure/capacity data is worse than not using a
   network at all.
3. **Where multimode helps:** destinations served by rail/barge export corridors —
   e.g. 2019 per-destination: CHN 0.835 vs 0.818, KOR 0.457 vs 0.336, FRA 0.436 vs
   0.383. Where it hurts: NLD 0.478 vs 0.589, DEU 0.389 vs 0.455.

## Caveats

- **Central solve only** — no bootstrap uncertainty bands (LP solve is 11 min–5.5 h
  per iteration on this hardware; wall time varies wildly by year).
- **Water cargo 2010–2016 proxied with 2017** (ANTAQ's server, `web3.antaq.gov.br`,
  down for the whole run window; ≤2016 zips are not in the Wayback Machine). Redo
  those years when ANTAQ resurfaces: drop the files in `data/geo/ANTAQ/`, delete
  `data/generated/outputs/06_{2010..2016}` + `outputs/gams/bs_res_{2010..2016}`, rerun
  `code/run_multimode_all.sh`.
- **Static infrastructure**: one OSM road snapshot (2014), one ANTT rail-line layer,
  one ANTAQ port registry (~2025 vintage, `IP.shp` + rebuilt `ip_add.gpkg`) for all
  years. Only cargo volumes/capacities vary by year. Same simplification as Stefan's
  original 2013 study.
- **2021 is unsolved**: the LP is infeasible (others all solve to optimality).
  Working hypothesis (undiagnosed): a supply/demand-balance node dropped from the
  distance matrices (non-geographic placeholder municipality) breaks the equality
  constraints. Its `results/tables/benchmarks/2021/` tables are Euclidean-only —
  the "multimode" column there is the no-bootstrap fallback (= euclid), **not** a
  multimode result.
- Rail cargo is real per-year data (ANTT OD CSVs, 2006–2023) for **all** years —
  the proxy caveat concerns water only.

## Data provenance (recovered 2026-07-27/28)

- **ANTT rail OD** (`data/geo/ANTT/RailCargo_od/`, 2006–2023, 2023 partial):
  Wayback Machine copies of `dados.antt.gov.br` resources (WAF blocks non-BR IPs).
  Replaces Stefan's lost `RailCargo_2006-21_ANTT.xls`. See folder README.
- **ip_add.gpkg** (`data/geo/ANTAQ/`): rebuilt by `code/prep/prep_ip_add.R` (6 river
  terminals absent from IP.shp; ~1–2.5 %/yr of interior soy tonnage; only the
  non-geographic catch-all `BR200` remains unmapped).
- **ANTAQ water cargo** 2017–2022: were already in the repo.

## Code fixes made for these runs (in `code/pipeline/`)

`06_transport_cost.R`: rail xls→CSV reader; terra-based OSM layer write (sf's
CPL_write_ogr segfaults intermittently on the 295k-feature layer); name-based
station column selection; SOY_MUN↔MUN_capitals row alignment; auto-snap of ports
off the 5-km water raster (BRPA005 carried ~5 % of water tonnage); modal-split
diagnostic tolerant of years with <3 rail products; ANTAQ nearest-year fallback.
`08_export_link_mean.R` + `10_create_benchmarks.R`: bootstrap columns detected by
pattern instead of hardcoded "00001".

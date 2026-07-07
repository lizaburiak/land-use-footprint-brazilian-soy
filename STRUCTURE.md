# Repository structure

This repo holds Liza's **year-parameterized reproduction/extension** of Stefan Trsek's 2013 soy
thesis model. Stefan's original pipeline is preserved under `archive/code_old_stefan/`. Everything
runs **from the project root** with root-relative paths (RStudio working dir = this folder).

```
soyprint/
├── data/                    ← all pipeline data (git-ignored), organized by purpose:
│   ├── raw/                 ←   per-step multi-year inputs  (raw/NN/)
│   ├── geo/                 ←   spatial layers (GADM, OSM, DNIT, ANTAQ, ANTT, biomes, MB tiles)
│   ├── fabio/               ←   FABIO v2 backend (v2/) + trade data for steps 04/12 (trade/)
│   ├── trase/               ←   Trase composite benchmark
│   ├── exiobase/            ←   EXIOBASE pxp
│   └── generated/           ←   intermediate data the pipeline PRODUCES & later steps CONSUME:
│       ├── outputs/         ←     steps 00–12 per-step per-year (NN_{YEAR}/)
│       ├── fabio/           ←     steps 13–20 MRIO matrices
│       ├── footprints/      ←     {YEAR}_{F,P}_{mass,value}.rds
│       └── base/            ←     old-pipeline intermediates (live plotting deps)
├── code/                    ← all code
│   ├── pipeline/            ←   the model, steps 00–21  + transport_lp/ (Python transport)
│   ├── analysis/            ←   paper figures/plots (footprint_*, plot_*, correlation_*, web)
│   ├── prep/                ←   data-prep feeders (prep_exiobase_*, prep_fabio_*, prep_map_*, …)
│   ├── shared/              ←   helpers sourced by the pipeline (was R/auxiliary)
│   ├── run_all.sh  run_year_full.sh  run_footprints.sh   ← pipeline + footprint runners
│   └── download_data.py  aggregate_years.R               ← data + results tools
├── results/                 ← terminal, human-facing outputs, grouped by purpose:
│   ├── figures/             ←   paper/ footprint_dynamics/ sensitivity/ correlation_scatter/
│   ├── maps/                ←   footprint_maps/ probability_maps/ benchmark_maps/ commodity_balance_maps/
│   ├── tables/              ←   benchmarks/ comparison_2013/ comparison_years/
│   └── reference/           ←   mun_biome_lookup.csv, pipeline_scheme.* (was structure/)
│       ( folder names describe contents; per-year step-11 output nests as
│         <content_folder>/{YEAR}/ — e.g. correlation_scatter/2013/, benchmark_maps/2013/ )
├── logs/                    ← run logs (year_YYYY/) + run_all_summary.txt
├── docs/                    ← paper_plan, literature_review, figures_plan, validation records
│                                (comparison_2013, multi_year), Thesis_Trsek_2507.pdf, workflow_scheme.png
├── archive/                 ←   code_old_stefan/ (2013 thesis pipeline), code_python_scaffold/,
│                                docs_generators/, market_share_experiment/ — not in any active pipeline
├── RUNBOOK.md               ← how to run it (start here)
├── STRUCTURE.md             ← this file
├── WHAT_IS_MISSING.md       ← data / dependency gaps
└── README.md  LICENSE  soyprint.Rproj
```

## Running it

```bash
bash code/run_all.sh              # every year 2000–2020, steps 00–21
bash code/run_all.sh 2013 2013    # a single year
bash code/run_year_full.sh 2013   # one year (core 00–12 fatal; 13–21 soft-skip if FABIO/EXIOBASE absent)
bash code/run_footprints.sh 2010 2020   # footprint chain (steps 13–20) over a year range
```
See `RUNBOOK.md` for the full guide. Logs → `logs/year_YYYY/`. The core runs 00→12 with Euclidean
transport (skips the GAMS multimode 06/07 and sensitivity 09). (Two older convenience runners,
`run_year_pathB.sh` and `run_from05.sh`, now live in `archive/legacy_runners/`.)

## code/

| Folder | What it is |
|---|---|
| `code/pipeline/` | **The model** — year-parameterized steps `00_*.R … 21_*.R` (year = `commandArgs[1]`, default 2013, range 2000–2022). Reads `data/raw/`, `data/geo/`, `data/trase/`, `data/fabio/`, writes `data/generated/outputs/NN_{YEAR}/`. `00_data_preparation/` holds the rewritten step 00; `transport_lp/` is the Python multimode transport. See `code/pipeline/CHANGELOG.md`. |
| `code/analysis/` | Paper figures & plots run *after* the pipeline: `footprint_*`, `plot_*`, `correlation_*`, `compare_*`, `fig_*`, `figstyle.py`, web builders. Read `results/`, write `results/figures/`. |
| `code/prep/` | Data-prep feeders for the footprint chain & figures: `prep_exiobase_*`, `prep_fabio_X`, `prep_map_*`, `prep_web_data`, `prep_enduse_ha`. |
| `code/shared/` | Helpers (`fabio_tidy_functions.R`, plotting/maps) sourced by the pipeline as `source("code/shared/...")`. |
| `code/*.sh`, `*.py`, `*.R` (root) | Runners (`run_all`, `run_year_full`, `run_footprints`) + tools (`download_data.py`, `aggregate_years.R`). |
| `archive/code_old_stefan/` | Stefan's unmodified 2013 thesis pipeline `00_*.R … 21_*.R` + `gams/` (GAMS transport model). Superseded by `code/pipeline/`; kept for provenance. |
| `archive/code_python_scaffold/` | Partial Python port of the pipeline (steps 00–04 validated, rest scaffold). Not wired into any runner. |

## data/ — organized by purpose

All git-ignored (large / license-restricted). Since the earlier "old vs new" split was confusing
(both were live inputs), the tree is now organized by what the data *is*:

- `data/raw/` — the per-step multi-year inputs: `data/raw/NN/` per step (`00, 02, 03, 04`).
  `data/raw/00/` is organized by source (`ABIOVE_processing/`, `ANP_biodiesel/`,
  `COMEX_{exports,imports,codes}/`, `FAO_CBS/`, `IBGE_*`, `trase_facilities/`).
  *(Stefan's 2013 step-00 originals now live in `archive/data_stefan_2013/`, used only by the
  `compare_processing_methods.R` diagnostic.)*
- `data/geo/` — spatial layers: GADM boundaries, OSM roads, DNIT waterways, ANTAQ ports, ANTT rail,
  IBGE biomes, MapBiomas soy tiles, plus `RailCargo…ANTT.xls`.
- `data/fabio/` — `v2/` (the FABIO v2 backend for steps 13–20) + `trade/` (FABIO bilateral trade
  read by steps 04/12). *(Stefan's original FABIO lives in `archive/fabio_stefan/`.)*
- `data/trase/` — the Trase composite benchmark (`brazil_soy_v2_6_1_composite.csv`).
- `data/exiobase/` — EXIOBASE pxp matrices.
- `data/generated/` — **intermediate data the pipeline produces and later steps consume**
  (regenerable, so it lives with the data it feeds on): `outputs/` (steps 00–12, ≈14G), `fabio/`
  (steps 13–20 MRIO, ≈31G), `footprints/` (`{YEAR}_{F,P}_{mass,value}.rds`), `base/` (old-pipeline
  intermediates still read by the plotting layer).

## results/ — curated deliverables only (grouped by purpose)

Only the paper outputs live here now (the 40 git-tracked files + the current paper figures); all
regenerable pipeline data moved to `data/generated/`.

Folder names describe their contents. Per-year step-11 output nests under the matching content
folder as `<folder>/{YEAR}/` (e.g. `correlation_scatter/2013/`, `benchmark_maps/2013/`,
`benchmarks/2013/`).

- `results/figures/` — `paper/` (main paper figures), `footprint_dynamics/` (composition over
  time), `sensitivity/` (sensitivity analysis), `correlation_scatter/` (model-vs-Trase scatter).
- `results/maps/` — `footprint_maps/` (land-footprint choropleths over time), `probability_maps/`
  (grid probability maps), `benchmark_maps/` (model vs Trase), `commodity_balance_maps/`.
- `results/tables/` — `benchmarks/` (per-year pearson/rmse/export tables), `comparison_2013/`,
  `comparison_years/` (multi-year correlation & intensity), + loose aggregate `.tex`/`.csv`.
- `results/reference/` — `mun_biome_lookup.csv`, `pipeline_scheme.*` (was `structure/`).

## Known data gaps

See `WHAT_IS_MISSING.md` for the full audit. Headlines: the multimode transport (step 06 →
`transport_lp`) needs a few `data/geo/` files that aren't present; steps 13–21 need
WU/fineprint's FABIO + EXIOBASE data (`/mnt/nfs_fineprint/…`, not local). Neither blocks the
default Path B, which runs for all of 2000–2020.

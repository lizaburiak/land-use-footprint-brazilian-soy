# Data manifest

This repository holds the **code** for the soyprint model. The **input data** and the
**footprint outputs** are too large (and partly license-restricted) to ship in git, so
they live in separate hosted archives. This file says exactly what data is needed, where
to get it, and where each file must be placed for the pipeline to find it.

Three tiers:

| Tier | What | Where it lives |
|---|---|---|
| **Code** | pipeline + data-collection scripts | this GitHub repo |
| **Inputs** (~36 GB) | raw source data the pipeline reads (`data/`) | hosted archive — see [Hosted archives](#hosted-archives) |
| **Outputs** (~12 GB) | the footprint results (`data/generated/footprints/`) | hosted archive — see [Hosted archives](#hosted-archives) |

All of `data/` is git-ignored. Nothing below is committed; you download or regenerate it locally.

---

## Quick start

```bash
# 1. Programmatically fetch the auto-downloadable inputs for 2014-2025
python3 code/download_data.py                 # all sources, all years
python3 code/download_data.py --dry-run       # preview targets without downloading

# 2. Add the manual + large-backend inputs (see tables below)

# 3. Run the pipeline (see RUNBOOK.md)
bash code/run_all.sh
```

`download_data.py` writes each file straight into the `data/raw/<step>/<SOURCE>/` location the
pipeline reads it from — no manual moving needed. Files that already exist are skipped.

---

## Automated inputs — `code/download_data.py`

Fetched programmatically for **2014–2025** (years 2000–2013 come from the original archive; see
[Hosted archives](#hosted-archives)). Sources are public and free.

| Dataset | Source | Lands in |
|---|---|---|
| COMEX municipal trade (exports/imports) | MDIC — balanca.economia.gov.br | `data/raw/00/COMEX_exports/`, `data/raw/00/COMEX_imports/` |
| COMEX lookup tables (country / municipality codes) | MDIC | `data/raw/00/COMEX_codes/` (+ `PAIS_COMEX.csv` copied to `data/raw/04/`) |
| Soybean production (IBGE SIDRA table 1612) | IBGE SIDRA API | `data/raw/00/IBGE_production/` |
| Population (IBGE SIDRA table 6579) | IBGE SIDRA API | `data/raw/00/IBGE_population/` |
| Livestock headcounts (IBGE SIDRA table 3939) | IBGE SIDRA API | `data/raw/00/IBGE_livestock/` |
| Milked cows (IBGE SIDRA table 94) | IBGE SIDRA API | `data/raw/00/IBGE_milkcows/` |
| FAOSTAT commodity balance (FBS, soy) | FAOSTAT bulk | `data/raw/00/FAO_CBS/` |
| FAOSTAT bilateral trade matrix (soy) | FAOSTAT bulk | `data/raw/04/` |
| Municipality code list | IBGE localidades API | `data/raw/00/IBGE_municipalities/` |
| Municipality boundaries | generates an R helper using the `geobr` package | `data/raw/00/IBGE_boundaries/` |

> Boundaries: the script writes `data/raw/00/_scripts/download_geobr_boundaries.R`; run it in R
> (`source(...)`) to fetch the `.gpkg` boundaries via `geobr`.

---

## Manual inputs

Not automatable — download once from the source and save to the listed path.
`download_data.py` prints this same checklist at the end of its run.

| Dataset | Source | Save to |
|---|---|---|
| ABIOVE processing/refining capacity | https://abiove.org.br/estatisticas/ | `data/raw/00/ABIOVE_processing/ABIOVE_raw_capacity_{YEAR}.xlsx` |
| ANP biodiesel capacity | https://www.gov.br/anp/ (annual yearbook, Table 2.6) | `data/raw/00/ANP_biodiesel/Biodiesel_capacity_{YEAR}_ANP.xlsx` |
| IBGE POF (soy-oil consumption) | https://www.ibge.gov.br/ (POF 2017–2018) | `data/raw/00/IBGE_POF/POF_soy_oil_{YEAR}_IBGE.csv` |
| IBGE grain storage (armazéns) | https://sidra.ibge.gov.br/tabela/278 | `data/raw/00/IBGE_storage/armazens_{YEAR}.shp` |
| IBGE localities (capitals) | IBGE geoftp | `data/raw/00/IBGE_localities/` |
| IBGE feedlot-cattle census (2017, table 6911) | https://sidra.ibge.gov.br/tabela/6911 | `data/raw/02/FeedlotCattle_2017_tabela6911_IBGE.xlsx` |
| FAO gridded livestock (GLW3, 2010) | https://dataverse.harvard.edu/dataverse/glw | `data/raw/02/geo/FAO_gridded_livestock/` |
| FAO GLEAM production-system raster & feed ratios | https://www.fao.org/gleam/ | `data/raw/02/geo/FAO_gridded_livestock/`, `data/raw/03/Feed_ratios_FAO.xlsx` |

---

## Large backends & spatial layers

Needed for the footprint steps (13–21) and transport; obtain separately.

| Dataset | Source | Save to |
|---|---|---|
| FABIO bilateral trade (1986–2013 prebuilt) | https://doi.org/10.5281/zenodo.2577066 | `data/fabio/trade/` |
| FABIO v2 backend | fineprint-global / WU | `data/fabio/v2/` |
| EXIOBASE 3 (pxp) | https://www.exiobase.eu/ | `data/exiobase/pxp/` |
| Trase composite benchmark | https://trase.earth/ | `data/trase/` |
| Spatial layers (GADM, OSM roads, DNIT waterways, ANTAQ ports, ANTT rail, IBGE biomes, MapBiomas soy tiles) | see `STRUCTURE.md` | `data/geo/` |

The `data/geo/` spatial layers feed the transport step; the footprint steps (13–21)
additionally require the FABIO v2 and EXIOBASE backends listed above.

---

## Hosted archives

> **TODO — fill in once uploaded.** The full input tree and the footprint outputs are hosted
> outside git so colleagues can download them directly.

| Archive | Contents | Link |
|---|---|---|
| **Initial data** (~36 GB) | the complete `data/` input tree (2000–2025), ready to unpack at the repo root — the fastest way to get a runnable checkout without re-fetching from every source | _‹add link / DOI›_ |
| **Footprint outputs** (~12 GB) | `data/generated/footprints/{YEAR}_{F,P}_{mass,value}.rds` — the results themselves, for reproducing figures/tables without rerunning the 00–20 pipeline | _‹add link / DOI›_ |

To use an archive: download, unpack at the repo root so paths resolve as `data/...`, then run
the pipeline (`RUNBOOK.md`) or the analysis scripts (`STRUCTURE.md`).

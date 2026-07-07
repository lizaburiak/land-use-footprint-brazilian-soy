 [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
 
# Mapping the land-use footprint of Brazilian soy embodied in international consumption: A spatially explicit input-output approach

### 🌐 [**Explore the interactive footprint map →**](https://lizaburiak.github.io/soyprint-footprint-map/)

### 📄 Paper drafts (render in-browser): [**Data section**](https://lizaburiak.github.io/land-use-footprint-brazilian-soy/paper/data_section/data.pdf) · [**Methods section**](https://lizaburiak.github.io/land-use-footprint-brazilian-soy/paper/methods_section/methods.pdf)

### Note for people interested in reproducing results:
The model requires a wide range of input data for all modelling steps. All data is publicly and freely available, but cannot directly be provided here for download due to different copyright licenses. Instead, see [`DATA.md`](DATA.md) for the full manifest — where every dataset comes from and where it must be placed — plus the `code/download_data.py` script that programmatically fetches the auto-downloadable inputs straight into the pipeline's input tree. 

----

> **Repository layout:** see [`STRUCTURE.md`](STRUCTURE.md) for the folder map — the
> year-parameterized model (`code/pipeline/`), its paper figures (`code/analysis/`) and
> prep feeders (`code/prep/`), the purpose-organized `data/` (raw/geo/fabio/trase/exiobase),
> and Stefan Trsek's original 2013 pipeline preserved under `archive/code_old_stefan/`.
>
> **Running it:** from the repo root, `bash code/run_all.sh` runs the full pipeline
> (steps 00–21) for all years 2000–2020 (or `bash code/run_all.sh 2013 2013` for one year).
> See [`RUNBOOK.md`](RUNBOOK.md) for setup, data prerequisites, and per-year caveats.

----

### Code structure:

 - Code files are numbered in chronological order:
   - 0-5 build the subnational data foundation
   - 7 models subnational transport flows (straight-line/Euclidean distances)
   - 8-11 connect flows to importing countries, assess model sensitivity and benchmark the "origin-to-importer" flows against trase and a pure downscaling
   - 12-19 nest the subnational supply chain flows into FABIO, adapting the existing [FABIO](https://github.com/fineprint-global/fabio) and [FABIO hybrid](https://github.com/fineprint-global/fabio-hybrid) code
   - 20-21 compute land-use footprints on the municipal level and refine them to the grid level (30m) using [MapBiomas](https://mapbiomas.org/) data. The soy land-use tiles are downloaded from Google Erath Engine, using an [adapted version](https://code.earthengine.google.com/969e903c53a0bf85db4f1e804a5c3b32) of the official MapBiomas [user toolkit](https://github.com/mapbiomas-brazil/user-toolkit).

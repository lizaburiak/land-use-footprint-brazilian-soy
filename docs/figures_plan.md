# Figures plan — "make them beautiful"

Working checklist for the SOYPRINT paper/website figures. Companion to
[`paper_plan.md`](paper_plan.md) §6 (which maps figures → paper claims). The science is
drafted; this doc is about **polish + a consistent house style**, and tracking each figure
from draft → final.

**Status legend:** ☐ todo · ◐ draft exists, needs polish · ☑ final.
**Metric note:** footprints are now clean for the full **2010–2022** (soybean-oil re-export
fix, 2026-06-23) — every figure should use the full series, not stop at 2015.

---

## House style (apply to ALL figures)

Goal: one coherent look across static (paper) and interactive (web) figures.

- **Region palette** (already in `code/plot_footprint_dynamics.py`):
  China `#C44536` · EU-27 `#197278` · Rest of Asia `#E9A03B` · Rest of world `#7D8CA3` ·
  Brazil (domestic) `#5B8C5A`.
- **End-use palette:** Animal products `#7F2704` · Soybeans/meal/oil `#D94801` ·
  Other food `#FD8D3C` · Non-food/industrial `#FDD0A2`.
- **Maps:** `inferno_r`, shared sqrt scale; light Carto base for interactive.
- Ink `#1A1A1A`, muted `#6B6B6B`, grid `#E3E3E3`; font DejaVu Sans; no top/right spines;
  y-grid only; legends frameless.
- **Two render targets per figure:** a **static** version (PNG+PDF, paper-ready) and, where it
  helps, an **interactive** version (Plotly HTML) for the website.

---

## The figures

### 1) By destination region  ◐
- **Shows:** Brazilian soy footprint split China / EU-27 / Rest of Asia / Rest of world /
  Brazil-domestic, over time (the "responsibility shifted to China" headline).
- **Data:** `results/figures/footprint_dynamics/csv/by_region.csv` (2010–2022).
- **Scripts:** `code/plot_footprint_dynamics.{R,py}` → `01_by_destination_region.png`.
- **Beautify TODO:**
  - ☐ stacked area → also a share-normalised (100%) variant; pick the cleaner one.
  - ☐ direct end-of-line labels instead of a legend; annotate China 28%→~45%.
  - ☐ consistent palette + Mt axis; mark the 2015→2016 join (data-source change).

### 2) By end-use  ◐  + probability maps (step 21)
- **Shows:** footprint by end-use bucket (animal products / soy commodity / other food /
  non-food) over time — tests "increasingly embodied in animal feed."
- **Data:** `results/figures/footprint_dynamics/csv/by_enduse.csv` (2010–2022).
- **Scripts:** `code/plot_footprint_dynamics.{R,py}` → `02_by_enduse.png`.
- **Probability maps (step 21):** `code/pipeline/21_probability_maps.R` → `{YEAR}_prob_map_*` —
  30 m grid maps of footprint origin by destination × end-use (food / nonfood / meat-dairy-eggs).
  - ⚠️ **Blocked / stale:** current `prob_map_*` are 2013-era (no year prefix); step 21 needs the
    **MapBiomas 30 m soy tiles** (`data/old/geo/mb_tiles/`, GEE download) + R pkgs
    `fasterize`/`gdalUtilities`/`rasterVis`. Must source tiles before re-running for 2010–2022.
- **Beautify TODO:**
  - ☐ enduse stacked area, house palette, end-of-line labels.
  - ☐ decide: do we need the 30 m prob maps for the paper, or is the municipal map (below) enough?
  - ☐ if yes → get MapBiomas tiles, re-run step 21 for key years (2010, 2022), restyle.

### 3) Top importers  ◐
- **Shows:** the largest individual destination countries and their trajectories.
- **Data:** `results/figures/footprint_dynamics/csv/by_country.csv` (2010–2022).
- **Scripts:** `code/plot_footprint_dynamics.{R,py}` → `03_top_importers*.png`,
  `05_importer_dumbbell.png` (2010 vs latest).
- **Beautify TODO:**
  - ☐ top-N lines OR a 2010-vs-2022 dumbbell (dumbbell likely cleaner for a paper).
  - ☐ flag/clean the post-fix country attribution (no more USA artefact).

### 4) Domestic vs imported (consumed-abroad)  ☐
- **Shows:** share of Brazil's soy land footprint consumed **domestically** vs **exported**
  (embodied in foreign consumption) over time — the telecoupling framing in one panel.
- **Data:** derive from `by_region.csv` (Brazil-domestic vs sum of the rest), 2010–2022.
- **Scripts:** new small script (reuse the dynamics palette).
- **Beautify TODO:**
  - ☐ two-series stacked/area or a single "% exported" line (domestic fell ~23%→~1%).
  - ☐ sanity-check the low domestic share in 2018 & 2022 before publishing (see paper_plan note).

### (bonus) Municipal origin maps  ◐  — already underway
- **Static:** `code/{prep_map_2010_2022.R, plot_map_2010_2022.py}` → `map_2010_2022.{png,pdf}`
  (5×2: Total/China/EU/Asia/RoW × 2010 vs 2022, shared scale).
- **Interactive:** `code/{prep_map_allyears.R, build_web_map.py}` → `web/footprint_map.html`,
  published at **https://lizaburiak.github.io/soyprint-footprint-map/** (WebGL/MapLibre).
- **Beautify TODO:** ☐ optional MapLibre GL JS rewrite (smoother); ☐ frontier (Amazon+MATOPIBA)
  overlay; ☐ end-use selector alongside the destination dropdown.

---

## Execution order (proposed)

1. Lock the **house style** in one shared Python module both static scripts import.
2. Polish **(1) destination region** + **(4) domestic vs imported** (same data, quick wins).
3. Polish **(3) top importers** (dumbbell).
4. Polish **(2) end-use**; decide on the step-21 prob maps (tile-dependent).
5. Finalize the **municipal maps** (static + web) and the frontier overlay.
6. Optional: bring (1)–(4) into the website as interactive tabs next to the map.

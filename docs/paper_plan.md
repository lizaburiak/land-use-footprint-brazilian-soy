# Paper plan — open, reproducible, multi-year subnational soy footprint

*Working strategy doc. Companion to [`literature_review.md`](literature_review.md). Aimed at the
Nature family; see §1 for honest target positioning.*

---

## 1. Target & positioning

**Aspiration: Nature family.** Honest read of fit:

| Tier | Journal | Fit | What it needs |
|---|---|---|---|
| Stretch | *Nature* / *Nature Sustainability* | hard — needs a *surprising* global-significance finding, not just a better method | a genuinely new empirical result about *where/whose* responsibility moved |
| **Primary realistic** | **Nature Food** | **strong** — soy/land/telecoupling is squarely in scope; open+reproducible+temporal is a clear novelty | full 2010–2020 footprint series + one clean empirical headline |
| Strong alt | *Nature Communications*, *PNAS* | good | same |
| Solid fallback | *Global Environmental Change*, *Environ. Res. Lett.* | very good | minimal extra |

**Strategy: build the Nature Food version; the flagship is a stretch upgrade if the empirical
finding turns out striking.** The method alone (open/reproducible) is *not* flagship material — the
**empirical story carried by the method** is what could lift it.

---

## 2. The one-sentence story

> *Using the first fully open, reproducible, municipality-to-consumer model of Brazil's soy land
> footprint, we trace a decade (2010–2020) of telecoupling and show that responsibility for the
> footprint shifted decisively toward China — a volume surge, not an intensity change — while the
> footprint's origin migrated toward Brazil's agricultural frontier (the Amazon and the Cerrado's
> MATOPIBA expansion zone), all without the proprietary data that locks up the current state of the art.*

**Two-part contribution:** (i) **substantive/empirical** — the moving geography of responsibility;
(ii) **methodological/infrastructure** — an open, validated, reproducible alternative to the
proprietary black box.

---

## 3. Narrative arc (what's new vs what's known)

1. *Known:* China dominates Brazil's soy footprint; the Amazon/Cerrado-MATOPIBA frontier is the
   active expansion zone; trade offshores deforestation (Escobar, Trase, Hoang & Kanemoto,
   Soterroni, Pendrill).
2. *Known but locked up:* the spatially explicit version of this exists only inside **Trase**
   (proprietary data, unpublished code) or as **single-year** academic snapshots.
3. **New (ours):** an **open, reproducible, subnational, continuous-time-series** rendering of the
   same system that (a) reproduces the proprietary benchmark, (b) resolves the *dynamics* nobody has
   shown openly, and (c) cleanly separates the **volume vs intensity** drivers of China's rise.

---

## 4. The claims and how we prove each

Legend: ✅ have it · 🔶 partial · ❌ needs work.

### Claim A (method) — "An open model reproduces the proprietary benchmark."
- **Evidence ✅:** our Euclidean model matches Trsek/Trase 2013 (pooled direct *r* 0.685 vs his
  0.692; downscale 0.694 vs 0.694) and holds across 2010–2020. Figure: `correlation_comparison.png`
  + `correlation_heatmap_years.png`.
- **Strength:** strong, done. This is the credibility foundation.

### Claim B (method) — "Subnational modeling beats downscaling *where it matters*, and we can say when."
- **Evidence ✅:** the volume–correlation analysis — subnational gains are largest for small/specific
  importers; a quantified volume floor (~1 kt) below which there is no spatial signal. Figure:
  `correlation_vs_volume.png`.
- **Strength:** clean, generalisable, novel framing. Good as a secondary contribution / decision rule.

### Claim C (empirical headline) — "Responsibility for Brazil's soy land footprint shifted to China, 2010–2020 — a volume effect, not an intensity effect."
- **Evidence 🔶:** China's share 28%→40% (2010–2015) ✅; per-tonne land intensity flat across
  destinations (EU/China within ±4%) ✅ → **the rise is volume, not intensity**. Figures:
  `01_by_destination_region`, `04_composition_share`, `footprint_intensity.png`.
- **Blocker ✅ FIXED 2026-06-23:** the series previously stopped at 2015 because FABIO attribution
  degenerated in **2016, 2021, 2022** (negative Brazil-domestic + inflated USA/foreign). **2017–2020
  were already clean.** Root cause was *not* the suspected soybean-2555 re-export singularity but an
  **off-by-one in step 12** for soybean **oil (2571)**: Brazil (area 21) leaking back into `cbs_ext`
  added a spurious row to the re-export merge (`all = TRUE`), recycling and corrupting the oil
  re-export → negative Brazil footprint downstream. Fixed (re-assert area-21 soy exclusion +
  `all.x = TRUE` + dimension guard). The decade **2010–2020 is now usable**; see §5.

### Claim D (empirical) — "The footprint's origin migrated toward Brazil's agricultural frontier (Amazon + Cerrado-MATOPIBA), and China's frontier exposure roughly doubled."
- **Evidence ✅ (prototyped, 2010–2015):** municipality→biome lookup (IBGE 1:250k biomes) applied to
  the per-municipality land-footprint origin. **Frontier = Amazon biome + MATOPIBA (Cerrado expansion
  zone in MA/TO/PI/BA), disjoint.** Frontier share of footprint origin rose for all destinations
  (19%→26%) and **roughly doubled for China (12%→23%)**, converging toward the EU's already-high
  level (27%→32%). Figures: `footprint_origin_biome.png` (frontier-share lines + China origin
  composition). Code: `footprint_origin_biome.R` + `plot_footprint_origin_biome.py`.
- **🔑 Refinement (important):** **Cerrado *as a whole* is flat** (~41% of China's origin, no trend) —
  the Cerrado lumps the established core with the frontier. The signal is specifically in the
  **frontier (Amazon + MATOPIBA)**, not "the Cerrado." Frame as "frontier," not "Cerrado," or the
  claim is wrong.
- **Needs 🔶:** (a) the 2016–2020 fix to extend past 2015; (b) swap the MATOPIBA proxy (Cerrado ∩
  MA/TO/PI/BA, 367 munis) for Embrapa's **official MATOPIBA delimitation**; (c) optional MapBiomas
  30 m refinement (step 21, tiles missing) — nice-to-have, *not* required.
- **⚠️ Framing guard:** this is a **land-footprint origin** shift, not a **deforestation** claim,
  unless we add a land-use-change stressor (§5). Say "footprint origin / soy-area frontier," not
  "deforestation," until then.

### Claim E (empirical, softer) — "The footprint is increasingly embodied in animal feed/livestock."
- **Evidence 🔶:** `02_by_enduse` shows the end-use split; literature says the feed-share trajectory
  is *not yet established* → genuine novelty if robust.
- **Needs:** the 2016–2020 fix; sanity-check the end-use attribution stability across years.

---

## 5. Critical path (data/infra blockers, in priority order)

1. **✅ DONE 2026-06-23 — FABIO attribution fixed (2016–2020, + 2021–2022).** The earlier
   `WHAT_IS_MISSING.md §3` diagnosis (soybean **2555** re-export going singular ≥2018) was wrong:
   2555 inverts exactly every year, and 2017–2020 were already clean. The actual bug was an
   **off-by-one in step 12** for soybean **oil (2571)** (broke 2016/2021/2022 only): Brazil
   (`area_code 21`) leaked back into `cbs_ext` after the BTD-harmonization `full_join`, but 21 is
   absent from `regions_code_soy` (the 5761-row re-export matrix dims), so `merge(..., all = TRUE)`
   appended a 5762nd row and the element-wise ops recycled, corrupting the entire oil re-export
   (`btd_final` BRA −2744 Mt) → garbage step-15 supply shares → −55 Mt step-16 `balancing` slack →
   negative Brazil footprint in step 20. **Fix:** re-assert the area-21 soy exclusion after
   harmonization, switch the per-commodity merge to `all.x = TRUE`, and add a
   `stopifnot(nrow(data)==nrow(mat))` guard. Verified: 2022 oil re-export now balances TRUE/TRUE,
   `btd_final` BRA oil = +8.88 Mt (≈ supply). Claims C/D/E can now run the full **2010–2020**
   (and 2021–2022, beyond the EXIOBASE-pxp horizon caveat).
2. **🟠 Add a land-use-change / deforestation stressor** (to upgrade Claim D from "land" to
   "deforestation"). Options: MapBiomas annual LUC, or a Trase/Pendrill deforestation-risk layer
   keyed to municipalities. Decide whether the paper is a **land-footprint** paper (safer, defensible
   now) or a **deforestation-footprint** paper (higher impact, more work + verification).
3. **🟡 Municipality→biome lookup** (Amazon / Cerrado / Atlantic Forest / MATOPIBA) — cheap, enables
   Claim D's "moving frontier" without MapBiomas tiles.
4. **🟢 (Optional) MapBiomas 30 m tiles** for grid-level refinement (step 21) — visual polish, not
   load-bearing.

**Temporal-scope honesty:** FABIO v2 core is **2010–2023**, so the *footprint* series cannot predate
2010 — frame it as **"a decade, 2010–2020,"** not "two decades." The origin→importer *flow*
benchmark does run 2004–2020 and can support a longer methods/validation backdrop.

---

## 6. Proposed main figures (Nature Food: ~4 main + extended data)

> Figure-by-figure polish/build tracker (house style, scripts, status): see
> [`figures_plan.md`](figures_plan.md).


1. **Fig 1 — The framework + validation.** Schematic (municipality→FABIO→consumer) *+* the
   reproduction-of-Trase panel (`correlation_heatmap_years` / `correlation_comparison`). "Open model,
   proprietary-grade accuracy."
2. **Fig 2 — Who consumes it, over time.** `01_by_destination_region` + `04_composition_share`
   (China 28%→40%) — the responsibility-shift headline.
3. **Fig 3 — Volume, not intensity.** `footprint_intensity` (flat per-tonne) + the volume–correlation
   panel (`correlation_vs_volume`) — the mechanistic + methodological double-hit.
4. **Fig 4 — Where it lands, over time.** The "moving frontier" municipal maps (Claim D) + the
   frontier-share (Amazon + MATOPIBA) trajectory by destination (`footprint_origin_biome.png`),
   showing China's frontier exposure ~doubling.
- **Extended Data:** end-use split (`02_by_enduse`), dumbbell (`05`), change-by-region (`06`), full
  per-country correlation tables, the worst-correlation/volume table.

---

## 7. Proposed structure

- **Abstract** — open reproducible model; reproduces Trase; decade of telecoupling; China = volume
  not intensity; footprint origin shifts to the agricultural frontier (Amazon + Cerrado-MATOPIBA),
  China's frontier exposure ~doubling.
- **Intro** — telecoupling, the coverage↔resolution↔openness trilemma, the proprietary-data problem.
- **Results** — (1) validation, (2) shifting responsibility, (3) volume-vs-intensity + the
  subnational-value rule, (4) moving frontier.
- **Discussion** — policy (EUDR, Soy Moratorium, Cerrado), what openness enables, limits.
- **Methods** — the open pipeline, FABIO nesting, benchmarking, data, code/data availability (the
  open-science selling point).

---

## 8. Risks & honest assessment

- **R1 (highest):** the 2016–2020 fix may be hard or reveal deeper FABIO post-2017 trade-data
  problems → fallback: a rigorous **2010–2015** paper (still novel, lower tier — GEC/ERL).
- **R2:** "deforestation" requires the LUC stressor; without it the land-footprint framing is less
  Nature-grabby. Decide early (§5.2).
- **R3:** novelty challenge — reviewers may say "Trase/Escobar already showed China + Cerrado." Our
  defense = **openness + reproducibility + continuous dynamics + the volume/intensity decomposition**,
  none of which exists together in the literature (see lit-review open questions).
- **R4:** the per-tonne-flat result is a *negative* result for the "EU worse" angle — but we turn it
  into a *positive* (clean volume-vs-intensity decomposition). Keep that framing tight.

---

## 9. Immediate next actions

1. ✅ **Done 2026-06-23 — FABIO 2016–2020 attribution fixed** (step 12 soybean-oil off-by-one;
   see §5.1). Remaining: re-run the footprint chain 13–20 for 2016/2021/2022 and regenerate the
   `plot_footprint_dynamics` CSVs (currently capped at 2015) across the full 2010–2020 series.
2. Decide **land-footprint vs deforestation-footprint** scope (drives whether we add the LUC stressor).
3. ✅ **Done (2010–2015):** municipality→biome lookup + frontier-share analysis (Claim D prototype,
   `footprint_origin_biome.*`). Remaining: swap MATOPIBA proxy → Embrapa official list; add the
   "moving frontier" municipal maps; extend to 2020 once R1 is fixed.
4. Lock Fig 1 (validation) — it's done and de-risks the methods claim.

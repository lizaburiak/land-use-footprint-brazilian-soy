# Literature review — Brazilian soy land footprint, China telecoupling, open footprint methods

*Compiled from a deep web-search + adversarial verification run (22 sources fetched, 104 claims
extracted, 25 fact-checked → 24 confirmed, 1 refuted). Citations are reconstructed from the
verified sources; **confirm exact author/year/venue against the DOI before submission** — a few
attributions are marked (?).*

Organised around the paper's three claim-threads. Each verified finding shows its
adversarial vote (e.g. 3-0 = all three checkers confirmed; 2-1 = one dissent).

---

## Thread 1 — China–Brazil soy telecoupling & the land-use/deforestation footprint (PRIMARY)

**Verified findings**

- **China holds the majority of the carbon embodied in Brazil's soy exports.** China accounted for
  **~51% of CO₂ emissions embodied in Brazilian soy exports (2010–2015)**; emissions are spatially
  concentrated in a few municipalities. — *Escobar et al. 2020, Global Environmental Change* 62,
  102067 (via SEI). [3-0] — **the single closest analogue to our study.**
- **China is the dominant destination and the "most-exposed" market** for Brazilian soy
  deforestation risk. — Trase / Escobar. [3-0]
- **The EU imports less volume but carries a higher footprint *per tonne* than China** (it sourced
  more from higher-deforestation regions). — [3-0]. ⚠️ This is a **carbon/deforestation-intensity**
  result, not a land-area one (see Caveats — our land footprint does *not* show this).
- **China (with developed countries) became a net "importer of deforestation"** — offshoring
  land-use impact through trade. — *Hoang & Kanemoto 2021, Nature Ecology & Evolution* 5, 845–853
  ("Mapping the deforestation footprint of nations"). [3-0]
- **By 2022 the Cerrado dominated soy-driven deforestation; Europe and China are the major
  importers of deforestation-risk soy.** — Trase. [3-0]
- **~20% of Brazil's soy exports (and ~17% of beef) to the EU were potentially contaminated by
  illegal deforestation**, concentrated in a minority of properties. — *Rajão et al. 2020, Science*
  369, 246–248 ("The rotten apples of Brazil's agribusiness"). [3-0]
- **Agriculture/forestry trade drives a large share of tropical deforestation emissions**, but
  **61–71% of soy-related emissions are domestic** (consumed within Brazil). — *Pendrill et al.
  2019, Global Environmental Change* 56, 1–10. [3-0]
- **Eliminating deforestation from a few supply chains / consumption-based deforestation risk
  differs sharply between importing countries.** [3-0]
- **29–39% of deforestation-related emissions were driven by [export demand]** (exact split
  source = Nature Communications 2022 (?)). [3-0]

## Thread 2 — Amazon Soy Moratorium & the Cerrado/MATOPIBA frontier shift

- **The Amazon Soy Moratorium (ASM) is associated with sharply lower direct soy-driven Amazon
  deforestation.** [3-0] ⚠️ The often-cited ASM effect size (Heilmayr et al.) is **within-Amazon
  only** — do not generalise it, because of Cerrado leakage.
- **Expanding the Soy Moratorium from the Amazon to the Cerrado would prevent large additional
  native-vegetation loss.** — *Soterroni et al. 2019, Science Advances* 5(7), eaav7336
  ("Expanding the Soy Moratorium to Brazil's Cerrado"). [3-0]
- **Future native-vegetation conversion to soy is concentrated in the Cerrado**, a global
  biodiversity hotspot under pressure. [3-0 / 2-1]
- **Within-Brazil (domestic) leakage offsets ~43–50%** of the moratorium's avoided-conversion
  effect. [3-0]

## Thread 3 — Open / reproducible footprint methods (context for the open-source claim)

- **FABIO** — open physical multi-regional input-output system, 130 agri-food products × 191
  countries. — *Bruckner et al. 2019, Environ. Sci. Technol.* 53(19), 11302–11312
  ("FABIO — The Construction of the Food and Agriculture Biomass Input–Output Model"). [primary]
- **Trase** — spatially explicit supply-chain mapping; methodology documented but **relies on
  proprietary customs/company (tax-registration) data and unpublished code** → not fully
  reproducible. — trase.earth/methodology. [primary]
- EE-MRIO reproducibility / open-research-software venues (e.g. *Journal of Open Research
  Software*; ACS *Environ. Sci. Technol.*) confirm openness/reproducibility is a recognised,
  valued gap in material-flow analysis. [primary]
- **Openness↔accuracy spectrum:** Trase = accurate but proprietary; FABIO/EXIOBASE = open MRIO;
  pure proportional downscaling = open but crude. Our model targets the open + subnational +
  FABIO-linked middle that is currently empty.

---

## ⚠️ Caveats (these prevent over-claiming — read before writing)

1. **Volume vs intensity.** China dominates by **volume/area**; the **EU has the higher footprint
   per tonne** (carbon). Our 28%→40% China figure is a *share-of-total* (volume/land) number — frame
   it as China's growing share of the *total* footprint, not as China having the most intense or
   damaging per-tonne footprint.
2. **Our land footprint does NOT reproduce "EU higher per tonne."** Per-tonne *land* intensity
   (ha/t = inverse yield) is ~flat across destinations (~0.33 ha/t; EU/China within ±4%). The
   literature's EU>China is a **carbon/deforestation** phenomenon driven by *where* soy is sourced
   (recently-deforested frontier), not by land area. To show it we'd need a deforestation/LUC
   stressor, not cropland area.
3. **Brazil domestic is the #1 Cerrado driver (~46%), ahead of China** — do not call China the top
   driver of Cerrado conversion.
4. **Most soy land use is domestic, not exported** (Pendrill: 61–71% domestic). Our domestic share
   (~15–23%) is consistent.
5. The "China imports grew ~6× since 2001" stat is reported **jointly for China+India** — attribute
   carefully.
6. **Refuted (excluded, 0-3):** the claim that cattle-associated deforestation risk is concentrated
   by biome with the Cerrado dominating cattle exports (48.1% Cerrado / 25.5% Amazon / 18.2%
   Atlantic Forest) — from *zu Ermgassen et al. 2020, PNAS* (a **beef** paper); the checkers found
   the figures did not hold up as stated. Do not cite for soy.

---

## Open questions the search could not close (→ our novelty)

- **No published *continuous multi-year subnational* series of importer-attributed Brazilian-soy
  footprints surfaced.** Existing work is single-year (Escobar 2010–2015 pooled), proprietary
  (Trase), or national-level (Hoang & Kanemoto, Pendrill).
- How much of the 2018 import surge is US-soy substitution (trade war) vs underlying feed growth — **not quantified** in the literature.
- How the **animal-feed end-use share** of the footprint evolves over time — **not established**.

## Bottom line for our framing

The genuine gap = **the first open, reproducible, subnational, multi-year, FABIO-linked footprint
trajectory** — showing *how consumption-based responsibility for Brazil's soy land footprint shifted
over time (toward China)* and *where the footprint sits within Brazil (toward the Cerrado frontier)*,
reproducibly and without proprietary data. Everyone else has a snapshot, a black box, or a national
average.

---

## Source list (URL · venue · quality)

| # | Source | Venue | Quality |
|---|---|---|---|
| 1 | sei.org/publications/carbon-footprints-brazil-soy + sciencedirect S0959378019308623 | Global Environmental Change (Escobar et al. 2020) | primary |
| 2 | trase.earth/insights/brazilian-soy-exports-and-deforestation | Trase | primary |
| 3 | science.org/doi/10.1126/sciadv.aav7336 | Science Advances (Soterroni et al. 2019) | primary |
| 4 | nature.com/articles/s41559-021-01417-z | Nature Ecology & Evolution (Hoang & Kanemoto 2021) | primary |
| 5 | news.mongabay.com/2020/06/china-and-eu-appetite-for-soy… | Mongabay (summary of Escobar) | secondary |
| 6 | nature.com/articles/s41467-022-33213-z | Nature Communications 2022 | primary |
| 7 | science.org/doi/10.1126/science.aba6646 | Science (Rajão et al. 2020) | primary |
| 8 | pnas.org/doi/10.1073/pnas.2003270117 | PNAS (zu Ermgassen et al. 2020 — beef; one claim refuted) | primary |
| 9 | sciencedirect S0959378018314365 | Global Environmental Change (Pendrill et al. 2019) | primary |
| 10 | nature.com/articles/s43016-020-00194-5 | Nature Food 2020 (ASM/Cerrado) | primary |
| 11 | iopscience 10.1088/1748-9326/aafb85 | Environ. Res. Lett. (ASM) | primary |
| 12 | pmc.ncbi.nlm.nih.gov/articles/PMC6636994 | (ASM, open access) | primary |
| 13 | pubs.acs.org/doi/10.1021/acs.est.9b03554 | Environ. Sci. Technol. | primary |
| 14 | trase.earth/methodology/supply-chains-methodology | Trase methodology | primary |
| 15 | openresearchsoftware.metajnl.com/articles/10.5334/jors.251 | J. Open Research Software | primary |
| 16 | iopscience 10.1088/2976-601X/ade71e | IOP (recent) | primary |
| 17 | fineprint.resource-use.global/publications/briefs/fabio | FABIO (Bruckner et al. 2019, ES&T) | primary |
| 18 | science.org/doi/10.1126/science.abj1572 | Science 2021 | primary |
| 19 | nature.com/articles/s43016-026-01311-6 | Nature Food | secondary |
| 20 | zenodo.org/records/5886600 | dataset | primary |
| 21 | nature.com/articles/s43016-021-00338-1 | Nature Food 2021 | primary |

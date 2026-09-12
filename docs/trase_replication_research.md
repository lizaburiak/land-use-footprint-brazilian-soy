# Reproducing Trase's numbers with open data: what it would take

Deep-research report, 2026-08-11. Question: what exactly would it take to
reproduce or approach Trase SEI-PCS Brazil soy v2.6.1's
municipality-to-importer flows with openly available data, given our open
pipeline reaches pooled municipality x destination r ~ 0.72 (2019) and
0.59-0.79 (2010-2022), with within-state crush location as the dominant
sensitivity (spread 0.073)?

Method: 5 search angles, 16 sources fetched, 69 claims extracted, top 25
adversarially verified (3 independent refutation votes each; all 25
survived, two at 2-1 with version caveats). 98 agents total.

## Headline

An exact reproduction is impossible: the backbone of every SEI-PCS version
is commercially purchased per-shipment customs declarations (2004-2018)
and bills of lading (2019-2022, maritime only), whose vendor is never
named in any Trase document. Each Brazilian customs record carries the
exporter's municipal tax location; that field is what anchors flows to
municipalities. Everything else in Trase's pipeline is open or
reconstructible. Critically, on per-plant crushing capacity Trase has the
same data gap we do, and Trase publishes no municipality-level accuracy
metric of its own, so "their numbers" are a softer target than they look.

## 1. Trase's inputs and their status (v2.6, verified verbatim)

| Input | Status | Where |
|---|---|---|
| Per-shipment customs (2004-18) / bills of lading (2019-22) | Proprietary, vendor unnamed ("Various sources" in v2.3) | purchased from trade-intelligence vendors |
| CNPJ/CNAE tax registry (decision tree: municipality of taxation + activity codes) | Public bulk data | Receita Federal open CNPJ dumps (dadosabertos.rfb.gov.br/CNPJ/) |
| CONAB SICARM silo registry incl. capacities | Public | conab.gov.br / sisdep.conab.gov.br |
| MAPA SICASQ/CGC export-permitted storage facilities | Public | gov.br/agricultura; drives decision-tree branches 3.3.1-3.3.3 |
| SIDRA-IBGE municipal soybean production | Public | sidra.ibge.gov.br |
| IBGE 2017 municipal boundaries (5,570) | Public | ibge.gov.br |
| Comex Stat (LP constraint 2019-22 + Trase's own QA) | Public | MDIC |
| OSRM/OSM travel-time matrix (osrmtime, 2015-2019 average) | Public; Trase publishes the matrix for download | v2.6 methods doc link |
| ABIOVE plant locations/ownership + JJ Hinrichsen market research | Partially public / proprietary yearbook | abiove.org.br/estatisticas, jotajota.com.ar |

## 2. Per-plant crushing capacity (our weakest input): no public source exists, and Trase has none either

- Exhaustive check of the v2.6 methods PDF: "capacit" appears only for
  SICARM silo capacity and for "crushing capacity" as a modelling
  construct; no per-plant crushing capacity dataset is cited anywhere.
- ABIOVE gives Trase only location and ownership, "completed with market
  research published by JJ Hinrichsen" (commercial subscription).
- v2.5.0 verbatim: capacities "were estimated from a variety of sources".
- In the LP, Trase equates municipal soybean consumption to crushing
  capacity as a constraint.
- ABIOVE's own Capacidade Instalada survey publishes state totals and
  plant-size classes only, i.e. exactly what we already use.

Implication for the paper: our dominant sensitivity axis reflects a data
gap of the field, not a deficiency relative to the benchmark.

## 3. The ceiling Trase's own numbers represent

- Only self-validation published: national totals vs Comex Stat (Table 5).
  2004-2018 within 0.1-2.4 Mt; maritime-only years diverge (2019: 84.2 vs
  92.3; 2020: 97.9 vs 101.6; 2022: 93.7 vs 102.4 Mt).
- Unknown-origin exports: 4-10 Mt/yr 2004-2017, 18 Mt 2018, 14-22 Mt
  2019-2022 (~23% of 2022 exports). The 2018 manual reports 10-15% of
  volumes unlinkable to a hub (cake and oil over-represented); v2.5.0
  reports 7.5-21.3% by year; zu Ermgassen et al. 2020 report 6.7-9.9%
  post-2014 for v2.4.
- No municipality-level accuracy metric is published; the
  hub-to-municipality LP is validated only informally by trader feedback.
- 2019-2022 is structurally weaker: maritime-only source, country of
  FIRST IMPORT rather than destination (Singapore/Hong Kong vs mainland
  China), non-maritime tonnage labelled Unknown (2.6/0.8/0.5/0.4 Mt for
  2019/20/21/22), and Trase explicitly recommends against cross-period
  comparisons. Part of our 0.59-0.79 year band is Trase's source change,
  not our pipeline; r ~ 0.72 in 2019 may be near the practical ceiling.

## 4. Ranked actions (impact x open-pipeline feasibility)

1. Replicate the CNPJ/CNAE trader decision tree from the free Receita
   Federal bulk registry (municipality of taxation + CNAE activity codes
   are published fields). Highest impact; fully open. Missing piece:
   shipment-to-exporter identity (Comex Stat municipal files carry no
   CNPJs), which must be approximated.
2. Add SICARM silo capacities and SICASQ export permissions as
   allocation constraints. Open; moderate impact.
3. Constrain the allocation with Comex Stat port x state x country
   volumes and adopt sticky supply sheds (dos Reis et al. 2020; Trase
   itself uses 2015-2017 stickiness for 2019-2022). Open; moderate.
4. Purchase the JJ Hinrichsen yearbook to close the capacity gap.
   Breaks full openness; marginal gain may be limited since Trase's own
   capacity basis is similar.
5. Reframe 2019-2022 validation: accept the lower ceiling or weight the
   headline comparison toward 2010-2018.

Caveat on the main open substitute: Comex Stat's municipal field is the
exporter's FISCAL DOMICILE, monthly SH4 aggregates only (coarser than the
NCM-8 national files); MDIC's own manual warns the exporter is not always
the producer and statistics concentrate in port/HQ municipalities. That is
precisely the bias Trase's shipment data corrects.

## Open questions / leads

- No documented open-data-only replication of Trase-like
  municipality-to-country flows was found (zu Ermgassen, Lathuilliere,
  dos Reis, Escobar searched). Our pipeline may be the first; that is
  itself a claim for the paper.
- Does JJ Hinrichsen list per-plant Brazilian capacities (it does for
  Paraguay in Trase's v2.3 source list)? Cost and license terms unknown.
- State environmental licensing records (SEMA/IMA operating licenses) and
  ANTAQ per-terminal cargo statistics as open capacity proxies:
  unexplored.
- Trase press release "AI maps 9,300 Brazilian soy facilities" (2025-era,
  trase.earth/media/press-release/ai-maps-9-300-brazilian-soy-facilities-
  unlocking-supply-chain-traceability): potentially a new open facility
  layer postdating v2.6; not covered by the verified claims.
- What is the maximum r attainable in principle for 2019-2022 given
  Trase's own unknown-origin and country-of-first-import error budget?

## Key sources

- SEI-PCS Brazil soy v2.6 methods (Jan 2025 revision), DOI
  10.48650/X24R-YK29:
  https://resources.trase.earth/documents/data_methods/SEI_PCS_Brazil_soy_2.6_External_January%202025%20Revision.pdf
- SEI-PCS Brazil soy v2.5.0 methods (June 2020):
  http://resources.trase.earth/documents/data_methods/Brazil-soy-v2.5.0%20June%202020.pdf
- Trase supply chain mapping manual (Dec 2018):
  http://resources.trase.earth/documents/Trase_supply_chain_mapping_manual.pdf
- Trase data sources release (May 2019):
  http://resources.trase.earth/documents/Trase-data-sources_release_may_2019.pdf
- zu Ermgassen et al. 2020, ERL 15 035003:
  https://iopscience.iop.org/article/10.1088/1748-9326/ab6497
- MDIC Comex Stat raw data page:
  https://www.gov.br/mdic/pt-br/assuntos/comercio-exterior/estatisticas/base-de-dados-bruta
- Comex Stat manual: https://balanca.economia.gov.br/balanca/manual/Manual.pdf

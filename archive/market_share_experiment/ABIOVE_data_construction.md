# ABIOVE municipal-level capacity data — origin & construction

This is a reference note on **where the municipal-level processing / refining / bottling
capacity numbers actually come from** in the soyprint pipeline. The short version:
the *state-level* numbers are published by ABIOVE; the *municipal* numbers are
**not** a direct ABIOVE release — they are produced inside this project by
distributing state capacity across the plants ABIOVE lists in each state.

## What ABIOVE publishes

ABIOVE (Associação Brasileira das Indústrias de Óleos Vegetais) runs an annual
survey *Pesquisa de Capacidade Instalada da Indústria de Óleos Vegetais*. Each
yearly workbook contains:

| Sheet (2013 file) | What it has | Granularity |
|---|---|---|
| `1. resumo` | Capacity totals per state for Processamento / Refino / Envase (t/day) | **State** |
| `2. evolução` | Same totals as time series, 1998–2013 | State × year |
| `3. geralproces` | List of surveyed crushing plants: company, municipality, UF, extraction process, oilseed type, status (Ativa/Parada) | Plant location, **no individual capacity** |
| `4. estratific` | National plant-count by capacity stratum (≤599, 600–1499, 1500–2999, ≥3000 t/day). Mentions 330 days/year operating assumption | National |
| `5. estadoproces` | Per-state capacity split into Fábricas Ativas / Inativas | State |
| `6. empreproces` | List of surveyed companies | Company |
| `7. geralrefin` | Refining plant list (analogous to sheet 3) | Plant location, no capacity |
| `8. estadorefin` | Per-state refining + bottling capacity, active/inactive | State |
| `9. empresasrefin` | Refining companies list | Company |

Source footer on every published sheet:
`FONTE/ELABORAÇÃO: ABIOVE — COORDENADORIA DE ECONOMIA E ESTATÍSTICA`

**ABIOVE does NOT publish capacity for individual plants.** Plant-level capacity
is commercially confidential. The published plant list gives names and locations
only, not t/day per row.

## How the municipal numbers are constructed

The municipal-level capacity is built by **equal-per-state allocation** (the
"Trsek-style allocation"):

```
per_plant_cap[s, y] = state_cap[s, y] / n_active_soy_plants[s, y]
mun_cap[m, y]       = sum over plants p in mun m of per_plant_cap[state(p), y]
```

Procedure:

1. Take ABIOVE's plant list (sheet 3 / 7) for the target year.
2. Filter to **active plants** with soy as oilseed (`Situação == "Ativa"`,
   `Oleaginosas == "Soja"` or new-format `Soja == "x"`).
3. Look up the state-level capacity for that year (sheet 2 `Evolução`,
   restricted to the Processamento block — there's a real bug risk of
   summing Processamento + Refino + Envase together if you don't slice it).
4. Count plants per state, divide state capacity by that count.
5. Assign the same per-plant capacity to every plant in the state.
6. Map `Localização da Unidade` → IBGE `co_mun` by uppercased name + UF match,
   with a small manual name-fix table for spelling mismatches between ABIOVE
   and IBGE.
7. Aggregate plant rows to the municipality.

### Fingerprint in the data

If you open `input_data/Processing_facilities_2013_ABIOVE.xlsx` →
`facilities_proc`, the allocation is visible:

- All active MT plants → 2282.4 t/day
- All active PR plants → 1609.285714…
- All active RS plants → 1280.909090…
- All inactive MT plants → 1500
- Single-plant states match the state total exactly:
  CE 100 → Cocentral Fortaleza 100; RO 300 → Portal Vilhena 300; PE 400 → Nossa Soja Petrolina 400.

## What this means for downstream use

- **Plant location** (which municipality has a crusher) is real ABIOVE data.
- **Per-plant capacity** is an estimate. If two ADM plants are in different
  municipalities of the same state, the model assumes they have identical
  capacity. A state like PR with seven active plants gets its total smeared
  evenly across them.
- A second estimate is layered on top in `01_consumption_and_processing.R`:
  ```
  proc_days  = CBS_SOY["bean","processing"] / sum(proc_cap)
  proc_bean  = proc_cap × proc_days
  prod_oil   = proc_bean × oil_conv
  prod_cake  = proc_bean × cake_conv
  ```
  This forces the sum of municipal annual crush to equal FAO national crush,
  which means **every plant is assumed to run the same number of days per
  year**. Combined with the state allocation, the final `proc_bean[m]` is:
  ```
  proc_bean[m] = (n_active_plants[m, state(m)] / n_active_plants[state(m)])
                 × state_cap[state(m)] × proc_days
  ```

## ABIOVE versus Trase

Trase publishes municipality-of-production → trader → port → importing country
flows, plus trader-municipality sourcing shares. Trase does **not** publish
crushing or refining plant capacities. For municipal-level facility capacities
in Brazil, ABIOVE (crushing, refining, bottling) and ANP (biodiesel) remain the
primary public sources, and the per-plant capacity has to be estimated as above.

## Files in this project

- `input_data/Processing_facilities_2013_ABIOVE.xlsx` — the 2013 workbook used
  by Stefan's original 2013-only pipeline. Includes pre-computed
  `facilities_proc` / `facilities_ref` / `processing_MUN` /
  `refining_bottling_MUN` sheets where the allocation was done in Excel.
- `inputs/00/new/ABIOVE_processing/` — the multi-year inputs used by the new
  pipeline:
  - `ABIOVE_raw_capacity_2025.xlsx` — multi-year state-level capacity
    (sheet `2.Evolução`), and 2024/2025 plant rosters.
  - `ABIOVE_raw_capacity_2023.xlsx` — 2023 / 2022 / 2020 rosters.
  - `pesquisa_capacidade_YYYY_PT.xls(x)` — annual ABIOVE workbooks
    2003–2022 (file schema changes across "early" / "mid" / "new" eras).

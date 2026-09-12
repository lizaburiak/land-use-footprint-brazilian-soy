# Two points for discussion

Prepared from the SOYPRINT footprint pipeline. Point 1 is a **modelling choice**
(ours); point 2 is a **data characteristic** of the FABIO v2 input.

---

## 1. What is `supply_side`? (modelling choice)

**The question.** When the national soy commodity balance is downscaled to
municipalities, how should a year with a **net national stock *withdrawal***
(soy drawn *out* of storage) be handled?

**`supply_side` (now the pipeline default).** A drawdown is treated as a
**source of supply**, following the standard commodity-balance identity:

```
production + imports + stock_withdrawal  =  exports + food + feed + seed + processing + other
```

`|withdrawal|` is added to municipal **supply** (distributed by storage
capacity); the use side is just the ordinary, non-negative use items.

**The alternative it replaced (`use_prop`).** Kept the withdrawal as a *negative
use* term (reallocated by use share) — a device to preserve non-negativity, but
it contradicts the balance identity.

**Why `supply_side` is the better choice**

1. It *is* the commodity-balance identity (and the paper's Methods Eq. 2 already
   writes it this way).
2. It is consistent with **FABIO's own** stock treatment — and we *nest into*
   FABIO, so the municipal block should follow the same convention.
3. It keeps municipal use **non-negative by construction**, which the re-export
   Leontief inversion requires.
4. It is physically consistent: the consumption footprint stays *within* Brazil's
   harvested-area envelope. Under `use_prop`, drawdown years pushed the food
   footprint *above* the physical soy area (impossible).

**Honest caveat.** Single-year static model: tonnes drawn from stock were grown
in *earlier* years but inherit the *current* year's land intensity — a proxy;
a proper multi-year stock account would be needed to do otherwise. Affects only
the small share of throughput met from net stock changes. (Stated in Methods.)

---

## 2. Extreme coefficients / near-zero outputs in the FABIO v2 data (data characteristic)

**What we observed.** The FABIO Leontief inverse `L = (I − A)^-1` came out with
large **negative** entries in some years (2020: 55,331 negatives, min −163),
which produced **negative land footprints** for a few consumers — most visibly
the **Philippines 2020** (net −0.18 Mha). 2014–2019 inverses were clean.

**What's required.** For the model to solve, the Leontief inverse `L = (I−A)^-1`
must exist and be **non-negative**, which needs the economy to be *productive*
(spectral radius `ρ(A) < 1`), `A = Z·diag(x)^-1`.

**Not every `use > output` is an error.** In a **mass** table a process can
legitimately consume more mass than it outputs:
- crushing: ~5 t soybeans → ~1 t oil (+ cake) → `colSum(A) ≈ 5`
- slaughter: ~16 t live pigs → ~11 t pigmeat → `colSum(A) ≈ 1.5`

So the ~3,600 columns per year with `colSum(A) > 1` are **mostly legitimate**
processing/livestock — they are *not* the problem by themselves.

**What is not physical — near-zero output.** A small set of cells have an
**extreme** ratio (≥ 100, up to millions) driven by a **near-zero recorded
gross output** despite very large inputs. There are **511 such cells across
2010–2023** (114 unique region × commodity), ~26–46 per year:

| year | cols use>output | EXTREME (ratio ≥ 100) | max ratio |
|---|---|---|---|
| 2015 | 3620 | 37 | 1,610,024 |
| 2019 | 3602 | 35 | 2,710,420 |
| 2020 | 3588 | 37 | 1,253,456 |
| 2022 | 3615 | 42 | 404,323 |
| … | ~3,600 | 26–46 | 0.3–2.7 M |

Worst offenders — note the near-zero **output** vs millions of tonnes of input:

| year | region | commodity | output (t) | intermediate use (t) | ratio |
|---|---|---|---|---|---|
| 2019 | SDN | Sugar (Raw Eq.) | 2 | 5,420,840 | 2.7 M× |
| 2015 | JPN | Pigmeat | 10 | 16,100,238 | 1.6 M× |
| 2021 | MLI | Mutton & Goat Meat | 1 | 1,362,655 | 1.4 M× |
| 2020 | BEN | Mutton & Goat Meat | 2 | 1,981,184 | 1.0 M× |
| 2020 | TCD | Bovine Meat | 5 | 3,279,418 | 0.66 M× |

Japan pigmeat consumes ~16 Mt of *live pigs* (order-plausible for a slaughter
flow) but records ~10 t of pigmeat **output** — which should be *millions* of
tonnes. That near-zero output makes the coefficient ~1.6 million×, which is what
can push `ρ(A)` past 1.

**How it surfaced.** In our footprint runs the Leontief inverse acquired large
**negative** entries for **2012, 2020, 2021, 2022** (2020: 55,331 negatives),
producing negative land footprints (Philippines 2020). 2014–2019 inverted
cleanly. A valid physical MRIO inverse should never be negative.

**What we did (a patch, not a cure).** A productiveness safeguard in the
inversion caps any column with `colSum(A) ≥ 1` to just below 1 before inverting
(no-op for already-productive years). It removes the negatives, but it is
downstream regularisation — the clean fix is in the FABIO data / build.

**Questions for you (the data owner):**
1. Why is the gross output (`x`) near-zero for these high-throughput processes
   (Japan pigmeat 10 t, Sudan sugar 2 t)? Data error, or is the output booked to
   another commodity / flow?
2. How is the inverse meant to stay productive (`ρ(A) < 1`) given these cells —
   import supply in the trade block, a balancing / value-added adjustment, or
   commodity exclusion?
3. Are the recent vintages (2020–2023) as balanced as 2010–2019, or provisional?

**Reproduce / check on your data (self-contained, no pipeline rebuild):**

```bash
Rscript code/analysis/check_fabio_data_errors.R  [path/to/fabio/v2]
# default path: data/fabio/v2 ; reads only X.rds, Z_mass_b.rds, inst/items_full.csv
```

It prints the per-year counts (columns with use>output, and the EXTREME subset)
and the worst offenders, and writes the full list of the **511 extreme cells** to
`results/fabio_data_check/fabio_extreme_coefficients.csv`
(year, region, commodity, output_t, intermediate_use_t, use_over_output),
sorted worst-first — so each can be checked against source.

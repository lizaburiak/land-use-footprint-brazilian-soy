# Methods ↔ code reader (`paper/methods_code_map.html`)

A single self-contained HTML file that puts the rendered Methods section next to the
pipeline code that implements it. Open it directly from disk — no server, no network
needed for the content (KaTeX and highlight.js are pulled from cdnjs; offline the page
still works, equations just fall back to raw TeX and code loses syntax colour).

```
open paper/methods_code_map.html
```

## What it does

- **Left:** `paper/methods_section/methods.tex` rendered — prose, headings, numbered
  equations, tables, figure captions. Every sentence is individually clickable.
  TikZ figures are replaced by a placeholder box; their captions are kept and are
  clickable, because the captions carry real methodological content.
- **Right:** the mapped source excerpt, with **true file line numbers** in the gutter,
  the mapped range highlighted, and a one-line note saying what in those lines
  corresponds to the sentence.
- **Sentences with a green underline are mapped. Muted sentences are not** — the gaps
  are the point. `Focus mapped` fades the unmapped ones so the covered spine stands out;
  reading the muted ones alone tells you which claims currently have no code behind them.
- Keyboard: `↑` / `↓` step through sentences, `Home` / `End` jump to the ends.
  The subsection dropdown navigates; the ◐ button toggles light/dark (it follows the OS
  preference on load).

## Coverage

145 of 203 clickable units are mapped (71%). The 58 unmapped ones are all deliberate and
each carries a recorded reason, shown in the right pane when you click them:

| reason | n | meaning |
|---|---|---|
| pointer | 21 | cross-reference to another section, figure or table |
| framing | 16 | roadmap / motivation with no computation behind it |
| interpret | 9 | interpretation of a result rather than a step |
| notation | 4 | notation or definition only |
| todo | 3 | an unresolved `\textcolor{red}{...}` TODO in the manuscript |
| result | 3 | a reported number, produced by a run rather than by a line of code |
| **gap** | **2** | **a claim with no implementation found in the repository** |

The two `gap` sentences are the EU origin-exclusion counterfactual in
§9.4 Uncertainty and sensitivity (the "perfect Amazon Soy Moratorium" run and the
0.9 Mha / 28.8% → 16% numbers). Nothing in `code/` performs that counterfactual, so it
is currently a Methods claim without a script.

## Two mismatches the mapping flags

Notes beginning with `CHECK:` are rendered in the warning colour. There are two:

- **`s161`** — the footnote "EXIOBASE inventory changes are treated analogously" points at
  `code/pipeline/20_footrpints.R:118-119`, where the comment says the EXIOBASE
  *Changes in inventories* category is **left untouched**. Text and code disagree.
- **`s170`** — "Trase flows with unknown municipality of origin are excluded"
  (`code/pipeline/10_create_benchmarks.R:187-196`): the code recodes them to `9999999`
  and **retains** them, and `11_analyse_benchmarks.R:171-177` explicitly adds a `9999999`
  row to every spatial-weight matrix.

Two further notes are worth reading rather than trusting: `s148` (the "municipal soy
processes are never affected" claim is not asserted anywhere in code) and `s149`
(`prod_cap` is a plain default argument; no driver varies it, and the sensitivity run is
still flagged as deferred in `methods.tex`).

## Extending the mapping by hand

Near the top of the `<script>` block there is one clearly-marked object:

```js
const MAPPING = {
  "s024": { file: "code/pipeline/01_consumption_and_processing.R", lines: [41, 68],
            note: "proc_days = national crush / total capacity; ..." },
  ...
};
```

Sentence ids are stable and run in document order, `s001` … `s203`. The id of whatever
you have selected is shown as a green chip in the right-hand header, so: click the
sentence, read the id, add or edit its entry.

One caveat: the embedded excerpts are the mapped range **±15 lines**, with overlapping
windows merged — they are not whole files. If you point a sentence at a range that falls
outside every embedded window for that file, the pane will say `excerpt missing`. Move the
range inside an existing window, or ask for a rebuild with the wider excerpt.

Sentence ids are positional. If `methods.tex` changes such that sentences are added or
removed, the ids shift and the mapping has to be rebuilt rather than patched.

## How the ranges were chosen

Every range was read in the actual file before being recorded — the subsection-level
`% Pipeline step NN` comments under each `\subsection` were only the starting point.
Where a sentence states a formula, a weight, a threshold, a fallback rule or a
conservation check, the range points at the lines that implement it; where a sentence is
framing, it is left unmapped rather than pointed at the whole file. Correctness was
preferred to coverage throughout.

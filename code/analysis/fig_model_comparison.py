#!/usr/bin/env python3
# ============================================================================
# Paper figure: the three allocation variants against the Trase benchmark.
# (a) pooled municipality x destination correlation per year, 2010-2022
#     (multimode has no 2021 solve: LP infeasible, line gap);
# (b) mean per-destination direct Pearson r by import-volume quartile.
#
# Reads : results/tables/benchmarks/multimode_vs_euclid_panel_2010-2022.csv
#         results/tables/benchmarks/<year>/pearson_by_dest.csv
# Writes: results/figures/paper/fig_model_comparison.{png,pdf}
# ============================================================================
import re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from figstyle import ROOT, PAPER, INK, MUTED, GRID, style_axes

MODEL = {"euclid": ("Euclidean (reported)", "#2E7D88"),
         "multimode": ("Multimodal", "#B5485B"),
         "downscale": ("Downscale", "#A9B4C2")}

# ---- panel a: pooled r per year --------------------------------------------
panel = pd.read_csv(ROOT / "results/tables/benchmarks/multimode_vs_euclid_panel_2010-2022.csv")
panel = panel[panel.weighting == "base"].set_index("year")
panel.loc[2021, "pearson_multimode"] = np.nan  # no 2021 solve (LP infeasible)

# ---- panel b: per-destination r by volume quartile --------------------------
def unstar(s):
    if pd.isna(s) or str(s).strip() in ("-", ""):
        return np.nan
    m = re.match(r"\s*(-?\d*\.?\d+)", str(s))
    return float(m.group(1)) if m else np.nan

rows = []
for y in range(2010, 2023):
    d = pd.read_csv(ROOT / f"results/tables/benchmarks/{y}/pearson_by_dest.csv")
    for _, r in d.iterrows():
        if r["to_code"] in ("-", "ROW", "Total"):
            continue
        rows.append(dict(year=y, mt=r["exports_trase"],
                         multimode=np.nan if y == 2021 else unstar(r["base.multimode"]),
                         euclid=unstar(r["base.euclid"]),
                         downscale=unstar(r["base.downscale"])))
dest = pd.DataFrame(rows)
dest = dest[dest.mt > 0].copy()
dest["q"] = pd.qcut(dest.mt, 4, labels=["Q1\nsmallest", "Q2", "Q3", "Q4\nlargest"])
qm = dest.groupby("q", observed=True)[["euclid", "multimode", "downscale"]].mean()

# ---- plot -------------------------------------------------------------------
fig, (axA, axB) = plt.subplots(1, 2, figsize=(11.5, 4.4),
                               gridspec_kw={"width_ratios": [1.35, 1]})

for key in ("downscale", "euclid", "multimode"):
    lab, col = MODEL[key]
    axA.plot(panel.index, panel[f"pearson_{key}"], color=col, lw=2.2,
             marker="o", ms=4.5, label=lab)
axA.set_xlabel("Year")
axA.set_ylabel("Pooled correlation with Trase")
axA.set_title("a   Pooled agreement per year", loc="left", fontsize=12)
axA.set_xticks(range(2010, 2023, 2))
axA.set_ylim(0.5, 0.9)
axA.legend(loc="upper right", fontsize=9)
style_axes(axA)

x = np.arange(len(qm))
w = 0.27
for k, key in enumerate(("downscale", "euclid", "multimode")):
    lab, col = MODEL[key]
    axB.bar(x + (k - 1) * w, qm[key], w, color=col, label=lab)
axB.set_xticks(x)
axB.set_xticklabels(qm.index)
axB.set_ylabel("Mean per-destination correlation")
axB.set_title("b   Agreement by destination volume", loc="left", fontsize=12)
axB.set_ylim(0, 0.62)
style_axes(axB)

fig.tight_layout()
for ext in ("png", "pdf"):
    fig.savefig(PAPER / f"fig_model_comparison.{ext}")
print("quartile means:\n", qm.round(2))
print("wrote", PAPER / "fig_model_comparison.pdf")

#!/usr/bin/env python3
# ============================================================================
# Paper figure: input-assumption sensitivity of the model-Trase correlation.
# One dot per perturbed re-run of the 2019 flow reconstruction (Euclidean
# model, pooled municipality x destination correlation, base weighting),
# grouped in rows by assumption; vertical line = baseline run.
#
# Reads : results/sensitivity/inputs_<year>/tidy_correlations.csv
# Writes: results/figures/paper/fig_sens_inputs.{png,pdf}
# ============================================================================
import sys
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from figstyle import ROOT, INK, MUTED, GRID, save

YEAR = int(sys.argv[1]) if len(sys.argv) > 1 else 2019

tidy = pd.read_csv(ROOT / f"results/sensitivity/inputs_{YEAR}/tidy_correlations.csv")
tidy = tidy[tidy.weighting == "base"]
base_r = float(tidy.loc[tidy.variant == "base", "euclid"].iloc[0])
tidy = tidy[tidy.variant != "base"]

ROWS = [  # top -> bottom: (assumption key, row label, colour)
    ("1_crush_split", "Crush location\n(within-state split)", "#2E7D88"),
    ("1_crush_gamma", "Crush location\n(allocation sharpness $\\gamma$)", "#2E7D88"),
    ("2_feed_rate",   "Feed rates\n(per-system jitter)", "#E0A458"),
    ("2_feed_shares", "Herd composition\n(state-average shares)", "#E0A458"),
]

fig, ax = plt.subplots(figsize=(7.6, 3.2))
rng = np.random.default_rng(1)

for i, (key, label, col) in enumerate(ROWS):
    y0 = len(ROWS) - 1 - i
    sub = tidy[tidy.assumption == key]
    jit = rng.uniform(-0.13, 0.13, len(sub)) if len(sub) > 2 else np.zeros(len(sub))
    ax.scatter(sub.euclid, y0 + jit, s=42, color=col, alpha=0.85,
               edgecolors="white", linewidths=0.6, zorder=3)
    # the one named (non-random) crush split gets its own marker
    if key == "1_crush_split":
        prod = sub[sub.variant == "crush_prod"]
        ax.scatter(prod.euclid, [y0], s=58, facecolors="white", edgecolors=col,
                   linewidths=1.6, marker="D", zorder=4)
        ax.annotate("production-\nproportional", xy=(float(prod.euclid.iloc[0]), y0),
                    xytext=(0, 14), textcoords="offset points", ha="center",
                    fontsize=8, color=MUTED)
    if key == "1_crush_gamma":
        for _, r in sub.iterrows():
            g = r.variant.split("_")[1]
            ax.annotate(f"$\\gamma$={g}", xy=(r.euclid, y0), xytext=(0, 9),
                        textcoords="offset points", ha="center", fontsize=8, color=MUTED)

ax.axvline(base_r, color=INK, lw=1.1, ls=(0, (4, 3)), zorder=2)
ax.annotate(f"baseline $r$ = {base_r:.3f}", xy=(base_r, len(ROWS) - 0.42),
            xytext=(5, 0), textcoords="offset points", fontsize=9, color=INK)

ax.set_yticks(range(len(ROWS)))
ax.set_yticklabels([r[1] for r in ROWS[::-1]], fontsize=9.5)
ax.set_xlabel("Pooled correlation with Trase (Euclidean model)")
ax.set_ylim(-0.55, len(ROWS) - 0.25)
ax.grid(axis="x", color=GRID, linewidth=0.8)
ax.grid(axis="y", visible=False)
ax.tick_params(axis="y", length=0)

fig.tight_layout()
save(fig, "fig_sens_inputs")

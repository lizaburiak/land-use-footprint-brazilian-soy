#!/usr/bin/env python3
# ============================================================================
# ROCKET PLOT (PIOLab style, cf. Wieland et al.) - modeled vs reported flows.
# Every municipality x destination x year soy export flow: our Euclidean
# model (y) against Trase (x), both log10 tonnes. Big flows converge onto the
# 1:1 diagonal (the rocket's nose), small flows scatter (the plume) - i.e.
# agreement grows with volume. Density contours + 1:1 dashed line.
#
# Reads : results/plots_2001_2022/csv/rocket_pairs.csv (from prep_rocket_pairs.R)
# Writes: $ROCKET_OUT/rocket_plot.{png,pdf}   (default results/plots_2001_2022)
# ============================================================================
from pathlib import Path
import os
import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[2]  # scripts live in code/analysis/
CSV  = Path(os.environ.get("ROCKET_CSV") or ROOT / "results/plots_2001_2022/csv/rocket_pairs.csv")
OUT  = Path(os.environ.get("ROCKET_OUT") or ROOT / "results/plots_2001_2022")
OUT.mkdir(parents=True, exist_ok=True)

EU, GRID = "#197278", "#E3E3E3"

df = pd.read_csv(CSV)
# flows under 1 t are numerical dust (model spreads grams across many cells)
# and Trase's smallest reported flows are ~30 t - restrict to >= 1 t per side.
both = df[(df.trase >= 1) & (df.euclid >= 1)].copy()
one_sided = len(df) - len(both)
x = np.log10(both.trase)
y = np.log10(both.euclid)

r_log = np.corrcoef(x, y)[0, 1]

mpl.rcParams.update({"font.family": "DejaVu Sans", "savefig.dpi": 200,
                     "savefig.bbox": "tight",
                     "axes.spines.top": False, "axes.spines.right": False})
fig, ax = plt.subplots(figsize=(7.6, 7.4))
ax.set_axisbelow(True)
ax.grid(color=GRID, linewidth=0.8)

# point cloud (rasterized so the PDF stays small)
ax.scatter(x, y, s=3.5, c="#C5D86D", alpha=0.35, edgecolors="none", rasterized=True)

# density contours from a 2-D histogram (robust for ~700k points)
H, xe, ye = np.histogram2d(x, y, bins=120)
Hs = H.T
# smooth lightly with a separable 3-bin box filter
k = np.array([0.25, 0.5, 0.25])
Hs = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 0, Hs)
Hs = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 1, Hs)
xc, yc = (xe[:-1] + xe[1:]) / 2, (ye[:-1] + ye[1:]) / 2
levels = np.quantile(Hs[Hs > 0], [0.80, 0.92, 0.985])
ax.contour(xc, yc, Hs, levels=levels, colors="#7A7A7A", linewidths=0.9)

# 1:1 diagonal
lo = min(x.min(), y.min())
hi = max(x.max(), y.max())
pad = 0.15 * (hi - lo)
lo, hi = lo - pad * 0.2, hi + pad * 0.2
ax.plot([lo, hi], [lo, hi], ls="--", color="#333", lw=1.2)

ax.set_xlim(lo, hi); ax.set_ylim(lo, hi)
ax.set_aspect("equal")
ax.set_xlabel("Trase reported value (log10 tonnes)", fontsize=11.5)
ax.set_ylabel("Model realized value (log10 tonnes)", fontsize=11.5)
ax.set_title(f"Rocket plot: municipal soy export flows vs Trase, "
             f"{df.year.min()}–{df.year.max()}",
             fontsize=12.5, fontweight="bold", loc="left", pad=10)
ax.annotate(f"{len(both):,} municipality×destination×year flows\n"
            f"r(log flows) = {r_log:.2f}\n"
            f"({one_sided:,} flows excluded: zero or <1 t on either side)",
            xy=(0.02, 0.98), xycoords="axes fraction", va="top", fontsize=9,
            bbox=dict(boxstyle="round,pad=0.4", fc="#F4F4F4", ec="#CCC"))

for ext in ("png", "pdf"):
    fig.savefig(OUT / f"rocket_plot.{ext}")
print("wrote", OUT / "rocket_plot.png", "(+ .pdf)")

# ---------------------------------------------------------------------------
# Per-year panels (default 2005, 2010, 2015, 2020) - same design, one rocket
# per year, shared limits so the panels compare directly.
# ---------------------------------------------------------------------------
PANEL_YEARS = [int(v) for v in os.environ.get("ROCKET_YEARS", "2005,2010,2015,2020").split(",")]

def draw_rocket(ax, xx, yy, lo, hi, title):
    ax.set_axisbelow(True)
    ax.grid(color=GRID, linewidth=0.8)
    ax.scatter(xx, yy, s=3.5, c="#C5D86D", alpha=0.35, edgecolors="none", rasterized=True)
    H, xe, ye = np.histogram2d(xx, yy, bins=80)
    Hs = H.T
    Hs = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 0, Hs)
    Hs = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 1, Hs)
    xc, yc = (xe[:-1] + xe[1:]) / 2, (ye[:-1] + ye[1:]) / 2
    lv = np.quantile(Hs[Hs > 0], [0.80, 0.92, 0.985])
    ax.contour(xc, yc, Hs, levels=lv, colors="#7A7A7A", linewidths=0.8)
    ax.plot([lo, hi], [lo, hi], ls="--", color="#333", lw=1.1)
    ax.set_xlim(lo, hi); ax.set_ylim(lo, hi); ax.set_aspect("equal")
    r = np.corrcoef(xx, yy)[0, 1]
    ax.set_title(title, fontsize=11.5, fontweight="bold", loc="left", pad=6)
    ax.annotate(f"n = {len(xx):,}\nr(log) = {r:.2f}",
                xy=(0.03, 0.97), xycoords="axes fraction", va="top", fontsize=8.5,
                bbox=dict(boxstyle="round,pad=0.35", fc="#F4F4F4", ec="#CCC"))

fig2, axes = plt.subplots(2, 2, figsize=(11.6, 11.2))
for ax2, yr in zip(axes.ravel(), PANEL_YEARS):
    d = both[both.year == yr]
    draw_rocket(ax2, np.log10(d.trase), np.log10(d.euclid), lo, hi, str(yr))
for ax2 in axes[-1, :]:
    ax2.set_xlabel("Trase reported value (log10 tonnes)", fontsize=10.5)
for ax2 in axes[:, 0]:
    ax2.set_ylabel("Model realized value (log10 tonnes)", fontsize=10.5)
# ROCKET_SUPTITLE=0 drops the figure-level title (for paper use, where the
# LaTeX caption carries it)
if os.environ.get("ROCKET_SUPTITLE", "1") != "0":
    fig2.suptitle("Rocket plots by year: municipal soy export flows vs Trase",
                  fontsize=13.5, fontweight="bold", x=0.02, ha="left")
    fig2.tight_layout(rect=(0, 0, 1, 0.97))
else:
    fig2.tight_layout()
for ext in ("png", "pdf"):
    fig2.savefig(OUT / f"rocket_plot_years.{ext}")
print("wrote", OUT / "rocket_plot_years.png", "(+ .pdf)")

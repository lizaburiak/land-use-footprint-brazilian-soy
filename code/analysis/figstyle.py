#!/usr/bin/env python3
# Shared house style for the SOYPRINT paper figures.  Usage: from figstyle import *
from pathlib import Path
import os
import matplotlib as mpl
import matplotlib.pyplot as plt

# scripts moved from code/ to code/analysis/ -> repo root is two levels up
ROOT  = Path(os.environ.get("SOYPRINT_ROOT") or Path(__file__).resolve().parents[2])
PAPER = Path(os.environ.get("FIG_OUT") or ROOT / "results/figures/paper")
PAPER.mkdir(parents=True, exist_ok=True)
CSV   = Path(os.environ.get("FIG_CSV") or ROOT / "results/figures/footprint_dynamics/csv")   # by_region / by_enduse / by_country

# ---- palettes (consistent across all figures) ----------------------------
REGION = {"China":"#B5485B", "EU-27":"#2E7D88", "Rest of Asia":"#E0A458",
          "Rest of world":"#A9B4C2", "Brazil (domestic)":"#6FA56B"}
REGION_ORDER = ["China", "EU-27", "Rest of Asia", "Rest of world", "Brazil (domestic)"]  # bottom->top

ENDUSE = {"Animal products (meat/dairy/eggs)":"#7F2704",
          "Soybeans, meal & oil (commodity)":"#D94801",
          "Other food":"#FD8D3C", "Non-food / industrial":"#FDD0A2"}
ENDUSE_ORDER = ["Animal products (meat/dairy/eggs)", "Soybeans, meal & oil (commodity)",
                "Other food", "Non-food / industrial"]

INK, MUTED, GRID = "#1A1A1A", "#6B6B6B", "#E3E3E3"

mpl.rcParams.update({
    "figure.dpi":150, "savefig.dpi":240, "savefig.bbox":"tight",
    "font.family":"DejaVu Sans", "font.size":11,
    "axes.edgecolor":MUTED, "axes.linewidth":0.8,
    "axes.titlesize":14, "axes.titleweight":"bold", "axes.titlepad":10,
    "axes.labelcolor":INK, "text.color":INK, "xtick.color":MUTED, "ytick.color":MUTED,
    "axes.spines.top":False, "axes.spines.right":False, "axes.axisbelow":True,
    "figure.facecolor":"white", "axes.facecolor":"white", "legend.frameon":False,
})

def region_ha():
    """Land-use footprint (hectares) by destination region x year, from the map data.
    Returns a year-indexed DataFrame with columns China / EU-27 / Rest of Asia /
    Rest of world / Brazil (domestic) (+ Total). Brazil-domestic = Total - the 4 regions."""
    import pandas as pd
    m = pd.read_csv(os.environ.get("MAP_CSV") or ROOT / "results/maps/footprint_maps/map_data_allyears.csv")
    g = m.groupby(["year", "layer"])["ha"].sum().unstack("layer")
    g["Brazil (domestic)"] = g["Total"] - g[["China", "EU-27", "Rest of Asia", "Rest of world"]].sum(axis=1)
    return g

def style_axes(ax):
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.grid(axis="x", visible=False)

def smooth_stack(ax, data, order, colors, npts=260, sep="white", sep_lw=0.7):
    """Smooth stacked-area: PCHIP-interpolate each cumulative boundary (monotone, no
    overshoot) so band edges are curves, not straight segments. `data` = DataFrame
    indexed by x with one column per key in `order` (bottom->top)."""
    import numpy as np
    from scipy.interpolate import PchipInterpolator
    x  = data.index.values.astype(float)
    xf = np.linspace(x.min(), x.max(), npts)
    cum = np.zeros(len(x)); lower = np.zeros(len(xf))
    for k in order:
        cum = cum + data[k].values
        upper = np.maximum(PchipInterpolator(x, cum)(xf), lower)
        ax.fill_between(xf, lower, upper, color=colors[k], alpha=1.0, linewidth=0)
        if sep: ax.plot(xf, upper, color=sep, linewidth=sep_lw)
        lower = upper

def end_labels(ax, x_at, tops, order, colors, fontsize=10):
    """Right-edge band labels at each stacked band's vertical centre (replaces a legend).
    `tops` = dict label -> final-year band height (in plot units)."""
    cum = 0
    for k in order:
        v = tops[k]
        ax.annotate(k, xy=(x_at, cum + v/2), xytext=(7, 0), textcoords="offset points",
                    va="center", ha="left", fontsize=fontsize, color=colors[k],
                    fontweight="bold", annotation_clip=False)
        cum += v

def save(fig, name):
    for ext in ("png", "pdf"):
        fig.savefig(PAPER / f"{name}.{ext}")
    print("wrote", PAPER / f"{name}.png", "(+ .pdf)")

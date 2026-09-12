#!/usr/bin/env python3
# ============================================================================
# 2010-vs-2022 municipal land-use footprint maps (5 rows x 2 cols).
#   Row 1 Total | Row 2 China | Row 3 EU-27 | Row 4 Rest of Asia | Row 5 Rest of world
#   Cols: 2010 (left) vs 2022 (right).
# Metric: Brazilian soy LAND-use footprint (ha, F_mass) embodied in each
# destination's consumption, by municipality of origin.
#
# Each ROW shares one colour scale across both years (2010 vs 2022 directly
# comparable); scales differ between rows (Total >> Rest of world). A sqrt-type
# norm is used because per-municipality footprint is heavily right-skewed.
#
# Input : results/maps/footprint_maps/map_data_2010_2022.csv   (from prep_map_2010_2022.R)
#         data/generated/base/GEO_MUN_SOY.gpkg                    (municipal geometry, co_mun)
#         data/geo/GADM_boundaries/gadm36_BRA_1.shp            (state outlines)
# Output: results/maps/footprint_maps/map_2010_2022.{png,pdf}
# Usage : .venv/bin/python code/plot_map_2010_2022.py
# ============================================================================
from pathlib import Path
import numpy as np
import pandas as pd
import geopandas as gpd
import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib.colors import PowerNorm
from matplotlib.cm import ScalarMappable

ROOT = Path(__file__).resolve().parents[2]  # scripts live in code/analysis/
import os
MAPS = Path(os.environ.get("MAPS_DIR") or ROOT / "results/maps/footprint_maps")
MAPS_OUT = Path(os.environ.get("MAPS_OUT") or MAPS)
CRS  = 5880  # SIRGAS 2000 / Brazil Polyconic

LAYERS = ["Total", "China", "EU-27", "Rest of Asia", "Rest of world"]
YEARS  = [int(y) for y in os.environ.get("MAP_YEARS", "2010,2022").split(",")]
CMAP   = "inferno_r"          # light = low, dark = high (repo's existing choropleth aesthetic)
GAMMA  = 0.45                 # PowerNorm exponent (sqrt-ish) to tame the skew

# ---- style ---------------------------------------------------------------
INK, MUTED = "#1A1A1A", "#6B6B6B"
mpl.rcParams.update({
    "figure.dpi": 150, "savefig.dpi": 240, "savefig.bbox": "tight",
    "font.family": "DejaVu Sans", "font.size": 11, "text.color": INK,
    "figure.facecolor": "white", "axes.facecolor": "white",
})

# ---- load ----------------------------------------------------------------
df = pd.read_csv(MAPS / f"map_data_{YEARS[0]}_{YEARS[1]}.csv")
geo = gpd.read_file(ROOT / "data/generated/base/GEO_MUN_SOY.gpkg")[["co_mun", "geometry"]].to_crs(CRS)

states_path = ROOT / "data/geo/GADM_boundaries/gadm36_BRA_1.shp"
states = gpd.read_file(states_path).to_crs(CRS) if states_path.exists() else None

# total footprint per (layer, year) for panel annotations (Mha)
tot = df.groupby(["layer", "year"])["ha"].sum().div(1e6)

# SINGLE global colour normalisation shared by ALL panels (every layer & year),
# so identical colour == identical footprint everywhere - a dark municipality in
# "Rest of world" carries the same hectares as a dark one in "Total". vmax is the
# 99th percentile of the Total layer (the per-municipality envelope, since every
# destination <= Total), pooled across both years.
gvals = df.loc[(df.layer == "Total") & (df.ha > 0), "ha"].to_numpy()
GVMAX = float(np.percentile(gvals, 99)) if gvals.size else 1.0
norm = PowerNorm(gamma=GAMMA, vmin=0, vmax=GVMAX)

# ---- figure: 5 rows x 2 maps, one shared colorbar at the bottom ----------
fig = plt.figure(figsize=(11.0, 15.5))
# symmetric left/right margins (equal whitespace each side); wider column gap;
# headroom at top for the title; room at bottom for the single shared colorbar.
gs = fig.add_gridspec(len(LAYERS), 2, wspace=0.04, hspace=0.03,
                      left=0.06, right=0.94, top=0.925, bottom=0.055)

for r, L in enumerate(LAYERS):
    for c, Y in enumerate(YEARS):
        ax = fig.add_subplot(gs[r, c])
        sub = df[(df.layer == L) & (df.year == Y)][["co_mun", "ha"]]
        g = geo.merge(sub, on="co_mun", how="left")
        g["ha"] = g["ha"].fillna(0.0)
        if states is not None:
            states.plot(ax=ax, facecolor="#F2F2F2", edgecolor="white", linewidth=0.4, zorder=0)
        g.plot(ax=ax, column="ha", cmap=CMAP, norm=norm, linewidth=0, zorder=1)
        if states is not None:
            states.boundary.plot(ax=ax, edgecolor="#B9B9B9", linewidth=0.35, zorder=2)
        ax.set_axis_off()
        ax.set_aspect("equal")
        # magnitude annotation
        ax.annotate(f"{tot.loc[(L, Y)]:.1f} Mha", xy=(0.04, 0.06), xycoords="axes fraction",
                    fontsize=10, color=MUTED, ha="left", va="bottom")
        if r == 0:
            ax.set_title(str(Y), fontsize=15, fontweight="bold", pad=6)
        if c == 0:
            ax.text(-0.04, 0.5, L, transform=ax.transAxes, rotation=90,
                    fontsize=13, fontweight="bold", ha="right", va="center")

# single shared colorbar for ALL panels (horizontal, bottom-centre)
cax = fig.add_axes([0.14, 0.035, 0.72, 0.010])
sm = ScalarMappable(norm=norm, cmap=CMAP); sm.set_array([])
cb = fig.colorbar(sm, cax=cax, orientation="horizontal", extend="max")
cb.ax.tick_params(labelsize=8, color=MUTED, labelcolor=MUTED)
ticks = [t for t in cb.get_ticks() if norm.vmin <= t <= norm.vmax]
cb.set_ticks(ticks)
cb.set_ticklabels([f"{t/1e3:.0f}" for t in ticks])
cb.set_label("Land footprint per municipality (1000 ha)", fontsize=9, color=MUTED)
cb.outline.set_visible(False)

fig.suptitle(f"Brazilian soy land-use footprint by destination, municipal origin, {YEARS[0]} vs {YEARS[1]}",
             fontsize=15, fontweight="bold", y=0.975)
fig.text(0.5, 0.955, "Hectares of soy land embodied in consumption (F_mass). "
         "All panels share one colour scale; sqrt-scaled.",
         ha="center", fontsize=10, color=MUTED)

png = MAPS_OUT / f"map_{YEARS[0]}_{YEARS[1]}.png"
pdf = MAPS_OUT / f"map_{YEARS[0]}_{YEARS[1]}.pdf"
fig.savefig(png); fig.savefig(pdf)
print("wrote", png)
print("wrote", pdf)
print("\nLayer totals (Mha):")
print(tot.unstack().reindex(LAYERS).round(2))

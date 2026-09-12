#!/usr/bin/env python3
# ============================================================================
# Destination-set views of the three-model Trase comparison, 2010-2022.
# BRA (domestic use) is excluded everywhere; volumes are Trase-recorded.
#
# fig_dest_top70   : mean per-destination r over the fixed top-70%-of-volume
#                    importer set (lines only) + three per-importer r tables
#                    (downscale / euclid / multimode) under the plot.
# fig_dest_bottom5 : same layout for the 5 smallest-volume importers among
#                    those matched in every year.
# fig_dest_weighted: volume-weighted mean per-destination r per year
#                    (weights = importer's Trase volume share that year,
#                    renormalised over destinations with a defined r).
#
# Reads : results/tables/benchmarks/<year>/pearson_by_dest.csv
# Writes: results/figures/paper/fig_dest_{top70,bottom5,weighted}.{png,pdf}
# ============================================================================
import re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from figstyle import ROOT, PAPER, style_axes

MODEL = {"euclid": ("Euclidean", "#2E7D88"),
         "multimode": ("Multimodal", "#B5485B"),
         "downscale": ("Downscale", "#A9B4C2")}
KEYS = ["downscale", "euclid", "multimode"]
YEARS = list(range(2010, 2023))


def unstar(s):
    if pd.isna(s) or str(s).strip() in ("-", ""):
        return np.nan
    m = re.match(r"\s*(-?\d*\.?\d+)", str(s))
    return float(m.group(1)) if m else np.nan


rows = []
for y in YEARS:
    d = pd.read_csv(ROOT / f"results/tables/benchmarks/{y}/pearson_by_dest.csv")
    for _, r in d.iterrows():
        if r["to_code"] in ("-", "ROW", "Total", "BRA"):
            continue
        rows.append(dict(year=y, to_code=r["to_code"], mt=r["exports_trase"],
                         multimode=np.nan if y == 2021 else unstar(r["base.multimode"]),
                         euclid=unstar(r["base.euclid"]),
                         downscale=unstar(r["base.downscale"])))
dest = pd.DataFrame(rows)
dest = dest[dest.mt > 0].copy()

vol = dest.groupby("to_code").mt.sum().sort_values(ascending=False)
cum = vol.cumsum() / vol.sum()

# top-70% set: smallest set of largest importers reaching 70% of volume
top70 = list(cum.index[: int((cum <= 0.70).sum()) + 1])

# bottom 5: smallest pooled volume among importers matched in every year
n_years = dest.groupby("to_code").year.nunique()
always = n_years[n_years == len(YEARS)].index
bottom5 = list(vol[vol.index.isin(always)].tail(5).index)

print("top-70% set:", top70, f"(cum share {cum[top70[-1]]:.2f})")
print("bottom-5 set:", bottom5, "pooled Mt:", vol[bottom5].round(3).to_dict())


def table_for(codes, key):
    sub = dest[dest.to_code.isin(codes)].pivot(index="to_code", columns="year",
                                               values=key)
    return sub.reindex(codes).reindex(columns=YEARS)


def set_figure(codes, fname, title):
    n_tab = 3
    hplot = 4.2
    htab = 0.26 * (len(codes) + 1) + 0.30
    fig = plt.figure(figsize=(12.5, hplot + n_tab * (htab + 0.42) + 0.5))
    heights = [hplot] + [htab] * n_tab
    gs = fig.add_gridspec(1 + n_tab, 1, height_ratios=heights, hspace=0.9)

    ax = fig.add_subplot(gs[0])
    grp = dest[dest.to_code.isin(codes)].groupby("year")[KEYS].mean()
    for key in KEYS:
        lab, col = MODEL[key]
        ax.plot(grp.index, grp[key], color=col, lw=2.2, label=lab)
    ax.set_title(title, loc="left", fontsize=12)
    ax.set_ylabel("Mean per-destination r")
    ax.set_xticks(range(2010, 2023, 2))
    ax.set_ylim(0, 1.0)
    ax.legend(loc="best", fontsize=8, ncol=3)
    style_axes(ax)

    for i, key in enumerate(KEYS):
        lab, col = MODEL[key]
        axT = fig.add_subplot(gs[1 + i])
        axT.set_axis_off()
        tb = table_for(codes, key)
        cell = [[("" if pd.isna(v) else f"{v:.2f}") for v in row]
                for row in tb.values]
        t = axT.table(cellText=cell, rowLabels=list(tb.index),
                      colLabels=[str(y) for y in YEARS],
                      cellLoc="center", loc="center")
        t.auto_set_font_size(False)
        t.set_fontsize(7.5)
        t.scale(1, 1.25)
        greens = plt.get_cmap("Greens")
        for (irow, icol), c in t.get_celld().items():
            c.set_edgecolor("#DDDDDD")
            if irow > 0 and icol >= 0:  # data cells; header row is irow 0
                v = tb.values[irow - 1, icol]
                if not pd.isna(v):
                    c.set_facecolor(greens(max(0.0, min(1.0, v)) * 0.85))
                    if v > 0.65:
                        c.get_text().set_color("white")
        axT.text(0.0, 1.45, lab, transform=axT.transAxes,
                 fontsize=9, color="black", fontweight="bold", va="bottom")

    for ext in ("png", "pdf"):
        fig.savefig(PAPER / f"{fname}.{ext}", bbox_inches="tight")
    plt.close(fig)
    print("wrote", PAPER / f"{fname}.pdf")


set_figure(top70, "fig_dest_top70",
           f"Top importers covering 70% of volume ({', '.join(top70)})")
set_figure(bottom5, "fig_dest_bottom5",
           f"Five smallest always-matched importers ({', '.join(bottom5)})")

# ---- headline: volume-weighted mean per year --------------------------------
wtab = {}
for y, g in dest.groupby("year"):
    row = {}
    for k in KEYS:
        v = g.dropna(subset=[k])
        row[k] = np.average(v[k], weights=v.mt) if len(v) else np.nan
    wtab[y] = row
w = pd.DataFrame(wtab).T

fig, ax = plt.subplots(figsize=(7.2, 4.4))
for key in KEYS:
    lab, col = MODEL[key]
    ax.plot(w.index, w[key], color=col, lw=2.4, marker="o", ms=4.5, label=lab)
ax.set_xlabel("Year")
ax.set_ylabel("Volume-weighted per-destination correlation")
ax.set_title("Agreement with Trase, weighted by import volume",
             loc="left", fontsize=12)
ax.set_xticks(range(2010, 2023, 2))
ax.set_ylim(0.4, 0.9)
ax.legend(loc="lower left", fontsize=9)
style_axes(ax)
fig.tight_layout()
for ext in ("png", "pdf"):
    fig.savefig(PAPER / f"fig_dest_weighted.{ext}")
print("wrote", PAPER / "fig_dest_weighted.pdf")
print("\nweighted table:\n", w.round(3).to_string())

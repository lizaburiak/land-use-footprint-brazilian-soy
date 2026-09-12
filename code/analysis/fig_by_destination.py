#!/usr/bin/env python3
# ============================================================================
# PAPER FIGURE 1 - Brazilian soy footprint by destination region, 2010-2022.
# (a) absolute volume (Mt)   (b) share (%).  Production footprint (P_mass).
# Smooth (PCHIP) stacked areas. Input: by_region.csv.
# Output: results/figures/paper/fig_by_destination.{png,pdf}
# ============================================================================
import numpy as np, pandas as pd, matplotlib.pyplot as plt
from matplotlib.patches import Patch
from figstyle import REGION, REGION_ORDER, MUTED, style_axes, smooth_stack, save, region_ha

w  = region_ha().reindex(columns=REGION_ORDER)
yrs = w.index.values
Mt, share = w/1e6, 100*w.div(w.sum(axis=1), axis=0)   # Mt var name = million hectares here

fig, (axL, axR) = plt.subplots(1, 2, figsize=(12.4, 5.2))
plt.subplots_adjust(wspace=0.20, bottom=0.19, top=0.88)

# (a) area - smooth stacked
smooth_stack(axL, Mt, REGION_ORDER, REGION)
axL.set_xlim(yrs.min(), yrs.max()); axL.set_xticks(yrs[::2]); style_axes(axL); axL.tick_params(labelsize=8.5)
axL.set_ylim(0, Mt.sum(axis=1).max()*1.05); axL.set_ylabel("Million hectares of soy land", fontsize=9.5)
axL.set_title("a   Area", loc="left", fontsize=10.5)

# (b) share - one smooth (PCHIP) line per region
from scipy.interpolate import PchipInterpolator
xs = np.linspace(yrs.min(), yrs.max(), 260)
for k in REGION_ORDER:
    axR.plot(xs, PchipInterpolator(yrs, share[k].values)(xs),
             color=REGION[k], lw=2.2, solid_capstyle="round")
axR.set_xlim(yrs.min(), yrs.max()); axR.set_xticks(yrs[::2]); style_axes(axR); axR.tick_params(labelsize=8.5)
axR.set_ylim(0, float(share.to_numpy().max())*1.10); axR.set_ylabel("Share of footprint (%)", fontsize=9.5)
axR.set_title("b   Share", loc="left", fontsize=10.5)

handles = [Patch(facecolor=REGION[k], label=k) for k in REGION_ORDER]
fig.legend(handles=handles, loc="lower center", ncol=5, bbox_to_anchor=(0.5, 0.03),
           fontsize=9, handlelength=1.0, columnspacing=1.4, borderaxespad=0)

fig.suptitle(f"Brazilian soy land-use footprint by destination region, {yrs.min()}\u2013{yrs.max()}",
             fontsize=12.5, fontweight="bold", x=0.5, y=0.965)

save(fig, "fig_by_destination")

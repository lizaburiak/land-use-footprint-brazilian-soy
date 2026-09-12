#!/usr/bin/env python3
# ============================================================================
# PAPER FIGURE 2 - Brazilian soy land-use footprint by end-use, 2010-2022.
# (a) area (Mha)   (b) share (%) as grouped bars sorted per year. Land footprint (F_mass).
# Input : results/figures/footprint_dynamics/csv/by_enduse_ha.csv  (from prep_enduse_ha.R)
# Output: results/figures/paper/fig_enduse.{png,pdf}
# ============================================================================
import numpy as np, pandas as pd, matplotlib.pyplot as plt
from matplotlib.patches import Patch
from figstyle import ENDUSE, ENDUSE_ORDER, CSV, MUTED, style_axes, smooth_stack, save

df = pd.read_csv(CSV/"by_enduse_ha.csv")
w  = df.pivot_table(index="year", columns="bucket", values="ha", aggfunc="sum").fillna(0)
w  = w.reindex(columns=[c for c in ENDUSE_ORDER if c in w.columns])
yrs = w.index.values
Mt, share = w/1e6, 100*w.div(w.sum(axis=1), axis=0)
ORDER = list(w.columns)

fig, (axL, axR) = plt.subplots(1, 2, figsize=(12.4, 5.2))
plt.subplots_adjust(wspace=0.20, bottom=0.24, top=0.88)

# (a) area - smooth stacked
smooth_stack(axL, Mt, ORDER, ENDUSE)
axL.set_xlim(yrs.min(), yrs.max()); axL.set_xticks(yrs[::2]); style_axes(axL); axL.tick_params(labelsize=8.5)
axL.set_ylim(0, Mt.sum(axis=1).max()*1.05); axL.set_ylabel("Million hectares of soy land", fontsize=9.5)
axL.set_title("a   Area", loc="left", fontsize=10.5)

# (b) share - one smooth (PCHIP) line per end-use
from scipy.interpolate import PchipInterpolator
xs = np.linspace(yrs.min(), yrs.max(), 260)
for k in ORDER:
    axR.plot(xs, PchipInterpolator(yrs, share[k].values)(xs),
             color=ENDUSE[k], lw=2.2, solid_capstyle="round")
axR.set_xlim(yrs.min(), yrs.max()); axR.set_xticks(yrs[::2]); style_axes(axR); axR.tick_params(labelsize=8.5)
axR.set_ylim(0, float(share.to_numpy().max())*1.10); axR.set_ylabel("Share of footprint (%)", fontsize=9.5)
axR.set_title("b   Share", loc="left", fontsize=10.5)

handles = [Patch(facecolor=ENDUSE[k], label=k) for k in ORDER]
fig.legend(handles=handles, loc="lower center", ncol=2, bbox_to_anchor=(0.5, 0.02),
           fontsize=9, handlelength=1.0, columnspacing=1.6, borderaxespad=0)
fig.suptitle(f"Brazilian soy land-use footprint by end-use, {df.year.min()}\u2013{df.year.max()}",
             fontsize=12.5, fontweight="bold", x=0.5, y=0.965)
save(fig, "fig_enduse")
print(share.round(1).to_string())

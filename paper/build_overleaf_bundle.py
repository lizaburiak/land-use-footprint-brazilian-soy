import os, re, shutil

ROOT = "/Users/elizavetaburiak/Desktop/work/wu/soybean/soyprint_liza's_update"
PAPER = os.path.join(ROOT, "paper")
OUT = os.path.join(PAPER, "main")
os.makedirs(os.path.join(OUT, "figures"), exist_ok=True)

def body(path):
    s = open(path).read()
    s = s[s.index("\\maketitle") + len("\\maketitle"):]
    s = s[:s.index("\\end{document}")]
    return s

# ---- results: straight body, but strip its graphicspath (set in main) ------
res = body(os.path.join(PAPER, "results_section/results.tex"))
open(os.path.join(OUT, "results_body.tex"), "w").write(res.strip() + "\n")

# ---- methods: split main part and appendix ---------------------------------
met = body(os.path.join(PAPER, "methods_section/methods.tex"))
met_main, met_app = met.split("\\appendix", 1)
met_app = met_app[:met_app.index("\\bibliography")] if "\\bibliography" in met_app else met_app
met_main = met_main.rstrip().rstrip("%= \n")
# remove the trailing comment ruler before \appendix if present
met_main = re.sub(r"(%\s*=+\s*)$", "", met_main.rstrip())
open(os.path.join(OUT, "methods_body.tex"), "w").write(met_main.strip() + "\n")
open(os.path.join(OUT, "methods_appendix.tex"), "w").write(
    met_app.replace("% ==================================================================", "").strip() + "\n")

# ---- data: split main part and its appendix (annex input) ------------------
dat = body(os.path.join(PAPER, "data_section/data.tex"))
dat_main, dat_app = dat.split("\\appendix", 1)
dat_app = dat_app[:dat_app.index("\\bibliography")]
open(os.path.join(OUT, "data_body.tex"), "w").write(dat_main.strip().rstrip("%= \n").strip() + "\n")
# the annex itself is already body-only
shutil.copy(os.path.join(PAPER, "data_section/annex_links.tex"), os.path.join(OUT, "annex_links.tex"))

# ---- support files ----------------------------------------------------------
for f in ["sn-jnl.cls", "sn-nature.bst"]:
    shutil.copy(os.path.join(PAPER, "methods_section", f), os.path.join(OUT, f))
shutil.copy(os.path.join(PAPER, "methods_section/refs.bib"), os.path.join(OUT, "refs.bib"))

# ---- figures used by results -------------------------------------------------
figdir = os.path.join(ROOT, "results/plots_2001_2022")
for f in ["fig_by_destination.pdf", "fig_enduse.pdf", "map_2001_2022.png", "rocket_plot.pdf"]:
    shutil.copy(os.path.join(figdir, f), os.path.join(OUT, "figures", f))

# ---- main.tex ----------------------------------------------------------------
main = r"""%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SOYPRINT -- assembled manuscript (Overleaf master file)
%% Body content lives in *_body.tex (generated from the standalone
%% section documents); edit those, not this file, for section text.
%% Compile: pdflatex main && bibtex main && pdflatex main && pdflatex main
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\documentclass[pdflatex,sn-nature]{sn-jnl}% Nature Portfolio reference style

%%%% Standard packages
\usepackage{graphicx}%
\usepackage{amsmath,amssymb,amsfonts}%
\usepackage{amsthm}%
\usepackage{xcolor}%
\usepackage{textcomp}%
\usepackage{manyfoot}%
\usepackage{booktabs}%
\usepackage{geometry}%
\usepackage{tikz}%
\usetikzlibrary{arrows.meta,positioning,decorations.pathreplacing}

%%%% Math helpers (used by the Methods section)
\DeclareMathOperator*{\argmin}{arg\,min}
\DeclareMathOperator{\diag}{diag}
\newcommand{\CBS}[2]{\mathrm{CBS}[#1,#2]}

\graphicspath{{figures/}}

\raggedbottom

\begin{document}

\title[Land-use footprint of Brazilian soy]{Mapping the land-use footprint
of Brazilian soy embodied in international consumption: a spatially explicit
input--output approach}

\author*[1]{\fnm{} \sur{}}\email{}

\affil*[1]{\orgdiv{Institute for Ecological Economics},
\orgname{Vienna University of Economics and Business (WU)},
\orgaddress{\city{Vienna}, \country{Austria}}}

\abstract{\emph{TODO: abstract.}}

\keywords{soy, land footprint, telecoupling, MRIO, FABIO, Brazil, deforestation}

\maketitle

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Introduction}\label{sec:intro}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\emph{TODO: introduction.}

\input{results_body}

\input{methods_body}

\input{data_body}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\appendix
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\input{methods_appendix}
\input{annex_links}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\bibliography{refs}%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\end{document}
"""
open(os.path.join(OUT, "main.tex"), "w").write(main)
print("bundle written to", OUT)
print(sorted(os.listdir(OUT)))

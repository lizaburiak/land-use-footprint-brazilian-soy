"""Generate a side-by-side HTML diff of the 00_* R scripts.

Left column  = Stefan Trsek's pristine code (extracted from `git show HEAD:`).
Right column = Liza's updated code from R/new/, with changed lines highlighted
               red and an explanation of the changes per file.

Run from the project root:
    python3 docs/build_00_diff.py
Output: docs/00_code_comparison.html
"""

import difflib
import html
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "00_code_comparison.html"


def git_head(path: str) -> list[str]:
    """Return file content at HEAD as a list of lines (with newlines)."""
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    return result.stdout.splitlines(keepends=True)


def read_lines(path: Path) -> list[str]:
    return path.read_text().splitlines(keepends=True)


def render_diff_table(old_lines: list[str], new_lines: list[str]) -> str:
    """Render a side-by-side HTML table using difflib opcodes."""
    sm = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    rows: list[str] = []

    def cell(line_no, content, cls):
        text = html.escape(content.rstrip("\n")) if content is not None else ""
        ln = str(line_no) if line_no is not None else ""
        return f'<td class="ln">{ln}</td><td class="code {cls}"><pre>{text}</pre></td>'

    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                rows.append(
                    "<tr>"
                    + cell(i1 + k + 1, old_lines[i1 + k], "eq")
                    + cell(j1 + k + 1, new_lines[j1 + k], "eq")
                    + "</tr>"
                )
        elif tag == "delete":
            for k in range(i2 - i1):
                rows.append(
                    "<tr>"
                    + cell(i1 + k + 1, old_lines[i1 + k], "del")
                    + cell(None, "", "blank")
                    + "</tr>"
                )
        elif tag == "insert":
            for k in range(j2 - j1):
                rows.append(
                    "<tr>"
                    + cell(None, "", "blank")
                    + cell(j1 + k + 1, new_lines[j1 + k], "ins")
                    + "</tr>"
                )
        elif tag == "replace":
            old_block = old_lines[i1:i2]
            new_block = new_lines[j1:j2]
            n = max(len(old_block), len(new_block))
            for k in range(n):
                left = (i1 + k + 1, old_block[k], "chg") if k < len(old_block) else (None, "", "blank")
                right = (j1 + k + 1, new_block[k], "chg") if k < len(new_block) else (None, "", "blank")
                rows.append("<tr>" + cell(*left) + cell(*right) + "</tr>")

    return (
        '<table class="diff">'
        '<thead><tr>'
        '<th class="ln-h"></th><th>Stefan Trsek &mdash; original</th>'
        '<th class="ln-h"></th><th>Liza &mdash; updated</th>'
        '</tr></thead><tbody>'
        + "".join(rows)
        + "</tbody></table>"
    )


# Per-file explanation blocks (drawn from R/new/CHANGELOG.md)
EXPLANATIONS = {
    "00_data_preperation.R": """
<h3>Summary of changes</h3>
<ul>
  <li><b>Year parameterization.</b> The script now accepts a year via
      <code>commandArgs(trailingOnly = TRUE)[1]</code> (default 2013, range
      2000&ndash;2022) instead of being hard-coded to 2013.</li>
  <li><b>Input paths moved.</b> All raw-data reads switched from
      <code>inputs/00/old/</code> to <code>inputs/00/new/&lt;subfolder&gt;/</code>
      with year selection.</li>
  <li><b>Output paths moved.</b> Saves are now written to
      <code>outputs/00_{YEAR}/</code> instead of <code>outputs/00/</code>.</li>
  <li><b>Processing block (&sect;1.4) replaced.</b> Stefan's 2013-only
      <code>processing_MUN</code> sheet was swapped for a per-year dispatcher
      that reads <code>ABIOVE_raw_capacity_2025.xlsx</code> sheet&nbsp;2 (state
      capacity) and year-specific <code>pesquisa_capacidade_*</code> files
      (plant roster), then applies Trsek's equal-per-state allocation.</li>
  <li><b>Refining block (&sect;1.4b) added.</b> A new block mirrors the
      processing logic to compute <code>ref_cap</code> and
      <code>bot_cap</code>.</li>
  <li><b>Bugfix:</b> <code>.abiove_state_cap()</code> now restricts to the
      Processamento block only (previously summed Proc&nbsp;+&nbsp;Refino&nbsp;+&nbsp;Envase).</li>
  <li><b>Cleanup:</b> stray <code>!!!!!!!!!!!</code> parse error removed; a
      redundant hard-coded <code>YEAR &lt;- 2013</code> deleted.</li>
</ul>
""",
    "00_FAO_consitency_checks.R": """
<h3>Summary of changes</h3>
<ul>
  <li>Added <code>YEAR</code> parsing from
      <code>commandArgs(trailingOnly = TRUE)</code> at the top (default 2013).</li>
  <li><code>"outputs/00/CBS_SOY.rds"</code> &rarr;
      <code>paste0("outputs/00_", YEAR, "/CBS_SOY.rds")</code></li>
  <li><code>"outputs/00/SOY_MUN_00.rds"</code> &rarr;
      <code>paste0("outputs/00_", YEAR, "/SOY_MUN_00.rds")</code></li>
  <li><code>"inputs/00/CBS_SOY_2013_FAO.xlsx"</code> &rarr;
      <code>paste0("inputs/00/new/FAO_CBS/CBS_SOY_", YEAR, "_FAO.xlsx")</code></li>
  <li><code>saveRDS</code> output paths moved to
      <code>outputs/00_{YEAR}/</code>.</li>
  <li>No logic changes &mdash; only path parameterization.</li>
</ul>
""",
    "00_function_library.R": """
<h3>Summary of changes</h3>
<p><b>No changes.</b> <code>R/new/00_function_library.R</code> is byte-identical
to Stefan's version at <code>HEAD:R/00_function_library.R</code>. The file is
included in <code>R/new/</code> only so the new pipeline is self-contained.</p>
""",
}

# (label, old-source-path-in-git, new-file-on-disk)
FILES = [
    (
        "00_data_preperation.R",
        "R/00_data_preperation.R",
        ROOT / "R" / "new" / "00_data_preparation" / "00_data_preparation.R",
    ),
    (
        "00_FAO_consitency_checks.R",
        "R/00_FAO_consitency_checks.R",
        ROOT / "R" / "new" / "00_FAO_consitency_checks.R",
    ),
    (
        "00_function_library.R",
        "R/00_function_library.R",
        ROOT / "R" / "new" / "00_function_library.R",
    ),
]


CSS = """
:root {
  --bg: #ffffff;
  --fg: #1f2328;
  --muted: #57606a;
  --border: #d0d7de;
  --eq-bg: #ffffff;
  --del-bg: #ffe5e5;
  --del-fg: #b00020;
  --ins-bg: #e6ffec;
  --ins-fg: #116329;
  --chg-bg: #fff5b1;
  --chg-fg: #b00020;
  --ln-bg: #f6f8fa;
  --ln-fg: #8b949e;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  color: var(--fg);
  background: var(--bg);
  line-height: 1.5;
}
header {
  padding: 24px 32px;
  border-bottom: 1px solid var(--border);
  background: #f6f8fa;
}
header h1 { margin: 0 0 4px 0; font-size: 22px; }
header p  { margin: 0; color: var(--muted); font-size: 14px; }
nav { padding: 16px 32px; border-bottom: 1px solid var(--border); }
nav a { display: inline-block; margin-right: 16px; color: #0969da; text-decoration: none; font-size: 14px; }
section { padding: 24px 32px; border-bottom: 1px solid var(--border); }
section h2 { margin-top: 0; font-size: 18px; }
.expl { background: #f6f8fa; padding: 12px 16px; border-left: 4px solid #0969da; border-radius: 4px; margin-bottom: 16px; font-size: 14px; }
.expl h3 { margin-top: 0; font-size: 15px; }
.expl ul { margin: 8px 0; padding-left: 20px; }
.expl code { background: rgba(175,184,193,0.2); padding: 1px 4px; border-radius: 3px; font-size: 12px; }
.legend { font-size: 12px; color: var(--muted); margin-bottom: 8px; }
.legend span { display: inline-block; padding: 2px 6px; border-radius: 3px; margin-right: 8px; font-family: monospace; }
.legend .l-eq  { background: var(--eq-bg);  border: 1px solid var(--border); }
.legend .l-del { background: var(--del-bg); color: var(--del-fg); }
.legend .l-ins { background: var(--ins-bg); color: var(--ins-fg); }
.legend .l-chg { background: var(--chg-bg); color: var(--chg-fg); }

table.diff {
  border-collapse: collapse;
  width: 100%;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
  table-layout: fixed;
}
table.diff thead th {
  text-align: left;
  background: #f6f8fa;
  border: 1px solid var(--border);
  padding: 8px;
  font-size: 13px;
  position: sticky;
  top: 0;
}
table.diff td {
  border: 1px solid var(--border);
  vertical-align: top;
  padding: 0;
}
table.diff td.ln {
  width: 48px;
  background: var(--ln-bg);
  color: var(--ln-fg);
  text-align: right;
  padding: 2px 6px;
  user-select: none;
}
table.diff th.ln-h { width: 48px; }
table.diff td.code { padding: 2px 8px; }
table.diff pre {
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
  font-family: inherit;
}
table.diff td.eq    { background: var(--eq-bg); }
table.diff td.del   { background: var(--del-bg); color: var(--del-fg); }
table.diff td.ins   { background: var(--ins-bg); color: var(--ins-fg); }
table.diff td.chg   { background: var(--chg-bg); color: var(--chg-fg); }
table.diff td.blank { background: #fafbfc; }
"""


def main() -> None:
    parts: list[str] = []
    parts.append("<!doctype html><html lang='en'><head>")
    parts.append("<meta charset='utf-8'>")
    parts.append("<title>Pipeline 00 &mdash; Stefan vs Liza</title>")
    parts.append(f"<style>{CSS}</style>")
    parts.append("</head><body>")
    parts.append("<header>")
    parts.append("<h1>Pipeline step 00 &mdash; original vs updated code</h1>")
    parts.append(
        "<p>Left column: Stefan Trsek's pristine code at "
        "<code>HEAD:R/&lt;file&gt;</code>. Right column: Liza's updated code "
        "from <code>R/new/</code>. Changed regions are highlighted.</p>"
    )
    parts.append("</header>")

    parts.append("<nav>")
    for label, _, _ in FILES:
        anchor = label.replace(".", "-")
        parts.append(f"<a href='#{anchor}'>{label}</a>")
    parts.append("</nav>")

    for label, git_path, new_path in FILES:
        anchor = label.replace(".", "-")
        old = git_head(git_path)
        new = read_lines(new_path)

        parts.append(f"<section id='{anchor}'>")
        parts.append(f"<h2>{label}</h2>")
        parts.append(f"<div class='expl'>{EXPLANATIONS.get(label, '')}</div>")
        parts.append(
            "<div class='legend'>"
            "<span class='l-eq'>unchanged</span>"
            "<span class='l-del'>removed</span>"
            "<span class='l-ins'>added</span>"
            "<span class='l-chg'>modified</span>"
            "</div>"
        )
        parts.append(render_diff_table(old, new))
        parts.append("</section>")

    parts.append("</body></html>")
    OUT.write_text("".join(parts))
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()

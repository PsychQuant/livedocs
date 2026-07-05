"""Per-library vs-context7 freshness chart (issue #50) — matplotlib SVG.

Renders the SAME dated snapshot the CLI table/tally use, as a per-library
scorecard: for each library, LiveDocs' answer (the current release, by
construction) beside context7's default / top-ranked match (its version + how
far behind, or version-less).

MEASURED, never asserted (#27/#29): every value is verbatim from the snapshot —
`chart_rows` does no prose-parsing and invents nothing, so it is the data-guard
surface a test pins against the snapshot. The honesty caveats live in the README
caption (visible markdown), not inside this image.

Regenerable SVG with a fixed `svg.hashsalt` + `svg.fonttype='none'` (version strings
stay real `<text>` — greppable) + `Date`/`Creator` metadata stripped. NOTE: the SVG is
NOT byte-stable across matplotlib/freetype versions (text coordinates reflow), so the
drift guard is the version-independent SEMANTIC check in test_chart.py — it verifies each
cell's content, column, colour, and the footer against the snapshot — not byte-identity.
"""
import io
import os
import sys

import matplotlib
matplotlib.use("Agg")            # headless; must precede pyplot import
matplotlib.rcParams["svg.hashsalt"] = "livedocs-vs-context7"
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from compare_context7 import (  # noqa: E402 — reuse the harness's judgment + guards
    judge_row,
    tally,
    _require_iso_date,
)

_GREEN, _RED, _GREY, _INK, _SUB = "#1b7f4b", "#c0392b", "#8a8f98", "#222222", "#777777"


def chart_rows(sample):
    """Pure: snapshot dict → per-library chart data. Reuses `judge_row` for the
    current/stale verdict (single source of truth with the CLI tally) and reads
    context7's structured `default_version` / `default_status` verbatim."""
    rows = []
    for entry in sample.get("results", []):
        j = judge_row(entry)
        c7 = entry.get("context7") or {}
        rows.append({
            "library": entry["library"],
            "ecosystem": entry.get("ecosystem", ""),
            "ground_truth": j["ground_truth"],
            "livedocs_version": j["livedocs_answer"],
            "livedocs_current": j["livedocs_current"],       # None-able (faithful; tally() reads this)
            "context7_version": c7.get("default_version"),   # str | None (version-less)
            "context7_status": c7.get("default_status"),
            "context7_current": j["context7_current"],       # None-able (faithful; tally() reads this)
        })
    return rows


def _cell(ax, x, y, color, main, sub):
    ax.text(x, y + 0.13, main, fontsize=10.5, fontweight="bold", color=color, va="center")
    ax.text(x, y - 0.23, sub, fontsize=8, color=_SUB, va="center")


def scorecard_cells(row):
    """The (main-text, colour, sub-text) for a row's LiveDocs and context7 cells,
    DERIVED FROM THE MEASURED VERDICT (livedocs_current / context7_current), not from
    the column. This is the SINGLE definition shared by build_figure (rendering) and the
    drift guard (verification), so the image and the check can never disagree, and a
    future context7-current row renders ✓ instead of a hardcoded ✗ (#50 verify R2)."""
    ld_cur, c7_cur = row["livedocs_current"], row["context7_current"]
    livedocs = (("✓ " if ld_cur else "✗ ") + str(row["livedocs_version"]),
                _GREEN if ld_cur else _RED,
                "current" if ld_cur else "stale")
    if c7_cur:
        context7 = ("✓ " + str(row["context7_version"]), _GREEN, str(row["context7_status"]))
    elif row["context7_version"]:
        context7 = ("✗ " + str(row["context7_version"]), _RED, str(row["context7_status"]))
    else:
        context7 = ("✗ version-less", _GREY, "no version in top match")
    return {"livedocs": livedocs, "context7": context7}


def build_figure(rows, captured_at, counts):
    """Build the scorecard Figure. No shared numeric axis — versions across libs
    (19.2.7 / 0.139.0 / 1.0.228) aren't comparable, so this is categorical: each
    library is a row with a LiveDocs cell (current ✓) and a context7 cell
    (stale ✗ / version-less).

    `counts` is tally(rows) — the *contested-set* headline (n / livedocs_current /
    context7_current), shared with the README caption + CLI table so the image can
    never contradict them (#50 verify R1). Layout uses len(rows); the numeric claims
    use `counts` (today identical — all rows are contested)."""
    n_rows = len(rows)
    n = counts["n"]
    lc, cc = counts["livedocs_current"], counts["context7_current"]
    # Fail loud rather than silently ship a chart that DRAWS n_rows rows while its title +
    # footer claim the (contested) tally n. Today they're equal (all rows contested); a
    # future non-contested row must be a DELIBERATE display decision, not a silent skew
    # between the visible body and the printed denominator (#50 verify R2).
    assert n_rows == n, (
        f"chart would draw {n_rows} rows but the headline/footer claim {n} "
        f"(a non-contested row slipped in — decide how to present partial data first)"
    )
    fig, ax = plt.subplots(figsize=(8.4, 0.72 * n_rows + 2.5))
    ax.set_xlim(0, 10)
    ax.set_ylim(-0.7, n_rows + 2.0)
    ax.axis("off")

    ax.text(5, n_rows + 1.55,
            f"Latest-version freshness · {n} fast-moving libraries (npm / PyPI / crates) · captured {captured_at}",
            fontsize=11.5, fontweight="bold", ha="center", color=_INK)
    ax.text(0.25, n_rows + 0.75, "library", fontsize=9.5, fontweight="bold", color="#444", va="center")
    ax.text(3.6, n_rows + 0.75, "LiveDocs", fontsize=9.5, fontweight="bold", color=_GREEN, va="center")
    ax.text(6.55, n_rows + 0.75, "context7 (default match)", fontsize=9.5, fontweight="bold", color=_RED, va="center")
    ax.plot([0.2, 9.8], [n_rows + 0.45, n_rows + 0.45], color="#dddddd", lw=1)

    for i, r in enumerate(rows):
        y = n_rows - i - 0.2
        if i:
            ax.plot([0.2, 9.8], [y + 0.5, y + 0.5], color="#f0f0f0", lw=0.8)
        ax.text(0.25, y + 0.13, r["library"], fontsize=11, fontweight="bold", va="center", color=_INK)
        ax.text(0.25, y - 0.23, r["ecosystem"], fontsize=8, va="center", color=_GREY)
        cells = scorecard_cells(r)   # mark/colour derived from the verdict (shared with the guard)
        _cell(ax, 3.6, y, cells["livedocs"][1], cells["livedocs"][0], cells["livedocs"][2])
        _cell(ax, 6.55, y, cells["context7"][1], cells["context7"][0], cells["context7"][2])

    ax.plot([0.2, 9.8], [0.05, 0.05], color="#dddddd", lw=1)
    ax.text(5, -0.35,
            f"LiveDocs current on {lc}/{n}  ·  context7 on {cc}/{n}   "
            f"— freshness only; context7 wins coverage (not measured)",
            fontsize=9, ha="center", color="#555555")
    fig.subplots_adjust(left=0.02, right=0.98, top=0.98, bottom=0.02)
    return fig


def render_svg(sample, captured_at=None):
    """Return the deterministic SVG string rendered from the snapshot.

    Validates captured_at (parity with the README path — #50 verify R1) so an
    unvalidated date can't be baked into the front-page image. Strips `Date` + `Creator`
    metadata: `Creator` otherwise hard-codes `Matplotlib vX.Y.Z`. That removes ONE
    version-volatile source, but does NOT byte-stabilize the SVG — with `fonttype='none'`
    the text y-coordinates are still computed from freetype font metrics, so a matplotlib/
    freetype bump reflows them. Byte-identity is therefore NOT the CI drift guard; the
    version-independent semantic guard in test_chart.py (content + column-x + fill-colour
    + anchored footer, all vs the snapshot) is (#50 verify R2)."""
    captured_at = captured_at or sample.get("captured_at")
    _require_iso_date(captured_at)
    rows = chart_rows(sample)
    fig = build_figure(rows, captured_at, tally(rows))
    buf = io.StringIO()
    fig.savefig(buf, format="svg", metadata={"Date": None, "Creator": None})
    plt.close(fig)
    return buf.getvalue()

"""Unit tests for the per-library vs-context7 chart (issue #50).

The drift guard is SEMANTIC + version-independent (not a matplotlib byte-diff, which
is platform/version fragile — #50 verify R1). It parses the committed SVG's <text>
cells POSITIONALLY and checks each against the snapshot with the harness's own
`version_matches` boundary matcher — so a stale number, a false substring
(`1.0.2` vs `1.0.228`), a column swap (a current version in the wrong cell), or a
hand-tuned headline score all fail loud. This keeps the front-page competitive
numbers 'measured, not asserted' across matplotlib upgrades.

Residual (honestly scoped): a deliberate STRUCTURAL rewrite of the SVG that also
re-orders the <text> layout is caught by the maintainer's byte-level
`--emit-chart --check` (exercised version-independently by the write+check and
drift tests), not by this version-independent pytest floor.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVAL_DIR = os.path.dirname(HERE)
sys.path.insert(0, EVAL_DIR)
import chart  # noqa: E402
from compare_context7 import load_sample, tally, version_matches  # noqa: E402

SAMPLE = load_sample()
SVG_PATH = os.path.abspath(os.path.join(EVAL_DIR, "..", "..", "docs", "assets", "vs-context7-freshness.svg"))


def test_chart_rows_is_verbatim_projection_of_snapshot():
    # Data-guard: chart_rows invents nothing — every field is the snapshot's, and the
    # current/stale verdict is the harness's judge_row (None-able, single source of truth).
    rows = chart.chart_rows(SAMPLE)
    assert len(rows) == len(SAMPLE["results"])
    by_lib = {r["library"]: r for r in rows}
    assert all(r["livedocs_current"] is True for r in rows)    # current on every lib, by construction
    assert all(r["context7_current"] is False for r in rows)   # stale (known) on every lib in this set
    assert by_lib["react"]["ground_truth"] == "19.2.7" and by_lib["react"]["context7_version"] == "v18"
    assert by_lib["vite"]["context7_version"] == "8.0.10" and by_lib["vite"]["context7_status"] == "one minor behind"
    assert by_lib["fastapi"]["context7_version"] is None and by_lib["fastapi"]["context7_status"] == "version-less"


def test_render_svg_contains_every_snapshot_version_token():
    # The competitive numbers rendered in the SVG must be the snapshot's — via the
    # boundary matcher (not naive `in`, which false-matches `1.0.2` inside `1.0.228`).
    svg = chart.render_svg(SAMPLE)
    for tok in _snapshot_version_tokens():
        assert version_matches(svg, tok), f"snapshot token {tok!r} missing from rendered SVG"
    assert SAMPLE["captured_at"] in svg


def test_render_svg_is_deterministic():
    # Same-process byte stability (no Date/salt/version leak into the bytes). NOT a
    # claim of cross-matplotlib stability — that's what the semantic guard below covers.
    assert chart.render_svg(SAMPLE) == chart.render_svg(SAMPLE)


def test_committed_svg_is_semantically_faithful():
    # Strong drift guard on the COMMITTED asset: every per-library cell matches the
    # snapshot in the RIGHT column, and the headline matches tally() exactly.
    assert os.path.exists(SVG_PATH), \
        "committed SVG missing — run: python3 evals/look-up/compare_context7.py --emit-chart --write"
    svg = open(SVG_PATH, encoding="utf-8").read()
    _assert_svg_faithful(svg)
    assert SAMPLE["captured_at"] in svg   # the dated claim


def test_semantic_guard_catches_column_swap():
    # Prove the guard catches what token-presence could not: swap react's two cells so
    # the SVG lies (LiveDocs behind, context7 current). Every version token still
    # PRESENT — only the positional/marker binding exposes the lie.
    import pytest
    svg = open(SVG_PATH, encoding="utf-8").read()
    swapped = (svg.replace("✓ 19.2.7", "\x00").replace("✗ v18", "✓ 19.2.7").replace("\x00", "✗ v18"))
    assert swapped != svg
    with pytest.raises(AssertionError):
        _assert_svg_faithful(swapped)


def test_emit_chart_check_flags_drift(tmp_path):
    # A drifted snapshot → committed SVG no longer matches → --check returns 1 (fail-loud).
    import json as _json
    from compare_context7 import main, load_sample, SAMPLE_PATH
    s = load_sample(SAMPLE_PATH)
    s["captured_at"] = "2020-01-01"
    drifted = tmp_path / "drift.json"
    drifted.write_text(_json.dumps(s), encoding="utf-8")
    assert main(["--emit-chart", "--check", "--sample", str(drifted)]) == 1


def test_emit_chart_write_round_trips(tmp_path, monkeypatch):
    # --emit-chart --write then --check → 0 in the SAME env (version-independent: the
    # write and the check share one matplotlib, so no false drift).
    import compare_context7 as C
    asset = tmp_path / "sub" / "chart.svg"
    monkeypatch.setattr(C, "chart_asset_path", lambda: str(asset))
    assert C.main(["--emit-chart", "--write"]) == 0
    assert asset.exists()
    assert C.main(["--emit-chart", "--check"]) == 0


def test_emit_flag_mutual_exclusion_and_dependency():
    # --check/--write need an --emit-* mode; --emit-readme + --emit-chart are mutually
    # exclusive — all must fail LOUD (non-zero), never a silent exit-0.
    import pytest
    from compare_context7 import main
    for argv in (["--check"], ["--write"], ["--emit-readme", "--emit-chart"],
                 ["--emit-chart", "--check", "--write"]):
        with pytest.raises(SystemExit) as e:
            main(argv)
        assert e.value.code != 0, f"{argv} must fail loud, got {e.value.code}"


# ── helpers ───────────────────────────────────────────────────────────────────
def _snapshot_version_tokens():
    rows = chart.chart_rows(SAMPLE)
    return ([r["ground_truth"] for r in rows if r["ground_truth"]]
            + [r["context7_version"] for r in rows if r["context7_version"]])


def _parse_svg_scorecard(svg):
    """Parse the SVG's ordered <text> cells into {library: {livedocs_cell, context7_cell}}.
    The chart emits one <text> per label in a fixed order — title, 3 headers, then 6
    per row (library, ecosystem, LiveDocs-cell, 'current', context7-cell, status), then
    a footer — so a layout change makes the % 6 assert fail LOUD, never silently pass."""
    texts = [re.sub(r"\s+", " ", m).strip()
             for m in re.findall(r"<text[^>]*>(.*?)</text>", svg, re.DOTALL)]
    body = texts[4:-1]                                # drop title + 3 headers and the footer
    assert body and len(body) % 6 == 0, f"unexpected SVG <text> layout ({len(texts)} texts)"
    cells = {}
    for i in range(0, len(body), 6):
        lib, _eco, ld_cell, _cur, c7_cell, _sub = body[i:i + 6]
        cells[lib] = {"livedocs_cell": ld_cell, "context7_cell": c7_cell}
    return cells, texts[-1]


def _assert_svg_faithful(svg):
    """Raise AssertionError unless the SVG encodes the snapshot's per-library claims in
    the right columns and the headline matches tally() (the reusable guard body)."""
    cells, footer = _parse_svg_scorecard(svg)
    rows = chart.chart_rows(SAMPLE)
    for r in rows:
        c = cells.get(r["library"])
        assert c, f"{r['library']} row missing from SVG"
        ld, c7 = c["livedocs_cell"], c["context7_cell"]
        assert ld.startswith("✓") and version_matches(ld, r["ground_truth"]), \
            f"{r['library']}: LiveDocs cell {ld!r} is not '✓ {r['ground_truth']}' (stale/swapped)"
        assert c7.startswith("✗"), f"{r['library']}: context7 cell {c7!r} not marked stale"
        if r["context7_version"]:
            assert version_matches(c7, r["context7_version"]), \
                f"{r['library']}: context7 cell {c7!r} != {r['context7_version']}"
        else:
            assert "version-less" in c7, f"{r['library']}: context7 cell {c7!r} not version-less"
    t = tally(rows)
    assert f"{t['livedocs_current']}/{t['n']}" in footer, f"LiveDocs score not {t['livedocs_current']}/{t['n']}: {footer!r}"
    assert f"{t['context7_current']}/{t['n']}" in footer, f"context7 score not {t['context7_current']}/{t['n']}: {footer!r}"

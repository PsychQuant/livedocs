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


def test_semantic_guard_catches_visual_lies():
    # Prove the guard catches EVERY <text>-level lie, not just the value cells (#50 verify
    # R2 + R3): value-cell text-swap / added-prose / COLUMN-x swap / fill-COLOUR swap /
    # footer transpose, AND a SUB-CAPTION lie and a HEADER swap — all fail loud. Each
    # leaves most of the SVG individually true; only whole-image faithfulness exposes it.
    import pytest
    svg = open(SVG_PATH, encoding="utf-8").read()
    _assert_svg_faithful(svg)                             # baseline: the committed asset passes

    nodes = _svg_text_nodes(svg)
    ld_x, c7_x = nodes[6]["x"], nodes[8]["x"]             # react's two value-cell x (body[2]/[4])

    def swap(s, a, b):
        return s.replace(a, "\x00").replace(b, a).replace("\x00", b)

    mutations = {
        "text-swap":        lambda s: swap(s, "✓ 19.2.7", "✗ v18"),
        "added-prose":      lambda s: s.replace("✓ 19.2.7", "✓ 19.2.7 — context7 is outdated garbage"),
        "column-x-swap":    lambda s: swap(s, f'x="{ld_x}"', f'x="{c7_x}"'),
        "colour-swap":      lambda s: swap(s, "fill: #1b7f4b", "fill: #c0392b"),
        "footer-transpose": lambda s: swap(s, "6/6", "0/6"),
        "sub-caption-lie":  lambda s: s.replace("no version in top match", "context7 is actually current + better"),
        "header-swap":      lambda s: swap(s, ">LiveDocs<", ">context7 (default match)<"),
    }
    for name, mutate in mutations.items():
        tampered = mutate(svg)
        assert tampered != svg, f"{name}: mutation was a no-op (test bug)"
        with pytest.raises(AssertionError):
            _assert_svg_faithful(tampered)


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


_TEXT_RE = re.compile(r"<text\s+([^>]*?)>(.*?)</text>", re.DOTALL)


def _svg_text_nodes(svg):
    """Every <text> as {text, x, fill} — NOT just the string. The x-attribute and the
    `fill:` colour live on each <text>, so parsing them lets the guard catch a coordinate
    or colour swap that leaves the text content + document order untouched (#50 verify R2)."""
    nodes = []
    for attrs, content in _TEXT_RE.findall(svg):
        xm = re.search(r'\bx="([-\d.]+)"', attrs)
        fm = re.search(r"fill:\s*(#[0-9a-fA-F]{6})", attrs)
        nodes.append({
            "text": re.sub(r"\s+", " ", content).strip(),
            "x": float(xm.group(1)) if xm else None,
            "fill": fm.group(1).lower() if fm else None,
        })
    return nodes


def _assert_svg_faithful(svg):
    """Raise AssertionError unless the committed SVG faithfully encodes the snapshot.

    Closes the whole 'another uncovered <text>' class (#50 verify R3): it compares the
    COMPLETE ordered <text> content to a fresh render of the same snapshot — so the title,
    BOTH column headers, every library / ecosystem / value-cell / sub-caption, AND the
    footer are covered, and a fabricated extra row or a doctored sub-caption / header
    changes the list. Version-independent: <text> STRINGS are stable across matplotlib
    (only coordinates / bytes drift), so this never false-fails on a matplotlib bump.

    Then, for the value cells only, it checks fill-COLOUR and column ORDER (x) so a
    coordinate or colour swap that leaves the text intact still fails."""
    committed = _svg_text_nodes(svg)
    expected = _svg_text_nodes(chart.render_svg(SAMPLE))
    # (1) every <text> string == the snapshot render — title / headers / cells / subs /
    #     footer / no-extras. Catches stale, tampered, sub-caption lies, header swaps.
    assert [n["text"] for n in committed] == [n["text"] for n in expected], \
        "committed SVG text content diverged from the snapshot render (stale / tampered / extra row)"
    # (2) value cells (body[i+2]=LiveDocs, body[i+4]=context7): a coord/colour swap keeps the
    #     text but moves x / fill, so check colour == expected + column order (ld.x < c7.x).
    cbody, ebody = committed[4:-1], expected[4:-1]
    assert cbody and len(cbody) % 6 == 0, f"unexpected SVG <text> layout ({len(committed)} nodes)"
    for i in range(0, len(cbody), 6):
        lib = cbody[i]["text"]
        ld, c7, eld, ec7 = cbody[i + 2], cbody[i + 4], ebody[i + 2], ebody[i + 4]
        assert ld["fill"] == eld["fill"], f"{lib}: LiveDocs fill {ld['fill']} != {eld['fill']} (colour swap?)"
        assert c7["fill"] == ec7["fill"], f"{lib}: context7 fill {c7['fill']} != {ec7['fill']} (colour swap?)"
        assert ld["x"] is not None and c7["x"] is not None, f"{lib}: cell x missing"
        assert ld["x"] < c7["x"], f"{lib}: columns swapped (LiveDocs x {ld['x']} !< context7 x {c7['x']})"

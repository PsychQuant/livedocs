"""Unit tests for the per-library vs-context7 chart (issue #50).

No matplotlib rendering is asserted byte-for-byte here (that's platform/version
fragile); instead the tests pin the DATA the chart is built from and the version
tokens that must survive into the committed SVG — the version-independent drift
guard that keeps the front-page competitive numbers 'measured, not asserted'.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVAL_DIR = os.path.dirname(HERE)
sys.path.insert(0, EVAL_DIR)
import chart  # noqa: E402
from compare_context7 import load_sample  # noqa: E402

SAMPLE = load_sample()
SVG_PATH = os.path.abspath(os.path.join(EVAL_DIR, "..", "..", "docs", "assets", "vs-context7-freshness.svg"))


def test_chart_rows_is_verbatim_projection_of_snapshot():
    # Data-guard: chart_rows invents nothing — every field is the snapshot's, and the
    # current/stale verdict comes from the harness's judge_row (single source of truth).
    rows = chart.chart_rows(SAMPLE)
    assert len(rows) == len(SAMPLE["results"])
    by_lib = {r["library"]: r for r in rows}
    assert all(r["livedocs_current"] for r in rows)        # current on every lib, by construction
    assert not any(r["context7_current"] for r in rows)    # stale on every lib in this forward-selected set
    assert by_lib["react"]["ground_truth"] == "19.2.7" and by_lib["react"]["context7_version"] == "v18"
    assert by_lib["vite"]["context7_version"] == "8.0.10" and by_lib["vite"]["context7_status"] == "one minor behind"
    assert by_lib["fastapi"]["context7_version"] is None and by_lib["fastapi"]["context7_status"] == "version-less"


def test_render_svg_contains_every_snapshot_version_token():
    # The competitive numbers rendered in the SVG MUST be the snapshot's — the greppable
    # drift surface (fonttype='none' keeps version strings as real <text>).
    svg = chart.render_svg(SAMPLE)
    for t in _snapshot_tokens():
        assert t in svg, f"snapshot token {t!r} missing from rendered SVG"


def test_render_svg_is_deterministic():
    # Byte-stable across renders — required for the committed-SVG `--emit-chart --check`.
    assert chart.render_svg(SAMPLE) == chart.render_svg(SAMPLE)


def test_committed_svg_matches_snapshot():
    # Drift guard on the COMMITTED asset: a stale committed SVG (or a hand-edited label)
    # drops a snapshot token and fails loud. Version-independent (text tokens, not bytes),
    # so a matplotlib upgrade that reflows the SVG doesn't break this — only a wrong number does.
    assert os.path.exists(SVG_PATH), \
        "committed SVG missing — run: python3 evals/look-up/compare_context7.py --emit-chart --write"
    svg = open(SVG_PATH, encoding="utf-8").read()
    for t in _snapshot_tokens():
        assert t in svg, f"committed SVG is stale — {t!r} missing; run --emit-chart --write"


def test_emit_chart_check_in_sync():
    # Drive the CLI byte-guard: the committed SVG matches the current snapshot render.
    from compare_context7 import main
    assert main(["--emit-chart", "--check"]) == 0


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
    # Drive --emit-chart --write (+ _atomic_write, makedirs) to a temp asset, then --check → 0.
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


def _snapshot_tokens():
    rows = chart.chart_rows(SAMPLE)
    return ([r["ground_truth"] for r in rows]
            + [r["context7_version"] for r in rows if r["context7_version"]]
            + [SAMPLE["captured_at"]])

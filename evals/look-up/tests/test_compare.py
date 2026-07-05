"""Unit tests for the vs-context7 comparison harness (issue #27).

All stubbed — no live registry / MCP calls. Validates the comparison logic:
LiveDocs freshness is *computed* against registry ground truth; context7's
freshness is a *recorded human judgment* (its answer is prose, not a clean
version string), so the harness trusts the captured `is_current` flag.
"""
import json
import os
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
EVAL_DIR = os.path.dirname(HERE)
sys.path.insert(0, EVAL_DIR)
from compare_context7 import version_matches, judge_row, tally, render_table  # noqa: E402


def test_version_matches_exact():
    assert version_matches("19.2.7", "19.2.7") is True


def test_version_matches_contains():
    assert version_matches("the current release is 19.2.7 (from npm)", "19.2.7") is True


def test_version_matches_mismatch():
    assert version_matches("v18", "19.2.7") is False
    # the meaningful boundary direction (#27 verify fix): searching for the shorter
    # "8.1" inside the longer "8.1.3" must NOT match — a prefix is not the release.
    assert version_matches("8.1.3", "8.1") is False


def test_version_matches_boundary_forms():
    # v-prefix and @-pinned forms still match the release token
    assert version_matches("v19.2.7", "19.2.7") is True
    assert version_matches("react@19.2.7", "19.2.7") is True
    # a trailing sentence period is fine (not a longer version)
    assert version_matches("the latest is 19.2.7.", "19.2.7") is True
    # a SUFFIX of a longer version must not match (round-2 fix: dot-prefix guard)
    assert version_matches("1.19.2.7", "19.2.7") is False


def test_judge_row_context7_missing_is_none():
    # a MISSING is_current is unknown (None), not silently scored stale (fairness fix)
    entry = {
        "id": "x", "library": "x", "ground_truth": "1.0.0",
        "livedocs": {"answer": "1.0.0"},
        "context7": {"answer": "no judgment recorded"},   # no is_current key
    }
    assert judge_row(entry)["context7_current"] is None


def test_version_matches_empty():
    assert version_matches("", "19.2.7") is False
    assert version_matches("19.2.7", "") is False


def test_judge_row_livedocs_current_is_computed():
    entry = {
        "id": "react-npm", "library": "react", "ground_truth": "19.2.7",
        "livedocs": {"answer": "19.2.7"},
        "context7": {"answer": "top match pinned v18", "is_current": False},
    }
    row = judge_row(entry)
    assert row["livedocs_current"] is True          # computed from answer vs truth
    assert row["context7_current"] is False         # trusted recorded judgment


def test_judge_row_context7_trusted_not_reparsed():
    # context7 answer happens to contain the current version string, but the
    # recorded judgment is False (e.g. it was a lower-ranked entry, not the
    # default). The harness MUST honor the recorded judgment, not re-parse.
    entry = {
        "id": "x", "library": "x", "ground_truth": "1.0.0",
        "livedocs": {"answer": "1.0.0"},
        "context7": {"answer": "default is old; 1.0.0 exists only in a lower entry", "is_current": False},
    }
    assert judge_row(entry)["context7_current"] is False


def test_judge_row_missing_ground_truth_no_crash():
    entry = {
        "id": "x", "library": "x", "ground_truth": None,
        "livedocs": {"answer": "1.0.0"},
        "context7": {"answer": "whatever", "is_current": False},
    }
    row = judge_row(entry)
    assert row["livedocs_current"] is None          # unknown, not a crash


def test_tally():
    rows = [
        {"livedocs_current": True, "context7_current": False},
        {"livedocs_current": True, "context7_current": False},
        {"livedocs_current": True, "context7_current": True},
        {"livedocs_current": None, "context7_current": False},  # unknown excluded from denom
    ]
    t = tally(rows)
    assert t["n"] == 3                               # None row excluded
    assert t["livedocs_current"] == 3
    assert t["context7_current"] == 1


def test_render_table_has_header_and_rows():
    rows = [
        {"library": "react", "ground_truth": "19.2.7",
         "livedocs_answer": "19.2.7", "livedocs_current": True,
         "context7_answer": "v18", "context7_current": False},
    ]
    md = render_table(rows)
    assert "| react |" in md
    assert "19.2.7" in md
    assert md.count("\n") >= 2                        # header + separator + >=1 row


def test_emit_readme_block_matches_committed_readme():
    # Drift guard: the README vs-context7 block (issue #50: an SVG image embed + caption)
    # MUST be byte-identical to what the harness emits from the dated snapshot. Makes a
    # hand-edited / stale caption or capture-date a RED suite (measured, never asserted —
    # #27/#29). The competitive NUMBERS live in the SVG, guarded separately by test_chart.py.
    import re
    from compare_context7 import render_readme_block, load_sample, judge_row, README_BEGIN, README_END
    sample = load_sample()
    rows = [judge_row(e) for e in sample.get("results", [])]
    emitted = render_readme_block(rows, sample.get("captured_at"))
    readme_path = os.path.abspath(os.path.join(EVAL_DIR, "..", "..", "README.md"))
    with open(readme_path, encoding="utf-8") as f:
        readme = f.read()
    m = re.search(re.escape(README_BEGIN) + r".*?" + re.escape(README_END), readme, re.DOTALL)
    assert m, "README is missing the vs-context7 sentinel block"
    assert m.group(0).strip() == emitted.strip(), (
        "README vs-context7 block is stale — run: "
        "python3 evals/look-up/compare_context7.py --emit-readme --write"
    )


def test_check_via_main_in_sync():
    # #46 verify (DA): the fail-loud exit path lives in main(), but the drift test
    # re-implements the regex instead of driving main(). Drive the ACTUAL CLI entry:
    # --emit-readme --check against the committed README returns 0.
    from compare_context7 import main
    assert main(["--emit-readme", "--check"]) == 0


def test_check_via_main_flags_drift(tmp_path):
    # Feed a sample whose captured_at differs → emitted block no longer matches the
    # committed README → --check must return 1. This exercises the real fail-loud
    # exit code (main() returns 1), not a re-derived comparison.
    import json as _json
    from compare_context7 import main, load_sample, SAMPLE_PATH
    sample = load_sample(SAMPLE_PATH)
    sample["captured_at"] = "2020-01-01"          # valid date, but ≠ the committed block's
    drifted = tmp_path / "drifted_sample.json"
    drifted.write_text(_json.dumps(sample), encoding="utf-8")
    assert main(["--emit-readme", "--check", "--sample", str(drifted)]) == 1


def test_check_write_require_emit_readme():
    # #46 verify: --check / --write without --emit-readme must be a NON-ZERO usage error,
    # and --check + --write together is mutually exclusive. Round-2 DA: assert the exit
    # CODE, not just that SystemExit was raised — sys.exit(0) is also a SystemExit, so a
    # bare raises() check wouldn't catch the guard degrading to a false pass.
    import pytest
    from compare_context7 import main
    for argv in (["--check"], ["--write"], ["--emit-readme", "--check", "--write"]):
        with pytest.raises(SystemExit) as e:
            main(argv)
        assert e.value.code != 0, f"{argv} must fail loud (non-zero), got {e.value.code}"


def test_render_readme_block_rejects_bad_captured_at():
    # #46 verify: a missing/malformed date must fail loud (never ship "captured None"),
    # a value carrying markup can't inject a sentinel, and (round 2) a calendar-impossible
    # or Unicode-digit date is rejected too.
    import pytest
    from compare_context7 import render_readme_block
    rows = [{"livedocs_current": True, "context7_current": False}]
    for bad in (None, "", "captured None", "2026-07-02 --> <!-- END vs-context7 -->",
                "2026/07/02", "2026-99-99", "9999-99-99", "٢٠٢٦-٠٧-٠٢"):
        with pytest.raises(ValueError):
            render_readme_block(rows, bad)
    # a real ISO date still round-trips (no false positive)
    assert "2026-07-02" in render_readme_block(rows, "2026-07-02")


def test_check_flags_orphaned_second_block_via_main(tmp_path, monkeypatch):
    # #46 verify round 2 (MEDIUM): an orphaned second BEGIN (stale chart, no matching END)
    # still renders on GitHub — main --check must catch it (exit 1), not only complete pairs.
    import compare_context7 as C
    block = f"{C.README_BEGIN}\n```text\nchart\n```\n{C.README_END}"
    readme = tmp_path / "README.md"
    readme.write_text(f"# X\n{block}\n\n{C.README_BEGIN}\nstale 5/6\n", encoding="utf-8")  # 2 BEGIN, 1 END
    monkeypatch.setattr(C, "readme_path", lambda: str(readme))
    assert C.main(["--emit-readme", "--check"]) == 1


def test_write_round_trips_via_main(tmp_path, monkeypatch):
    # #46 verify round 2: drive the real --write path (+ _atomic_write) end-to-end, then
    # --check must confirm in sync (exit 0). The write path was previously inspection-only.
    import compare_context7 as C
    stale = f"{C.README_BEGIN}\n```text\nstale\n```\n{C.README_END}"
    readme = tmp_path / "README.md"
    readme.write_text(f"# X\n{stale}\nfooter\n", encoding="utf-8")
    monkeypatch.setattr(C, "readme_path", lambda: str(readme))
    assert C.main(["--emit-readme", "--write"]) == 0
    assert C.main(["--emit-readme", "--check"]) == 0            # now in sync with the snapshot
    assert "footer" in readme.read_text(encoding="utf-8")       # content outside the block preserved


def test_replace_readme_block_requires_exactly_one():
    # #46 verify (HIGH): the guard rests on exactly-one-block. Zero or two sentinel
    # pairs must raise, so a second stale block can't slip past --check / --write.
    import pytest
    from compare_context7 import replace_readme_block, README_BEGIN, README_END
    one = f"top\n{README_BEGIN}\nX\n{README_END}\nbottom"
    assert "NEW" in replace_readme_block(one, "NEW")
    two = f"{README_BEGIN}\nA\n{README_END}\nmid\n{README_BEGIN}\nB\n{README_END}"
    with pytest.raises(ValueError):
        replace_readme_block(two, "NEW")
    with pytest.raises(ValueError):
        replace_readme_block("no sentinels at all", "NEW")


def test_sample_covers_corpus():
    # compare_corpus.yaml is the canonical library list; the recorded sample must
    # cover every one of them (so adding a lib to the corpus without recording its
    # head-to-head data is caught here, not silently under-reported).
    with open(os.path.join(EVAL_DIR, "compare_corpus.yaml"), encoding="utf-8") as f:
        corpus_ids = {c["id"] for c in yaml.safe_load(f)}
    with open(os.path.join(EVAL_DIR, "compare_context7_sample.json"), encoding="utf-8") as f:
        sample_ids = {r["id"] for r in json.load(f)["results"]}
    assert corpus_ids <= sample_ids, f"sample missing corpus libs: {corpus_ids - sample_ids}"

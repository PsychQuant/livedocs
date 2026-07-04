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


def test_render_bar_chart_structural():
    # Issue #46: the README top block is a Unicode bar chart of the *same* tally()
    # contested-set counts. Assert structure, not golden bar art: both tools labeled,
    # the N/M numbers match the tally, the honesty caveat travels with the chart, and
    # a higher count means a more-filled bar (so the visual can't invert the number).
    from compare_context7 import render_bar_chart  # in-function: clean RED before it exists
    t = {"n": 6, "livedocs_current": 6, "context7_current": 0}
    chart = render_bar_chart(t, "2026-07-02")
    assert "LiveDocs" in chart and "context7" in chart
    assert "6/6" in chart and "0/6" in chart           # counts match the tally
    assert "2026-07-02" in chart                        # dated capture is visible
    assert "measured, not asserted" in chart            # load-bearing honesty caveat inline
    livedocs_line = next(l for l in chart.splitlines() if "LiveDocs" in l)
    context7_line = next(l for l in chart.splitlines() if "context7" in l)
    # bar length ∝ count/n → LiveDocs (6/6) more filled than context7 (0/6)
    assert livedocs_line.count("█") > context7_line.count("█")


def test_render_bar_chart_zero_n_no_crash():
    # Empty contested set must not ZeroDivisionError.
    from compare_context7 import render_bar_chart
    chart = render_bar_chart({"n": 0, "livedocs_current": 0, "context7_current": 0}, "2026-07-02")
    assert "0/0" in chart


def test_emit_readme_block_matches_committed_readme():
    # Issue #46 drift guard: the README vs-context7 block MUST be byte-identical to what
    # the harness emits from the dated snapshot. Makes a hand-edited / stale competitive
    # number a RED suite (the project iron rule: measured, never asserted — #27/#29).
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
    # #46 verify: --check / --write without --emit-readme must be a usage error
    # (argparse SystemExit), NOT a silent exit-0 false pass.
    import pytest
    from compare_context7 import main
    with pytest.raises(SystemExit):
        main(["--check"])
    with pytest.raises(SystemExit):
        main(["--write"])


def test_render_readme_block_rejects_bad_captured_at():
    # #46 verify: a missing/malformed date must fail loud (never ship "captured None"),
    # and a value carrying markup can't inject a sentinel into the emitted block.
    import pytest
    from compare_context7 import render_readme_block
    rows = [{"livedocs_current": True, "context7_current": False}]
    for bad in (None, "", "captured None", "2026-07-02 --> <!-- END vs-context7 -->", "2026/07/02"):
        with pytest.raises(ValueError):
            render_readme_block(rows, bad)


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

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
    # a prefix must not count as a match (8.1 must not match 8.1.3)
    assert version_matches("8.1", "8.1.3") is False


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


def test_sample_covers_corpus():
    # compare_corpus.yaml is the canonical library list; the recorded sample must
    # cover every one of them (so adding a lib to the corpus without recording its
    # head-to-head data is caught here, not silently under-reported).
    with open(os.path.join(EVAL_DIR, "compare_corpus.yaml"), encoding="utf-8") as f:
        corpus_ids = {c["id"] for c in yaml.safe_load(f)}
    with open(os.path.join(EVAL_DIR, "compare_context7_sample.json"), encoding="utf-8") as f:
        sample_ids = {r["id"] for r in json.load(f)["results"]}
    assert corpus_ids <= sample_ids, f"sample missing corpus libs: {corpus_ids - sample_ids}"

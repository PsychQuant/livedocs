"""Corpus coverage guards (issue #22, from the #20 verify ensemble).

Ensures the seed corpus actually exercises (a) the golden oracle path end-to-end,
not just its unit test, and (b) over-trigger discrimination against a hard
negative that names a real library but should not fetch.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from run_eval import load_corpus  # noqa: E402
from oracle import evaluate_correctness  # noqa: E402

CORPUS = load_corpus()
KNOWN_LIBS = ("react", "hono", "fastapi", "tokio", "express", "vue", "django")


def test_corpus_has_a_golden_case_that_evaluates():
    golden = [c for c in CORPUS if (c.get("oracle") or {}).get("type") == "golden"]
    assert golden, "corpus must exercise the golden oracle path (issue #22 gap #11)"
    for c in golden:
        oc = c["oracle"]
        assert "expect" in oc and "last_verified" in oc, "golden case needs expect + last_verified"
        # passes when the answer contains the expected substring, fails otherwise
        assert evaluate_correctness(c, triggered=True, final_text=f"... {oc['expect']} ...")[0] is True
        assert evaluate_correctness(c, triggered=True, final_text="something else")[0] is False


def test_corpus_has_a_library_named_negative():
    # A negative that names a real library but should NOT trigger (issue #22 gap #12).
    named = [
        c for c in CORPUS
        if c["category"] == "negative"
        and c.get("expected_trigger") is False
        and any(lib in c["prompt"].lower() for lib in KNOWN_LIBS)
    ]
    assert named, "corpus must include a negative that names a real library yet should not fetch"

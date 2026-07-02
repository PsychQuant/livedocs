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


def test_corpus_covers_explicit_invocation_shapes():
    # Explicit /livedocs:look-up invocation routing (issue #38): every documented
    # argument shape gets at least one corpus case, so regressions in the
    # explicit-doc-lookup contract show up in the eval, not just in prose review.
    explicit = [c for c in CORPUS if c["category"] == "explicit"]
    assert explicit, "corpus must exercise explicit /livedocs:look-up invocation (issue #38)"
    prompts = " || ".join(c["prompt"] for c in explicit)
    for shape_marker in (
        "/livedocs:look-up R",        # language (R: not-resolved degrade until #35 lands)
        "@",                          # name@version pin
        "dplyr",                      # named-only ecosystem (cran)
        "https://",                   # URL shape
        "openapi.json",               # named API schema path
        "javascript",                 # javascript -> node normalization
    ):
        assert shape_marker in prompts, f"missing explicit shape case: {shape_marker}"
    # Bare invocation loads routing guidance without demanding an argument —
    # scored as a non-trigger (no library question was asked).
    bare = [c for c in explicit if c["prompt"].strip() == "/livedocs:look-up"]
    assert bare and all(c["expected_trigger"] is False for c in bare), \
        "explicit category needs a bare no-argument case with expected_trigger: false"


def test_corpus_has_a_library_named_negative():
    # A negative that names a real library but should NOT trigger (issue #22 gap #12).
    named = [
        c for c in CORPUS
        if c["category"] == "negative"
        and c.get("expected_trigger") is False
        and any(lib in c["prompt"].lower() for lib in KNOWN_LIBS)
    ]
    assert named, "corpus must include a negative that names a real library yet should not fetch"

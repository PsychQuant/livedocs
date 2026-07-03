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


# Explicit /livedocs:look-up routing coverage (issue #38): one case per
# documented argument shape, id-keyed so a removed/mislabeled case fails loudly.
# Values: (expected_trigger, oracle type, expected_tools set).
EXPLICIT_EXPECTATIONS = {
    "explicit-lookup-r-en":           (True, "structural", {"introspect"}),
    "explicit-lookup-pin-en":         (True, "structural", {"resolve_source", "fetch_docs"}),
    "explicit-lookup-scoped-pin-en":  (True, "structural", {"resolve_source", "fetch_docs"}),
    "explicit-lookup-crates-pin-en":  (True, "structural", {"resolve_source", "fetch_docs"}),
    "explicit-lookup-cran-zh":        (True, "structural", {"resolve_source", "fetch_docs"}),
    "explicit-lookup-docs-url-en":    (True, "structural", {"resolve_source", "fetch_docs"}),
    "explicit-lookup-openapi-url-en": (True, "structural", {"introspect"}),
    "explicit-lookup-js-alias-en":    (True, "structural", {"introspect"}),
    "explicit-lookup-shadow-gh-en":   (True, "structural", {"resolve_source", "fetch_docs"}),
    "explicit-lookup-noargs-en":      (False, "none", set()),
}


def test_corpus_covers_explicit_invocation_shapes():
    # Shapes locked: R language degrade, simple pin, scoped last-@ pin,
    # non-npm/pypi pin (serde -> not applied), named-only cran + zh topic,
    # docs-site URL, named openapi.json schema path, javascript->node alias,
    # same-name shadowing (gh: npm package wins over CLI), bare no-arg.
    explicit = {c["id"]: c for c in CORPUS if c["category"] == "explicit"}
    assert set(explicit) == set(EXPLICIT_EXPECTATIONS), (
        f"explicit case set drifted: extra={set(explicit) - set(EXPLICIT_EXPECTATIONS)}, "
        f"missing={set(EXPLICIT_EXPECTATIONS) - set(explicit)}"
    )
    for cid, (trig, otype, tools) in EXPLICIT_EXPECTATIONS.items():
        c = explicit[cid]
        assert c["expected_trigger"] is trig, f"{cid}: expected_trigger != {trig}"
        assert (c.get("oracle") or {}).get("type") == otype, f"{cid}: oracle.type != {otype}"
        assert set(c.get("expected_tools") or []) == tools, f"{cid}: expected_tools != {tools}"
    # Boundary-exact prompt checks (not big-string substring matching):
    assert explicit["explicit-lookup-r-en"]["prompt"] == "/livedocs:look-up R"
    assert explicit["explicit-lookup-scoped-pin-en"]["prompt"].count("@") == 2, \
        "scoped pin case must contain TWO @ to exercise the last-@ split rule"
    assert explicit["explicit-lookup-crates-pin-en"]["prompt"] == "/livedocs:look-up serde@1.0.100"
    assert explicit["explicit-lookup-shadow-gh-en"]["prompt"] == "/livedocs:look-up gh"
    assert explicit["explicit-lookup-noargs-en"]["prompt"].strip() == "/livedocs:look-up"
    assert any("一" <= ch <= "鿿" for ch in explicit["explicit-lookup-cran-zh"]["prompt"]), \
        "lang:zh explicit case must actually contain Chinese text"


def test_corpus_has_a_library_named_negative():
    # A negative that names a real library but should NOT trigger (issue #22 gap #12).
    named = [
        c for c in CORPUS
        if c["category"] == "negative"
        and c.get("expected_trigger") is False
        and any(lib in c["prompt"].lower() for lib in KNOWN_LIBS)
    ]
    assert named, "corpus must include a negative that names a real library yet should not fetch"


# expected_args coverage (issue #38 verify): the arg-sensitive shapes — where the
# right tool firing is not enough — must pin the actual resolve_source inputs so a
# mis-split name@version or a dropped ecosystem pin is caught, not silently passed.
EXPECTED_ARGS = {
    "explicit-lookup-pin-en":        {"resolve_source": {"library": "react", "version": "18"}},
    "explicit-lookup-cran-zh":       {"resolve_source": {"library": "dplyr", "ecosystem": "cran"}},
    "explicit-lookup-scoped-pin-en": {"resolve_source": {"library": "@types/node", "version": "20"}},
    "explicit-lookup-crates-pin-en": {"resolve_source": {"library": "serde", "ecosystem": "crates", "version": "1.0.100"}},
}


def test_corpus_arg_sensitive_cases_pin_expected_args():
    explicit = {c["id"]: c for c in CORPUS if c["category"] == "explicit"}
    for cid, want in EXPECTED_ARGS.items():
        c = explicit[cid]
        got = c.get("expected_args")
        assert got == want, f"{cid}: expected_args drifted — got {got}, want {want}"
        # every tool named in expected_args must also be in expected_tools (so the
        # route check and the arg check stay consistent).
        for tool in got:
            assert tool in (c.get("expected_tools") or []), \
                f"{cid}: expected_args tool '{tool}' not in expected_tools"

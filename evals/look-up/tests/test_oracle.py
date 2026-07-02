"""TDD for oracle correctness checks.

The self_check oracle is deliberately rot-proof: it fetches the registry version
at eval time and asserts it appears in the answer. Tests stub the fetch so they
run offline and deterministically.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from oracle import self_check, structural, golden, evaluate_correctness  # noqa: E402


def test_self_check_passes_when_current_version_in_answer():
    ok, _ = self_check("The latest tokio is 1.40.0 as of today.",
                       library="tokio", ecosystem="crates",
                       fetch_fn=lambda lib, eco: "1.40.0")
    assert ok is True


def test_self_check_fails_when_answer_lacks_current_version():
    ok, detail = self_check("tokio is pretty up to date these days.",
                            library="tokio", ecosystem="crates",
                            fetch_fn=lambda lib, eco: "1.40.0")
    assert ok is False
    assert "1.40.0" in detail  # detail names what was expected


def test_self_check_inconclusive_when_registry_unreachable():
    ok, detail = self_check("anything", library="x", ecosystem="npm",
                            fetch_fn=lambda lib, eco: None)
    assert ok is False
    assert "registry" in detail.lower()


def test_structural_passes_on_trigger_plus_nonempty_answer():
    ok, _ = structural(triggered=True, final_text="Use app.add_middleware(CORSMiddleware, ...).")
    assert ok is True


def test_structural_fails_when_not_triggered():
    ok, _ = structural(triggered=False, final_text="Some answer from memory.")
    assert ok is False


def test_structural_fails_on_empty_or_timeout_answer():
    assert structural(triggered=True, final_text="")[0] is False
    assert structural(triggered=True, final_text="__timeout__")[0] is False


def test_golden_substring_match():
    assert golden("The answer is 42.", expect="42")[0] is True
    assert golden("The answer is 41.", expect="42")[0] is False


def test_evaluate_dispatches_on_oracle_type():
    case = {"oracle": {"type": "self_check", "library": "tokio", "ecosystem": "crates"}}
    ok, _ = evaluate_correctness(case, triggered=True, final_text="tokio 1.40.0",
                                 fetch_fn=lambda lib, eco: "1.40.0")
    assert ok is True

    case2 = {"oracle": {"type": "structural"}}
    ok2, _ = evaluate_correctness(case2, triggered=True, final_text="hi")
    assert ok2 is True

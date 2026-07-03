"""TDD for the pure threshold-judging core of the runner.

judge_case decides pass/fail from a case's measured rates + thresholds. Keeping
it pure means the statistical policy (positive trigger floor / negative
false-trigger ceiling / correctness floor) is tested without any live API calls.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from run_eval import (judge_case, run_case, thresholds_reachable,  # noqa: E402
                      DEFAULT_THRESHOLDS, args_match)

TH = DEFAULT_THRESHOLDS  # trigger_min=0.8, false_trigger_max=0.2, correctness_min=0.8


def _pos(oracle_type="structural"):
    return {"id": "p", "category": "config", "prompt": "q", "expected_trigger": True,
            "oracle": {"type": oracle_type}}


def _neg():
    return {"id": "n", "category": "negative", "prompt": "q", "expected_trigger": False,
            "oracle": {"type": "none"}}


def test_positive_passes_when_trigger_and_correctness_above_floor():
    ok, _ = judge_case(_pos(), trigger_rate=1.0, correctness_rate=1.0, th=TH)
    assert ok is True


def test_positive_fails_on_low_trigger_rate():
    ok, reason = judge_case(_pos(), trigger_rate=0.4, correctness_rate=1.0, th=TH)
    assert ok is False
    assert "trigger" in reason.lower()


def test_positive_fails_on_low_correctness_even_if_triggered():
    ok, reason = judge_case(_pos("self_check"), trigger_rate=1.0, correctness_rate=0.3, th=TH)
    assert ok is False
    assert "correct" in reason.lower()


def test_positive_none_oracle_ignores_correctness():
    # a positive with no correctness oracle passes on trigger alone
    ok, _ = judge_case(_pos("none"), trigger_rate=1.0, correctness_rate=0.0, th=TH)
    assert ok is True


def test_negative_passes_when_false_trigger_below_ceiling():
    ok, _ = judge_case(_neg(), trigger_rate=0.0, correctness_rate=0.0, th=TH)
    assert ok is True


def test_negative_fails_on_over_triggering():
    ok, reason = judge_case(_neg(), trigger_rate=0.6, correctness_rate=0.0, th=TH)
    assert ok is False
    assert "over-trigger" in reason.lower() or "false" in reason.lower()


# ── threshold reachability (#1) ───────────────────────────────────────────────

def test_thresholds_collapse_at_n3():
    pos_ok, neg_ok = thresholds_reachable(3, TH)
    assert pos_ok is False   # 80% floor requires 3/3 = 100% at N=3
    assert neg_ok is False   # 20% ceiling requires 0/3 at N=3


def test_thresholds_non_degenerate_at_n5():
    pos_ok, neg_ok = thresholds_reachable(5, TH)
    assert pos_ok is True    # 4/5 = 80% reachable
    assert neg_ok is True    # 1/5 = 20% reachable


# ── run_case failure / inconclusive handling (#2, #3, #4) ─────────────────────

def _fake(triggered, ok, final="answer"):
    return lambda prompt, cwd=None: (triggered, [], final, ok, [])


def test_all_runs_failed_is_inconclusive_not_pass():
    # #2: a broken env (every run ok=False) must NOT score a negative as PASS.
    r = run_case(_neg(), runs=3, cwd=None, run_fn=_fake(False, ok=False))
    assert r.get("inconclusive") is True
    assert "failed" in r["reason"].lower()
    assert "passed" not in r  # no PASS/FAIL verdict on an all-failed case


def test_failed_runs_excluded_from_denominator():
    # 2 good triggering runs + 1 failed run → trigger_rate over the 2 valid = 100%.
    calls = {"n": 0}
    def run_fn(prompt, cwd=None):
        calls["n"] += 1
        return (True, [], "x", calls["n"] != 2, [])  # 2nd run fails
    r = run_case(_pos("none"), runs=3, cwd=None, run_fn=run_fn)
    assert r["failed_runs"] == 1
    assert r["trigger_rate"] == 1.0   # 2/2 valid, not 2/3
    assert r["passed"] is True


def _self_check_case():
    return {"id": "v", "category": "version", "prompt": "q", "expected_trigger": True,
            "oracle": {"type": "self_check", "library": "tokio", "ecosystem": "crates"}}


def test_self_check_registry_unreachable_is_inconclusive():
    # #4: an unreachable registry must not fail the case as "wrong answer".
    r = run_case(_self_check_case(), runs=3, cwd=None,
                 run_fn=_fake(True, ok=True, final="1.40.0"),
                 fetch_fn=lambda lib, eco: None)
    assert r.get("inconclusive") is True
    assert "registry" in r["reason"].lower()


def test_self_check_correct_when_answer_has_current_version():
    r = run_case(_self_check_case(), runs=3, cwd=None,
                 run_fn=_fake(True, ok=True, final="the version is 1.40.0"),
                 fetch_fn=lambda lib, eco: "1.40.0")
    assert r["passed"] is True
    assert r["correctness_rate"] == 1.0


def test_route_matches_compares_short_tool_names():
    # issue #38: explicit-category route check — fully-qualified stream names
    # vs corpus short names; empty expectation = unconstrained.
    from run_eval import route_matches
    fired = ["mcp__plugin_livedocs_livedocs__introspect"]
    assert route_matches(["introspect"], fired) is True
    assert route_matches(["resolve_source", "fetch_docs"], fired) is False
    assert route_matches([], []) is True


def test_run_case_explicit_route_mismatch_scores_incorrect():
    # issue #38: an explicit case whose expected route did not fire must not
    # score correct just because SOME LiveDocs tool fired (structural oracle).
    case = {"id": "x", "category": "explicit", "prompt": "/livedocs:look-up y",
            "expected_trigger": True, "expected_tools": ["introspect"],
            "oracle": {"type": "structural"}}
    def wrong_route(prompt, cwd=None):
        return True, ["mcp__plugin_livedocs_livedocs__fetch_docs"], "an answer", True, []
    r = run_case(case, runs=2, cwd=None, run_fn=wrong_route)
    assert r["trigger_rate"] == 1.0
    assert r["correctness_rate"] == 0.0


# ── args_match: right tool, wrong args (issue #38 verify) ─────────────────────

def test_args_match_subset_and_string_normalized():
    calls = [{"name": "resolve_source", "input": {"library": "react", "version": 18, "extra": "x"}}]
    assert args_match({"resolve_source": {"library": "react", "version": "18"}}, calls) is True
    assert args_match({}, calls) is True                       # empty = unconstrained
    assert args_match({"resolve_source": {"library": "vue"}}, calls) is False   # wrong value
    assert args_match({"introspect": {"target": "r"}}, calls) is False          # tool never called


def test_args_match_catches_last_at_mis_split():
    # @types/node@20 mis-split to library "@types" (version node@20) must fail.
    good = [{"name": "resolve_source", "input": {"library": "@types/node", "version": "20"}}]
    bad = [{"name": "resolve_source", "input": {"library": "@types", "version": "node@20"}}]
    want = {"resolve_source": {"library": "@types/node", "version": "20"}}
    assert args_match(want, good) is True
    assert args_match(want, bad) is False


def test_run_case_explicit_wrong_args_scores_incorrect():
    # issue #38 verify: the RIGHT tool fires (resolve_source) but with a mis-split
    # library — route passes, args do not → not correct.
    case = {"id": "scoped", "category": "explicit",
            "prompt": "/livedocs:look-up @types/node@20", "expected_trigger": True,
            "expected_tools": ["resolve_source"],
            "expected_args": {"resolve_source": {"library": "@types/node", "version": "20"}},
            "oracle": {"type": "structural"}}
    def mis_split(prompt, cwd=None):
        return (True, ["mcp__plugin_livedocs_livedocs__resolve_source"], "an answer", True,
                [{"name": "resolve_source", "input": {"library": "@types", "version": "node@20"}}])
    r = run_case(case, runs=2, cwd=None, run_fn=mis_split)
    assert r["trigger_rate"] == 1.0
    assert r["correctness_rate"] == 0.0   # right tool, wrong args → wrong

    def correct(prompt, cwd=None):
        return (True, ["mcp__plugin_livedocs_livedocs__resolve_source"], "an answer", True,
                [{"name": "resolve_source", "input": {"library": "@types/node", "version": "20"}}])
    r2 = run_case(case, runs=2, cwd=None, run_fn=correct)
    assert r2["correctness_rate"] == 1.0

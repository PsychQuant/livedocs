"""TDD for the pure threshold-judging core of the runner.

judge_case decides pass/fail from a case's measured rates + thresholds. Keeping
it pure means the statistical policy (positive trigger floor / negative
false-trigger ceiling / correctness floor) is tested without any live API calls.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from run_eval import judge_case, DEFAULT_THRESHOLDS  # noqa: E402

TH = DEFAULT_THRESHOLDS  # trigger_min=0.8, false_trigger_max=0.2, correctness_min=0.8


def _pos(oracle_type="structural"):
    return {"id": "p", "expected_trigger": True, "oracle": {"type": oracle_type}}


def _neg():
    return {"id": "n", "expected_trigger": False, "oracle": {"type": "none"}}


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

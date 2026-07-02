#!/usr/bin/env python3
"""docs-router eval runner.

Loads the prompt corpus, runs each prompt N times through the real Claude Code
plugin (via detect.run_prompt), scores trigger + correctness, and reports
rate-based pass/fail against thresholds. A genuinely failing prompt is the
SIGNAL this eval exists to surface — not a harness bug.

Usage:
    python3 run_eval.py                     # live, N=3, all categories
    python3 run_eval.py --runs 5 --filter version
    python3 run_eval.py --dry-run           # load + enumerate, no live calls

Exit code is non-zero if any case breaches its threshold (CI-friendly, though
this is intended as a periodic/manual eval, not per-PR).
"""
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import detect  # noqa: E402
import oracle  # noqa: E402

CORPUS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus.yaml")


@dataclass(frozen=True)
class Thresholds:
    trigger_min: float = 0.8         # positive cases: fraction that must trigger
    false_trigger_max: float = 0.2   # negative cases: fraction allowed to trigger
    correctness_min: float = 0.8     # positive cases with an oracle


DEFAULT_THRESHOLDS = Thresholds()


# ── pure judging (unit-tested) ────────────────────────────────────────────────

def judge_case(case: dict, trigger_rate: float, correctness_rate: float,
               th: Thresholds = DEFAULT_THRESHOLDS):
    """Decide pass/fail for a case from its measured rates. Pure."""
    if case.get("expected_trigger"):
        if trigger_rate < th.trigger_min:
            return False, f"trigger-rate {trigger_rate:.0%} < {th.trigger_min:.0%} floor"
        otype = (case.get("oracle") or {}).get("type", "structural")
        if otype != "none" and correctness_rate < th.correctness_min:
            return False, f"correctness-rate {correctness_rate:.0%} < {th.correctness_min:.0%} floor"
        return True, f"trigger {trigger_rate:.0%}, correctness {correctness_rate:.0%}"
    # negative
    if trigger_rate > th.false_trigger_max:
        return False, f"over-triggered {trigger_rate:.0%} > {th.false_trigger_max:.0%} ceiling"
    return True, f"false-trigger {trigger_rate:.0%} (ok)"


# ── live running ──────────────────────────────────────────────────────────────

def run_case(case: dict, runs: int, cwd: str | None,
             run_fn=detect.run_prompt, fetch_fn=oracle.fetch_latest_version) -> dict:
    triggers, corrects = [], []
    for _ in range(runs):
        triggered, _tools, final = run_fn(case["prompt"], cwd=cwd)
        triggers.append(bool(triggered))
        if case.get("expected_trigger"):
            ok, _ = oracle.evaluate_correctness(case, triggered, final, fetch_fn=fetch_fn)
            corrects.append(bool(ok))
        else:
            corrects.append(not triggered)  # not triggering IS correct for negatives
    trigger_rate = sum(triggers) / runs
    correctness_rate = sum(corrects) / runs
    passed, reason = judge_case(case, trigger_rate, correctness_rate)
    return {"id": case["id"], "category": case["category"], "runs": runs,
            "trigger_rate": trigger_rate, "correctness_rate": correctness_rate,
            "passed": passed, "reason": reason}


def load_corpus(path: str = CORPUS_PATH) -> list:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def report(results: list) -> int:
    print(f"\n{'id':32} {'cat':9} {'trig':>5} {'corr':>5}  result")
    print("-" * 72)
    for r in results:
        mark = "PASS" if r["passed"] else "FAIL"
        print(f"{r['id']:32} {r['category']:9} {r['trigger_rate']:>5.0%} "
              f"{r['correctness_rate']:>5.0%}  {mark} — {r['reason']}")
    failed = [r for r in results if not r["passed"]]
    print("-" * 72)
    print(f"{len(results) - len(failed)}/{len(results)} cases passed"
          + (f"  ({len(failed)} FAILING — this is the RED signal)" if failed else ""))
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="docs-router prompt-triggering + correctness eval")
    ap.add_argument("--runs", type=int, default=3, help="runs per prompt (statistical)")
    ap.add_argument("--filter", default=None, help="only run one category")
    ap.add_argument("--dry-run", action="store_true", help="load + enumerate, no live calls")
    ap.add_argument("--cwd", default=None, help="working dir for the headless claude runs")
    args = ap.parse_args()

    corpus = load_corpus()
    if args.filter:
        corpus = [c for c in corpus if c["category"] == args.filter]

    if args.dry_run:
        print(f"Loaded {len(corpus)} cases:")
        for c in corpus:
            trig = "trigger" if c["expected_trigger"] else "NO-trigger"
            print(f"  {c['id']:32} {c['category']:9} expect={trig:11} oracle={c['oracle']['type']}")
        print("\n(dry-run — no live `claude -p` calls made)")
        return 0

    print(f"Running {len(corpus)} cases × {args.runs} runs each (live `claude -p`)...")
    results = [run_case(c, args.runs, cwd=args.cwd) for c in corpus]
    return report(results)


if __name__ == "__main__":
    raise SystemExit(main())

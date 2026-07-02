#!/usr/bin/env python3
"""docs-router eval runner.

Loads the prompt corpus, runs each prompt N times through the real Claude Code
plugin (via detect.run_prompt), scores trigger + correctness, and reports
rate-based pass/fail against thresholds. A genuinely failing prompt is the
SIGNAL this eval exists to surface — not a harness bug.

Usage:
    python3 run_eval.py                     # live, N=5, all categories
    python3 run_eval.py --runs 5 --filter version
    python3 run_eval.py --dry-run           # load + enumerate, no live calls

Exit code is non-zero if any case FAILs or is INCONCLUSIVE (can't claim green).

Statistical note: with N runs a rate can only land on the grid {0, 1/N, …, 1}.
The default N=5 is the smallest N at which the 80%/20% thresholds are reachable
as a non-all-or-nothing bar (4/5 = 80%, 1/5 = 20%). `thresholds_reachable` +
a startup warning guard against picking an N too small for the configured floors.
"""
from __future__ import annotations

import argparse
import math
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


def thresholds_reachable(runs: int, th: Thresholds = DEFAULT_THRESHOLDS):
    """Are the floors reachable at this N without collapsing to all-or-nothing?

    Returns (positive_ok, negative_ok). At N=3 the 80% positive floor requires
    ceil(0.8*3)=3 i.e. 3/3=100% (collapsed); the 20% negative ceiling allows
    floor(0.2*3)=0 i.e. only 0/3 (collapsed). Both become non-degenerate at N=5.
    """
    pos_ok = th.trigger_min >= 1.0 or math.ceil(th.trigger_min * runs) < runs
    neg_ok = th.false_trigger_max <= 0.0 or math.floor(th.false_trigger_max * runs) >= 1
    return pos_ok, neg_ok


# ── live running ──────────────────────────────────────────────────────────────

def run_case(case: dict, runs: int, cwd: str | None,
             run_fn=detect.run_prompt, fetch_fn=oracle.fetch_latest_version) -> dict:
    base = {"id": case["id"], "category": case["category"], "runs": runs,
            "trigger_rate": 0.0, "correctness_rate": 0.0, "failed_runs": 0}

    # self_check: resolve the registry version ONCE. Unreachable → inconclusive
    # (a network outage must not be scored as a wrong answer). #4
    oc = case.get("oracle") or {}
    expected_version = None
    if oc.get("type") == "self_check":
        expected_version = fetch_fn(oc["library"], oc["ecosystem"])
        if not expected_version:
            return {**base, "inconclusive": True,
                    "reason": f"registry unreachable for {oc['library']} ({oc['ecosystem']})"}

    triggers, corrects, failed = [], [], 0
    for _ in range(runs):
        triggered, _tools, final, ok = run_fn(case["prompt"], cwd=cwd)
        if not ok:
            failed += 1          # a failed run is not evidence — exclude it (#2, #3)
            continue
        triggers.append(bool(triggered))
        if case.get("expected_trigger"):
            if expected_version is not None:
                corrects.append(expected_version in (final or ""))
            else:
                c_ok, _ = oracle.evaluate_correctness(case, triggered, final, fetch_fn=fetch_fn)
                corrects.append(bool(c_ok))
        else:
            corrects.append(not triggered)

    valid = len(triggers)
    if valid == 0:
        return {**base, "failed_runs": failed, "inconclusive": True,
                "reason": f"all {runs} runs failed (broken environment / no credits)"}

    trigger_rate = sum(triggers) / valid
    correctness_rate = sum(corrects) / valid
    passed, reason = judge_case(case, trigger_rate, correctness_rate)
    if failed:
        reason += f" [{failed}/{runs} runs failed, excluded]"
    return {**base, "trigger_rate": trigger_rate, "correctness_rate": correctness_rate,
            "failed_runs": failed, "passed": passed, "reason": reason}


def load_corpus(path: str = CORPUS_PATH) -> list:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def report(results: list) -> int:
    print(f"\n{'id':32} {'cat':9} {'trig':>5} {'corr':>5}  result")
    print("-" * 74)
    failed, inconclusive = [], []
    for r in results:
        if r.get("inconclusive"):
            inconclusive.append(r)
            print(f"{r['id']:32} {r['category']:9} {'':>5} {'':>5}  INCONCLUSIVE — {r['reason']}")
            continue
        mark = "PASS" if r["passed"] else "FAIL"
        if not r["passed"]:
            failed.append(r)
        print(f"{r['id']:32} {r['category']:9} {r['trigger_rate']:>5.0%} "
              f"{r['correctness_rate']:>5.0%}  {mark} — {r['reason']}")
    print("-" * 74)
    passed = len(results) - len(failed) - len(inconclusive)
    print(f"{passed}/{len(results)} passed"
          + (f", {len(failed)} FAILING (RED signal)" if failed else "")
          + (f", {len(inconclusive)} inconclusive" if inconclusive else ""))
    return 1 if (failed or inconclusive) else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="docs-router prompt-triggering + correctness eval")
    ap.add_argument("--runs", type=int, default=5, help="runs per prompt (statistical; >=1)")
    ap.add_argument("--filter", default=None, help="only run one category")
    ap.add_argument("--dry-run", action="store_true", help="load + enumerate, no live calls")
    ap.add_argument("--cwd", default=None, help="working dir for the headless claude runs")
    args = ap.parse_args()

    if args.runs < 1:
        ap.error("--runs must be >= 1")  # #7: no ZeroDivisionError

    pos_ok, neg_ok = thresholds_reachable(args.runs)
    if not (pos_ok and neg_ok):
        print(f"⚠ WARNING: with --runs {args.runs} the thresholds collapse to all-or-nothing "
              f"(positive floor {'unreachable' if not pos_ok else 'ok'}, "
              f"negative ceiling {'unreachable' if not neg_ok else 'ok'}). "
              f"Use --runs 5 or more so 80%/20% are non-degenerate.", file=sys.stderr)

    corpus = load_corpus()
    if args.filter:
        corpus = [c for c in corpus if c["category"] == args.filter]

    if args.dry_run:
        print(f"Loaded {len(corpus)} cases:")
        for c in corpus:
            trig = "trigger" if c["expected_trigger"] else "NO-trigger"
            print(f"  {c['id']:32} {c['category']:9} expect={trig:11} oracle={c['oracle']['type']}")
        print(f"\n(dry-run — no live `claude -p` calls; thresholds reachable at N={args.runs}: "
              f"pos={pos_ok} neg={neg_ok})")
        return 0

    print(f"Running {len(corpus)} cases × {args.runs} runs each (live `claude -p`)...")
    results = [run_case(c, args.runs, cwd=args.cwd) for c in corpus]
    return report(results)


if __name__ == "__main__":
    raise SystemExit(main())

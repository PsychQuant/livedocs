"""Correctness oracles for docs-router eval.

Three strategies, chosen so the oracle never becomes the stale index LiveDocs
exists to replace:

  - self_check : fetch the registry version AT EVAL TIME and assert it appears in
                 the answer. Zero hardcoding, cannot rot.
  - structural : assert a LiveDocs tool fired AND the answer is non-empty — i.e.
                 the model consulted primary source, without asserting an eternal
                 fact.
  - golden     : a dated exact-substring expectation, kept minimal and re-verified.

`evaluate_correctness` dispatches on the case's `oracle.type`. Negatives
(`type: none`) have no correctness dimension — the runner scores them purely on
trigger-match.
"""
from __future__ import annotations

import json
import urllib.request
from typing import Callable, Optional, Tuple

Fetch = Callable[[str, str], Optional[str]]


# ── registry version fetch (the rot-proof oracle's ground truth) ──────────────

def fetch_latest_version(library: str, ecosystem: str, timeout: int = 15) -> Optional[str]:
    """Fetch the current latest version straight from the package registry.

    Mirrors the ecosystems LiveDocs itself resolves. Returns None on any failure
    (network, unknown ecosystem, parse error) so the oracle reports inconclusive
    rather than a false negative.
    """
    try:
        if ecosystem == "npm":
            url = f"https://registry.npmjs.org/{library}/latest"
            data = _get_json(url, timeout)
            return data.get("version")
        if ecosystem == "pypi":
            url = f"https://pypi.org/pypi/{library}/json"
            data = _get_json(url, timeout)
            return (data.get("info") or {}).get("version")
        if ecosystem == "crates":
            url = f"https://crates.io/api/v1/crates/{library}"
            data = _get_json(url, timeout)
            return (data.get("crate") or {}).get("max_stable_version") or (data.get("crate") or {}).get("newest_version")
    except Exception:
        return None
    return None


# Cap the registry response we buffer. A misbehaving / redirect-hijacked endpoint
# could otherwise return an unbounded body and exhaust memory (defense-in-depth —
# the endpoints are fixed first-party TLS registries). A truncated body fails to
# parse → None → the caller reports inconclusive.
_MAX_REGISTRY_BYTES = 5_000_000


def _get_json(url: str, timeout: int) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "livedocs-eval"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read(_MAX_REGISTRY_BYTES + 1)
        if len(raw) > _MAX_REGISTRY_BYTES:
            raise ValueError(f"registry response exceeded {_MAX_REGISTRY_BYTES}-byte cap")
        return json.loads(raw.decode("utf-8"))


# ── oracle strategies ─────────────────────────────────────────────────────────

def self_check(answer: str, library: str, ecosystem: str,
               fetch_fn: Fetch = fetch_latest_version) -> Tuple[bool, str]:
    # NOTE (brittle coupling, by design): self_check scores ONLY whether the
    # current version appears in the answer — it is triggered-agnostic. A pure
    # memory answer that happens to name today's version would pass here. This is
    # safe only because run_eval.judge_case gates a positive case on trigger-rate
    # FIRST (requirement (a) "queried LiveDocs"), so requirement (b) never stands
    # alone. Keep those two dimensions both-required in judge_case.
    version = fetch_fn(library, ecosystem)
    if not version:
        return False, f"inconclusive: registry unreachable for {library} ({ecosystem})"
    if version in (answer or ""):
        return True, f"answer contains current version {version}"
    return False, f"answer is missing the current version {version}"


def structural(triggered: bool, final_text: str) -> Tuple[bool, str]:
    if not triggered:
        return False, "no LiveDocs tool fired — answer would be from memory"
    text = (final_text or "").strip()
    if not text or text == "__timeout__":
        return False, "empty or timed-out answer"
    return True, "queried primary source and produced a non-empty answer"


def golden(answer: str, expect: str) -> Tuple[bool, str]:
    if expect in (answer or ""):
        return True, f"answer contains expected substring '{expect}'"
    return False, f"answer is missing expected substring '{expect}'"


def evaluate_correctness(case: dict, triggered: bool, final_text: str,
                         fetch_fn: Fetch = fetch_latest_version) -> Tuple[bool, str]:
    """Dispatch on the case's oracle.type. Returns (passed, detail)."""
    oracle = case.get("oracle") or {}
    otype = oracle.get("type", "structural")
    if otype == "self_check":
        return self_check(final_text, oracle["library"], oracle["ecosystem"], fetch_fn=fetch_fn)
    if otype == "structural":
        return structural(triggered, final_text)
    if otype == "golden":
        return golden(final_text, oracle["expect"])
    # 'none' — correctness not applicable (negative cases scored on trigger-match)
    return True, "n/a (no correctness oracle)"

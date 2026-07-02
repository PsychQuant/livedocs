# docs-router eval

Does the `docs-router` skill actually **query LiveDocs** when a user asks a
docs/version/API question — across varied phrasings — and does it give a
**correct/current** answer? This harness measures both.

LiveDocs' whole value is "answer from live primary source, not stale training
data." That only holds if the skill *fires*. The silent failure mode is the
model answering from memory: stale/hallucinated, and nobody notices. This eval
turns "does it fire + answer right" into a repeatable measurement, TDD-style —
the prompt corpus is the test; a failing prompt is the signal.

## How it works

For each prompt in [`corpus.yaml`](corpus.yaml), the runner:

1. runs it `N` times through the **real installed plugin** via
   `claude -p "<prompt>" --output-format stream-json --dangerously-skip-permissions`;
2. scans the stream for a `tool_use` whose name starts with
   `mcp__plugin_livedocs_livedocs__` — that's the **trigger** signal (see
   `detect.py`);
3. scores **correctness** with an oracle (see `oracle.py`);
4. judges each case against rate thresholds and reports (see `run_eval.py`).

## Run it

```bash
# harness's own unit tests (pure logic — no API calls)
python3 -m pytest evals/docs-router/tests/

# smoke: load + enumerate the corpus, no live calls
python3 evals/docs-router/run_eval.py --dry-run

# live baseline (makes real `claude -p` calls — costs tokens, minutes per case)
python3 evals/docs-router/run_eval.py --runs 3
python3 evals/docs-router/run_eval.py --runs 3 --filter version   # one category
```

Requires the `livedocs` plugin installed (the eval tests the shipped plugin, not
a mock) and the `claude` CLI on `PATH`.

## The three design decisions

**A — trigger detection = Claude Code headless.** We run the *real plugin* end to
end. Triggering is a property of the skill description + the model's routing, so
only a path where the skill is live can measure it — the existing `swift test`
suite cannot (it tests the MCP tools once called, never the routing).

**B — correctness oracle, chosen to never rot.** LiveDocs exists *because* static
indexes go stale, so a hardcoded fact oracle would betray the premise:

| oracle | used for | check |
|--------|----------|-------|
| `self_check` | version queries | fetch the registry **at eval time**, assert the current version appears in the answer (zero hardcoding) |
| `structural` | config / API / CLI / runtime | a LiveDocs tool fired **and** the answer is non-empty — i.e. it consulted primary source (no eternal-fact claim) |
| `golden` | rare exact facts | dated substring, kept minimal, re-verified periodically |

Negatives (`type: none`) have no correctness dimension — they pass by **not**
triggering.

**C — statistical, not deterministic.** LLM routing is stochastic, so each prompt
runs `N` times and thresholds are rate-based:

| case kind | threshold |
|-----------|-----------|
| positive | trigger-rate ≥ 80% |
| positive w/ oracle | correctness-rate ≥ 80% |
| negative | false-trigger-rate ≤ 20% |

The runner exits non-zero on any breach. This is a **periodic / manual** eval,
not per-PR CI — the live cost and stochastic flakiness don't belong on the
critical path.

## Corpus dimensions

Positive prompts span 4 question shapes (version → `latest_version`;
config/API → `resolve_source`+`fetch_docs`; CLI → `introspect kind=cli`; runtime
→ `introspect kind=runtime`) × phrasing (direct / indirect / embedded in a coding
task) × language (English / 中文). Negatives cover general concepts and the
user's own code — where **over-triggering** is itself a failure.

## Scope / caveats

- Measures a **sample**, not a proof of universal correctness — the corpus must
  grow. Treat pass-rates as directional.
- Watch for **Goodhart**: tuning `SKILL.md` until this corpus is green can overfit;
  diversify the corpus rather than chase the number.
- This harness intentionally does **not** tune `SKILL.md`. The first run is a RED
  baseline; improving the skill against it is separate follow-up work.

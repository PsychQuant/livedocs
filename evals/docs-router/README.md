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
pip install -r evals/docs-router/requirements.txt   # PyYAML + pytest

# harness's own unit tests (pure logic — no API calls)
python3 -m pytest evals/docs-router/tests/

# smoke: load + enumerate the corpus, no live calls
python3 evals/docs-router/run_eval.py --dry-run

# live baseline (makes real `claude -p` calls — costs tokens, minutes per case)
python3 evals/docs-router/run_eval.py --runs 5
python3 evals/docs-router/run_eval.py --runs 5 --filter version   # one category
```

> **`--runs` must be ≥ 5** for the 80%/20% thresholds to be meaningful: with `N`
> runs a rate can only land on `{0, 1/N, …, 1}`, so at `N=3` the 80% floor
> collapses to "must be 3/3" and the 20% ceiling to "must be 0/3" (all-or-nothing).
> `N=5` is the smallest N where `4/5 = 80%` and `1/5 = 20%` are reachable; the
> runner warns if you pick an N too small.

Requires the `livedocs` plugin installed (the eval tests the shipped plugin, not
a mock) and the `claude` CLI on `PATH`.

> **Cost/environment note.** Each case is a full headless `claude -p` agentic run
> and costs real tokens. Run it from a **clean project directory** (not nested
> inside another Claude Code session — a nested run inherits the parent's whole
> MCP/plugin config, inflating the per-call system prompt to tens of thousands of
> tokens and slowing startup). Budget a few `$` and several minutes for a full
> `--runs 3` pass, and make sure the account has credits — an out-of-credits
> account will stall mid-run.

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

## vs-context7 comparison (issue #27)

A separate, focused dimension: **how fresh is LiveDocs vs context7**, measured on
one honest, structural axis — **latest-version freshness**, with the package
registry as neutral ground truth.

```bash
python3 evals/docs-router/compare_context7.py            # print the table + tally
python3 evals/docs-router/compare_context7.py --json     # machine-readable
python3 evals/docs-router/compare_context7.py --verify-live   # warn if the snapshot drifted
```

- Corpus: [`compare_corpus.yaml`](compare_corpus.yaml) — fast-moving libraries across
  npm / PyPI / crates.
- Data: [`compare_context7_sample.json`](compare_context7_sample.json) — a **dated**
  capture (2026-07-02) of what each tool returned. LiveDocs' answer is checked *by
  computation* against the registry; context7's is a **recorded human judgment** of
  whether its top-ranked default match reflects the current release (its answer is
  prose, not a clean version string). Reproduce by re-running both MCP tools.

**Why this axis, and the honesty guard.** LiveDocs wins here *structurally* (it
fetches the registry live; a pre-built index reflects its last crawl) — but the
harness lets the data show it and **concedes** what context7 is good at:

- We measure **freshness only**, never **coverage breadth** — a pre-built index's
  home turf; measuring coverage would be reverse cherry-picking.
- **The corpus is forward-selected** — deliberately fast-moving libraries, where a
  re-crawled index lags most. This is *not* a neutral sample; it is the case where the
  difference is real. Stated plainly so the number isn't read as a universal claim.
- **LiveDocs' side is the registry by construction.** LiveDocs *fetches* the registry,
  and the ground truth *is* the registry, so `livedocs_current` is effectively
  tautological (`answer == ground_truth`). That's the point — LiveDocs returns the live
  release — but it means the real measured finding is **context7's default-match
  staleness**, not a symmetric contest. The homepage says as much.
- context7 is a coverage-ranked *doc/snippet retriever*, not a version API. It can
  *have* the current version in a lower-ranked entry (in this sample: react, 1/6);
  the sample notes that per library. We measure the freshness of the **default**
  answer, not "context7 can't find the version." Per library the default is either
  *behind* (react, vite) or *version-less* (fastapi, pydantic, tokio, serde) — the
  sample records which.
- **`--verify-live` is one-sided:** it re-fetches the registry (LiveDocs' side) and warns
  on drift, but does not re-query context7. The context7 column is a dated snapshot;
  refresh it by re-running both MCP tools.
- **D1 (this harness):** a dated recorded head-to-head. **D2 (future, not built):**
  a fully-automated live A/B that shells `claude -p` per tool — stronger but
  costly/flaky, so it stays out of the default path.

Result at capture (2026-07-02): context7's top-ranked default match reflected the current
release on **0 of 6** (behind for react/vite, version-less for fastapi/pydantic/tokio/serde);
LiveDocs returned the live registry version each time.

## Scope / caveats

- Measures a **sample**, not a proof of universal correctness — the corpus must
  grow. Treat pass-rates as directional.
- Watch for **Goodhart**: tuning `SKILL.md` until this corpus is green can overfit;
  diversify the corpus rather than chase the number.
- This harness intentionally does **not** tune `SKILL.md`. The first run is a RED
  baseline; improving the skill against it is separate follow-up work.

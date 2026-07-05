# LiveDocs — project instructions

A Claude Code plugin: primary-source-first, always-latest documentation for AI agents.
Swift MCP server (engine) + `look-up` skill (routing) + Python evals.

## Architecture

- `Sources/LiveDocsCore` — dependency-free discovery engine (registry parsing, llms.txt
  probing, soft-404 classification, ranking, SSRF guard, sanitization, ETag cache).
  Network is injected via the `HTTPClient` protocol → unit-testable without a server.
- `Sources/CheLiveDocsMCP` — thin MCP stdio shell (process/file layer: CLI/R/runtime
  introspection, ProcessRunner).
- `evals/look-up/` — Python: skill-eval harness (does `look-up` fire + answer
  currently) + the vs-context7 freshness comparison.
- Fuzzy "which library is this?" belongs to the calling agent (`look-up` skill);
  MCP tools take concrete inputs and do deterministic work.

## Commands

```bash
swift test                                   # 144 Swift tests (no network)
python3 -m pytest evals/look-up/tests/   # 72 Python tests (no API calls)
python3 evals/look-up/compare_context7.py --verify-live   # freshness snapshot drift check
make release-signed VERSION=vX.Y.Z           # build + sign + notarize + mcpb (needs DEVELOPER_ID/NOTARY_PROFILE)
bash scripts/sync-wiki.sh                    # mirror docs/wiki/ -> GitHub wiki (after merge)
```

CI runs `swift build` + `swift test` AND the Python unit suite per push/PR (the Python job
is what fires the vs-context7 drift guards mechanically at the PR gate, #48 — it makes no
network / API calls). `scripts/release.sh` gates on green tests + version-source/tag match.
Version source of truth: `Sources/LiveDocsCore/Version.swift`.
Live evals (`run_eval.py --runs N`) are periodic/manual — real `claude -p` calls; run from a
clean non-nested directory with credits.

## Conventions (learned the hard way)

- **Wiki**: `docs/wiki/` is the source of truth, mirrored 1:1 by `scripts/sync-wiki.sh`.
  Every page is a bilingual pair — `X.md` + `X-zh-TW.md` with a top nav line; edit both.
- **Test-count sync**: adding/removing tests changes counts on `docs/wiki/Testing.md` +
  `Testing-zh-TW.md` — the **totals** (headline, `## Swift`/`## Python`, code-block
  comments), the Swift-only **`### <Target> — N` section subtotals** (the Python section is
  a flat table with no subtotal), and the **per-file table rows** — plus the Home pages'
  Guides line and the README breakdown. This regressed repeatedly, so **run
  `bash scripts/sync-test-counts.sh`** after every test add/remove: it runs both suites for
  real (a red suite aborts, never mints a false "all green"), and **first verifies** the
  subtotals and per-file rows you hand-edit are internally consistent (rows sum to their
  subtotal, subtotals sum to the suite total) — **failing loudly and writing nothing** if
  you forgot to update a row, instead of silently shipping a contradiction — and **only then
  rewrites** the totals + breakdown it owns. So the flow is: hand-edit the `###` subtotals
  and table rows, then run the script to catch any mismatch and sync the totals. It
  deliberately does NOT touch historical/milestone prose (e.g. "grew 72 → 110 during the
  v0.7.0 hardening") — those are frozen facts you reason about by hand, even though their
  endpoints happen to equal today's totals. Adding a new count reference elsewhere? Add its
  phrasing (with an expected hit count) to the script's `edits` map — the guard only knows
  the phrasings registered there.
- **Competitive claims are measured, never asserted**: any vs-context7 (or similar) number
  must come from the `evals/look-up` harness as a dated capture, with the honesty
  caveats stated inline (forward-selected corpus, LiveDocs-side is the registry by
  construction, "version-less" ≠ "behind", concede lower-ranked hits). Never hardcode
  registry versions into prose — cite the harness as the living source (see #27/#29).
- **IDD**: work flows through `issue-driven-dev` (issue → diagnose → implement → verify →
  close). PR bodies use `Refs #N` — never `Closes/Fixes/Resolves` trailers (auto-close
  bypasses the close gate). Pipelines stop at verified; close is a human checkpoint.

<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

# LiveDocs — project instructions

A Claude Code plugin: primary-source-first, always-latest documentation for AI agents.
Swift MCP server (engine) + `docs-router` skill (routing) + Python evals.

## Architecture

- `Sources/LiveDocsCore` — dependency-free discovery engine (registry parsing, llms.txt
  probing, soft-404 classification, ranking, SSRF guard, sanitization, ETag cache).
  Network is injected via the `HTTPClient` protocol → unit-testable without a server.
- `Sources/CheLiveDocsMCP` — thin MCP stdio shell (process/file layer: CLI/R/runtime
  introspection, ProcessRunner).
- `evals/docs-router/` — Python: skill-eval harness (does `docs-router` fire + answer
  currently) + the vs-context7 freshness comparison.
- Fuzzy "which library is this?" belongs to the calling agent (`docs-router` skill);
  MCP tools take concrete inputs and do deterministic work.

## Commands

```bash
swift test                                   # 110 Swift tests (no network)
python3 -m pytest evals/docs-router/tests/   # 41 Python tests (no API calls)
python3 evals/docs-router/compare_context7.py --verify-live   # freshness snapshot drift check
make release-signed VERSION=vX.Y.Z           # build + sign + notarize + mcpb (needs DEVELOPER_ID/NOTARY_PROFILE)
bash scripts/sync-wiki.sh                    # mirror docs/wiki/ -> GitHub wiki (after merge)
```

CI runs `swift build` + `swift test` per push/PR. `scripts/release.sh` gates on green tests +
version-source/tag match. Version source of truth: `Sources/LiveDocsCore/Version.swift`.
Live evals (`run_eval.py --runs N`) are periodic/manual — real `claude -p` calls; run from a
clean non-nested directory with credits.

## Conventions (learned the hard way)

- **Wiki**: `docs/wiki/` is the source of truth, mirrored 1:1 by `scripts/sync-wiki.sh`.
  Every page is a bilingual pair — `X.md` + `X-zh-TW.md` with a top nav line; edit both.
- **Test-count sync**: adding/removing tests requires updating the counts on
  `docs/wiki/Testing.md` AND `Testing-zh-TW.md` (headline, code-block comments, per-file
  table, discipline line) plus the Home pages' Guides line. This regressed twice in one day.
- **Competitive claims are measured, never asserted**: any vs-context7 (or similar) number
  must come from the `evals/docs-router` harness as a dated capture, with the honesty
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

# Primary-Source Spectrum — what LiveDocs is (and isn't) for

> Product-boundary source of truth. Companion to the archived change
> `add-target-type-version-reconciliation` (2026-07-01) and its living specs
> (`target-type-classification`, `version-reconciliation`, `installed-version-introspection`).

## Principle

LiveDocs is primary-source-first: for any documentation question, go to the canonical,
version-matched primary source, not training memory (stale) and not a pre-built lossy index
(context7). The generalization that makes this scale: "primary source" is resolved by target
type, not by assuming it always lives on the web.

## The spectrum

| Target type | Where the primary source lives | How it's resolved | Owner |
|---|---|---|---|
| Third-party public library / tool / API | remote (registry / `llms.txt` / repo / OpenAPI / GraphQL), and the model's memory of it is stale | LiveDocs auto-discovery chain | LiveDocs (value highest here) |
| Installed package / CLI | the locally installed artifact | `introspect` (`cli` / `r-pkg`; npm/pip to come) | LiveDocs (read-only) |
| Web-only hosted docs / SaaS (e.g. Claude Code features/config) | remote, latest-only (no local version) | web-latest fetch, no reconciliation | LiveDocs (`docs-router` web-only branch) |
| Your own / private / internal code | local source files (the working tree, always current) | read the files directly | the coding agent (NOT LiveDocs) |

## Where LiveDocs's value is concentrated

Highest where the primary source is remote and the model's copy is stale (third-party
dependencies). For code whose primary source is local and directly readable (your own repo),
the agent already reaches primary source by reading the files, so LiveDocs's fetch layer adds
little there.

## The boundary — what LiveDocs is NOT for

- Private / internal / proprietary code: there is no public canonical source; the source of
  truth is the local codebase itself. Making LiveDocs RAG a private repo would overlap with
  what a coding agent already does (read the code). Out of scope by design, not a missing feature.
- Your current project's own code: read the files.

## Division of labor — they compose

A single task splits along the "where does the primary source live" line. Debugging your code
that uses FastAPI: the agent reads your files (local primary), and uses LiveDocs for FastAPI
(external primary). LiveDocs owns the external/remote half; the agent's file-reading owns the
local half. Together that is complete coverage, and neither should swallow the other.

## Remaining in-scope gap

Non-machine-readable third-party docs (PDF-only, auth-walled wiki, video, Discord) degrade to
the repo README or nothing. This edge is shrinking as `llms.txt` adoption grows (about 88% of
popular docs hosts shipped it as of 2026-06).

## Mapping to the implementation

The per-question has-local vs web-only classification and the defer-to-local invariant (rows
1-3) became executable in change `add-target-type-version-reconciliation`. Row 4 (local/private
code = the agent reads files) is deliberately left to the agent, not the MCP. That is the
product boundary.

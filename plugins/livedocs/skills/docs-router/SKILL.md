---
name: docs-router
description: Use when answering questions about any library, framework, SDK, API, CLI tool, or cloud service — how to use it, its config, its latest version, API signatures, migration, or CLI usage. Routes the question to the highest-fidelity PRIMARY source via the LiveDocs MCP (llms.txt / package registry / repo / OpenAPI / GraphQL / CLI introspection) instead of relying on possibly-stale training data or a lossy pre-built index.
---

# docs-router

You have the **LiveDocs** MCP — it fetches the *latest* docs from each library's
canonical **primary source**, live. Everything LiveDocs returns is fetched on
demand; it never serves a pre-built index. Your job is to route a question to the
right tool, and prefer LiveDocs primary sources over training memory (which lags).

## Step 0 — Classify the query (per-question): has-local or web-only?

Before routing, ask of **this specific query** (classify per-question, NOT per-target —
the same tool can be both): **is there a LOCAL, version-matched authoritative source
for what's being asked?**

- **web-only** — the authoritative docs live only online: a hosted tool's features/config
  (e.g. "how do I configure MCP in Claude Code"), a SaaS/REST API, a docs site. → go to
  **Decision flow** and answer from web-latest. **No version reconciliation, no upgrade
  prompt** — you don't "install" web docs, and you make **no** `introspect`/installed call.
- **has-local** — the answer depends on an installed artifact: an installed package's
  API/behavior, or an installed CLI's flags. → if the **context-aware trigger** fires, go to
  **Version reconciliation**; otherwise fall through to web-latest.

Same tool, split per-question: "how do I configure Claude Code" = web-only;
"what flags does the installed `claude` take" = has-local.

## Version reconciliation (has-local)

**Context-aware trigger** — reconcile only when warranted: the query is **inside a project
that uses the package**, OR the query is **version/upgrade/debug-shaped** ("why doesn't X
work", "should I upgrade", "does my version have Y"). A bare conceptual question with no
consuming project → **skip the local lookup**, answer from web-latest (bounds latency+noise).

When triggered:
1. **Local**: `introspect{kind:"r-pkg", target:"<pkg>"}` → installed version (**READ-ONLY**;
   R first — npm/pip/CLI to come). `resolved_env` tells you which library answered.
2. **Latest**: `latest_version{library, ecosystem}` → web-latest.
3. **Compare, then defer to local** — the installed version is **always the answer**; web is
   used **only** to gate the upgrade:
   - installed **==** latest → answer from the **installed** docs.
   - web newer, user **declines** upgrade → answer from the **installed** docs.
   - web newer, user **confirms** upgrade → **you** (not the MCP) run the install command
     (`install.packages("<pkg>")` / `npm i` / `pip install -U`), then answer from the
     now-installed docs.
   - **Invariant**: every branch ends "answer from local". Never present web-latest docs as
     the answer to a has-local query.

**Install is a confirmed mutation** — never install without **explicit user confirmation**;
if not given, nothing is installed. The MCP stays **read-only** (it introspects, never installs).

## Decision flow

1. **Identify the entity** in the question: the library/tool/API, and — if it's a
   package — its **ecosystem** and, if the question is version-specific, the
   **version**. This is the one fuzzy step; the tools take it from there.
   - Ecosystems + library format: `npm` (`react`, `@scope/name`), `pypi` (`fastapi`),
     `crates` (Rust: `serde`), `go` (full module path `github.com/gin-gonic/gin`),
     `rubygems` (`rails`), `jsr` (Deno: `@std/assert`), `packagist` (PHP: `vendor/package`),
     `maven` (JVM: `group:artifact`), `cran` (R: `dplyr`).
   - `npm`/`pypi` auto-detect if you omit ecosystem; the others **must** be named.

2. **Pick the tool by question type:**

   | The question is about… | Call |
   |---|---|
   | "what's the latest version / did X change / what's new" | `latest_version` (exact version + changelog URL) |
   | a **specific version** (e.g. React 18 vs 19) | any of the below + `version:"18.3.1"` (honored for npm/pypi registry+repo; llms.txt is always latest and gets labeled) |
   | how to use / configure / general docs | `resolve_source` → then `fetch_docs` on the top result |
   | exact API surface — endpoints, request/response shape | `introspect` (kind=openapi or graphql) |
   | a CLI's flags / subcommands / installed version | `introspect` (kind=cli, target = bare command) |

3. **`resolve_source` → `fetch_docs`**: `resolve_source` returns ranked sources
   `{kind,url,fidelity,freshness,version}`. Take the **top** (highest fidelity)
   and `fetch_docs` its `url` for the verbatim text. For exactness-critical
   answers (config keys, API signatures) always fetch **raw** rather than
   paraphrasing a snippet.

4. **When there's no primary source.** If `resolve_source` returns `{"sources":[]}`,
   LiveDocs found no live primary source. Prefer another *dynamic* route first
   (name the ecosystem, try the repo directly, or a live web search + fetch the real
   page). Only as a last resort consult **context7** — and treat it strictly as an
   external **reference index**, not part of LiveDocs: it's a periodically-recrawled,
   LLM-summarized snapshot (snippets are generated by a model and can be weeks old),
   so label any answer from it as lower-fidelity and non-live. LiveDocs itself never
   serves that index under its own name.

## Examples

- *"What's the newest FastAPI and what changed?"* →
  `latest_version{library:"fastapi", ecosystem:"pypi"}` → report version + open the changelog.
- *"How do I set up Hono middleware?"* →
  `resolve_source{docs_url:"https://hono.dev"}` → `fetch_docs` the `llms-full.txt` hit → answer from raw.
- *"What endpoints does this service expose?"* (you have its URL) →
  `introspect{target:"https://api.example.com", kind:"openapi"}`.
- *"What gh subcommands exist for releases?"* →
  `introspect{target:"gh", kind:"cli"}`.
- *"Does React 18 support `use`?"* (version-specific) →
  `resolve_source{library:"react", ecosystem:"npm", version:"18.3.1"}` → the repo is pinned to that tag; note llms.txt is latest-only.
- *"Latest tokio (Rust)?"* → `latest_version{library:"tokio", ecosystem:"crates"}`.

## Why this beats guessing or a generic index

Training data lags releases; a pre-built index lags re-crawls and can only return
ranked snippets. LiveDocs reads the **current** primary source and can return it
**raw**, plus the **exact** latest version (registry) and the **API contract
itself** (introspection). When you can reach a primary source, use it.

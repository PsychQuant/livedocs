---
name: look-up
description: Use when answering questions about any library, framework, SDK, API, CLI tool, or cloud service — how to use it, its config, its latest version, API signatures, migration, or CLI usage. Routes the question to the highest-fidelity PRIMARY source via the LiveDocs MCP (llms.txt / package registry / repo / OpenAPI / GraphQL / CLI introspection) instead of relying on possibly-stale training data or a lossy pre-built index.
---

# look-up

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
  API/behavior, an installed CLI's flags, or the **effective language runtime** version. → go to
  **Version reconciliation**: **detect** (eager, cached, silent) anchors the answer to the local
  version; **offer** an upgrade only when it's relevant. A bare conceptual query with no
  consuming project falls through to web-latest.

Same tool, split per-question: "how do I configure Claude Code" = web-only;
"what flags does the installed `claude` take" = has-local.

## Version reconciliation (has-local) — detect, then offer

Two phases, so reconciliation can be **proactive without being noisy**.

**Detect — eager, cached, silent.** When a query is inside a project with a resolvable local
target (installed package, CLI, or **language runtime**), resolve the local version *once* and
silently anchor every answer to it. Cache the detect result **per project working directory**
(key it on the relevant pin files) so you don't re-introspect on every turn. Web-latest stays
current cheaply because `latest_version` sits behind an ETag conditional-revalidation cache —
when nothing changed, staying up to date costs almost nothing.

**Offer — lazy, only when relevant.** Offer an *upgrade* only when the answer is
version-sensitive OR an actual skew/error shows up ("why doesn't X work", "should I upgrade",
"does my version have Y"). When the version gap doesn't affect the answer, stay silent — no
upgrade prompt. A bare conceptual question with no consuming project → skip the local lookup.

**Local sources:**
1. installed **package**: `introspect{kind:"r-pkg", target:"<pkg>"}` (R; npm/pip to come) —
   `resolved_env` says which library answered.
2. installed **CLI**: `introspect{kind:"cli", target:"<cmd>"}`.
3. **language runtime** (Python / Node / Go / Rust / Java / .NET / Swift):
   `introspect{kind:"runtime", target:"<language>" or "auto"}` → the *effective* runtime version.
   Active toolchain is authoritative; declared pins (`.python-version`, `go.mod` `go`,
   `swift-tools-version`, …) only cross-check; a bare constraint or a language-mode declaration
   returns **not resolved** rather than a guessed version. Anchor stdlib/syntax/API answers to
   the effective version — a project pinned to Python 3.11 gets 3.11 answers, not 3.13.

**Latest, then defer to local:**
- `latest_version{library, ecosystem}` → web-latest (for a runtime, the language's latest release).
- Compare — the local version is **always the answer**; web only gates the upgrade:
  - local **==** latest → answer from local.
  - web newer, user **declines** → answer from local.
  - web newer, user **confirms** → **you** (not the MCP) run the install/upgrade
    (`install.packages(...)` / `npm i` / `pip install -U` / a runtime version-manager), then
    answer from the now-updated local.
  - **Invariant**: every branch ends "answer from local". Never present web-latest as the
    answer to a has-local query.

**Install is a confirmed mutation** — never install or upgrade without **explicit user
confirmation**; if not given, nothing changes. The MCP stays **read-only** (it introspects,
never installs).

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

## Explicit invocation (`/livedocs:look-up`)

The user can invoke this skill directly: `/livedocs:look-up <target> [topic...]`.
Invocation arguments (empty when the skill fired implicitly): $ARGUMENTS

Classify the **first** argument token into exactly one shape, using this precedence
order; any remaining tokens are a **topic filter** applied when reading the fetched docs:

1. **URL** — token starts with `http://` or `https://`. API-endpoint URLs →
   `introspect{kind:"openapi"|"graphql"}`; documentation-site URLs →
   `resolve_source{docs_url}` → `fetch_docs`.
2. **Language** — token matches (case-insensitively) one of: r, python, node,
   javascript, go, rust, java, dotnet, swift → `introspect{kind:"runtime",
   target:<language>}`, then answer language/stdlib questions anchored to the
   effective local version per **Version reconciliation** above.
3. **Package** — any other token, optionally version-pinned as `name@version` →
   `resolve_source{library, ecosystem, version?}` → `fetch_docs` on the top result.
   Ecosystem resolution follows **Decision flow** step 1 (npm/pypi auto-detect;
   other ecosystems must be named).
4. **CLI fallback** — package resolution returned `{"sources":[]}` AND the token
   names an installed command → `introspect{kind:"cli", target:<token>}`.

With **no arguments**, this invocation simply loads the routing guidance — behave
exactly as when the skill fires implicitly, answering subsequent questions per the
Decision flow. Never error or demand an argument.

Shape examples: `/livedocs:look-up R` → runtime introspect, R docs anchored to the
local version · `/livedocs:look-up react@18` → registry docs pinned to 18 ·
`/livedocs:look-up dplyr mutate` → resolve dplyr, read docs for `mutate` ·
`/livedocs:look-up https://api.example.com` → OpenAPI introspection ·
`/livedocs:look-up gh` → package miss, falls back to CLI introspection.

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
  `resolve_source{library:"react", ecosystem:"npm", version:"18.3.1"}` → the **registry** leg resolves that exact version; the repo/changelog and llms.txt legs are default-branch/latest and get labeled "NOT pinned to 18.3.1" — trust the registry version, not the repo content, for a pinned answer.
- *"Latest tokio (Rust)?"* → `latest_version{library:"tokio", ecosystem:"crates"}`.

## Why this beats guessing or a generic index

Training data lags releases; a pre-built index lags re-crawls and can only return
ranked snippets. LiveDocs reads the **current** primary source and can return it
**raw**, plus the **exact** latest version (registry) and the **API contract
itself** (introspection). When you can reach a primary source, use it.

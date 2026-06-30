---
name: docs-router
description: Use when answering questions about any library, framework, SDK, API, CLI tool, or cloud service — how to use it, its config, its latest version, API signatures, migration, or CLI usage. Routes the question to the highest-fidelity PRIMARY source via the LiveDocs MCP (llms.txt / package registry / repo / OpenAPI / GraphQL / CLI introspection) instead of relying on possibly-stale training data or a lossy pre-built index.
---

# docs-router

You have the **LiveDocs** MCP — it fetches the *latest* docs from each library's
canonical **primary source**, live. Your job is to route a question to the right
tool. Prefer LiveDocs primary sources over training memory (which lags) and over
context7/web (which is a lossy, periodically-recrawled index).

## Decision flow

1. **Identify the entity** in the question: the library/tool/API and, if a
   package, its ecosystem (npm vs PyPI). This is the one fuzzy step — it's yours
   to make; the tools take it from there.

2. **Pick the tool by question type:**

   | The question is about… | Call |
   |---|---|
   | "what's the latest version / did X change / what's new" | `latest_version` (exact version + changelog URL) |
   | how to use / configure / general docs | `resolve_source` → then `fetch_docs` on the top result |
   | exact API surface — endpoints, request/response shape | `introspect` (kind=openapi or graphql) |
   | a CLI's flags / subcommands / installed version | `introspect` (kind=cli, target = bare command) |

3. **`resolve_source` → `fetch_docs`**: `resolve_source` returns ranked sources
   `{kind,url,fidelity,freshness,version}`. Take the **top** (highest fidelity)
   and `fetch_docs` its `url` for the verbatim text. For exactness-critical
   answers (config keys, API signatures) always fetch **raw** rather than
   paraphrasing a snippet.

4. **Honor the fidelity label.** If `resolve_source` returns `{"sources":[]}`,
   there is no primary source — *then* fall back to context7 or web search, and
   **tell the user** the answer is from a lower-fidelity index, not the primary.

## Examples

- *"What's the newest FastAPI and what changed?"* →
  `latest_version{library:"fastapi", ecosystem:"pypi"}` → report version + open the changelog.
- *"How do I set up Hono middleware?"* →
  `resolve_source{docs_url:"https://hono.dev"}` → `fetch_docs` the `llms-full.txt` hit → answer from raw.
- *"What endpoints does this service expose?"* (you have its URL) →
  `introspect{target:"https://api.example.com", kind:"openapi"}`.
- *"What gh subcommands exist for releases?"* →
  `introspect{target:"gh", kind:"cli"}`.

## Why this beats guessing or a generic index

Training data lags releases; a pre-built index lags re-crawls and can only return
ranked snippets. LiveDocs reads the **current** primary source and can return it
**raw**, plus the **exact** latest version (registry) and the **API contract
itself** (introspection). When you can reach a primary source, use it.

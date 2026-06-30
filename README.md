# LiveDocs MCP (`che-livedocs-mcp`)

A **primary-source-first, always-latest** documentation engine for AI agents.

Where context7 is a *pre-built, periodically-recrawled, lossy vector index*, LiveDocs
**auto-discovers each library's canonical machine-readable source on demand** and reads it
live. It can reach **raw** primary content and the **exact latest version**, which a lossy
index structurally cannot.

## Why this exists

The ecosystem is moving toward machine-discoverable primary sources (`llms.txt`, package
registries, OpenAPI). Live probing of 25 popular docs hosts (2026-06-30) found **~88% already
ship `llms.txt`**, and the rest resolve deterministically via package registries. That tailwind
makes a pre-built index increasingly redundant for the head of the distribution — and it's a
source LiveDocs can read verbatim.

## Discovery chain (primary-source-first)

1. **`llms.txt` / `llms-full.txt`** — the LLM-designed index/full dump, probed across root,
   `/docs/`, and full-variant paths, with a **soft-404 guard** (a real hit is `200` +
   `text/plain` + non-trivial size; many hosts answer `200`/`404` with an HTML shell).
2. **Package registry** — npm (`registry.npmjs.org/<pkg>/latest`) / PyPI
   (`pypi.org/pypi/<pkg>/json`): the *exact latest version* + changelog/repo/docs URLs,
   deterministically, no scraping.
3. **Repo** — GitHub README / CHANGELOG / releases (raw).
4. *(planned)* OpenAPI / GraphQL / CLI introspection — the highest-fidelity "can I use it" source.
5. **Fallback** — context7 / web, always **labeled low-fidelity**.

Results are ranked **fidelity-first, then freshness**.

## Tools

| Tool | Purpose |
|------|---------|
| `resolve_source` | Discover ranked primary sources for a library (`library`+`ecosystem` and/or `docs_url`). |
| `fetch_docs` | Fetch the **raw** text of a source URL — verbatim, no lossy layer. |
| `latest_version` | Deterministic "latest released version right now" + changelog/repo, from the registry. |

## Architecture

- **`LiveDocsCore`** — dependency-free discovery logic (candidate generation, soft-404
  classification, registry parsing, ranking). Network is injected via the `HTTPClient`
  protocol, so the whole engine is unit-tested without a server or the network.
- **`CheLiveDocsMCP`** — a thin MCP stdio shell over the engine.

The fuzzy "which library is this?" decision belongs to the calling agent (a router skill);
these tools take concrete inputs and do deterministic work.

## Develop

```bash
swift test     # 20 unit tests (pure logic + engine orchestration via fakes)
swift build    # builds the MCP executable
```

Status: **MVP** — `llms.txt` + registry + repo legs working end-to-end and verified live.
Planned: OpenAPI/CLI introspection, router skill, `.mcpb` packaging + signed release, marketplace distribution.

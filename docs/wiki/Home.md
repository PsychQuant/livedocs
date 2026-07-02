> English | [繁體中文](Home-zh-TW)

# LiveDocs

Live, primary-source-first documentation for AI agents. It fetches the latest docs for any
library straight from its canonical source, instead of a stale pre-built index or frozen
training memory.

## Why

An LLM's knowledge of a library is parametric memory frozen at its training cutoff; a
pre-built index (such as context7) lags its re-crawl. LiveDocs goes direct to the live
primary source every time, and can reconcile against the version you actually have installed.

## vs context7

context7 is a coverage-ranked, periodically re-crawled index; LiveDocs fetches the live
registry, so for "what's the current version of X" it returns today's release *by construction*.
The gap shows on fast-moving libraries. Asked for six (npm / PyPI / crates) on 2026-07-02,
context7's top-ranked default match reflected the current release on **0 of 6** — a version
behind (react → v18 vs 19.2.7; vite → 8.0.10 vs 8.1.3) or **version-less** (fastapi / pydantic /
tokio / serde: the top match is a docs page carrying no version). LiveDocs returned the exact
current version each time.

| on fast-moving libs | LiveDocs | context7 (default match) |
|---------------------|----------|--------------------------|
| reflects current release (6 libs) | 6/6 (live registry, by construction) | 0/6 |
| source | live registry / primary docs | periodically re-crawled index |

Honest scope: **freshness only**, on libraries picked *because* they move fast — a re-crawled
index's hardest case, not a neutral sample. LiveDocs' side is the registry by construction
(it fetches it live), so the finding here is really about context7's default-match staleness.
context7 wins on doc/snippet breadth (not measured here) and often carries the current version
in a *lower-ranked* entry. Method + per-library data:
[`evals/docs-router`](https://github.com/PsychQuant/livedocs/tree/main/evals/docs-router).
Deeper positioning: [vs context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md).

## Install

```
/plugin marketplace add PsychQuant/livedocs
/plugin install livedocs@livedocs-marketplace
```

Then use the `docs-router` skill; it routes questions to the right tool.

## Tools

| Tool | Purpose |
|------|---------|
| `resolve_source` | Ranked primary sources for a library (fidelity-first). |
| `fetch_docs` | Raw verbatim text of a source URL. |
| `latest_version` | Latest version + changelog/repo, from the registry (9 ecosystems: npm/pypi/crates/go/rubygems/jsr/packagist/maven/cran). Version pinning supported. |
| `introspect` | OpenAPI / GraphQL schema, an installed CLI's `--help`, an installed R package's version (`kind:"r-pkg"`), or the project's effective language-runtime version (`kind:"runtime"`, Python/Node/Go/Rust/Java/.NET/Swift). Read-only. |

## Guides

- [Version Reconciliation](Version-Reconciliation): the auto-detect update flow.
- [Primary-Source Spectrum](Primary-Source-Spectrum): what LiveDocs is and isn't for.
- [Testing](Testing): the test suites (151 tests) and what each covers.

## More

- [Positioning, vs context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md)
- [CHANGELOG](https://github.com/PsychQuant/livedocs/blob/main/CHANGELOG.md)

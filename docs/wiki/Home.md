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

That "lags its re-crawl" claim is measured, not asserted. Asked for the current version of
six fast-moving libraries (npm / PyPI / crates) and checked against each package registry on
2026-07-02, LiveDocs returned the **exact current version 6/6**; context7's top-ranked default
match was behind on all six — e.g. React → v18 while the registry is on 19.2.7.

| latest-version freshness | LiveDocs | context7 (default match) |
|--------------------------|----------|--------------------------|
| exact current version (6 libs) | **6/6** | 0/6 |
| source | live registry / primary docs | periodically re-crawled index |

Honest scope: this measures **freshness**, not doc breadth — context7 is a coverage-ranked
snippet retriever, wins on breadth, and often carries the current version in a lower-ranked
entry. Method + per-library data:
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
- [Testing](Testing): the test suites (139 tests) and what each covers.

## More

- [Positioning, vs context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md)
- [CHANGELOG](https://github.com/PsychQuant/livedocs/blob/main/CHANGELOG.md)

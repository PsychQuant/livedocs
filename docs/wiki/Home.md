> English | [繁體中文](Home-zh-TW)

# LiveDocs

Live, primary-source-first documentation for AI agents. It fetches the latest docs for any
library straight from its canonical source, instead of a stale pre-built index or frozen
training memory.

## Why

An LLM's knowledge of a library is parametric memory frozen at its training cutoff; a
pre-built index (such as context7) lags its re-crawl. LiveDocs goes direct to the live
primary source every time, and can reconcile against the version you actually have installed.

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
| `introspect` | OpenAPI / GraphQL schema, an installed CLI's `--help`, or an installed R package's version (`kind:"r-pkg"`, read-only). |

## Guides

- [Version Reconciliation](Version-Reconciliation): the auto-detect update flow.
- [Primary-Source Spectrum](Primary-Source-Spectrum): what LiveDocs is and isn't for.

## More

- [Positioning, vs context7](https://github.com/PsychQuant/livedocs/blob/main/docs/positioning.md)
- [CHANGELOG](https://github.com/PsychQuant/livedocs/blob/main/CHANGELOG.md)

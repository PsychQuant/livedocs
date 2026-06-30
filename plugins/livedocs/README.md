# livedocs (plugin)

The **LiveDocs** engine as a Claude Code plugin: an MCP server (4 tools) + a
`docs-router` skill.

LiveDocs fetches the **latest** documentation for any library from its canonical
**primary source**, live — `llms.txt` → npm/PyPI registry → GitHub repo →
OpenAPI/GraphQL/CLI introspection — and reads it **raw**. A high-fidelity
alternative to pre-built, periodically-recrawled docs indexes: it returns the
exact latest version and the API contract itself, which a lossy index can't.

## Tools

| Tool | Purpose |
|------|---------|
| `resolve_source` | Ranked primary sources for a library (fidelity-first). |
| `fetch_docs` | Raw verbatim text of a source URL. |
| `latest_version` | Exact latest version + changelog/repo, from the registry. |
| `introspect` | OpenAPI / GraphQL schema, or an installed CLI's `--help`/`--version`. |

## Install

```
/plugin marketplace add PsychQuant/livedocs
/plugin install livedocs@livedocs-marketplace
```

The `bin/livedocs-wrapper.sh` auto-downloads the signed `CheLiveDocsMCP` binary
from the [`PsychQuant/livedocs`](https://github.com/PsychQuant/livedocs) release
matching `plugin.json`'s `binary_version`, and keeps it current on plugin updates.

Binary source + engine internals: `PsychQuant/livedocs` (`~/Developer/che-mcps/livedocs`).

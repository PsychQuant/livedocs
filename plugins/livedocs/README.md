# livedocs (plugin)

The **LiveDocs** engine as a Claude Code plugin: an MCP server (4 tools) + a
`look-up` skill (implicit auto-fire, or invoke explicitly as `/livedocs:look-up <target>`).

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
/plugin marketplace add PsychQuantAgent/claude-code-logos
/plugin install livedocs@claude-code-logos
```

**Moved (2026-11):** the plugin is now installed from the [`claude-code-logos`](https://github.com/PsychQuantAgent/claude-code-logos) marketplace, which includes this repository as a git submodule pinned to a release tag. This repository no longer holds a marketplace of its own. If you installed `livedocs@livedocs-marketplace`, switch once:

```
/plugin marketplace remove livedocs-marketplace
/plugin marketplace add PsychQuantAgent/claude-code-logos
/plugin install livedocs@claude-code-logos
```

Removing the old marketplace also uninstalls the copy that came from it. macOS only; the plugin's wrapper downloads the MCP server binary from this repository's GitHub Releases.

The `bin/livedocs-wrapper.sh` auto-downloads the signed `CheLiveDocsMCP` binary
from the [`PsychQuantAgent/livedocs`](https://github.com/PsychQuantAgent/livedocs) release
matching `plugin.json`'s `binary_version`, and keeps it current on plugin updates.

Binary source + engine internals: `PsychQuantAgent/livedocs` (`~/Developer/che-mcps/livedocs`).

# Changelog

## v0.1.0

Initial release — primary-source-first, always-latest documentation engine.

**Discovery chain** (fidelity-first, then freshness):
- `llms.txt` / `llms-full.txt` auto-discovery across root / `/docs` / full-variant paths, with a soft-404 guard (a real hit is `200` + `text/plain` + non-trivial size) and index→full upgrade.
- Package registry resolution: npm (`/latest`) and PyPI (`/pypi/<pkg>/json`) — the exact latest version + changelog/repo/docs URLs, deterministically.
- GitHub repo as raw source.
- Introspection: OpenAPI/Swagger JSON, GraphQL schema, and installed-CLI `--help`/`--version` (with command-injection guard).
- context7/web reserved as labeled low-fidelity fallback (engine returns empty when no primary source exists).

**Tools**: `resolve_source`, `fetch_docs`, `latest_version`, `introspect`.

**Quality**: 26 unit tests (pure logic + engine via injected HTTP fakes); all 4 tools verified live end-to-end. Premise validated by probing 25 popular docs hosts (~88% ship `llms.txt`).

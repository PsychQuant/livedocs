# Changelog

## [0.3.0]

**CRAN (R) registry adapter** — 9th ecosystem. `ecosystem:"cran"` resolves an R package's latest version + repo (from the CRAN `URL`/`BugReports` fields) via the crandb JSON API, feeding the same chain (e.g. `dplyr` → github.com/tidyverse/dplyr → `dplyr.tidyverse.org/llms.txt`). Turns the mechanical half of a hand-curated R docs guide into a live lookup.

No other behavior change.

## [0.2.0]

Broader dynamic coverage + version pinning. context7 stays a purely external reference — never integrated as a fallback leg (LiveDocs only ever serves live primary sources).

**More registry adapters** (all keyless, single live GET, ranked into the same chain): crates.io (Rust), Go modules (proxy.golang.org; module path used as repo when Origin is absent), RubyGems, JSR (Deno; two-call for the repo), Packagist (PHP), Maven Central (version-only). `npm`/`pypi` still auto-detect; the rest need an explicit `ecosystem`.

**Version pinning** — `version` param on `resolve_source`/`latest_version` (e.g. React `18.3.1` vs latest). Honored deterministically by the npm/PyPI registry legs; the repo/changelog/llms.txt sources are labeled "content NOT pinned" since their URLs serve the default branch / latest (llms.txt has no per-version hosting convention). A pin ignored by a latest-only ecosystem is reported, not silently dropped.

**Security** — boundary validation (`isSafePackageName`/`isSafeVersion`) before any name/version is interpolated into a registry URL; Maven `group:artifact` gets a stricter charset so it can't inject extra Solr clauses.

Reviewed by a 4-lens adversarial workflow; 7 findings fixed, 40 unit tests green.

## [0.1.0]

Initial release — primary-source-first, always-latest documentation engine.

**Discovery chain** (fidelity-first, then freshness):
- `llms.txt` / `llms-full.txt` auto-discovery across root / `/docs` / full-variant paths, with a soft-404 guard (a real hit is `200` + `text/plain` + non-trivial size) and index→full upgrade.
- Package registry resolution: npm (`/latest`) and PyPI (`/pypi/<pkg>/json`) — the exact latest version + changelog/repo/docs URLs, deterministically.
- GitHub repo as raw source.
- Introspection: OpenAPI/Swagger JSON, GraphQL schema, and installed-CLI `--help`/`--version` (with command-injection guard).
- context7/web reserved as labeled low-fidelity fallback (engine returns empty when no primary source exists).

**Tools**: `resolve_source`, `fetch_docs`, `latest_version`, `introspect`.

**Quality**: 26 unit tests (pure logic + engine via injected HTTP fakes); all 4 tools verified live end-to-end. Premise validated by probing 25 popular docs hosts (~88% ship `llms.txt`).

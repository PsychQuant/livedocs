# Changelog

## [0.5.0]

ETag conditional-revalidation cache: the only thesis-safe way to be faster without becoming a stale index. An `ETagCachingHTTPClient` decorator wraps the network layer. When a URL is cached it always re-requests with `If-None-Match`, so the server decides freshness. On `304 Not Modified` it serves the cached body, skipping the re-download and re-parse of an unchanged, often large doc like an `llms.txt`; on `200` with a new `ETag` it refreshes. It deliberately ignores `max-age`, so latest stays latest and it's only cheaper when nothing changed. Sources without an `ETag` (some registry endpoints) are not cached; POSTs (GraphQL introspection) are never cached. In-memory, per session.

## [0.4.0]

Installed-version introspection plus version reconciliation (issue #1). Handles targets that have both a web-latest and a locally-installed version.

- MCP `introspect` gains `kind:"r-pkg"`, a read-only probe of a locally installed R package's version via `Rscript` (name-guarded, passed as an arg not `-e`, watchdog-timed). It returns `installed_version` and the `resolved_env` (`.libPaths()` entry) it came from, or an honest "not installed in the current context", never a fabricated global version. It never installs.
- `docs-router` skill gains per-question target-type classification (`has-local` vs `web-only`) and a version-reconciliation state machine: for a has-local query it introspects the installed version and fetches web-latest, then always answers from the installed version (web only gates the upgrade). A chosen upgrade is run by the skill after explicit confirmation; the MCP stays read-only. `web-only` targets (Claude Code features/config, SaaS) skip reconciliation entirely.

## [0.3.0]

CRAN (R) registry adapter, the 9th ecosystem. `ecosystem:"cran"` resolves an R package's latest version and repo (from the CRAN `URL`/`BugReports` fields) via the crandb JSON API, feeding the same chain (e.g. `dplyr` → github.com/tidyverse/dplyr → `dplyr.tidyverse.org/llms.txt`). It turns the mechanical half of a hand-curated R docs guide into a live lookup.

No other behavior change.

## [0.2.0]

Broader dynamic coverage plus version pinning. context7 stays a purely external reference, never integrated as a fallback leg; LiveDocs only ever serves live primary sources.

More registry adapters (all keyless, single live GET, ranked into the same chain): crates.io (Rust), Go modules (proxy.golang.org; the module path is used as the repo when Origin is absent), RubyGems, JSR (Deno; two calls for the repo), Packagist (PHP), Maven Central (version-only). `npm`/`pypi` still auto-detect; the rest need an explicit `ecosystem`.

Version pinning: a `version` param on `resolve_source`/`latest_version` (e.g. React `18.3.1` vs latest). Honored deterministically by the npm/PyPI registry legs; the repo/changelog/llms.txt sources are labeled "content NOT pinned" since their URLs serve the default branch or latest (llms.txt has no per-version hosting convention). A pin ignored by a latest-only ecosystem is reported, not silently dropped.

Security: boundary validation (`isSafePackageName`/`isSafeVersion`) before any name or version is interpolated into a registry URL; Maven `group:artifact` gets a stricter charset so it can't inject extra Solr clauses.

Reviewed by a 4-lens adversarial workflow; 7 findings fixed, 40 unit tests green.

## [0.1.0]

Initial release: primary-source-first, always-latest documentation engine.

Discovery chain (fidelity-first, then freshness):
- `llms.txt` / `llms-full.txt` auto-discovery across root / `/docs` / full-variant paths, with a soft-404 guard (a real hit is `200` + `text/plain` + non-trivial size) and index-to-full upgrade.
- Package registry resolution: npm (`/latest`) and PyPI (`/pypi/<pkg>/json`), for the exact latest version plus changelog/repo/docs URLs, deterministically.
- GitHub repo as raw source.
- Introspection: OpenAPI/Swagger JSON, GraphQL schema, and installed-CLI `--help`/`--version` (with a command-injection guard).
- context7/web reserved as a labeled low-fidelity fallback (the engine returns empty when no primary source exists).

Tools: `resolve_source`, `fetch_docs`, `latest_version`, `introspect`.

Quality: 26 unit tests (pure logic + engine via injected HTTP fakes); all 4 tools verified live end-to-end. Premise validated by probing 25 popular docs hosts (about 88% ship `llms.txt`).

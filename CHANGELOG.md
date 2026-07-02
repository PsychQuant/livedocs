# Changelog

## [0.8.0]

**BREAKING**: the plugin skill `docs-router` is renamed to `look-up` — the explicit command moves from `/livedocs:docs-router` to `/livedocs:look-up`. The skill was always dual-mode (Claude Code default); the old name described internal mechanics and made the explicit entry undiscoverable. The frontmatter description is unchanged, so implicit auto-fire behavior is identical. Migration: invoke `/livedocs:look-up` instead of `/livedocs:docs-router`; no other action needed.

- New **Explicit invocation** contract in the skill: `/livedocs:look-up <target> [topic...]` classifies the first argument deterministically (URL → language → package `name@version` → CLI fallback) and routes to the matching LiveDocs tool; remaining tokens act as a topic filter; a bare invocation just loads the routing guidance.
- The eval harness directory moves `evals/docs-router/` → `evals/look-up/` to follow the skill name. Historical CHANGELOG entries and archived openspec records keep the old name (provenance, not rewritten).
- Plugin-shell-only release: the MCP binary is unchanged (`binary_version` stays 0.7.0).

## [0.7.0]

Security and robustness hardening across the fetch and introspection surfaces (addresses the multi-agent review, issues #3–#17).

- **SSRF guard** — every outbound fetch (`fetch_docs`, `resolve_source` docs_url, openapi/graphql) is validated at the single transport choke point: an `http`/`https` scheme allowlist plus a host classifier that rejects loopback / link-local (incl. `169.254.169.254` metadata) / RFC-1918 / ULA / `.internal` / `.local` targets, with a DNS-resolution check for rebinding and a redirect delegate that re-validates every hop.
- **Response-size ceiling** — bodies are streamed and aborted past a byte limit, bounding the *decompressed* size so a gzip bomb can't OOM the server. The ETag cache is now LRU-bounded (total-byte budget + entry cap) and refuses to store oversized bodies.
- **`fetch_docs` crash fix** — a negative `max_bytes` no longer traps `prefix(_:)`; truncation is byte-accurate and fetched content is stripped of control/ANSI/bidi characters before returning.
- **Hardened process runner** — one `ProcessRunner` replaces three copies: pipes are drained concurrently (no >64 KB deadlock), the watchdog escalates SIGTERM → SIGKILL, a timed-out probe surfaces as an error instead of silent truncation, and executable resolution is PATH-first so pyenv/mise/asdf shims are honored.
- **Runtime introspection accuracy** — version files are refused if they are symlinks (closes a secret-exfil channel) and only version-shaped first lines are accepted; the toolchain probe requires a clean exit and labels the source with the command that actually ran; `parseMiseToml` strips inline comments / rejects arrays and reads the canonical `mise.toml`; uncovered-but-safe languages fall back to the universal pin layer; `introspect kind=runtime` accepts an optional validated `path`.
- **Single version source** — `LiveDocsVersion` is the one place the version lives; the MCP server, User-Agent (now pointing at `PsychQuant/livedocs`), and the mcpb/plugin/marketplace manifests all track it.

## [0.6.0]

Proactive language-runtime version detection. `introspect` gains a read-only `runtime` kind that resolves the effective language-runtime version for the current project across Python, Node/TypeScript, Go, Rust, Java, C#/.NET, and Swift. Resolution is two-layer: a universal pin parser reads cross-language declaration files (asdf `.tool-versions`, mise, idiomatic `.<lang>-version` files), and per-language depth adapters probe the active toolchain and read the manifest. The active toolchain is authoritative; declared sources are interpreted by their semantics — a constraint (`requires-python >=3.9`) or a language-mode declaration (`swift-tools-version`) is never reported as an exact version, and an unresolvable runtime returns not-resolved rather than a guessed global version. The `docs-router` skill splits version reconciliation into an eager, per-cwd-cached, silent detect phase and a lazy, only-when-relevant offer phase; defer-to-local and confirmed-install are unchanged.

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

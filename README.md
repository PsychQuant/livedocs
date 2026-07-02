# LiveDocs

A **Claude Code plugin** for primary-source-first, always-latest documentation.

context7 is a pre-built, periodically-recrawled, lossy vector index. LiveDocs instead
auto-discovers each library's canonical machine-readable source on demand and reads it live.
It can reach raw primary content and the exact latest version, which a pre-built index can't.

## Install

Two slash commands in Claude Code:

```
/plugin marketplace add PsychQuant/livedocs
/plugin install livedocs@livedocs-marketplace
```

**Or just paste this to your AI and it'll set it up for you:**

```
Install the "livedocs" Claude Code plugin from https://github.com/PsychQuant/livedocs.
Run  /plugin marketplace add PsychQuant/livedocs  then  /plugin install livedocs@livedocs-marketplace
```

After installing, just ask your usual documentation/version questions — the bundled
`look-up` skill routes each one to the right tool automatically. (LiveDocs is a network-only
plugin; its MCP server is signed + notarized and distributed through the marketplace.)

## Why this exists

The ecosystem is moving toward machine-discoverable primary sources (`llms.txt`, package
registries, OpenAPI). Live probing of 25 popular docs hosts (2026-06-30) found about 88%
already ship `llms.txt`, and the rest resolve deterministically via package registries. That
makes a pre-built index increasingly redundant for the head of the distribution, and it's a
source LiveDocs can read verbatim.

## Discovery chain (primary-source-first)

1. `llms.txt` / `llms-full.txt`. The LLM-designed index/full dump, probed across root,
   `/docs/`, and full-variant paths, with a soft-404 guard (a real hit is `200` +
   `text/plain` + non-trivial size; many hosts answer `200`/`404` with an HTML shell).
2. Package registry. npm (`registry.npmjs.org/<pkg>/latest`), PyPI (`pypi.org/pypi/<pkg>/json`),
   and 7 more: the exact latest version plus changelog / repo / docs URLs, deterministically, no
   scraping. Version pinning supported.
3. Repo. GitHub README / CHANGELOG / releases (raw).
4. Introspection (`introspect`). Read directly from the machine or installed artifact: an
   OpenAPI / GraphQL schema, an installed CLI's `--help`, or an installed R package's version
   (`kind:"r-pkg"`, read-only). This is the local half of a version check. For a target that has
   both a web-latest and an installed version, the `look-up` skill reconciles them and answers
   from the installed version; the web-latest only gates the upgrade.
5. Fallback. context7 / web, always labeled low-fidelity.

Results are ranked fidelity-first, then freshness. An ETag cache revalidates unchanged sources
cheaply without ever serving stale content; it's bounded (LRU + byte budget) so a long session
can't grow it without limit.

Every outbound fetch is validated (v0.7.0): an `http(s)` scheme allowlist plus a host classifier
that rejects loopback / link-local / private / metadata targets — re-checked on each redirect hop
and against DNS resolution — so a prompt-injection in fetched docs can't steer a request at an
internal address. Response bodies are streamed under a size ceiling (bounds the decompressed size,
defeating gzip bombs), and returned text is stripped of control / ANSI / bidi characters.

## Tools

| Tool | Purpose |
|------|---------|
| `resolve_source` | Ranked primary sources for a library (`library`+`ecosystem` and/or `docs_url`). |
| `fetch_docs` | Raw verbatim text of a source URL. |
| `latest_version` | Latest released version + changelog/repo, from the registry (9 ecosystems; version pinning on npm/pypi). |
| `introspect` | OpenAPI / GraphQL schema, an installed CLI's `--help`, an installed R package's version (`kind:"r-pkg"`), or the effective language-runtime version of the current project (`kind:"runtime"`, Python/Node/Go/Rust/Java/.NET/Swift). Read-only. |

## Architecture

- `LiveDocsCore`. Dependency-free discovery logic (candidate generation, soft-404 classification,
  registry parsing, ranking). Network is injected via the `HTTPClient` protocol, so the engine is
  unit-tested without a server or the network.
- `CheLiveDocsMCP`. A thin MCP stdio shell over the engine.

The fuzzy "which library is this?" decision belongs to the calling agent (the `look-up`
skill); these tools take concrete inputs and do deterministic work.

## Develop

```bash
swift test     # unit tests (pure logic + engine via injected HTTP fakes)
swift build    # builds the MCP executable
```

CI runs `swift build` + `swift test` on every push/PR. `scripts/release.sh` gates the release on a
green `swift test`, a version-source match against the tag, and Developer ID signing + notarization.

### Skill eval (`evals/look-up/`)

A Python harness that measures whether the `look-up` skill actually *fires a LiveDocs query*
for varied end-user prompts and answers currently — the trigger reliability the whole product
depends on. The oracle is rot-proof by design (version cases fetch the registry at eval time rather
than hardcoding a fact), and it's statistical (N runs, rate thresholds).

```bash
pip install -r evals/look-up/requirements.txt
python3 -m pytest evals/look-up/tests/     # 41 harness unit tests (no API calls)
python3 evals/look-up/run_eval.py --dry-run
python3 evals/look-up/run_eval.py --runs 5 # live baseline (real `claude -p` calls)
```

The same directory carries the **vs-context7 freshness comparison** — a dated, honest
head-to-head (registry = neutral ground truth) whose numbers the wiki homepage cites:

```bash
python3 evals/look-up/compare_context7.py                # table + tally
python3 evals/look-up/compare_context7.py --verify-live  # warn if the snapshot drifted
```

See [`evals/look-up/README.md`](evals/look-up/README.md) for the design of both, and
the [Testing wiki page](https://github.com/PsychQuant/livedocs/wiki/Testing) for the full
suite breakdown (151 tests: 110 Swift + 41 Python).

Status: shipped (v0.8.0; engine features below shipped v0.7.0, the skill's `look-up` rename +
explicit invocation landed in v0.8.0). 9-ecosystem registry resolution, version pinning (npm/pypi), OpenAPI/GraphQL/CLI +
installed-R + language-runtime introspection (Python/Node/Go/Rust/Java/.NET/Swift, active-toolchain
authoritative), bounded ETag revalidation cache, SSRF-guarded + size-capped fetch, the
`look-up` skill (per-question has-local/web-only classification + detect/offer version
reconciliation), and a measured vs-context7 freshness comparison cited on the homepage.
Signed+notarized release, marketplace distribution.

Design boundary (what LiveDocs is and isn't for): [docs/wiki/Primary-Source-Spectrum.md](docs/wiki/Primary-Source-Spectrum.md).

Wiki: <https://github.com/PsychQuant/livedocs/wiki>, mirrored 1:1 from `docs/wiki/` via `scripts/sync-wiki.sh` (edit `docs/wiki/`, then run the script).
Positioning (vs context7): [docs/positioning.md](docs/positioning.md).

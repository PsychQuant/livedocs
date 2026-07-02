> English | [繁體中文](Testing-zh-TW)

# Testing

LiveDocs has two independent test suites — **139 tests, all green** (as of v0.7.0). The
Swift suite verifies the engine; the Python suite verifies that the `docs-router` *skill*
actually triggers a LiveDocs query and answers currently. Counts below are a snapshot;
the source of truth is running the suites.

```bash
swift test                                  # 110 Swift tests
python3 -m pytest evals/docs-router/tests/  # 29 Python eval tests
```

## Swift — 110 tests (`swift test`)

Split along the pure-core / MCP-shell architecture. `LiveDocsCore` is dependency-free and
tested without a network (HTTP is injected as a fake); `CheLiveDocsMCP` covers the process
and file-system layer.

### `LiveDocsCoreTests` — 99 (pure logic)

| File | Tests | Covers |
|------|------:|--------|
| `RuntimeIntrospectionTests` | 25 | Language-runtime detection: pin parsers (`.tool-versions`, mise, idiomatic `.<lang>-version`), the precedence engine (active toolchain authoritative), mise inline-comment / array rejection, multi-line / alias rejection. |
| `RegistryAdaptersTests` | 11 | Parsers for all 9 registries (npm / PyPI / crates / go / rubygems / JSR / packagist / maven / CRAN). |
| `URLSafetyTests` | 9 | SSRF guard: scheme allowlist + loopback / link-local (`169.254`) / RFC-1918 / ULA / metadata host classification. |
| `TextSanitizeTests` | 7 | Control / ANSI / OSC / bidi / zero-width stripping of fetched content + UTF-8 byte truncation. |
| `LLMSTxtTests` | 6 | `llms.txt` candidate ordering, soft-404 content-type guard, index/full flavor split. |
| `IntrospectionTests` | 6 | OpenAPI / GraphQL schema parsing (method allowlist, shape-only, deterministic ordering). |
| `RIntrospectionTests` | 6 | Installed-R-package version parsing + safe-name validation. |
| `EngineTests` | 5 | Discovery chain over injected HTTP fakes (registry → llms.txt → repo). |
| `ETagCacheTests` | 5 | ETag revalidation semantics (304 → cached, 200 → refresh, never blind-stale, POST never cached). |
| `RegistryTests` | 5 | Per-ecosystem registry resolution + version pinning. |
| `ClassificationTests` | 4 | Soft-404 hit/miss classification. |
| `ETagCacheLRUTests` | 4 | Cache bounding (LRU eviction, byte budget, oversized-entry refusal). |
| `ValidationTests` | 4 | Boundary validation (package/version strings can't inject URL structure). |
| `RankingTests` | 2 | Fidelity-then-freshness ranking with a stable tiebreak. |

### `CheLiveDocsMCPTests` — 11 (process / file layer)

| File | Tests | Covers |
|------|------:|--------|
| `RuntimeIntrospectTests` | 7 | Symlink version-file refusal (secret-exfil guard), uncovered-language fallback to the universal pin layer, canonical `mise.toml`, PATH-first executable resolution. |
| `ProcessRunnerTests` | 4 | Large output doesn't deadlock (concurrent pipe drain), exit code surfaces, timeout reported, SIGTERM→SIGKILL escalation. |

## Python — 29 tests (`pytest evals/docs-router/`)

The `docs-router` **skill eval harness** — not a test of the Swift engine, but of whether
the skill fires a LiveDocs query for varied prompts and answers currently. See
[`evals/docs-router/README.md`](https://github.com/PsychQuant/livedocs/blob/main/evals/docs-router/README.md).

| File | Tests | Covers |
|------|------:|--------|
| `test_run_eval.py` | 12 | Rate-threshold judging, the N=3 threshold-collapse guard, failed-run / inconclusive handling. |
| `test_oracle.py` | 8 | `self_check` (fetch registry at eval time — rot-proof) / `structural` / `golden` oracles. |
| `test_detect.py` | 7 | `claude -p` stream-json parsing, `is_error` detection, LiveDocs trigger-signal recognition. |
| `test_corpus.py` | 2 | Corpus coverage guards (a golden case exists + a library-named adversarial negative exists). |

## CI and the release gate

- **CI** runs `swift build` + `swift test` on every push and pull request.
- **`scripts/release.sh`** gates a release on a green `swift test`, a version-source match
  against the tag, and Developer ID signing + notarization.
- The **Python eval** is periodic / manual, not per-PR CI — it makes real `claude -p` calls
  (cost + stochastic), so it runs as a maintainer baseline rather than on the critical path.

## Discipline

Security- and robustness-critical surfaces were built test-first (TDD): `URLSafety`,
`TextSanitize`, `ProcessRunner`, and the eval harness each had a failing test before the
implementation. The suite grew 72 → 110 Swift tests during the v0.7.0 hardening (adding the
previously-untested MCP shell layer), and 0 → 29 for the skill eval.

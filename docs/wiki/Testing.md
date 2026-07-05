> English | [繁體中文](Testing-zh-TW)

# Testing

LiveDocs has two independent test suites — **216 tests, all green**. The Swift suite verifies
the engine; the Python suite verifies that the `look-up` *skill* actually triggers a
LiveDocs query and answers currently, plus the vs-context7 comparison harness. Counts below
are a snapshot; the source of truth is running the suites.

```bash
swift test                                  # 144 Swift tests
python3 -m pytest evals/look-up/tests/  # 72 Python eval tests
```

## Swift — 144 tests (`swift test`)

Split along the pure-core / MCP-shell architecture. `LiveDocsCore` is dependency-free and
tested without a network (HTTP is injected as a fake); `CheLiveDocsMCP` covers the process
and file-system layer.

### `LiveDocsCoreTests` — 115 (pure logic)

| File | Tests | Covers |
|------|------:|--------|
| `RuntimeIntrospectionTests` | 30 | Language-runtime detection: pin parsers (`.tool-versions`, mise, idiomatic `.<lang>-version`), the precedence engine (active toolchain authoritative), mise inline-comment / array rejection, multi-line / alias rejection, R toolchain-banner parsing + DESCRIPTION `Depends` constraint, javascript→node canonicalization before the safety gate. |
| `RegistryAdaptersTests` | 15 | Parsers for all 9 registries (npm / PyPI / crates / go / rubygems / JSR / packagist / maven / CRAN), the three per-version confirm parsers (crates/go/rubygems pins), and `supportsVersionPin` coverage. |
| `URLSafetyTests` | 9 | SSRF guard: scheme allowlist + loopback / link-local (`169.254`) / RFC-1918 / ULA / metadata host classification. |
| `TextSanitizeTests` | 7 | Control / ANSI / OSC / bidi / zero-width stripping of fetched content + UTF-8 byte truncation. |
| `LLMSTxtTests` | 6 | `llms.txt` candidate ordering, soft-404 content-type guard, index/full flavor split. |
| `IntrospectionTests` | 6 | OpenAPI / GraphQL schema parsing (method allowlist, shape-only, deterministic ordering). |
| `RIntrospectionTests` | 6 | Installed-R-package version parsing + safe-name validation. |
| `EngineTests` | 12 | Discovery chain over injected HTTP fakes (registry → llms.txt → repo), non-npm/pypi version-pin honoring (`pin_honored` true/false/nil), the latest-only-ecosystem engine path setting `pin_honored=false`, and auto-detect's two-pass pin resolution (fall through npm→PyPI for an exact pin, then fall back to npm latest+false when the pin exists nowhere). |
| `ETagCacheTests` | 5 | ETag revalidation semantics (304 → cached, 200 → refresh, never blind-stale, POST never cached). |
| `RegistryTests` | 5 | Per-ecosystem registry resolution + version pinning. |
| `ClassificationTests` | 4 | Soft-404 hit/miss classification. |
| `ETagCacheLRUTests` | 4 | Cache bounding (LRU eviction, byte budget, oversized-entry refusal). |
| `ValidationTests` | 4 | Boundary validation (package/version strings can't inject URL structure). |
| `RankingTests` | 2 | Fidelity-then-freshness ranking with a stable tiebreak. |

### `CheLiveDocsMCPTests` — 29 (process / file layer)

| File | Tests | Covers |
|------|------:|--------|
| `RuntimeIntrospectTests` | 11 | Symlink version-file refusal (secret-exfil guard), uncovered-language fallback to the universal pin layer, canonical `mise.toml`, PATH-first executable resolution, uppercase-id acceptance with requested-id preservation (R / JavaScript), javascript↔node resolution equivalence. |
| `ProcessRunnerTests` | 4 | Large output doesn't deadlock (concurrent pipe drain), exit code surfaces, timeout reported, SIGTERM→SIGKILL escalation. |
| `LatestVersionEncodingTests` | 14 | `latest_version` tool boundary: `pin_honored` true/false/nil surfacing (incl. `false` in the nothing-resolved path, and absent when no pin asked), the Go `v`-prefix confirmed-pin case (must not read as not-applied), v-prefixed input building a valid confirm URL, npm not-found → latest+false, npm dist-tag / exact-pin discrimination (a moving tag is never a faked pin), RubyGems end-to-end pin (honored + not-found). |

## Python — 72 tests (`pytest evals/look-up/`)

The `look-up` **skill eval harness** — not a test of the Swift engine, but of whether
the skill fires a LiveDocs query for varied prompts and answers currently — plus the
vs-context7 comparison harness. See
[`evals/look-up/README.md`](https://github.com/PsychQuant/livedocs/blob/main/evals/look-up/README.md).

| File | Tests | Covers |
|------|------:|--------|
| `test_run_eval.py` | 17 | Rate-threshold judging, the N=3 threshold-collapse guard, failed-run / inconclusive handling, explicit-invocation route matching, and `args_match` — the right tool with the wrong args (a mis-split `name@version` / dropped ecosystem pin) scores incorrect. |
| `test_compare.py` | 26 | vs-context7 freshness harness: version-token matching (boundary forms), symmetric scoring, table render, README image-embed block drift guard (exactly-one *well-formed* block incl. orphaned sentinel, ISO calendar-date validation, `main()` `--check`/`--write` exit codes + write round-trip), corpus↔sample sync, snapshot-staleness budget (`--check-staleness` with injected `--today` + pinned sample fixture — pure math / fresh / over-budget / boundary / future / malformed / lenient-ISO), `--verify-live` fail-loud exit codes (drift AND unverified both red; registry stubbed), and the wiki Home pages' hand-written competitive numbers vs the sample (table row + prose score + react pair + capture date, both languages). |
| `test_chart.py` | 8 | Per-library vs-context7 SVG chart: `chart_rows` is a verbatim snapshot projection; the committed SVG is **semantically** faithful (each per-library cell bound to the right column via `version_matches`, headline == `tally()`, proven to catch a column swap) — a matplotlib-version-independent drift guard; deterministic render; `--emit-chart` `--check`/`--write` CLI (drift / write round-trip / flag mutual-exclusion). |
| `test_oracle.py` | 8 | `self_check` (fetch registry at eval time — rot-proof) / `structural` / `golden` oracles. |
| `test_detect.py` | 9 | `claude -p` stream-json parsing, `is_error` detection, LiveDocs trigger-signal recognition, and per-call tool-input capture (short name + input args). |
| `test_corpus.py` | 4 | Corpus coverage guards (a golden case exists + a library-named adversarial negative exists + the explicit /livedocs:look-up shape set stays id-exact + the arg-sensitive cases pin their `expected_args`: language degrade, simple/scoped/non-npm-pypi pins, cran+zh, two URL forms, js alias, same-name shadowing, bare no-arg). |

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
previously-untested MCP shell layer), and 0 → 50 for the Python evals (skill eval + vs-context7).

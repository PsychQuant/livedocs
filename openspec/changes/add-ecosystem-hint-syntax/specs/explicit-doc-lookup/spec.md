## MODIFIED Requirements

### Requirement: Explicit invocation routes deterministically by argument shape

The look-up skill SHALL define deterministic routing for explicit invocation with arguments. The first argument token SHALL be classified into exactly one of four shapes — URL, ecosystem-hint, Language, Package — using the following precedence order; CLI introspection is a resolution-time fallback inside the Package shape, not a separate classification. Subsequent tokens SHALL be treated as a topic filter applied when reading the fetched documentation:

1. URL — the token starts with http:// or https:// (the scheme match is case-insensitive). The default route is resolve_source with docs_url followed by fetch_docs. The skill SHALL route to introspect (kind openapi or graphql) instead only when the path is a named API schema/endpoint (case-insensitive: a path ending in /graphql routes to graphql; paths ending in /openapi.json, /openapi.yaml, /swagger.json, or /swagger.yaml route to openapi), or as a best-effort fallback when docs-site resolution returns an empty sources list (then /graphql paths route to graphql and all others to openapi; when that introspection fails to validate, the skill SHALL report that no docs source was found and SHALL NOT claim the URL is an API schema).
2. Ecosystem hint — the token is classified as an ecosystem hint when, splitting once at the FIRST colon into a prefix and a remainder, ALL of these hold: (a) the prefix case-insensitively equals one of the known ecosystem identifiers (npm, pypi, crates, go, rubygems, jsr, packagist, maven, cran); (b) the remainder is non-empty; and (c) the first character of the remainder is NOT a forward slash. Condition (c) separates a hint from a URL scheme, whose colon is followed by two slashes (so npm://x is not a hint); condition (b) means a bare prefix with nothing after the colon (npm:, cran:) is NOT a hint; a prefix that is not a known ecosystem is NOT a hint. In every not-a-hint case the whole token falls through unchanged to Language then Package. When it IS a hint, the skill SHALL use the prefix (lowercased) as the named ecosystem and classify the remainder as a Package per rule 4 — the remainder is the package identifier verbatim and is NOT re-classified as a URL, hint, Language, or CLI, so a remainder that itself contains colons (a Maven group:artifact coordinate, e.g. maven:com.google.guava:guava) stays intact as the package name, and any name@version pin on the remainder is applied per rule 4. An ecosystem hint is the explicit escape hatch that OVERRIDES Language-set shadowing (so npm:go looks up the npm package named go, not the Go runtime) and supplies the ecosystem for named-only registries (so cran:dplyr names CRAN without the invoking agent inferring it). The hint selects a package ecosystem only; it never reaches a URL, a CLI, or a runtime.
3. Language — the token case-insensitively matches a fixed supported-language set (r, python, node, javascript, go, rust, java, dotnet, swift). The engine treats javascript as an alias of node (per the runtime-version-introspection capability); the skill passes the requested identifier through unchanged. A bare language token that is not prefixed by an ecosystem hint routes as Language; to reach a same-named package instead, use the ecosystem hint (e.g. npm:go).
4. Package — any other token, optionally version-pinned with the name@version form. An @ character counts as a version separator only when it is not the first character of the token and the suffix after the LAST @ is non-empty; a leading @ is part of the package name. A trailing @ with an empty suffix means no pin and the trailing @ is stripped from the library name (react@ resolves the library react, not react@). Ecosystem identification belongs to the invoking agent (the one fuzzy step per the decision flow): npm and pypi auto-detect, and the agent SHALL name every other ecosystem explicitly in the call (the ecosystem hint is the user-facing form of naming it). CLI fallback: when package resolution returns no sources and the token names an installed command, the skill SHALL instruct CLI introspection.

#### Scenario: Ecosystem hint overrides language shadowing

- **WHEN** the skill is invoked explicitly with an ecosystem-hint token whose bare name would otherwise match the language set, such as npm:go or crates:swift
- **THEN** the skill strips the ecosystem prefix, classifies the remaining name as a Package in the named ecosystem, and instructs resolve_source with that ecosystem — it does NOT route the token to runtime introspection as a Language

#### Scenario: Ecosystem hint names a named-only registry

- **WHEN** the skill is invoked explicitly with an ecosystem-hint token for a named-only registry, such as cran:dplyr or crates:serde
- **THEN** the skill uses the hinted ecosystem in the resolve_source call for the remaining name, without the invoking agent having to infer the ecosystem from the bare token

#### Scenario: Ecosystem hint is disambiguated from a URL scheme and degenerate forms

- **WHEN** a token begins with a colon-bearing prefix
- **THEN** the skill classifies it as an ecosystem hint only if, splitting once at the first colon, the prefix case-insensitively equals a known ecosystem identifier AND the remainder is non-empty AND the remainder's first character is not a forward slash; a token like https://host (URL), npm:// (remainder starts with a slash), npm: (empty remainder), or foo:bar (prefix not a known ecosystem) is NOT a hint and follows the URL, Language, or Package rule instead — the whole token, colon included, is passed through to those rules

#### Scenario: Ecosystem-hint prefix match is case-insensitive

- **WHEN** the skill is invoked with an ecosystem-hint token whose prefix differs only in case, such as NPM:go or CRAN:dplyr
- **THEN** the skill matches the prefix case-insensitively (consistent with the URL and Language rules), lowercases it to the canonical ecosystem identifier, and classifies the remainder as a Package in that ecosystem

#### Scenario: Ecosystem-hint remainder is not re-classified

- **WHEN** the skill is invoked with an ecosystem-hint token whose remainder itself contains a colon, such as maven:com.google.guava:guava
- **THEN** the skill strips only the first ecosystem: prefix and treats the entire remainder (com.google.guava:guava) as the package identifier for the named ecosystem, without re-interpreting the inner colon as another hint or a URL

#### Scenario: Ecosystem hint carries a version pin

- **WHEN** the skill is invoked with an ecosystem-hint token that also bears a name@version pin, such as crates:serde@1.0.100
- **THEN** the skill resolves the named ecosystem (crates) with the version (1.0.100) via resolve_source, and the version-pin honesty scenario applies to the result

#### Scenario: Language argument anchors to the effective local runtime

- **WHEN** the skill is invoked explicitly with a language name whose runtime the engine resolves (the engine probes Python, Node, Go, Rust, Java, .NET, Swift, and R toolchains)
- **THEN** the skill instructs runtime introspection (introspect with kind runtime) and anchors documentation answers to the effective local runtime version per the existing version-reconciliation contract

#### Scenario: Language runtime not resolved degrades honestly to web-latest

- **WHEN** runtime introspection returns not-resolved for a language token (no version source in the project, or a language the engine has no runtime adapter for)
- **THEN** the skill states that the local runtime version was not resolved and answers from web-latest language documentation, and it SHALL NOT present a guessed version as the local one

#### Scenario: Package argument fetches primary-source docs with agent-named ecosystem

- **WHEN** the skill is invoked explicitly with a package identifier, optionally as name@version
- **THEN** the skill instructs resolve_source (with the version when given, and with the ecosystem named by the invoking agent for non-npm/pypi packages such as CRAN's dplyr) followed by fetch_docs on the top-ranked source

#### Scenario: Version pin honesty is surfaced per ecosystem

- **WHEN** a name@version pin (including an ecosystem-hint pin such as crates:serde@1.0.100) targets an ecosystem
- **THEN** the skill trusts the engine's pin_honored signal: for npm, pypi, crates, go, and rubygems the pin is confirmed at a per-version endpoint (pin_honored true, and the reported version is the pin) when the exact version exists; for jsr, packagist, maven, and cran, or for a version that is not found or a non-exact token, the registry serves its current resolution and the skill states that the pin was not confirmed (pin_honored false) instead of presenting the served version as the pinned one

#### Scenario: URL argument routes by the stated discriminator

- **WHEN** the skill is invoked explicitly with an http(s) URL
- **THEN** the skill routes per the URL rule in Requirement 1: default resolve_source with docs_url, switching to introspect with kind openapi or graphql on an explicit API schema/endpoint path or on an empty docs-site resolution

#### Scenario: Unresolvable bare token falls back to CLI introspection

- **WHEN** the skill is invoked with a bare token, package resolution returns an empty sources list, and the token names an installed command
- **THEN** the skill instructs introspect with kind cli for that command

##### Example: Argument-shape classification

| Input | Classified as | Route |
| ----- | ------------- | ----- |
| R | language | introspect kind runtime — the R depth adapter probes the R/Rscript toolchain; answers anchored to the local R version |
| javascript | language (engine alias to node) | introspect kind runtime target javascript, resolved via the Node adapter and anchored to the local Node version |
| npm:go | ecosystem hint (overrides language shadowing) | resolve_source ecosystem npm for package go, then fetch_docs — NOT runtime introspection |
| cran:dplyr | ecosystem hint (named-only registry) | resolve_source ecosystem cran for package dplyr, then fetch_docs |
| crates:serde@1.0.100 | ecosystem hint plus version pin | resolve_source ecosystem crates version 1.0.100; pin confirmed at the crates per-version endpoint (pin_honored true) when 1.0.100 exists |
| maven:com.google.guava:guava | ecosystem hint; remainder kept verbatim | resolve_source ecosystem maven for package com.google.guava:guava (the inner colon is part of the coordinate, not a second hint) |
| NPM:go | ecosystem hint (case-insensitive prefix) | prefix lowercased to npm; resolve_source ecosystem npm for package go |
| npm: | not a hint (empty remainder) | falls through to Package with the literal token npm: (resolution fails honestly) |
| npm://x | not a hint (remainder starts with a slash) | falls through — not an http(s) URL, so Package with the literal token |
| react@18 | package with a partial version pin | resolve_source with version 18; a partial pin is not an exact version — reported pin_honored false, version is the registry resolution |
| serde@1.0.100 | package with version pin (crates, named by agent) | resolve_source ecosystem crates version 1.0.100; pin confirmed at the per-version endpoint (pin_honored true) when it exists |
| react@ | package, no pin (trailing @ stripped) | resolve_source library react with no version |
| dplyr mutate | package plus topic filter | resolve_source with ecosystem cran (named by the invoking agent), then fetch_docs, read for the mutate topic |
| https://api.example.com/openapi.json | URL (explicit API schema path) | introspect kind openapi |
| https://hono.dev | URL (documentation site) | resolve_source docs_url, then fetch_docs |
| gh | package resolution empty, installed command | introspect kind cli |

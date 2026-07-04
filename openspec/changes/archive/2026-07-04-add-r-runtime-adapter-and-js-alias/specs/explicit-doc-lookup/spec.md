## MODIFIED Requirements

### Requirement: Explicit invocation routes deterministically by argument shape

The look-up skill SHALL define deterministic routing for explicit invocation with arguments. The first argument token SHALL be classified into exactly one of three shapes — URL, Language, Package — using the following precedence order; CLI introspection is a resolution-time fallback inside the Package shape, not a fourth classification. Subsequent tokens SHALL be treated as a topic filter applied when reading the fetched documentation:

1. URL — the token starts with http:// or https:// (the scheme match is case-insensitive). The default route is resolve_source with docs_url followed by fetch_docs. The skill SHALL route to introspect (kind openapi or graphql) instead only when the path is a named API schema/endpoint (case-insensitive: a path ending in /graphql routes to graphql; paths ending in /openapi.json, /openapi.yaml, /swagger.json, or /swagger.yaml route to openapi), or as a best-effort fallback when docs-site resolution returns an empty sources list (then /graphql paths route to graphql and all others to openapi; when that introspection fails to validate, the skill SHALL report that no docs source was found and SHALL NOT claim the URL is an API schema).
2. Language — the token case-insensitively matches a fixed supported-language set (r, python, node, javascript, go, rust, java, dotnet, swift). The engine treats javascript as an alias of node (per the runtime-version-introspection capability); the skill passes the requested identifier through unchanged.
3. Package — any other token, optionally version-pinned with the name@version form. An @ character counts as a version separator only when it is not the first character of the token and the suffix after the LAST @ is non-empty; a leading @ is part of the package name, and an empty suffix means no pin. Ecosystem identification belongs to the invoking agent (the one fuzzy step per the decision flow): npm and pypi auto-detect, and the agent SHALL name every other ecosystem explicitly in the call. CLI fallback: when package resolution returns no sources and the token names an installed command, the skill SHALL instruct CLI introspection.

#### Scenario: Language argument anchors to the effective local runtime

- **WHEN** the skill is invoked explicitly with a language name whose runtime the engine resolves (the engine probes Python, Node, Go, Rust, Java, .NET, Swift, and R toolchains)
- **THEN** the skill instructs runtime introspection (introspect with kind runtime) and anchors documentation answers to the effective local runtime version per the existing version-reconciliation contract

#### Scenario: Language runtime not resolved degrades honestly to web-latest

- **WHEN** runtime introspection returns not-resolved for a language token (no version source in the project, or a language the engine has no runtime adapter for)
- **THEN** the skill states that the local runtime version was not resolved and answers from web-latest language documentation, and it SHALL NOT present a guessed version as the local one

#### Scenario: Package argument fetches primary-source docs with agent-named ecosystem

- **WHEN** the skill is invoked explicitly with a package identifier, optionally as name@version
- **THEN** the skill instructs resolve_source (with the version when given, and with the ecosystem named by the invoking agent for non-npm/pypi packages such as CRAN's dplyr) followed by fetch_docs on the top-ranked source

#### Scenario: Version pin outside npm/pypi is surfaced as not applied

- **WHEN** a name@version pin targets an ecosystem other than npm or pypi
- **THEN** the skill states that the registry serves latest for that ecosystem and that the pin was not applied, instead of silently presenting latest documentation as the pinned version

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
| react@18 | package with version pin | resolve_source with version 18, then fetch_docs |
| serde@1.0.100 | package with version pin (crates, named by agent) | resolve_source ecosystem crates; registry serves latest — pin stated as not applied |
| dplyr mutate | package plus topic filter | resolve_source with ecosystem cran (named by the invoking agent), then fetch_docs, read for the mutate topic |
| https://api.example.com/openapi.json | URL (explicit API schema path) | introspect kind openapi |
| https://hono.dev | URL (documentation site) | resolve_source docs_url, then fetch_docs |
| gh | package resolution empty, installed command | introspect kind cli |

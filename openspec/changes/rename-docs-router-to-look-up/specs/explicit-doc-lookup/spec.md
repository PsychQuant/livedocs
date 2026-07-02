## ADDED Requirements

### Requirement: Explicit invocation routes deterministically by argument shape

The look-up skill SHALL define deterministic routing for explicit invocation with arguments. The first argument token SHALL be classified into exactly one of three shapes — URL, Language, Package — using the following precedence order; CLI introspection is a resolution-time fallback inside the Package shape, not a fourth classification. Subsequent tokens SHALL be treated as a topic filter applied when reading the fetched documentation:

1. URL — the token starts with http:// or https://. The default route is resolve_source with docs_url followed by fetch_docs. The skill SHALL route to introspect (kind openapi or graphql) instead when the URL is explicitly an API schema/endpoint (a path ending in /graphql routes to graphql; paths ending in /openapi.json, /openapi.yaml, or .json route to openapi), or when docs-site resolution returns an empty sources list (then /graphql paths route to graphql and all others to openapi).
2. Language — the token case-insensitively matches a fixed supported-language set (r, python, node, javascript, go, rust, java, dotnet, swift). The skill SHALL normalize javascript to node before introspection.
3. Package — any other token, optionally version-pinned with the name@version form. The version is the substring after the LAST @ character; a leading @ is part of the package name. Ecosystem identification belongs to the invoking agent (the one fuzzy step per the decision flow): npm and pypi auto-detect, and the agent SHALL name every other ecosystem explicitly in the call. CLI fallback: when package resolution returns no sources and the token names an installed command, the skill SHALL instruct CLI introspection.

#### Scenario: Language argument anchors to the effective local runtime

- **WHEN** the skill is invoked explicitly with a language name whose runtime the engine resolves (the engine probes Python, Node, Go, Rust, Java, .NET, and Swift toolchains)
- **THEN** the skill instructs runtime introspection (introspect with kind runtime) and anchors documentation answers to the effective local runtime version per the existing version-reconciliation contract

#### Scenario: Language runtime not resolved degrades honestly to web-latest

- **WHEN** runtime introspection returns not-resolved for a language token (no version source in the project, or a language the engine has no runtime adapter for — R as of this change)
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
| R | language | introspect kind runtime → not-resolved today (engine has no R runtime adapter) → web-latest R docs with the not-resolved caveat stated |
| javascript | language (normalized to node) | introspect kind runtime target node, anchored to the local Node version |
| react@18 | package with version pin | resolve_source with version 18, then fetch_docs |
| serde@1.0.100 | package with version pin (crates, named by agent) | resolve_source ecosystem crates; registry serves latest — pin stated as not applied |
| dplyr mutate | package plus topic filter | resolve_source with ecosystem cran (named by the invoking agent), then fetch_docs, read for the mutate topic |
| https://api.example.com/openapi.json | URL (explicit API schema path) | introspect kind openapi |
| https://hono.dev | URL (documentation site) | resolve_source docs_url, then fetch_docs |
| gh | package resolution empty, installed command | introspect kind cli |

### Requirement: Explicit invocation without arguments degrades to routing guidance

The look-up skill SHALL treat explicit invocation with no arguments as a request to load its routing guidance, identical in effect to implicit invocation. It SHALL NOT error or demand an argument.

#### Scenario: Bare explicit invocation

- **WHEN** the user invokes the skill explicitly with no arguments
- **THEN** the skill content loads and subsequent library or tool questions in the session follow the existing decision flow

### Requirement: Explicit targets remain subject to engine-layer guards

Explicit invocation SHALL NOT bypass the MCP engine's safety layer: URL targets remain subject to the engine's SSRF host classifier on every outbound fetch, and CLI targets remain subject to the engine's command-safety allowlist and argv-only execution. The skill layer adds routing only.

#### Scenario: Hostile URL target is refused by the engine guard

- **WHEN** an explicit invocation supplies a URL resolving to a loopback, link-local, private-range, or metadata address
- **THEN** the engine's SSRF guard refuses the fetch and the skill reports the refusal instead of retrying around it

### Requirement: Rename preserves the implicit triggering contract

The skill SHALL be published under the name look-up, and the rename SHALL NOT alter implicit (model-invoked) triggering behavior: the question-oriented frontmatter description SHALL carry the same triggering semantics as before the rename, and both invocation modes SHALL remain enabled (neither disable-model-invocation nor user-invocable restrictions are set).

#### Scenario: Explicit command available under the new name only

- **WHEN** the plugin is installed from the marketplace after this change
- **THEN** the skill is invocable as /livedocs:look-up and no docs-router skill is present

#### Scenario: Implicit auto-fire unaffected

- **WHEN** a session asks a library, framework, or CLI question without naming the skill
- **THEN** the skill loads automatically based on its description, with routing behavior identical to the pre-rename skill

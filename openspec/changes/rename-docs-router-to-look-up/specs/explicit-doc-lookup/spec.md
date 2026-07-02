## ADDED Requirements

### Requirement: Explicit invocation routes deterministically by argument shape

The look-up skill SHALL define deterministic routing for explicit invocation with arguments. The first argument token SHALL be classified into exactly one target shape using the following precedence order, and subsequent tokens SHALL be treated as a topic filter applied when reading the fetched documentation:

1. URL — the token starts with http:// or https://
2. Language — the token case-insensitively matches a fixed supported-language set (r, python, node, javascript, go, rust, java, dotnet, swift)
3. Package — any other token, optionally version-pinned with the name@version form; ecosystem resolution follows the existing decision-flow rules (npm and pypi auto-detect, other ecosystems named explicitly)
4. CLI fallback — when package resolution returns no sources and the token names an installed command, the skill SHALL instruct CLI introspection

#### Scenario: Language argument anchors to the effective local runtime

- **WHEN** the skill is invoked explicitly with a language name (for example R)
- **THEN** the skill instructs runtime introspection (introspect with kind runtime) and anchors documentation answers to the effective local runtime version per the existing version-reconciliation contract

#### Scenario: Package argument fetches primary-source docs

- **WHEN** the skill is invoked explicitly with a package identifier, optionally as name@version
- **THEN** the skill instructs resolve_source (with the version when given) followed by fetch_docs on the top-ranked source

#### Scenario: URL argument routes to API introspection or docs-site resolution

- **WHEN** the skill is invoked explicitly with an http(s) URL
- **THEN** the skill instructs introspect with kind openapi or graphql for API-endpoint URLs, and resolve_source with docs_url for documentation-site URLs

#### Scenario: Unresolvable bare token falls back to CLI introspection

- **WHEN** the skill is invoked with a bare token, package resolution returns an empty sources list, and the token names an installed command
- **THEN** the skill instructs introspect with kind cli for that command

##### Example: Argument-shape classification

| Input | Classified as | Route |
| ----- | ------------- | ----- |
| R | language | introspect kind runtime, then language docs anchored to local version |
| react@18 | package with version pin | resolve_source with version 18, then fetch_docs |
| dplyr mutate | package plus topic filter | resolve_source then fetch_docs, read for the mutate topic |
| https://api.example.com | URL (API endpoint) | introspect kind openapi |
| gh | package resolution empty, installed command | introspect kind cli |

### Requirement: Explicit invocation without arguments degrades to routing guidance

The look-up skill SHALL treat explicit invocation with no arguments as a request to load its routing guidance, identical in effect to implicit invocation. It SHALL NOT error or demand an argument.

#### Scenario: Bare explicit invocation

- **WHEN** the user invokes the skill explicitly with no arguments
- **THEN** the skill content loads and subsequent library or tool questions in the session follow the existing decision flow

### Requirement: Rename preserves the implicit triggering contract

The skill SHALL be published under the name look-up, and the rename SHALL NOT alter implicit (model-invoked) triggering behavior: the question-oriented frontmatter description SHALL carry the same triggering semantics as before the rename, and both invocation modes SHALL remain enabled (neither disable-model-invocation nor user-invocable restrictions are set).

#### Scenario: Explicit command available under the new name only

- **WHEN** the plugin is installed from the marketplace after this change
- **THEN** the skill is invocable as /livedocs:look-up and no docs-router skill is present

#### Scenario: Implicit auto-fire unaffected

- **WHEN** a session asks a library, framework, or CLI question without naming the skill
- **THEN** the skill loads automatically based on its description, with routing behavior identical to the pre-rename skill

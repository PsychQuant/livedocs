## MODIFIED Requirements

### Requirement: Context-aware reconciliation trigger

The system SHALL separate reconciliation into a **detect** phase and a **surface** phase.

In the **detect** phase, when a query occurs inside a project with a resolvable local target (an installed package, CLI, or language runtime), the system SHALL eagerly resolve the local version and silently anchor the answer to it. The detect result SHALL be cached per project working directory so the local lookup is not repeated on every interaction, and web-latest revalidation SHALL rely on conditional revalidation (ETag) to stay current without full re-download.

In the **surface** phase, the system SHALL present an upgrade prompt only when the answer is version-sensitive OR an actual version skew or error is observed, and SHALL NOT surface upgrade prompts for queries where the version gap is irrelevant.

For a bare conceptual query with no consuming project in context, the system SHALL NOT perform the local lookup.

#### Scenario: Detect eagerly and anchor silently inside a project

- **WHEN** a query occurs inside a project with a resolvable local target
- **THEN** the system resolves the local version once, caches it for that working directory, and silently answers from the local version without prompting to upgrade

#### Scenario: Surface an upgrade only when relevant

- **WHEN** the local version is behind web-latest AND the query is version-sensitive or an actual skew/error is observed
- **THEN** the system surfaces an upgrade prompt
- **AND** for an unrelated query where the version gap does not affect the answer, the system does not surface an upgrade prompt

#### Scenario: Bare conceptual query outside a consuming project

- **WHEN** a `has-local` query is a general "how does X work" with no consuming project in context
- **THEN** the system does NOT perform the local lookup and answers from web-latest primary source

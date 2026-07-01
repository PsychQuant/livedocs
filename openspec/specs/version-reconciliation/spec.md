# version-reconciliation Specification

## Purpose

TBD - created by archiving change 'add-target-type-version-reconciliation'. Update Purpose after archive.

## Requirements

### Requirement: Defer-to-local terminal invariant
For a `has-local` query, the system SHALL treat the **locally installed version as the authoritative source for the answer** in every branch. The web-latest version SHALL be used only to (a) detect that the local copy is behind and (b) offer an upgrade — never as the answer itself.

#### Scenario: Local equals latest
- **WHEN** the installed version equals the web-latest version
- **THEN** the system answers from the local installed docs and does not prompt to upgrade

#### Scenario: Web is newer, user declines upgrade
- **WHEN** web-latest is newer than the installed version AND the user declines to upgrade
- **THEN** the system answers from the (unchanged) local installed docs

#### Scenario: Web is newer, user accepts upgrade
- **WHEN** web-latest is newer AND the user confirms the upgrade
- **THEN** the new version is installed and the system answers from the now-updated local installed docs


<!-- @trace
source: add-target-type-version-reconciliation
updated: 2026-07-01
code:
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-commit/SKILL.md
  - README.md
  - Tests/LiveDocsCoreTests/RIntrospectionTests.swift
  - Sources/LiveDocsCore/RIntrospection.swift
  - plugins/livedocs/skills/docs-router/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - CHANGELOG.md
  - .spectra.yaml
  - Sources/CheLiveDocsMCP/Server.swift
  - Sources/CheLiveDocsMCP/RIntrospect.swift
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
-->

---
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

---
### Requirement: Install is a confirmed, skill-executed mutation
When an upgrade is chosen, the install SHALL be executed by the skill/model layer (running the ecosystem's install command) only after explicit user confirmation. The MCP layer SHALL NOT perform installs and SHALL remain read-only.

#### Scenario: Upgrade requires explicit confirmation
- **WHEN** web-latest is newer than installed
- **THEN** the system requests explicit user confirmation before running any install command
- **AND** if confirmation is not given, no environment mutation occurs

<!-- @trace
source: add-target-type-version-reconciliation
updated: 2026-07-01
code:
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-commit/SKILL.md
  - README.md
  - Tests/LiveDocsCoreTests/RIntrospectionTests.swift
  - Sources/LiveDocsCore/RIntrospection.swift
  - plugins/livedocs/skills/docs-router/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - CHANGELOG.md
  - .spectra.yaml
  - Sources/CheLiveDocsMCP/Server.swift
  - Sources/CheLiveDocsMCP/RIntrospect.swift
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
-->

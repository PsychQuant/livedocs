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
The system SHALL enter version reconciliation only when it is contextually warranted — specifically when the query occurs inside a project that uses the package, OR the query is version/upgrade/debug-shaped — and SHALL otherwise avoid the local lookup to bound latency and noise.

#### Scenario: Bare conceptual query outside a consuming project
- **WHEN** a `has-local` query is a general "how does X work" with no consuming project in context
- **THEN** the system does NOT perform the local lookup and answers from web-latest primary source

#### Scenario: Version/upgrade/debug-shaped query
- **WHEN** the query is version-, upgrade-, or debug-shaped (e.g. "why doesn't X work", "should I upgrade")
- **THEN** the system performs reconciliation even outside an obvious project context


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
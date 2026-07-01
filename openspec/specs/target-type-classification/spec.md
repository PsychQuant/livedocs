# target-type-classification Specification

## Purpose

TBD - created by archiving change 'add-target-type-version-reconciliation'. Update Purpose after archive.

## Requirements

### Requirement: Per-question target-type classification
The system SHALL classify each documentation query by whether a **local, version-matched authoritative source exists for that specific query** — not by target identity — and route accordingly: `has-local` queries to version reconciliation, `web-only` queries to direct web-latest fetch.

#### Scenario: Web-only feature/config question
- **WHEN** a query asks about a hosted tool's features or configuration whose authoritative docs live only online (e.g. "how do I configure MCP in Claude Code")
- **THEN** the query is classified `web-only`
- **AND** it is routed to a direct web-latest fetch with no version reconciliation and no upgrade prompt

#### Scenario: Installed-artifact question on the same tool
- **WHEN** a query about the SAME tool concerns behavior of a locally installed artifact (e.g. "what flags does the installed `claude` CLI accept")
- **THEN** the query is classified `has-local` (per-question, independent of how the tool's other questions classify)
- **AND** it is routed to introspect the installed artifact

#### Scenario: Package usage question inside a consuming project
- **WHEN** a query concerns how to use an installed package (e.g. "how do I use dplyr::across") while a local, version-matched copy is resolvable
- **THEN** the query is classified `has-local` and eligible for version reconciliation

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
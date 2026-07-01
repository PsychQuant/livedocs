## ADDED Requirements

### Requirement: Read-only installed-version introspection
The MCP `introspect` tool SHALL gain an installed-package mode that returns the **locally installed version** (and, where applicable, the installed help) of a package or CLI, WITHOUT mutating the environment. Installs and upgrades are out of scope for the MCP.

#### Scenario: Query installed package version
- **WHEN** `introspect` is invoked for an installed package (e.g. an R package via `packageVersion`)
- **THEN** it returns the installed version string without modifying any environment

#### Scenario: MCP never installs
- **WHEN** any introspection request is made
- **THEN** the MCP performs only read operations and never runs an install/upgrade command

### Requirement: cwd-project-scoped environment resolution
Installed-version introspection SHALL resolve "which installed version" from the **current project context** — the cwd's `node_modules` for npm, the active virtualenv/conda for Python, the default `.libPaths()` for R — rather than assuming a single global environment.

#### Scenario: Version resolved from the active project environment
- **WHEN** the query runs inside a project with a project-local environment (e.g. a virtualenv or a project `node_modules`)
- **THEN** the returned installed version reflects that project environment, not a global install

#### Scenario: No resolvable local environment
- **WHEN** no project-scoped environment can be resolved for the package
- **THEN** the tool reports "not installed in the current context" rather than reporting a misleading global version

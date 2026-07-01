## ADDED Requirements

### Requirement: Read-only effective runtime version resolution

The system SHALL provide a read-only introspection mode that resolves the **effective language-runtime version** in use for a project (the version of the interpreter, compiler, or toolchain that actually runs the code). This mode SHALL perform only read operations and SHALL NOT install, switch, or otherwise mutate the runtime environment.

#### Scenario: Resolve effective runtime version

- **WHEN** runtime introspection is invoked for a project whose language runtime can be determined
- **THEN** the system returns the effective runtime version together with the source that determined it and that source's semantics, without modifying any environment

#### Scenario: Introspection never mutates the environment

- **WHEN** any runtime introspection request is made
- **THEN** the system performs only read operations and never runs an install, upgrade, or version-switch command

### Requirement: Two-layer resolution with a universal pin layer and per-language depth adapters

The system SHALL resolve the runtime version through two layers. A **universal pin layer** SHALL read cross-language version-declaration sources — the asdf `.tool-versions` file, the mise configuration file, and idiomatic per-language version files (for example `.python-version`, `.nvmrc`, `.ruby-version`) — to obtain a declared version for any covered language. A **per-language depth-adapter layer** SHALL, for supported languages, additionally probe the active toolchain and read the language's manifest declaration.

#### Scenario: Declared version from the universal pin layer

- **WHEN** a project has an asdf `.tool-versions` or idiomatic per-language version file but no depth adapter runs
- **THEN** the system returns the declared version from the universal pin layer

#### Scenario: Depth adapter augments with the active toolchain

- **WHEN** a project's language has a depth adapter AND an active toolchain is present
- **THEN** the system returns the active toolchain version and records the manifest declaration as cross-check context

### Requirement: Active-toolchain-authoritative precedence

The system SHALL treat the **active toolchain** (the runtime that actually executes) as the authoritative source of the effective version. Declared sources SHALL be used only to cross-check or to fall back when no active toolchain is present, and SHALL be interpreted by their semantics: a **constraint** (for example `requires-python >=3.9`) SHALL NOT be treated as an exact version but only as a lower bound for cross-check; a **directive** (for example the `go.mod` `go` version) SHALL be recorded as the declared language version; a **language-mode** declaration (for example `swift-tools-version`) SHALL NOT be treated as the compiler or interpreter version.

#### Scenario: Active toolchain overrides a looser constraint

- **WHEN** the manifest declares a constraint and the active toolchain reports a specific version satisfying it
- **THEN** the system returns the active toolchain version, not the constraint text

#### Scenario: Pin file used when no active toolchain is present

- **WHEN** a project has an exact pin file but no resolvable active toolchain
- **THEN** the system returns the pinned version

##### Example: precedence across sources

| Project state | Effective version | Rationale |
| ------------- | ----------------- | --------- |
| active venv reports 3.12.1; pyproject `requires-python >=3.9` | 3.12.1 | active toolchain authoritative; constraint is a lower bound only |
| `.python-version` = 3.11.4; no active venv | 3.11.4 | exact pin file; no active toolchain present |
| `Package.swift` `swift-tools-version:5.9`; `swift --version` = 6.0 | 6.0 | swift-tools-version is language-mode, not the compiler version |
| `go.mod` `go 1.21`; `go version` = 1.22 | 1.22 | active toolchain authoritative; directive recorded as declared language version |

### Requirement: Honest not-resolved fallback and cwd-project-scoped resolution

The system SHALL resolve the runtime version from the **current project context** (the working directory's environment) rather than assuming a single global runtime. When no runtime version can be reliably resolved for the project context, the system SHALL report a not-resolved result with a reason and SHALL NOT report a misleading global version.

#### Scenario: Project-scoped resolution

- **WHEN** introspection runs inside a project with a project-local environment (for example an active virtualenv or a project toolchain file)
- **THEN** the returned version reflects that project context, not an unrelated global install

#### Scenario: No resolvable runtime

- **WHEN** no runtime version can be resolved for the project context
- **THEN** the system reports "not resolved" with a reason rather than reporting a global version

### Requirement: Initial depth-adapter language coverage

The system SHALL provide depth adapters for at least the following languages: Python, Node/TypeScript, Go, Rust, Java, C#/.NET, and Swift. Languages without a depth adapter SHALL still receive declared-version coverage through the universal pin layer.

#### Scenario: Covered language uses its depth adapter

- **WHEN** introspection runs for one of the listed languages in a project using it
- **THEN** the system uses that language's depth adapter for active-toolchain and manifest resolution

#### Scenario: Uncovered language falls back to the universal pin layer

- **WHEN** introspection runs for a language without a depth adapter but with a version-declaration file
- **THEN** the system returns the declared version from the universal pin layer

### Requirement: Boundary validation of runtime targets

The system SHALL validate any language identifier or target used to select an adapter or to construct a toolchain command before use, and SHALL reject unsafe values rather than passing them into command execution.

#### Scenario: Unsafe target rejected

- **WHEN** a runtime introspection target contains characters outside the safe set for a language identifier or command
- **THEN** the system rejects the request and does not execute any command with the unsafe value

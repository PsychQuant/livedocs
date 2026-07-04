## MODIFIED Requirements

### Requirement: Initial depth-adapter language coverage

The system SHALL provide depth adapters for at least the following languages: Python, Node/TypeScript, Go, Rust, Java, C#/.NET, Swift, and R. Languages without a depth adapter SHALL still receive declared-version coverage through the universal pin layer.

#### Scenario: Covered language uses its depth adapter

- **WHEN** introspection runs for one of the listed languages in a project using it
- **THEN** the system uses that language's depth adapter for active-toolchain and manifest resolution

#### Scenario: Uncovered language falls back to the universal pin layer

- **WHEN** introspection runs for a language without a depth adapter but with a version-declaration file
- **THEN** the system returns the declared version from the universal pin layer

#### Scenario: R runtime resolves from the active toolchain

- **WHEN** introspection runs for R in a project with an installed R toolchain
- **THEN** the R depth adapter probes the R command (falling back to Rscript) with the version flag and reports the active toolchain version as authoritative

#### Scenario: R DESCRIPTION dependency is treated as a constraint

- **WHEN** a project's DESCRIPTION file declares a minimum R version in its Depends field and no active R toolchain is present
- **THEN** the declared value is interpreted with constraint semantics (a lower bound for cross-check), never reported as the exact effective version

## ADDED Requirements

### Requirement: JavaScript language identifier aliases to Node

The system SHALL treat the language identifier javascript as an alias of node: runtime introspection invoked with target javascript SHALL resolve through the Node depth adapter, SHALL report the result under the requested identifier (javascript), and the resolution source SHALL disclose the Node probe that produced the version.

#### Scenario: javascript target resolves via the Node adapter

- **WHEN** introspect with kind runtime is invoked with target javascript in a project with an active Node toolchain
- **THEN** the result carries languageId javascript with the Node toolchain version, and the resolution source names the node command that was probed

#### Scenario: javascript alias never fabricates a distinct runtime

- **WHEN** no Node toolchain or Node version source is resolvable
- **THEN** a javascript-targeted introspection returns not-resolved exactly as a node-targeted one would, with no javascript-specific version invented

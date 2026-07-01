> English | [繁體中文](Version-Reconciliation-zh-TW)

# Version Reconciliation

## Step 0 — is there a local target to reconcile against? (per-question)

Classify *this specific query*, not the tool as a whole:

- **web-only** — nothing version-matched to check locally: hosted docs, a SaaS or REST API,
  or a tool's feature/config docs. Answer from web-latest. No reconciliation, no upgrade
  prompt, no `introspect` call — you don't "install" web docs.
- **has-local** — the answer depends on a local artifact: an installed package's API, an
  installed CLI's flags or version, or the project's language runtime. Run detect/surface below.

Claude Code is the tricky one, and it splits per-question. "How do I configure MCP in Claude
Code" is web-only — the answer lives in the online docs; there's no local artifact to introspect
for config semantics. "What flags does the installed `claude` take", or "does my installed
version have feature X", is has-local — introspect the CLI's version and flags. Same tool,
opposite branches, decided by the question.

## Has-local — detect, then surface

For a has-local query LiveDocs anchors the answer to the local version. The governing rule:

> Answer from your local version. The web-latest is used only to detect that you're behind and
> to offer an upgrade, never as the answer itself.

Two phases, so it can be proactive without being noisy:

- Detect (eager, cached, silent): resolve the local version once, cache it per working
  directory, anchor every answer to it. Web-latest stays current cheaply through the ETag
  revalidation cache.
- Surface (lazy, only when relevant): prompt about upgrading only when the answer is
  version-sensitive or an actual skew/error shows up.

```mermaid
flowchart TD
    Q["Docs query"] --> C{"Step 0 (per-question):<br/>is there a local, version-matched<br/>target? (package / CLI / runtime)"}
    C -->|"web-only<br/>(hosted docs, SaaS,<br/>a tool's config / how-to Qs)"| W["Answer from web-latest<br/>(no reconciliation, no introspect)"]
    C -->|"has-local"| D["DETECT: resolve local version once,<br/>cache per cwd, anchor answer<br/>(eager, silent)"]
    D --> A["Answer from LOCAL version"]
    A --> S{"Version-sensitive query,<br/>OR skew / error observed?"}
    S -->|"no"| DONE["done — no upgrade prompt"]
    S -->|"yes, web newer"| U{"Upgrade?<br/>(explicit confirm)"}
    U -->|"decline"| A
    U -->|"confirm"| INS["skill installs / upgrades<br/>(MCP stays read-only)"]
    INS --> A
```

## Local sources

- Installed package: `introspect{kind:"r-pkg", target:"<pkg>"}` (R; npm/pip to come).
- Installed CLI: `introspect{kind:"cli", target:"<cmd>"}`.
- Language runtime: `introspect{kind:"runtime", target:"<language>" or "auto"}` for Python,
  Node/TypeScript, Go, Rust, Java, C#/.NET, and Swift. It returns the effective runtime
  version: the active toolchain is authoritative; declared pins (`.python-version`, `go.mod`
  `go`, `swift-tools-version`, …) only cross-check; a bare constraint or a language-mode
  declaration returns not-resolved rather than a guessed version. A project pinned to Python
  3.11 gets 3.11 answers, not 3.13.

## Notes

- Classification is per-question, not per-tool — the Claude Code split above is the canonical
  case. A tool can land on either branch depending on what is being asked.
- Installed resolution is cwd-scoped: a Python venv, npm `node_modules`, or the project's
  runtime toolchain, never a misleading global assumption.
- Install is a confirmed mutation, run by the skill after explicit confirmation. The MCP itself
  stays read-only; it introspects, it never installs.

See also: [Primary-Source Spectrum](Primary-Source-Spectrum), the product boundary.

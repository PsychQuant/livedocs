import Foundation

// MARK: - Types

/// What a version-declaration source *means*. The precedence engine treats these
/// differently: an `activeToolchain` reading is what actually runs (authoritative);
/// an `exactVersion` pin file names a concrete version; a `directive` (e.g. the
/// `go.mod` `go` line) is a real declared language version; a `constraint`
/// (e.g. `requires-python >=3.9`) is only a lower bound, NOT a version; a
/// `languageMode` (e.g. `swift-tools-version`) is a manifest language mode, NOT
/// the compiler/interpreter version.
public enum PinSemantics: Equatable, Sendable {
    case activeToolchain
    case exactVersion
    case directive
    case constraint
    case languageMode
}

/// One candidate reading of the runtime version, tagged with where it came from
/// and what it means. The precedence engine ranks a set of these.
public struct PinCandidate: Equatable, Sendable {
    public let version: String
    public let source: String
    public let semantics: PinSemantics
    public init(version: String, source: String, semantics: PinSemantics) {
        self.version = version; self.source = source; self.semantics = semantics
    }
}

/// The effective-runtime-version result. Mirrors `RInstalledResult`'s honesty:
/// when nothing authoritative can be determined we say so (with a reason) rather
/// than fabricating a version.
public enum RuntimeResolution: Equatable, Sendable {
    case resolved(version: String, source: String, semantics: PinSemantics, env: String)
    case notResolved(reason: String)
}

/// Languages with a depth adapter (active-toolchain probe + manifest semantics).
/// Languages outside this set still get declared-version coverage via the
/// universal pin layer.
public enum RuntimeLanguage: String, CaseIterable, Sendable {
    case python, node, go, rust, java, dotnet, swift
}

// MARK: - Precedence engine

/// Resolve the effective runtime version from a set of candidates. The **active
/// toolchain** (what actually executes) is authoritative; an exact pin file is
/// next; a directive (a declared language version) is next. A bare constraint or
/// a language-mode declaration is NOT an exact version — if that is all we have,
/// we report not-resolved instead of guessing.
public func resolveEffectiveRuntime(_ candidates: [PinCandidate], env: String) -> RuntimeResolution {
    for sem in [PinSemantics.activeToolchain, .exactVersion, .directive] {
        if let c = candidates.first(where: { $0.semantics == sem }) {
            return .resolved(version: c.version, source: c.source, semantics: c.semantics, env: env)
        }
    }
    if candidates.contains(where: { $0.semantics == .constraint || $0.semantics == .languageMode }) {
        return .notResolved(reason: "only a constraint or language-mode declaration was found; the actual runtime version could not be determined")
    }
    return .notResolved(reason: "no runtime version source found in the project context")
}

// MARK: - Universal pin layer

/// Parse an asdf `.tool-versions` file: `lang version` per line, `#` comments and
/// blank lines skipped. Returns a map of tool name → declared version.
public func parseToolVersions(_ content: String) -> [String: String] {
    var out: [String: String] = [:]
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") { continue }
        let parts = t.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count >= 2 { out[String(parts[0])] = String(parts[1]) }
    }
    return out
}

/// Parse the `[tools]` section of a mise config (`.mise.toml` / `mise.toml`):
/// `key = "value"`. Deliberately minimal — only the tools table, only bare string
/// values. Inline comments are stripped and array / inline-table values are
/// rejected (they aren't a single version), so `python = "3.11" # main` yields
/// `3.11`, not `3.11" # main`, and `python = ["3.11","3.10"]` is skipped.
public func parseMiseToml(_ content: String) -> [String: String] {
    var out: [String: String] = [:]
    var inTools = false
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[") { inTools = (t == "[tools]"); continue }
        guard inTools, let eq = t.firstIndex(of: "=") else { continue }
        let key = t[..<eq].trimmingCharacters(in: .whitespaces)
        var raw = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        // Array / inline-table values aren't a single version — skip them.
        if raw.hasPrefix("[") || raw.hasPrefix("{") { continue }
        // `stripTomlInlineComment` removes a comment that starts outside quotes,
        // so a `#` inside a quoted value survives (rare, but not a comment).
        raw = stripTomlInlineComment(raw)
        let val = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        // Reject unbalanced-quote residue after unquoting (a malformed value).
        if val.isEmpty || val.contains("\"") || val.contains("'") { continue }
        if !key.isEmpty { out[String(key)] = val }
    }
    return out
}

/// Drop an inline `#` comment that begins *outside* a quoted string.
private func stripTomlInlineComment(_ s: String) -> String {
    var quote: Character? = nil
    var result = ""
    for ch in s {
        if let q = quote {
            result.append(ch)
            if ch == q { quote = nil }
            continue
        }
        if ch == "\"" || ch == "'" { quote = ch; result.append(ch); continue }
        if ch == "#" { break }
        result.append(ch)
    }
    return result.trimmingCharacters(in: .whitespaces)
}

/// Parse an idiomatic per-language version file (`.python-version`, `.nvmrc`,
/// `.ruby-version`, …): the **first non-empty, non-comment line**, optionally
/// prefixed `v`. Rejects a value that doesn't start with a digit — pyenv allows
/// multiple lines, and `.nvmrc` permits aliases (`lts/gallium`, `node`, `stable`)
/// that are NOT versions and must not be echoed as one. Returns nil when there is
/// no version-shaped line.
public func parseIdiomaticVersionFile(_ content: String) -> String? {
    for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line.hasPrefix("v"), let second = line.dropFirst().first, second.isNumber { line.removeFirst() }
        guard let first = line.first, first.isNumber else { return nil }
        return line
    }
    return nil
}

// MARK: - Per-language declaration parsers

/// `requires-python = ">=3.9"` from pyproject.toml — a **constraint**.
public func parsePyprojectRequiresPython(_ content: String) -> String? {
    firstCapture(content, #"requires-python\s*=\s*["']([^"']+)["']"#)
}

/// `engines.node` from package.json — a **constraint**.
public func parsePackageJsonEnginesNode(_ content: String) -> String? {
    guard let data = content.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let engines = obj["engines"] as? [String: Any],
          let node = engines["node"] as? String else { return nil }
    return node
}

/// The `go X.Y` directive from go.mod — a declared language version (**directive**).
public func parseGoModDirective(_ content: String) -> String? {
    for line in content.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("go "), let v = firstVersionToken(t) { return v }
    }
    return nil
}

/// `sdk.version` from a .NET global.json — an **exact** SDK pin.
public func parseGlobalJsonSdk(_ content: String) -> String? {
    guard let data = content.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sdk = obj["sdk"] as? [String: Any],
          let v = sdk["version"] as? String else { return nil }
    return v
}

/// `// swift-tools-version:5.9` from Package.swift — a **language-mode**, NOT the
/// compiler version.
public func parseSwiftToolsVersion(_ content: String) -> String? {
    firstCapture(content, #"swift-tools-version:\s*([0-9]+(?:\.[0-9]+){0,2})"#)
}

// MARK: - Active-toolchain output parsers

/// Parse the version out of a toolchain's `--version` output. The generic first
/// `X.Y[.Z]` token handles every target here (`Python 3.12.1`, `v20.1.0`,
/// `go version go1.22 …`, `rustc 1.75.0 …`, `openjdk version "21.0.1"`,
/// `Apple Swift version 6.0`, bare `8.0.100`). The language parameter is kept so
/// a target can diverge later without changing callers.
public func parseToolchainVersion(_ raw: String, language: RuntimeLanguage) -> String? {
    firstVersionToken(raw)
}

// MARK: - Language detection

/// Which depth-adapter languages a project uses, inferred from files present in
/// the working directory. Order follows `RuntimeLanguage.allCases` for
/// determinism.
public func detectLanguages(files: Set<String>) -> [RuntimeLanguage] {
    func any(_ names: Set<String>) -> Bool { !files.isDisjoint(with: names) }
    func anySuffix(_ suffixes: [String]) -> Bool {
        files.contains { f in suffixes.contains { f.hasSuffix($0) } }
    }
    var out: [RuntimeLanguage] = []
    if any(["pyproject.toml", ".python-version", "setup.py", "Pipfile", "requirements.txt"]) { out.append(.python) }
    if any(["package.json", ".nvmrc"]) { out.append(.node) }
    if any(["go.mod"]) { out.append(.go) }
    if any(["Cargo.toml", "rust-toolchain.toml", "rust-toolchain"]) { out.append(.rust) }
    if any(["pom.xml", ".java-version", "build.gradle", "build.gradle.kts"]) { out.append(.java) }
    if any(["global.json"]) || anySuffix([".csproj", ".fsproj", ".sln"]) { out.append(.dotnet) }
    if any(["Package.swift", ".swift-version"]) { out.append(.swift) }
    return out
}

// MARK: - Boundary validation

private let languageIdAllowed = CharacterSet(charactersIn:
    "abcdefghijklmnopqrstuvwxyz0123456789.+#-")

/// A language identifier is safe to select an adapter or build a command with if
/// it's a short, lowercase token of identifier-ish characters. Rejects paths,
/// whitespace, and shell metacharacters before any value reaches command
/// execution.
public func isSafeLanguageId(_ id: String) -> Bool {
    guard !id.isEmpty, id.count <= 32 else { return false }
    return id.unicodeScalars.allSatisfy { languageIdAllowed.contains($0) }
}

// MARK: - Regex helpers

private func firstCapture(_ s: String, _ pattern: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}

/// First `X.Y` or `X.Y.Z` version token in a string.
private func firstVersionToken(_ s: String) -> String? {
    firstCapture(s, #"([0-9]+\.[0-9]+(?:\.[0-9]+)?)"#)
}

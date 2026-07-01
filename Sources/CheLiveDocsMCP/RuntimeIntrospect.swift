import Foundation
import LiveDocsCore

/// Resolves the effective language-runtime version for a project directory. This
/// is the MCP-side execution half of runtime-version-introspection: it reads the
/// version-declaration files and probes the active toolchain, then hands the
/// gathered candidates to the pure `resolveEffectiveRuntime` precedence engine in
/// LiveDocsCore.
///
/// READ-ONLY: reads files and runs `<toolchain> --version`. It never installs,
/// switches, or mutates anything. The toolchain command is a fixed per-language
/// literal (never a tool argument), and the language id is validated via
/// `isSafeLanguageId` before selecting an adapter.
enum RuntimeIntrospect {

    struct LanguageResult {
        /// The language identifier (an adapter language's raw value, or a
        /// caller-supplied safe id for the generic pin-layer path).
        let languageId: String
        let resolution: RuntimeResolution
    }

    /// Per-language depth adapter: the idiomatic version file, the manifest, and
    /// the toolchain probe command.
    private struct Adapter {
        let idiomaticFile: String?
        let manifestFile: String?
        let manifestParse: ((String) -> String?)?
        let manifestSemantics: PinSemantics?
        let probeCommands: [String]   // first that resolves on PATH wins
        let probeArg: String
    }

    private static func adapter(for lang: RuntimeLanguage) -> Adapter {
        switch lang {
        case .python:
            return Adapter(idiomaticFile: ".python-version", manifestFile: "pyproject.toml",
                           manifestParse: parsePyprojectRequiresPython, manifestSemantics: .constraint,
                           probeCommands: ["python3", "python"], probeArg: "--version")
        case .node:
            return Adapter(idiomaticFile: ".nvmrc", manifestFile: "package.json",
                           manifestParse: parsePackageJsonEnginesNode, manifestSemantics: .constraint,
                           probeCommands: ["node"], probeArg: "--version")
        case .go:
            return Adapter(idiomaticFile: nil, manifestFile: "go.mod",
                           manifestParse: parseGoModDirective, manifestSemantics: .directive,
                           probeCommands: ["go"], probeArg: "version")
        case .rust:
            return Adapter(idiomaticFile: "rust-toolchain", manifestFile: nil,
                           manifestParse: nil, manifestSemantics: nil,
                           probeCommands: ["rustc"], probeArg: "--version")
        case .java:
            return Adapter(idiomaticFile: ".java-version", manifestFile: nil,
                           manifestParse: nil, manifestSemantics: nil,
                           probeCommands: ["java"], probeArg: "-version")
        case .dotnet:
            return Adapter(idiomaticFile: nil, manifestFile: "global.json",
                           manifestParse: parseGlobalJsonSdk, manifestSemantics: .exactVersion,
                           probeCommands: ["dotnet"], probeArg: "--version")
        case .swift:
            return Adapter(idiomaticFile: ".swift-version", manifestFile: "Package.swift",
                           manifestParse: parseSwiftToolsVersion, manifestSemantics: .languageMode,
                           probeCommands: ["swift"], probeArg: "--version")
        }
    }

    /// Resolve the effective runtime version(s). If `languageId` is given, resolve
    /// just that language: a depth-adapter language gets the full treatment; any
    /// other safe id falls back to the universal pin layer (declared-version only).
    /// With no id, auto-detect every depth-adapter language present in `cwd`.
    static func resolve(cwd: String, languageId: String?) -> [LanguageResult] {
        if let id = languageId {
            guard isSafeLanguageId(id) else { return [] }
            if let l = RuntimeLanguage(rawValue: id) {
                return [LanguageResult(languageId: id, resolution: resolveOne(l, cwd: cwd))]
            }
            // Uncovered but safe language (e.g. ruby, elixir): universal pin layer only.
            return [LanguageResult(languageId: id, resolution: resolveGeneric(id, cwd: cwd))]
        }
        return detectLanguages(files: directoryEntries(cwd))
            .map { LanguageResult(languageId: $0.rawValue, resolution: resolveOne($0, cwd: cwd)) }
    }

    private static func resolveOne(_ lang: RuntimeLanguage, cwd: String) -> RuntimeResolution {
        let ad = adapter(for: lang)
        var candidates: [PinCandidate] = []

        // 1. Active toolchain (authoritative) — probe <cmd> <arg>; only trust a
        //    clean exit, and label the source with the command that actually ran.
        if let probed = probeToolchain(ad.probeCommands, arg: ad.probeArg),
           let v = parseToolchainVersion(probed.output, language: lang) {
            candidates.append(PinCandidate(version: v, source: "\(probed.command) \(ad.probeArg)", semantics: .activeToolchain))
        }

        // 2. Universal pin layer — .tool-versions, mise config (declared, exact).
        if let v = universalPinVersion(names: toolNames(for: lang), cwd: cwd) {
            candidates.append(PinCandidate(version: v, source: "universal pin layer", semantics: .exactVersion))
        }

        // 3. Idiomatic per-language version file (declared, exact).
        if let f = ad.idiomaticFile, let content = readFile(cwd, f), let v = parseIdiomaticVersionFile(content) {
            candidates.append(PinCandidate(version: v, source: f, semantics: .exactVersion))
        }

        // 4. Manifest declaration (constraint / directive / language-mode).
        if let f = ad.manifestFile, let parse = ad.manifestParse, let sem = ad.manifestSemantics,
           let content = readFile(cwd, f), let v = parse(content) {
            candidates.append(PinCandidate(version: v, source: f, semantics: sem))
        }

        return resolveEffectiveRuntime(candidates, env: cwd)
    }

    /// Universal-pin-only resolution for a language without a depth adapter. Reads
    /// the cross-language declaration files plus the idiomatic `.<id>-version`, so
    /// a project declaring e.g. Ruby in `.tool-versions` still gets an answer.
    private static func resolveGeneric(_ id: String, cwd: String) -> RuntimeResolution {
        var candidates: [PinCandidate] = []
        if let v = universalPinVersion(names: [id], cwd: cwd) {
            candidates.append(PinCandidate(version: v, source: "universal pin layer", semantics: .exactVersion))
        }
        if let content = readFile(cwd, ".\(id)-version"), let v = parseIdiomaticVersionFile(content) {
            candidates.append(PinCandidate(version: v, source: ".\(id)-version", semantics: .exactVersion))
        }
        return resolveEffectiveRuntime(candidates, env: cwd)
    }

    /// The names a language goes by in `.tool-versions` / mise config.
    private static func toolNames(for lang: RuntimeLanguage) -> [String] {
        switch lang {
        case .python: return ["python"]
        case .node:   return ["node", "nodejs"]
        case .go:     return ["go", "golang"]
        case .rust:   return ["rust"]
        case .java:   return ["java"]
        case .dotnet: return ["dotnet"]
        case .swift:  return ["swift"]
        }
    }

    /// Look up a declared version across the cross-language pin files, trying each
    /// alias in `names`. Reads asdf `.tool-versions` and both mise config names
    /// (`.mise.toml` and the canonical `mise.toml`).
    private static func universalPinVersion(names: [String], cwd: String) -> String? {
        if let c = readFile(cwd, ".tool-versions") {
            let m = parseToolVersions(c)
            for n in names where m[n] != nil { return m[n] }
        }
        for miseFile in [".mise.toml", "mise.toml"] {
            if let c = readFile(cwd, miseFile) {
                let m = parseMiseToml(c)
                for n in names where m[n] != nil { return m[n] }
            }
        }
        return nil
    }

    // MARK: - Filesystem (read-only)

    private static func directoryEntries(_ cwd: String) -> Set<String> {
        (try? FileManager.default.contentsOfDirectory(atPath: cwd)).map(Set.init) ?? []
    }

    /// Read a version-declaration file, **refusing symlinks**. A malicious project
    /// could ship `.python-version` as a symlink to `~/.ssh/id_rsa` or `.env`; the
    /// old `String(contentsOfFile:)` followed it and echoed the secret back as the
    /// effective version. `attributesOfItem` lstat's (does not follow), so a
    /// symlink is detected and rejected before any read.
    private static func readFile(_ cwd: String, _ name: String) -> String? {
        let path = (cwd as NSString).appendingPathComponent(name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - Toolchain probe (read-only, watchdog-guarded)

    /// Probe the first resolvable command that exits cleanly with a version. Only
    /// a zero exit is trusted — a failing pyenv shim prints `version 'X' is not
    /// installed` to stderr with exit 1, and mining that for a version would report
    /// a runtime that cannot execute. Returns the command that actually answered so
    /// the source label is honest (not always `probeCommands[0]`).
    private static func probeToolchain(_ commands: [String], arg: String, timeout: TimeInterval = 8) -> (command: String, output: String)? {
        for cmd in commands {
            guard let path = ProcessRunner.resolveExecutable(cmd) else { continue }
            let r = ProcessRunner.run(executable: path, arguments: [arg], timeout: timeout)
            guard r.launched, !r.timedOut, r.exitCode == 0 else { continue }
            let combined = r.combined
            if !combined.isEmpty { return (cmd, combined) }
        }
        return nil
    }
}

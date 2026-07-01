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
        let language: RuntimeLanguage
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
    /// just that language (rejected if unsafe or unknown); otherwise auto-detect
    /// every depth-adapter language present in `cwd`.
    static func resolve(cwd: String, languageId: String?) -> [LanguageResult] {
        let langs: [RuntimeLanguage]
        if let id = languageId {
            guard isSafeLanguageId(id), let l = RuntimeLanguage(rawValue: id) else { return [] }
            langs = [l]
        } else {
            langs = detectLanguages(files: directoryEntries(cwd))
        }
        return langs.map { LanguageResult(language: $0, resolution: resolveOne($0, cwd: cwd)) }
    }

    private static func resolveOne(_ lang: RuntimeLanguage, cwd: String) -> RuntimeResolution {
        let ad = adapter(for: lang)
        var candidates: [PinCandidate] = []

        // 1. Active toolchain (authoritative) — probe <cmd> <arg>.
        if let probed = probeToolchain(ad.probeCommands, arg: ad.probeArg),
           let v = parseToolchainVersion(probed, language: lang) {
            candidates.append(PinCandidate(version: v, source: "\(ad.probeCommands[0]) \(ad.probeArg)", semantics: .activeToolchain))
        }

        // 2. Universal pin layer — .tool-versions, .mise.toml (declared, exact).
        if let v = universalPinVersion(for: lang, cwd: cwd) {
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

    /// Look up a declared version for a language across the cross-language pin
    /// files. Maps our `RuntimeLanguage` to the tool names those files use.
    private static func universalPinVersion(for lang: RuntimeLanguage, cwd: String) -> String? {
        let toolNames: [RuntimeLanguage: [String]] = [
            .python: ["python"], .node: ["node", "nodejs"], .go: ["go", "golang"],
            .rust: ["rust"], .java: ["java"], .dotnet: ["dotnet"], .swift: ["swift"],
        ]
        guard let names = toolNames[lang] else { return nil }
        if let c = readFile(cwd, ".tool-versions") {
            let m = parseToolVersions(c)
            for n in names where m[n] != nil { return m[n] }
        }
        if let c = readFile(cwd, ".mise.toml") {
            let m = parseMiseToml(c)
            for n in names where m[n] != nil { return m[n] }
        }
        return nil
    }

    // MARK: - Filesystem (read-only)

    private static func directoryEntries(_ cwd: String) -> Set<String> {
        (try? FileManager.default.contentsOfDirectory(atPath: cwd)).map(Set.init) ?? []
    }

    private static func readFile(_ cwd: String, _ name: String) -> String? {
        try? String(contentsOfFile: (cwd as NSString).appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: - Toolchain probe (read-only, watchdog-guarded)

    private static func probeToolchain(_ commands: [String], arg: String, timeout: TimeInterval = 8) -> String? {
        for cmd in commands {
            guard let path = resolveExecutable(cmd) else { continue }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = [arg]
            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            proc.standardInput = FileHandle.nullDevice
            do { try proc.run() } catch { continue }
            let killer = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            proc.waitUntilExit()
            killer.cancel()
            let so = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let se = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            // Some toolchains (java) print --version to stderr; merge, prefer stdout.
            let combined = [so, se].filter { !$0.isEmpty }.joined(separator: "\n")
            if !combined.isEmpty { return combined }
        }
        return nil
    }

    private static func resolveExecutable(_ command: String) -> String? {
        let fm = FileManager.default
        for dir in ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"] {
            let p = "\(dir)/\(command)"
            if fm.isExecutableFile(atPath: p) { return p }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [command]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

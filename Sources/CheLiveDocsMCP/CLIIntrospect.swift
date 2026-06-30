import Foundation

enum CLIIntrospectError: Error, LocalizedError {
    case invalidCommand(String)
    case notFound(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand(let c): return "Refusing to run '\(c)': command must be a bare name (letters/digits/.-_), no paths or shell metacharacters"
        case .notFound(let c): return "'\(c)' is not on PATH"
        case .timedOut(let c): return "'\(c)' introspection timed out"
        }
    }
}

/// Live introspection of an installed CLI — the binary on disk is the freshest
/// possible source of "what flags/subcommands does this version actually have".
///
/// Security posture (this is a command-execution surface fed by a tool argument):
///   • command must match ^[A-Za-z0-9._-]+$ — no slashes, no `;`/`|`/`$()`/spaces.
///   • resolved via `/usr/bin/which` against PATH, never executed as a shell string.
///   • only an allowlisted introspection flag is appended (`--help` / `--version`).
///   • a watchdog terminates anything that blocks (a CLI that waits on stdin).
enum CLIIntrospect {
    static let allowedFlags: Set<String> = ["--help", "-h", "--version", "-v", "help"]

    static func isSafeCommand(_ cmd: String) -> Bool {
        cmd.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    static func run(command: String, flag: String = "--help", timeout: TimeInterval = 8) throws -> String {
        guard isSafeCommand(command) else { throw CLIIntrospectError.invalidCommand(command) }
        let safeFlag = allowedFlags.contains(flag) ? flag : "--help"
        guard let path = resolve(command) else { throw CLIIntrospectError.notFound(command) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [safeFlag]
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice   // never block on stdin
        try proc.run()

        // Watchdog: kill a hung introspection rather than wedging the server.
        let killer = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        proc.waitUntilExit()
        killer.cancel()

        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        // Many CLIs print help to stderr; merge, preferring stdout.
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return combined.isEmpty ? "(no output from \(command) \(safeFlag))" : combined
    }

    private static func resolve(_ command: String) -> String? {
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

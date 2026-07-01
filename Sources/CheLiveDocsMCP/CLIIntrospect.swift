import Foundation
import LiveDocsCore

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
        guard let path = ProcessRunner.resolveExecutable(command) else { throw CLIIntrospectError.notFound(command) }

        let r = ProcessRunner.run(executable: path, arguments: [safeFlag], timeout: timeout)
        // A hung introspection that the watchdog had to kill is an error, not a
        // silently-truncated "result" — surface it so the caller can distinguish.
        if r.timedOut { throw CLIIntrospectError.timedOut(command) }

        // CLI help is untrusted output rendered into the transcript — strip control
        // and ANSI escape sequences before returning.
        let combined = TextSanitize.forModel(r.combined)
        return combined.isEmpty ? "(no output from \(command) \(safeFlag))" : combined
    }
}

import Foundation

/// One hardened way to run a short-lived probe subprocess. Replaces three
/// near-identical copies (CLI `--help`, toolchain `--version`, `Rscript`) that
/// each had the same two latent bugs:
///
///   1. **Pipe-buffer deadlock**: they called `waitUntilExit()` *before* draining
///      stdout/stderr, so a child emitting more than the ~64 KB pipe buffer (a big
///      `--help`) blocked writing while the parent blocked waiting — wedged until
///      the watchdog fired, then returning silently truncated output.
///   2. **SIGTERM-only watchdog**: a child that ignores SIGTERM never dies.
///
/// This runner drains both pipes on background threads *concurrently* with the
/// child (so it can never fill a pipe), closes the parent's write ends so EOF is
/// reached when the child exits, and escalates SIGTERM → SIGKILL after a grace
/// period. Executable resolution is PATH-first so shims (pyenv/mise/asdf) win.
enum ProcessRunner {

    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let timedOut: Bool
        let launched: Bool

        /// stdout + stderr merged (some tools print `--help`/`--version` to stderr),
        /// stdout first, empties dropped.
        var combined: String {
            [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    /// Resolve a bare command name to an absolute path. **PATH first** so a
    /// project's pyenv/mise/asdf shim (`~/.pyenv/shims/python3`) is honored — the
    /// old order (fixed dirs first) reported the wrong "active toolchain" and then
    /// outranked the project's correct pins. Fixed directories are only a fallback
    /// for a stripped `$PATH`. The caller must pass a validated bare name.
    static func resolveExecutable(_ command: String) -> String? {
        let fm = FileManager.default
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
                let p = "\(dir)/\(command)"
                if fm.isExecutableFile(atPath: p) { return p }
            }
        }
        for dir in ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"] {
            let p = "\(dir)/\(command)"
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Run `executable arguments…`, capturing stdout/stderr, with a watchdog.
    /// `graceBeforeKill` is how long after the SIGTERM we wait before SIGKILL.
    static func run(executable: String,
                    arguments: [String],
                    timeout: TimeInterval = 8,
                    graceBeforeKill: TimeInterval = 2) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice   // never block on stdin

        do { try proc.run() } catch {
            return Result(stdout: "", stderr: "", exitCode: -1, timedOut: false, launched: false)
        }

        // Close the parent's write ends: after the fork the child owns its dup, so
        // the read side reaches EOF only when the child exits *and* we've let go of
        // our copy. Without this the reader threads would hang forever.
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        // Drain both pipes concurrently with the running child.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        // Watchdog: SIGTERM at the deadline, SIGKILL after a grace period.
        var timedOut = false
        let term = DispatchWorkItem { if proc.isRunning { timedOut = true; proc.terminate() } }
        let kill = DispatchWorkItem { if proc.isRunning { Foundation.kill(proc.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: term)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + graceBeforeKill, execute: kill)

        proc.waitUntilExit()
        term.cancel(); kill.cancel()
        group.wait()   // readers finish once the child's pipes hit EOF

        return Result(stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self),
                      exitCode: proc.terminationStatus,
                      timedOut: timedOut,
                      launched: true)
    }
}

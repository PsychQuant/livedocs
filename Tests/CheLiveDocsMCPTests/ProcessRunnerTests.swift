import XCTest
@testable import CheLiveDocsMCP

/// Behavior of the hardened process runner: large output does not deadlock
/// (pipes drained concurrently), timeouts are reported, and exit codes surface.
final class ProcessRunnerTests: XCTestCase {

    private func bin(_ name: String) -> String {
        ProcessRunner.resolveExecutable(name) ?? "/usr/bin/\(name)"
    }

    /// The pre-fix code drained pipes only after waitUntilExit(), so output larger
    /// than the ~64 KB pipe buffer deadlocked. Emit ~1 MB and require it all back.
    func testLargeOutputDoesNotDeadlock() throws {
        // `yes` + `head` via sh would need a shell; use python if present, else skip.
        guard let py = ProcessRunner.resolveExecutable("python3") else {
            throw XCTSkip("python3 not available")
        }
        let r = ProcessRunner.run(executable: py,
                                  arguments: ["-c", "print('x' * 1_000_000)"],
                                  timeout: 10)
        XCTAssertTrue(r.launched)
        XCTAssertFalse(r.timedOut)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertGreaterThan(r.stdout.count, 900_000, "large stdout must be captured in full")
    }

    func testExitCodeSurfaces() throws {
        guard let py = ProcessRunner.resolveExecutable("python3") else {
            throw XCTSkip("python3 not available")
        }
        let r = ProcessRunner.run(executable: py, arguments: ["-c", "import sys; sys.exit(3)"], timeout: 10)
        XCTAssertEqual(r.exitCode, 3)
        XCTAssertFalse(r.timedOut)
    }

    func testTimeoutReported() throws {
        guard let py = ProcessRunner.resolveExecutable("python3") else {
            throw XCTSkip("python3 not available")
        }
        let r = ProcessRunner.run(executable: py, arguments: ["-c", "import time; time.sleep(30)"],
                                  timeout: 1, graceBeforeKill: 1)
        XCTAssertTrue(r.timedOut, "a sleeper past the deadline must be flagged timedOut")
    }

    func testUnlaunchableReported() {
        let r = ProcessRunner.run(executable: "/nonexistent/binary", arguments: [], timeout: 1)
        XCTAssertFalse(r.launched)
    }
}

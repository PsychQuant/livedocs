import XCTest
@testable import LiveDocsCore

/// Sanitization of untrusted fetched/CLI content before it reaches the model or a
/// terminal, plus byte-accurate truncation.
final class TextSanitizeTests: XCTestCase {

    func testStripsANSIEscapes() {
        let input = "\u{1B}[31mred\u{1B}[0m normal"
        XCTAssertEqual(TextSanitize.forModel(input), "red normal")
    }

    func testStripsOSCSequence() {
        // ESC ] 0 ; title BEL — a window-title OSC.
        let input = "\u{1B}]0;pwned\u{07}visible"
        XCTAssertEqual(TextSanitize.forModel(input), "visible")
    }

    func testStripsControlAndBidiAndZeroWidth() {
        let input = "a\u{0000}b\u{202E}c\u{200B}d\u{7F}e"
        XCTAssertEqual(TextSanitize.forModel(input), "abcde")
    }

    func testKeepsNewlineTabAndUnicode() {
        let input = "line1\nline2\tcol\t中文 🎉 café"
        XCTAssertEqual(TextSanitize.forModel(input), input)
    }

    func testTruncateByUTF8Bytes() {
        // Each CJK char is 3 UTF-8 bytes; cap 6 keeps exactly two.
        let out = TextSanitize.truncateUTF8("中文字", maxBytes: 6)
        XCTAssertTrue(out.hasPrefix("中文"))
        XCTAssertTrue(out.contains("truncated at 6 bytes"))
        XCTAssertFalse(out.hasPrefix("中文字"))
    }

    func testTruncateNoOpWhenUnderCap() {
        XCTAssertEqual(TextSanitize.truncateUTF8("short", maxBytes: 1000), "short")
    }

    func testTruncateNegativeCapClampsToZero() {
        // Must not trap; clamps to 0 and truncates everything.
        let out = TextSanitize.truncateUTF8("anything", maxBytes: -5)
        XCTAssertTrue(out.contains("truncated at 0 bytes"))
    }
}

import Foundation

/// Pure text hygiene for content that flows back to the model / a terminal.
///
/// Fetched docs and CLI `--help` output are untrusted: a crafted `llms.txt` or a
/// CLI whose help embeds ANSI escapes / bidi overrides / zero-width characters
/// can smuggle hidden or terminal-manipulating content into the transcript.
/// Prompt-injection via ordinary prose is inherent and out of scope, but stripping
/// control bytes and ANSI CSI sequences is cheap and removes the terminal-hijack
/// surface. Kept pure so it's unit-tested without a network or a process.
public enum TextSanitize {

    /// Strip C0/C1 control characters (keeping `\n` and `\t`), DEL, ANSI CSI/OSC
    /// escape sequences, and bidirectional-override / directional-isolate code
    /// points. Every other Unicode scalar (CJK, emoji, accents) is preserved.
    public static func forModel(_ input: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(input.unicodeScalars.count)

        let scalars = Array(input.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let u = scalars[i]
            // ANSI escape: ESC (0x1B) begins a CSI (`ESC [ … final`) or OSC
            // (`ESC ] … BEL/ST`) sequence — consume the whole run.
            if u.value == 0x1B {
                i = skipEscapeSequence(scalars, from: i)
                continue
            }
            if isStripped(u) { i += 1; continue }
            out.append(u)
            i += 1
        }
        return String(out)
    }

    /// Whether a scalar should be dropped outright (independent of escape runs).
    private static func isStripped(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        if v == 0x09 || v == 0x0A { return false }          // keep tab, newline
        if v <= 0x1F { return true }                        // C0 controls
        if v == 0x7F { return true }                        // DEL
        if (0x80...0x9F).contains(v) { return true }        // C1 controls
        if (0x202A...0x202E).contains(v) { return true }    // bidi embeddings/overrides
        if (0x2066...0x2069).contains(v) { return true }    // directional isolates
        if v == 0x200B || v == 0x200C || v == 0x200D || v == 0xFEFF { return true } // zero-width
        return false
    }

    /// Given `scalars[start] == ESC`, return the index just past the escape
    /// sequence. Handles CSI (`ESC [ … @-~`) and OSC (`ESC ] … BEL` / `ESC \`);
    /// a lone/short ESC just consumes the ESC.
    private static func skipEscapeSequence(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        var i = start + 1
        guard i < scalars.count else { return i }
        let intro = scalars[i]
        if intro == "[" {                                   // CSI: params/intermediates then a final @-~
            i += 1
            while i < scalars.count {
                let v = scalars[i].value
                i += 1
                if (0x40...0x7E).contains(v) { break }      // final byte ends the CSI
            }
            return i
        }
        if intro == "]" {                                   // OSC: … terminated by BEL or ESC \
            i += 1
            while i < scalars.count {
                let v = scalars[i].value
                if v == 0x07 { return i + 1 }               // BEL
                if v == 0x1B { return i + 1 }               // ST (ESC \) — skip the ESC, next loop drops '\'
                i += 1
            }
            return i
        }
        return i + 1                                        // other ESC-x: drop ESC + the next byte
    }

    /// Truncate a string to at most `maxBytes` UTF-8 bytes on a scalar boundary,
    /// appending an explicit note when truncated. The old code truncated on
    /// `Character` count while claiming "bytes"; this is byte-accurate.
    public static func truncateUTF8(_ s: String, maxBytes: Int) -> String {
        let cap = max(0, maxBytes)
        if s.utf8.count <= cap { return s }
        var bytes = 0
        var end = s.startIndex
        for idx in s.indices {
            let w = String(s[idx]).utf8.count
            if bytes + w > cap { break }
            bytes += w
            end = s.index(after: idx)
        }
        return String(s[s.startIndex..<end]) + "\n\n[...truncated at \(cap) bytes; raise max_bytes for the rest]"
    }
}

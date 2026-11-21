import Foundation

/// A byte-level pass over the Grammar JSON files (`grammar-rules.json`, `tips.json`) that makes their reading
/// the same on Apple Foundation and Linux Foundation, whatever `JSONSerialization` or `JSONDecoder` do with the
/// cases below (SPEC.md, Grammar rules data). It looks only at the bytes, outside the text of the strings:
/// - a raw control character (below 0x20) inside a string is refused (JSON forbids it; platforms differ);
/// - a number is an integer only when written as an integer literal, `-?[0-9]+`: no fraction, no exponent
///   (`5.0`, `1e1` and `2.0` are not integers, though some decoders read them as 5, 10 and 2). It matters only for
///   the members named in `integerKeys`; any other number is left as written (counts accept decimals);
/// - `Policy.strict` (the rules file) refuses a JSON `null` anywhere and a non-integer under `integerKeys`;
///   `Policy.tolerant` (saved progress) keeps `null` and turns a non-integer under `integerKeys` into `null`,
///   which reads as "none" (a day, `opened`) or as an unreadable `schema`.
/// The input must already be valid JSON (`JSONSerialization` accepted it); the result is the bytes to decode.
enum GrammarJSON {
    enum Policy { case strict, tolerant }

    private struct Frame {
        let isObject: Bool
        var key: String?
    }

    static func scrubbed(_ data: Data, integerKeys: Set<String>, policy: Policy) -> Data? {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var stack: [Frame] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x7B, 0x5B:
                stack.append(Frame(isObject: byte == 0x7B, key: nil))
                out.append(byte)
                index += 1
            case 0x7D, 0x5D:
                _ = stack.popLast()
                out.append(byte)
                index += 1
            case 0x22:
                guard let end = endOfString(bytes, from: index) else { return nil }
                if isKey(bytes, after: end), !stack.isEmpty { stack[stack.count - 1].key = keyText(bytes[(index + 1)..<end]) }
                out.append(contentsOf: bytes[index...end])
                index = end + 1
            case 0x2D, 0x30...0x39:
                let end = tokenEnd(bytes, from: index)
                let token = bytes[index..<end]
                if let key = stack.last?.key, stack.last?.isObject == true, integerKeys.contains(key), !isInteger(token) {
                    guard policy == .tolerant else { return nil }
                    out.append(contentsOf: Array("null".utf8))
                } else {
                    out.append(contentsOf: token)
                }
                index = end
            case 0x6E where policy == .strict:
                return nil
            default:
                out.append(byte)
                index += 1
            }
        }
        return Data(out)
    }

    /// Whether `data` is JSON as RFC 8259 writes it and nothing else: no trailing comma, no comment, no leading zero or
    /// `+`, no `NaN`, no raw control character in a string, nothing after the value. `JSONSerialization` is lenient in
    /// different ways on each platform (swift-corelibs-foundation reads `{"a":1,}`; Apple's refuses it), so a strict reader
    /// checks the grammar itself first, and the decoder only ever sees valid JSON. Nesting past 64 is refused (the
    /// readers cap it far lower, with `JSONGuard`).
    static func isStrictJSON(_ data: Data) -> Bool {
        var parser = StrictParser(bytes: [UInt8](data))
        return parser.parseDocument()
    }

    private struct StrictParser {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func parseDocument() -> Bool {
            skipSpace()
            guard value(depth: 1) else { return false }
            skipSpace()
            return index == bytes.count
        }

        private mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        private mutating func value(depth: Int) -> Bool {
            guard depth <= 64, index < bytes.count else { return false }
            switch bytes[index] {
            case 0x7B: return object(depth: depth)
            case 0x5B: return array(depth: depth)
            case 0x22: return string()
            case 0x74: return literal("true")
            case 0x66: return literal("false")
            case 0x6E: return literal("null")
            default: return number()
            }
        }

        private mutating func literal(_ word: String) -> Bool {
            let expected = Array(word.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<(index + expected.count)]) == expected else { return false }
            index += expected.count
            return true
        }

        private mutating func object(depth: Int) -> Bool {
            index += 1
            skipSpace()
            if index < bytes.count, bytes[index] == 0x7D { index += 1; return true }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == 0x22, string() else { return false }
                skipSpace()
                guard index < bytes.count, bytes[index] == 0x3A else { return false }
                index += 1
                skipSpace()
                guard value(depth: depth + 1) else { return false }
                skipSpace()
                guard index < bytes.count else { return false }
                index += 1
                if bytes[index - 1] == 0x7D { return true }
                guard bytes[index - 1] == 0x2C else { return false }
            }
        }

        private mutating func array(depth: Int) -> Bool {
            index += 1
            skipSpace()
            if index < bytes.count, bytes[index] == 0x5D { index += 1; return true }
            while true {
                skipSpace()
                guard value(depth: depth + 1) else { return false }
                skipSpace()
                guard index < bytes.count else { return false }
                index += 1
                if bytes[index - 1] == 0x5D { return true }
                guard bytes[index - 1] == 0x2C else { return false }
            }
        }

        private mutating func string() -> Bool {
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 0x22 { return true }
                if byte < 0x20 { return false }
                guard byte == 0x5C else { continue }
                guard index < bytes.count else { return false }
                let escape = bytes[index]
                index += 1
                if escape == 0x75 {
                    let digits = bytes[min(index, bytes.count)..<min(index + 4, bytes.count)]
                    guard digits.count == 4, digits.allSatisfy({ Character(UnicodeScalar($0)).isHexDigit }) else { return false }
                    index += 4
                } else if !Array("\"\\/bfnrt".utf8).contains(escape) {
                    return false
                }
            }
            return false
        }

        private mutating func digits() -> Bool {
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
            return index > start
        }

        /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`
        private mutating func number() -> Bool {
            if index < bytes.count, bytes[index] == 0x2D { index += 1 }
            guard index < bytes.count else { return false }
            if bytes[index] == 0x30 {
                index += 1
            } else if !digits() {
                return false
            }
            if index < bytes.count, bytes[index] == 0x2E {
                index += 1
                guard digits() else { return false }
            }
            if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
                index += 1
                if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
                guard digits() else { return false }
            }
            return true
        }
    }

    /// Whether some object holds the same key twice, comparing the keys as a decoder reads them (escapes resolved:
    /// `"a"` and `"\u0061"` are one key). Decoders keep the last one or the first, by platform, so a file with
    /// a duplicate is read two ways: the strict readers (`irregular-verb-sentences.json`) refuse it. Unreadable
    /// strings count as duplicates. The input must already be valid JSON.
    static func hasDuplicateKey(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var stack: [(isObject: Bool, keys: Set<[UInt8]>)] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 0x7B, 0x5B:
                stack.append((bytes[index] == 0x7B, []))
                index += 1
            case 0x7D, 0x5D:
                _ = stack.popLast()
                index += 1
            case 0x22:
                guard let end = endOfString(bytes, from: index) else { return true }
                if isKey(bytes, after: end), stack.last?.isObject == true {
                    guard let key = keyText(bytes[(index + 1)..<end]) else { return true }
                    if !stack[stack.count - 1].keys.insert(Array(key.utf8)).inserted { return true }
                }
                index = end + 1
            default:
                index += 1
            }
        }
        return false
    }

    /// Whether a string holds a `\uD800`-`\uDFFF` escape that is not half of a valid pair: not a character at all.
    /// Platforms read it as U+FFFD or refuse it; the strict readers refuse it. Valid JSON in, as above.
    static func hasLoneSurrogateEscape(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == 0x22, let end = endOfString(bytes, from: index) else { index += 1; continue }
            if hasLoneSurrogate(bytes[(index + 1)..<end]) { return true }
            index = end + 1
        }
        return false
    }

    private static func hasLoneSurrogate(_ raw: ArraySlice<UInt8>) -> Bool {
        let body = Array(raw)
        var index = 0
        while index < body.count {
            guard body[index] == 0x5C else { index += 1; continue }
            if index + 1 < body.count, body[index + 1] == 0x75, let unit = hex4(body, index + 2) {
                if (0xD800...0xDBFF).contains(unit) {
                    guard index + 11 < body.count, body[index + 6] == 0x5C, body[index + 7] == 0x75,
                          let low = hex4(body, index + 8), (0xDC00...0xDFFF).contains(low) else { return true }
                    index += 12
                    continue
                }
                if (0xDC00...0xDFFF).contains(unit) { return true }
                index += 6
                continue
            }
            index += 2
        }
        return false
    }

    private static func hex4(_ body: [UInt8], _ start: Int) -> Int? {
        guard start + 4 <= body.count else { return nil }
        var value = 0
        for byte in body[start..<(start + 4)] {
            guard let digit = Character(UnicodeScalar(byte)).hexDigitValue else { return nil }
            value = value * 16 + digit
        }
        return value
    }

    /// The index of the closing quote, or nil for a raw control character in the string (or no end).
    private static func endOfString(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x20 { return nil }
            if byte == 0x5C { index += 2; continue }
            if byte == 0x22 { return index }
            index += 1
        }
        return nil
    }

    private static func isKey(_ bytes: [UInt8], after end: Int) -> Bool {
        var index = end + 1
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        return index < bytes.count && bytes[index] == 0x3A
    }

    /// The key as a decoder reads it: escapes (`day` is `day`) are resolved, so they cannot hide a key.
    private static func keyText(_ raw: ArraySlice<UInt8>) -> String? {
        guard raw.contains(0x5C) else { return String(decoding: raw, as: UTF8.self) }
        let wrapped = Data([0x5B, 0x22] + raw + [0x22, 0x5D])
        return ((try? JSONSerialization.jsonObject(with: wrapped)) as? [String])?.first
    }

    private static func tokenEnd(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, ![0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        return index
    }

    private static func isInteger(_ token: ArraySlice<UInt8>) -> Bool {
        let digits = token.first == 0x2D ? token.dropFirst() : token
        return !digits.isEmpty && digits.allSatisfy { (0x30...0x39).contains($0) }
    }
}

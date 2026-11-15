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

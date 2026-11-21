import XCTest
@testable import LingleafCore

/// The byte-level helpers of `GrammarJSON` the strict readers rely on, the same on every platform.
final class StrictJSONTests: XCTestCase {
    private func strict(_ text: String) -> Bool { GrammarJSON.isStrictJSON(Data(text.utf8)) }

    func testRFC8259JSONIsAccepted() {
        for text in [
            "{}", "[]", "0", "-0", "1", "-12", "0.5", "1e5", "1E+5", "1e-5", "-0.5e-3", "true", "false", "null", "\"\"", "\"a b\"",
            #"{"a":1}"#, #"{ "a" : [ 1 , 2 , { "b" : null } ] }"#, "\t\r\n {} \r\n", #""\u00e9\n\t\"\\\/\b\f\r""#, #"{"é":"ñ"}"#,
            #"[[],[[]],{}]"#, #""\ud83d\ude00""#, #"{"a":"x","b":"y"}"#,
        ] { XCTAssertTrue(strict(text), text) }
    }

    func testAnythingElseIsRefused() {
        for text in [
            "", " ", "{", "}", "[", "]", "{,}", "[,]", "[1,]", "[,1]", #"{"a":1,}"#, #"{"a":}"#, #"{"a"}"#, #"{"a" 1}"#, #"{a:1}"#,
            #"{'a':1}"#, #"{"a":1 "b":2}"#, "[1 2]", "01", "00", "+1", "-", "--1", ".5", "1.", "1.e5", "1e", "1e+", "0x10", "NaN",
                "Infinity",
            "-Infinity", "tru", "truee", "True", "nul", "nulll", "// c\n{}", "/* c */{}", "{} // c", "{}{}", "{} x", "[] []", "1 2",
            "\"a", "\"a\\", #""\x""#, #""\u12""#, #""\u12G4""#, #""\uD83""#, "\"a\tb\"", "\"a\nb\"", "\"a\u{01}b\"", "\u{0C}{}",
            "'a'", "{\"a\":1}\u{0B}", String(repeating: "[", count: 65) + String(repeating: "]", count: 65),
        ] { XCTAssertFalse(strict(text), text.debugDescription) }
        XCTAssertTrue(strict(String(repeating: "[", count: 64) + String(repeating: "]", count: 64)), "the cap itself")
    }

    func testDuplicateKeysAreFoundWithEscapesResolved() {
        let dup = { (text: String) in GrammarJSON.hasDuplicateKey(Data(text.utf8)) }
        XCTAssertTrue(dup(#"{"a":1,"a":2}"#))
        XCTAssertTrue(dup(#"{"a":1,"\u0061":2}"#))
        XCTAssertTrue(dup(#"{"x":{"a":1,"a":2}}"#))
        XCTAssertTrue(dup(#"[{"a":1,"a":2}]"#))
        XCTAssertTrue(dup(#"{"a":1,"b":{},"a":3}"#), "a duplicate after a nested object")
        XCTAssertTrue(dup(#"{"a\q":1}"#), "an unreadable key counts")
        XCTAssertFalse(dup(#"{"a":1,"b":2}"#))
        XCTAssertFalse(dup(#"{"a":{"a":1},"b":{"a":2}}"#), "the same key in different objects")
        XCTAssertFalse(dup(#"[{"a":1},{"a":2}]"#))
        XCTAssertFalse(dup(#"{"a":"a","b":"a"}"#), "a value is not a key")
        XCTAssertFalse(dup(#"{"a":["a","a"]}"#))
        XCTAssertFalse(dup("{}"))
        XCTAssertTrue(dup(#"{"unterminated"#), "an unreadable string counts")
    }

    func testLoneSurrogateEscapesAreFoundOutsideEscapedBackslashes() {
        let lone = { (text: String) in GrammarJSON.hasLoneSurrogateEscape(Data(text.utf8)) }
        for text in [#"["\ud800"]"#, #"["\udc00"]"#, #"["\uDBFF"]"#, #"["\ud800x"]"#, #"["\ud800\u0041"]"#, #"["\ud800\ud800"]"#,
            #"["\udfff\ud800"]"#,
                     #"["a\ud800"]"#, #"["\ud800\ude0"]"#] {
            XCTAssertTrue(lone(text), text)
        }
        for text in [#"["\ud83d\ude00"]"#, #"["\u00e9"]"#, #"["\\ud800"]"#, #"["\u0041\u0042"]"#, #"["\ud83d\ude00\ud83d\ude00"]"#,
            #"["plain"]"#,
                     #"["\n\t"]"#, #"["\uD7FF\uE000"]"#] {
            XCTAssertFalse(lone(text), text)
        }
    }

    func testARawControlCharacterInAStringStillFailsTheScrub() {
        for byte in [0x00, 0x09, 0x0A, 0x1F] as [UInt8] {
            let data = Data("{\"a\":\"x".utf8) + Data([byte]) + Data("y\"}".utf8)
            XCTAssertNil(GrammarJSON.scrubbed(data, integerKeys: [], policy: .strict))
        }
        XCTAssertNotNil(GrammarJSON.scrubbed(Data(#"{"a":"x y"}"#.utf8), integerKeys: [], policy: .strict))
    }
}

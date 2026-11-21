import XCTest
@testable import LingleafCore

/// The text rules of the verb sentences reader (SPEC.md, Verb sentences data): caps in code points, blank text, forbidden
/// characters, the fixed allowlist of blocks and the limit on combining marks.
final class VerbSentencesTextTests: VerbSentencesReaderCase {
    // MARK: Texts

    func atLength(_ count: Int, prefix: String = "I take the bus ") -> String {
        prefix + String(repeating: "x", count: count - prefix.unicodeScalars.count)
    }

    func testTheTextCapsAreInCodePoints() {
        loads(take { $0[0]["en"] = self.atLength(120) }, "en at 120")
        refused(take { $0[0]["en"] = self.atLength(121) }, "text-en")
        loads(take { $0[0]["es"] = String(repeating: "ñ", count: 160) }, "es at 160")
        refused(take { $0[0]["es"] = String(repeating: "ñ", count: 161) }, "text-es")
        loads(take { $0[0]["spoken"] = String(repeating: "x", count: 200) }, "spoken at 200")
        refused(take { $0[0]["spoken"] = String(repeating: "x", count: 201) }, "text-spoken")
        // A combining mark counts as a code point: 120 letters with a mark each is 240.
        refused(take { $0[0]["en"] = String(repeating: "e\u{0301}", count: 61) }, "text-en")
    }

    func testAtMostTwoConsecutiveCombiningMarksAreAllowed() {
        loads(take { $0[0]["es"] = "a\u{0301}\u{0302}b" }, "two marks")
        loads(take { $0[0]["es"] = "a\u{0301}b\u{0301}\u{0302}c\u{0301}" }, "runs are counted apart")
        refused(take { $0[0]["es"] = "a\u{0301}\u{0302}\u{0303}" }, "text-es")
        refused(take { $0[0]["en"] = "I take\u{0301}\u{0302}\u{0303}\u{0304} the bus." }, "text-en")
    }

    /// The same rule for the texts of grammar-rules.json and irregular-verbs.json (SPEC.md); the bundled files still load.
    func testTheGrammarRulesTextRuleIsTheSame() throws {
        XCTAssertTrue(GrammarRules.isText("café ñ — “así” ¿sí?"))
        let bad = [
            "a\u{0378}", "a\(Self.nc(0xFFFE))", "a\(Self.nc(0xFFFF))", "a\(Self.nc(0xFDD0))", "a\(Self.nc(0xFDEF))",
            "a\u{0301}\u{0302}\u{0303}", "a\u{E000}", "a\u{200B}",
        ]
        for text in bad {
            XCTAssertFalse(GrammarRules.isText(text), text.unicodeScalars.map(\.value).description)
        }
        XCTAssertTrue(GrammarRules.isText("a\u{0301}\u{0302}"))
        XCTAssertFalse(GrammarRules.isText(String(repeating: "x", count: 5), max: 4))
        XCTAssertTrue(GrammarRules.shared.isAvailable, "the bundled rules are not refused by the stricter text rule")
        XCTAssertFalse(IrregularVerbs.shared.verbs.isEmpty, "nor the bundled table")
        XCTAssertFalse(IrregularVerbs.isText("a\u{E000}"), "the table's texts follow the same rule (private use)")
        XCTAssertFalse(IrregularVerbs.isText("a\u{4E2D}"))
        XCTAssertTrue(IrregularVerbs.isText("tomar, llevar"))
    }

    /// Just outside the allowlist: the Greek block after U+036F, a CJK ideograph, an emoji, Cyrillic, the math block after the
    /// arrows; just inside: the last scalar of each allowed block.
    func testTextJustOutsideTheAllowlistIsRefusedAndJustInsideLoads() {
        for outside in ["\u{0370}", "\u{0378}", "\u{03B1}", "\u{0416}", "\u{4E2D}", "\u{1F600}", "\u{2070}", "\u{218F}", "\u{2200}"] {
            refused(take { $0[0]["es"] = "a\(outside)b" }, "text-es")
            refused(take { $0[0]["en"] = "I take the bus\(outside)" }, "text-en")
            refused(take { $0[0]["spoken"] = "a\(outside)b" }, "text-spoken")
            refused(f.file(of: "take", [], omitted: [["slot": "advice", "reason": "no\(outside) sentence"]]), "omitted-reason")
            XCTAssertFalse(GrammarRules.isText("a\(outside)b"), outside)
        }
        let inside = [
            "a\u{0301}\u{0302}b", "\u{00E9}",
            "\u{00BF}\u{00A1}\u{00AB}\u{00BB}", "\u{024F}", "\u{0250}", "\u{02FF}", "\u{0300}", "\u{2010}", "\u{2026}",
            "\u{2192}", "\u{21FF}", "\u{0254}\u{02C8}",
        ]
        for inside in inside {
            loads(take { $0[0]["es"] = "a\(inside)b" }, inside)
        }
    }

    /// Inside the blocks, refused one by one: invisible or reserved scalars, every space separator but U+0020.
    func testInvisibleReservedAndExoticSpaceScalarsAreRefused() {
        let scalars: [UInt32] = [0x2065, 0x034F, 0x2024, 0x2044, 0x00A0, 0x2000, 0x2001, 0x2003, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000]
        for value in scalars {
            let text = "a" + String(Unicode.Scalar(value)!) + "b"
            refused(take { $0[0]["es"] = text }, "text-es")
            refused(take { $0[0]["en"] = "I take" + text }, "text-en")
            XCTAssertFalse(GrammarRules.isText(text), String(value, radix: 16))
            XCTAssertFalse(IrregularVerbs.isText(text), String(value, radix: 16))
        }
        loads(take { $0[0]["es"] = "a b" }, "U+0020 is the one space")
    }

    /// A mark follows a letter, a digit or a mark; at most 2 in a row; spreading marks over spaces does not get round it.
    func testMarksCannotBeSpreadOverSpacesOrFollowASpace() {
        let marks = "\u{0301}\u{0302}"
        // The interleave PoC: a + 2 marks + U+2000 + 2 marks + U+2000 + 2 marks (the space is refused itself) ...
        refused(take { $0[0]["es"] = "a" + marks + "\u{2000}" + marks + "\u{2000}" + marks }, "text-es")
        // ... and the same over U+0020: a mark after a space is refused.
        refused(take { $0[0]["es"] = "a" + marks + " " + marks + " " + marks }, "text-es")
        refused(take { $0[0]["es"] = "a \u{0301}" }, "text-es")
        refused(take { $0[0]["es"] = "\u{0301}a" }, "text-es")
        refused(take { $0[0]["es"] = "a.\u{0301}" }, "text-es")
        loads(take { $0[0]["es"] = "a" + marks + " b" + marks }, "marks after letters, 2 in a row")
        loads(take { $0[0]["es"] = "5\u{0301}" }, "a mark after a digit")
        XCTAssertFalse(GrammarRules.isText("a" + marks + " " + marks))
        XCTAssertTrue(GrammarRules.isText("a" + marks + " b" + marks))
    }

    func testBlankTextIsRefused() {
        for blank in ["", " ", "   ", "\t", "\n", "\u{00A0}\u{2003}"] {
            refused(take { $0[0]["en"] = blank }, "text-en")
            refused(take { $0[0]["es"] = blank }, "text-es")
            refused(take { $0[0]["spoken"] = blank }, "text-spoken")
        }
    }

    static func nc(_ value: UInt32) -> String { String(Unicode.Scalar(value)!) }

    static let forbidden: [(String, String)] = {
        let nc = VerbSentencesTextTests.nc
        return [
            ("control", "a\u{0007}b"), ("newline", "a\nb"), ("delete", "a\u{007F}b"), ("C1 control", "a\u{0085}b"),
            ("bidi override", "a\u{202E}b"), ("bidi isolate", "a\u{2066}b"), ("zero-width space", "a\u{200B}b"),
            ("zero-width joiner", "a\u{200D}b"), ("byte order mark", "a\u{FEFF}b"), ("private use", "a\u{E000}b"),
            ("line separator", "a\u{2028}b"), ("paragraph separator", "a\u{2029}b"), ("soft hyphen", "a\u{00AD}b"),
            ("unassigned", "a\u{0378}b"), ("noncharacter FFFE", "a\(nc(0xFFFE))b"), ("noncharacter FFFF", "a\(nc(0xFFFF))b"),
            ("noncharacter FDD0", "a\(nc(0xFDD0))b"), ("noncharacter FDEF", "a\(nc(0xFDEF))b"),
            ("three marks", "a\u{0301}\u{0302}\u{0303}b"),
        ]
    }()

    func testEveryTextFieldRefusesEveryForbiddenCharacter() {
        for (name, text) in Self.forbidden {
            refused(take { $0[0]["en"] = text }, "text-en")
            refused(take { $0[0]["es"] = text }, "text-es")
            refused(take { $0[0]["spoken"] = text }, "text-spoken")
            refused(f.file(of: "take", [], omitted: [["slot": "advice", "reason": "no \(text) sentence"]]), "omitted-reason")
            XCTAssertFalse(name.isEmpty)
        }
        loads(take { $0[0]["es"] = "Tomo el autobús, ¿sí? ñ — “así”" }, "accents, punctuation and quotes are fine")
    }

}

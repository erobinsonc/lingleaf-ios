import XCTest
@testable import LingleafCore

/// Every refusal of `grammar-rules.json` (SPEC.md, Grammar rules data), field by field: each text field
/// against each forbidden character, each cap at N (loads) and N+1 (refused), and every object's keys.
/// Each refusal case is paired with the same edit made valid, so a test cannot pass for another reason.
final class GrammarRulesRefusalTests: XCTestCase {
    private typealias Json = [String: Any]
    private typealias Edit = (inout Json, String) -> Void

    private static let bundled: Data = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/LingleafCore/Resources/grammar-rules.json").standardizedFileURL
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    private static let forbidden: [(String, String)] = [
        ("control", "a\u{0007}b"), ("newline", "a\nb"), ("bidi override", "a\u{202E}b"), ("bidi isolate", "a\u{2066}b"),
        ("zero-width space", "a\u{200B}b"), ("zero-width joiner", "a\u{200D}b"), ("private use", "a\u{E000}b"),
        ("line separator", "a\u{2028}b"), ("paragraph separator", "a\u{2029}b"),
        ("only spaces", "   "), ("only a tab", "\t"), ("empty", ""),
    ]

    private func root() throws -> Json {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bundled) as? Json)
    }

    private func data(_ json: Json) throws -> Data { try JSONSerialization.data(withJSONObject: json) }

    private func loads(_ json: Json, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNoThrow(try GrammarRules.load(data(json)), message, file: file, line: line)
    }

    private func refused(_ json: Json, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let bytes = try data(json)
        XCTAssertThrowsError(try GrammarRules.load(bytes), message, file: file, line: line)
    }

    /// The file with `edit` applied to the rule `id`.
    private func rule(_ id: String = "his-her-its", _ edit: (inout Json) -> Void) throws -> Json {
        var json = try root()
        var rules = json["rules"] as? [Json] ?? []
        let index = try XCTUnwrap(rules.firstIndex { $0["id"] as? String == id })
        edit(&rules[index])
        json["rules"] = rules
        return json
    }

    /// The file with `edit` applied to the first practice item of the rule `id`.
    private func item(_ id: String = "his-her-its", _ edit: (inout Json) -> Void) throws -> Json {
        try rule(id) { rule in
            var items = rule["practice"] as? [Json] ?? []
            edit(&items[0])
            rule["practice"] = items
        }
    }

    // MARK: Text fields against forbidden characters

    func testEveryTextFieldRefusesEveryForbiddenCharacter() throws {
        let ruleFields: [(String, Edit)] = [
            ("title.en", { $0["title"] = ["en": $1, "es": "x"] }), ("title.es", { $0["title"] = ["en": "x", "es": $1] }),
            ("rule.en", { $0["rule"] = ["en": [$1], "es": ["x"]] }), ("rule.es", { $0["rule"] = ["en": ["x"], "es": [$1]] }),
            ("example.en", { $0["examples"] = [["en": $1, "es": "x"], ["en": "y", "es": "z"]] }),
            ("example.es", { $0["examples"] = [["en": "x", "es": $1], ["en": "y", "es": "z"]] }),
            ("contrast.forms[0]", { $0["contrast"] = ["forms": [$1, "b"]] }),
            ("contrast.forms[1]", { $0["contrast"] = ["forms": ["a", $1]] }),
            ("contrast.gloss.en", { $0["contrast"] = ["forms": ["a", "b"], "gloss": ["en": $1, "es": "x"]] }),
            ("contrast.gloss.es", { $0["contrast"] = ["forms": ["a", "b"], "gloss": ["en": "x", "es": $1]] }),
            ("note.en", { $0["note"] = ["en": $1, "es": "x"] }), ("note.es", { $0["note"] = ["en": "x", "es": $1] }),
            ("alias", { $0["aliases"] = [$1] }),
            ("spanish.en", { $0["spanish"] = ["en": $1, "es": "x"] }), ("spanish.es", { $0["spanish"] = ["en": "x", "es": $1] }),
        ]
        for (name, edit) in ruleFields {
            try loads(try rule { edit(&$0, "fine") }, "\(name) with a good text must load")
            for (kind, bad) in Self.forbidden {
                try refused(try rule { edit(&$0, bad) }, "\(name) must refuse \(kind)")
            }
        }
    }

    func testEveryItemFieldRefusesEveryForbiddenCharacter() throws {
        let three: ([Json]) -> [Json] = { $0 + [["en": "y", "es": "z"], ["en": "y", "es": "z"]] }
        let itemFields: [(String, Edit)] = [
            ("option", { $0["options"] = ["in", "on", $1] }),
            ("feedback.en", { $0["feedback"] = three([["en": $1, "es": "x"]]) }),
            ("feedback.es", { $0["feedback"] = three([["en": "x", "es": $1]]) }),
            ("text", { $0["text"] = $1 + " ___" }),
        ]
        for (name, edit) in itemFields {
            try loads(try item("his-her-its") { edit(&$0, "fine") }, "\(name) with a good text must load")
            // A blank text with the gap appended is still a text with a gap: the blank cases don't apply.
            for (kind, bad) in Self.forbidden where !(name == "text" && bad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                try refused(try item("his-her-its") { edit(&$0, bad) }, "\(name) must refuse \(kind)")
            }
        }
        let askFields: [(String, Edit)] = [
            ("ask.en", { $0["ask"] = ["en": $1, "es": "x"] }), ("ask.es", { $0["ask"] = ["en": "x", "es": $1] }),
            ("choose text", { $0["text"] = $1 }),
        ]
        for (name, edit) in askFields {
            try loads(try item("question-order") { edit(&$0, "fine") }, "\(name) with a good text must load")
            for (kind, bad) in Self.forbidden {
                try refused(try item("question-order") { edit(&$0, bad) }, "\(name) must refuse \(kind)")
            }
        }
    }

    func testEveryCategoryTextRefusesEveryForbiddenCharacter() throws {
        let fields: [(String, Edit)] = [
            ("category.title.en", { $0["title"] = ["en": $1, "es": "x"] }), ("category.title.es", { $0["title"] = ["en": "x", "es": $1] }),
        ]
        for (name, edit) in fields {
            for (kind, bad) in Self.forbidden {
                var json = try root()
                var categories = json["categories"] as? [Json] ?? []
                edit(&categories[0], bad)
                json["categories"] = categories
                try refused(json, "\(name) must refuse \(kind)")
            }
        }
    }

    func testACategoryIdMustBeASlug() throws {
        var json = try root()
        var categories = json["categories"] as? [Json] ?? []
        categories.append(["id": "Bad Id", "title": ["en": "x", "es": "y"]])
        json["categories"] = categories
        try refused(json, "category id with capitals and a space")
        categories[categories.count - 1]["id"] = "good-id"
        json["categories"] = categories
        try loads(json, "the same category with a slug id")
    }

    func testTextLengthCountsCodePointsNotCharacters() throws {
        let edit: Edit = { $0["title"] = ["en": $1, "es": "x"] }
        try loads(try rule { edit(&$0, String(repeating: "a", count: 400)) }, "400 code points")
        try refused(try rule { edit(&$0, String(repeating: "a", count: 401)) }, "401 code points")
        // 201 characters of two code points each: short by Characters, long by code points.
        try refused(try rule { edit(&$0, String(repeating: "e\u{0301}", count: 201)) }, "402 code points")
        try loads(try rule { edit(&$0, String(repeating: "e\u{0301}", count: 200)) }, "400 code points with marks")
        try loads(try rule { $0["aliases"] = [String(repeating: "a", count: 40)] }, "40-point alias")
        try refused(try rule { $0["aliases"] = [String(repeating: "a", count: 41)] }, "41-point alias")
        try refused(try rule { $0["aliases"] = [String(repeating: "e\u{0301}", count: 21)] }, "42-point alias")
    }

    // MARK: Caps: N loads, N+1 is refused

    private func lines(_ count: Int) -> Json { ["en": (0..<count).map { "line \($0)" }, "es": (0..<count).map { "línea \($0)" }] }

    func testRuleLinesExamplesAndContrastCaps() throws {
        try refused(try rule { $0["rule"] = lines(0) }, "0 rule lines")
        try loads(try rule { $0["rule"] = lines(1) }, "1 rule line")
        try loads(try rule { $0["rule"] = lines(4) }, "4 rule lines")
        try refused(try rule { $0["rule"] = lines(5) }, "5 rule lines")
        let example: (Int) -> [Json] = { count in (0..<count).map { ["en": "e\($0)", "es": "s\($0)"] } }
        try refused(try rule { $0["examples"] = example(1) }, "1 example")
        try loads(try rule { $0["examples"] = example(2) }, "2 examples")
        try loads(try rule { $0["examples"] = example(4) }, "4 examples")
        try refused(try rule { $0["examples"] = example(5) }, "5 examples")
        try refused(try rule { $0["contrast"] = ["forms": ["a"]] }, "1 contrast form")
        try loads(try rule { $0["contrast"] = ["forms": ["a", "b"]] }, "2 contrast forms")
        try refused(try rule { $0["contrast"] = ["forms": ["a", "b", "c"]] }, "3 contrast forms")
        try refused(try rule { $0["contrast"] = ["forms": [String]()] }, "0 contrast forms")
    }

    func testAliasOptionAndPracticeCaps() throws {
        let aliases: (Int) -> [String] = { count in (0..<count).map { "alias\($0)" } }
        try refused(try rule { $0["aliases"] = aliases(0) }, "0 aliases")
        try loads(try rule { $0["aliases"] = aliases(1) }, "1 alias")
        try loads(try rule { $0["aliases"] = aliases(20) }, "20 aliases")
        try refused(try rule { $0["aliases"] = aliases(21) }, "21 aliases")

        func options(_ count: Int) -> (inout Json) -> Void {
            { item in
                item["options"] = (0..<count).map { "o\($0)" }
                item["feedback"] = (0..<count).map { _ in ["en": "a", "es": "b"] }
                item["answer"] = 0
            }
        }
        try refused(try item("his-her-its", options(1)), "1 option")
        try loads(try item("his-her-its", options(2)), "2 options")
        try loads(try item("his-her-its", options(4)), "4 options")
        try refused(try item("his-her-its", options(5)), "5 options")
        try loads(try item("his-her-its") { $0["answer"] = 2 }, "last option right")
        try refused(try item("his-her-its") { $0["answer"] = 3 }, "answer past the options")

        func practice(_ count: Int) -> (inout Json) -> Void {
            { rule in
                let items = rule["practice"] as? [Json] ?? []
                rule["practice"] = (0..<count).map { index -> Json in
                    var copy = items[0]
                    copy["id"] = "zz-\(index)"
                    return copy
                }
            }
        }
        try refused(try rule("his-her-its", practice(2)), "2 practice items")
        try loads(try rule("his-her-its", practice(3)), "3 practice items")
        try loads(try rule("his-her-its", practice(12)), "12 practice items")
        try refused(try rule("his-her-its", practice(13)), "13 practice items")
    }

    func testCategoryAndRuleCounts() throws {
        func categories(_ count: Int) throws -> Json {
            var json = try root()
            var list = json["categories"] as? [Json] ?? []
            let first = list[0]
            while list.count < count {
                var next = first
                next["id"] = "extra-\(list.count)"
                list.append(next)
            }
            json["categories"] = list
            return json
        }
        try loads(try categories(20), "20 categories")
        try refused(try categories(21), "21 categories")

        // Small rules, so 200 of them stay under the size cap and the count is what is refused.
        func small(_ count: Int) -> Json {
            let rules = (0..<count).map { index -> Json in
                let items = (1...3).map { n -> Json in
                    ["id": "r\(index)-\(n)", "level": "A1", "kind": "gap", "text": "x ___", "options": ["a", "b"], "answer": 0,
                     "feedback": [["en": "a", "es": "b"], ["en": "a", "es": "b"]]]
                }
                return ["id": "r\(index)", "category": "c", "level": "A1", "title": ["en": "t", "es": "t"],
                        "rule": ["en": ["l"], "es": ["l"]], "examples": [["en": "e", "es": "e"], ["en": "e", "es": "e"]],
                        "contrast": ["forms": ["a", "b"]], "aliases": ["a"], "books": ["mode": "none"], "practice": items]
            }
            return ["schema": 1, "categories": [["id": "c", "title": ["en": "c", "es": "c"]]], "rules": rules]
        }
        XCTAssertLessThan(try data(small(200)).count, GrammarRules.maxBytes, "the 200-rule file must be under the size cap")
        XCTAssertNoThrow(try GrammarRules.load(data(small(200))), "200 rules")
        XCTAssertThrowsError(try GrammarRules.load(data(small(201))), "201 rules")
        XCTAssertNoThrow(try GrammarRules.load(data(small(1))), "the small rule itself is valid")
    }

    // MARK: Keys of every object

    func testEveryObjectRefusesAnUnknownAndAMissingKey() throws {
        func inCategory(_ edit: @escaping (inout Json) -> Void) throws -> Json {
            var json = try root()
            var categories = json["categories"] as? [Json] ?? []
            edit(&categories[0])
            json["categories"] = categories
            return json
        }
        try refused(try inCategory { $0["extra"] = 1 }, "category: unknown key")
        try refused(try inCategory { $0["title"] = nil }, "category: missing title")
        try refused(try inCategory { $0["id"] = nil }, "category: missing id")
        try refused(try inCategory { $0["title"] = ["en": "x", "es": "y", "fr": "z"] }, "category title: unknown language")
        try refused(try inCategory { $0["title"] = ["en": "x"] }, "category title: missing es")

        try refused(try rule { $0["examples"] = [["en": "a", "es": "b", "fr": "c"], ["en": "a", "es": "b"]] }, "example: unknown key")
        try refused(try rule { $0["examples"] = [["en": "a"], ["en": "a", "es": "b"]] }, "example: missing es")
        try refused(try rule { $0["examples"] = [["es": "a"], ["en": "a", "es": "b"]] }, "example: missing en")

        try refused(try rule { $0["rule"] = ["en": ["a"], "es": ["a"], "fr": ["a"]] }, "lines: unknown key")
        try refused(try rule { $0["rule"] = ["en": ["a"]] }, "lines: missing es")
        try refused(try rule { $0["rule"] = ["es": ["a"]] }, "lines: missing en")

        try refused(try rule { $0["contrast"] = ["forms": ["a", "b"], "extra": 1] }, "contrast: unknown key")
        try refused(try rule { $0["contrast"] = Json() }, "contrast: missing forms")
        try refused(try rule { $0["contrast"] = ["forms": ["a", "b"], "gloss": ["en": "x"]] }, "gloss: missing es")
        try refused(try rule { $0["note"] = ["en": "x", "es": "y", "fr": "z"] }, "note: unknown language")

        for key in ["id", "level", "kind", "options", "answer", "feedback"] {
            try refused(try item("his-her-its") { $0[key] = nil }, "item: missing \(key)")
        }
        try refused(try item("his-her-its") { $0["extra"] = 1 }, "item: unknown key")
        let extraKey: [Json] = [["en": "a", "es": "b", "fr": "c"], ["en": "a", "es": "b"], ["en": "a", "es": "b"]]
        try refused(try item("his-her-its") { $0["feedback"] = extraKey }, "item feedback: unknown key")
        for key in ["id", "category", "level", "title", "rule", "examples", "contrast", "aliases", "books", "practice"] {
            try refused(try rule { $0[key] = nil }, "rule: missing \(key)")
        }
        try refused(try rule { $0["extra"] = 1 }, "rule: unknown key")
        try refused(try rule { $0["practice"] = "none" }, "rule: practice of the wrong type")
        try refused(try item("his-her-its") { $0["answer"] = "0" }, "item: answer of the wrong type")
    }

    // MARK: Books

    func testTheBooksMatcherIsStrict() throws {
        func books(_ value: Any) -> (inout Json) -> Void { { $0["books"] = value } }
        func many(_ count: Int) -> [String] { (0..<count).map { "w" + String(repeating: "x", count: $0 + 1) } }
        try loads(try rule("his-her-its", books(["mode": "none"])), "none")
        try loads(try rule("his-her-its", books(["mode": "none", "patterns": [String]()])), "none with an empty list")
        try loads(try rule("his-her-its", books(["mode": "patterns", "patterns": ["went|came"]])), "one pattern")
        try loads(try rule("his-her-its", books(["mode": "patterns", "patterns": ["on monday|tuesday", "at * night", "a b c d e"]])), "wildcards")
        try refused(try rule("his-her-its", books(["mode": "none", "patterns": ["went"]])), "none with patterns")
        try refused(try rule("his-her-its", books(["mode": "patterns"])), "patterns without a list")
        try refused(try rule("his-her-its", books(["mode": "patterns", "patterns": [String]()])), "an empty list")
        try refused(try rule("his-her-its", books(["mode": "patterns", "patterns": many(13)])), "13 patterns")
        try loads(try rule("his-her-its", books(["mode": "patterns", "patterns": many(12)])), "12 patterns")
        try refused(try rule("his-her-its", books(["mode": "regex", "patterns": ["a"]])), "unknown mode")
        try refused(try rule("his-her-its", books(["patterns": ["a"]])), "missing mode")
        try refused(try rule("his-her-its", books(["mode": "none", "extra": 1])), "unknown key")
        for bad in ["", " ", "a  b", "a b c d e f", "Went", "went!", "a(b)", "a.*", "went\u{200B}", "caf\u{E9}", " went", "went "] {
            try refused(try rule("his-her-its", books(["mode": "patterns", "patterns": [bad]])), "pattern \(bad.debugDescription)")
        }
    }

    // MARK: Gap and ask

    func testAGapItemHasNoAskAndAChooseItemNeedsOne() throws {
        try refused(try item("his-her-its") { $0["ask"] = ["en": "Pick.", "es": "Elige."] }, "gap with ask")
        try refused(try item("question-order") { $0["ask"] = nil }, "choose without ask")
        try refused(try item("question-order") { $0["text"] = nil }, "choose without a stimulus")
        try refused(try item("his-her-its") { $0["text"] = "no gap" }, "gap text without a gap")
        try refused(try item("his-her-its") { $0["text"] = "___ and ___" }, "two gaps")
        try refused(try item("his-her-its") { $0["text"] = nil }, "gap without text")
    }
}

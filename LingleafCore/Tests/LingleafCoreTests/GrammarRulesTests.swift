import XCTest
@testable import LingleafCore

/// The Grammar rules: the bundled file loads, a crafted one is refused at the first problem, and the
/// search finds rules as SPEC.md S20 says.
final class GrammarRulesTests: XCTestCase {
    // MARK: Loading

    func testTheBundledRulesLoad() throws {
        let grammar = GrammarRules.shared
        XCTAssertEqual(grammar.rules.count, 13, "the bundled grammar-rules.json must load")
        XCTAssertEqual(grammar.categories.map(\.id), ["sentence", "verbs", "prepositions"])
        XCTAssertEqual(grammar.rules(in: "prepositions").map(\.id), ["time-prepositions", "place-prepositions"])
        XCTAssertNil(grammar.rule(id: "nope"))
        let time = try XCTUnwrap(grammar.rule(id: "time-prepositions"))
        XCTAssertEqual(time.level, "A1")
        XCTAssertEqual(time.title.text(for: "es"), "In, on, at: fechas y horas")
        XCTAssertEqual(time.title.text(for: "fr"), "In, on, at: time")
        XCTAssertEqual(time.lines.lines(for: "es").count, time.lines.lines(for: "en").count)
        XCTAssertNotNil(time.note)
        XCTAssertNotNil(time.spanish)
        XCTAssertEqual(time.books.mode, .patterns)
        XCTAssertEqual(try XCTUnwrap(grammar.rule(id: "his-her-its")).books, GrammarBooks(mode: .none, patterns: []))
        XCTAssertNil(try XCTUnwrap(grammar.rule(id: "present-s")).note)
    }

    func testAPracticeItemFillsItsGapAndKnowsTheRightOption() throws {
        let time = try XCTUnwrap(GrammarRules.shared.rule(id: "time-prepositions"))
        let item = time.practice[0]
        XCTAssertEqual(item.kind, .gap)
        XCTAssertEqual(item.correct, "on")
        XCTAssertTrue(item.isRight(1))
        XCTAssertFalse(item.isRight(0))
        XCTAssertEqual(item.filled(with: 1), "I'll see you on Monday.")
        XCTAssertEqual(item.filled(with: 9), "")
        let order = try XCTUnwrap(GrammarRules.shared.rule(id: "question-order"))
        XCTAssertEqual(order.practice[0].kind, .choose)
        XCTAssertEqual(order.practice[0].filled(with: 1), "Where you live?")
        XCTAssertEqual(order.practice[0].ask?.text(for: "es"), "Elige la pregunta.")
    }

    func testEveryBundledItemHasExactlyOneRightOptionWithItsFeedback() {
        for rule in GrammarRules.shared.rules {
            for item in rule.practice {
                XCTAssertEqual(item.options.indices.filter { item.isRight($0) }.count, 1, item.id)
                XCTAssertEqual(item.feedback.count, item.options.count, item.id)
            }
        }
    }

    // MARK: Refusals

    private static let bundled: Data = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/LingleafCore/Resources/grammar-rules.json").standardizedFileURL
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    /// The bundled file with `edit` applied to its top level.
    private func edited(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bundled) as? [String: Any])
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// The bundled file with `edit` applied to its first rule.
    private func rule(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        try edited { json in
            var rules = json["rules"] as? [[String: Any]] ?? []
            edit(&rules[0])
            json["rules"] = rules
        }
    }

    /// The bundled file with `edit` applied to the first practice item of its first rule.
    private func item(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        try rule { rule in
            var items = rule["practice"] as? [[String: Any]] ?? []
            edit(&items[0])
            rule["practice"] = items
        }
    }

    private func refused(_ data: Data, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try GrammarRules.load(data), message, file: file, line: line)
    }

    func testTheBundledDataLoadsFromBytes() throws {
        XCTAssertEqual(try GrammarRules.load(Self.bundled).rules.count, 13)
    }

    func testAFileThatIsTooLargeTooDeepOrAnotherSchemaIsRefused() throws {
        XCTAssertThrowsError(try GrammarRules.load(Data(repeating: 0x20, count: GrammarRules.maxBytes + 1))) {
            XCTAssertEqual($0 as? GrammarRulesError, .tooLarge)
        }
        let deep = Data((String(repeating: "[", count: 9) + String(repeating: "]", count: 9)).utf8)
        XCTAssertThrowsError(try GrammarRules.load(deep)) { XCTAssertEqual($0 as? GrammarRulesError, .tooDeep) }
        refused(try edited { $0["schema"] = 2 }, "schema 2")
        refused(try edited { $0["extra"] = 1 }, "unknown top-level key")
        refused(try edited { $0["schema"] = nil }, "missing schema")
        refused(Data("[]".utf8), "not an object")
    }

    func testAnUnknownOrMissingFieldIsRefused() throws {
        refused(try rule { $0["extra"] = "x" }, "unknown key in a rule")
        refused(try rule { $0["title"] = nil }, "missing title")
        refused(try rule { $0["title"] = ["en": "A", "es": "B", "fr": "C"] }, "unknown language")
        refused(try item { $0["hint"] = "x" }, "unknown key in an item")
        refused(try item { $0["kind"] = "type" }, "unknown kind")
        refused(try rule { $0["contrast"] = ["forms": ["a", "b"], "extra": 1] }, "unknown key in contrast")
    }

    func testARuleOutOfShapeIsRefused() throws {
        refused(try rule { $0["id"] = "Time" }, "id with capitals")
        refused(try rule { $0["id"] = String(repeating: "a", count: 41) }, "id too long")
        refused(try rule { $0["category"] = "grammar" }, "unknown category")
        refused(try rule { $0["level"] = "C1" }, "unknown level")
        refused(try rule { $0["rule"] = ["en": ["1", "2", "3", "4", "5"], "es": ["1", "2", "3", "4", "5"]] }, "5 rule lines")
        refused(try rule { $0["rule"] = ["en": ["1", "2"], "es": ["1"]] }, "lines differ by language")
        refused(try rule { $0["rule"] = ["en": [String](), "es": [String]()] }, "no rule lines")
        refused(try rule { $0["examples"] = [["en": "One.", "es": "Uno."]] }, "1 example")
        refused(try rule { $0["contrast"] = ["forms": ["only one"]] }, "one contrast form")
        refused(try rule { $0["contrast"] = ["forms": ["a", "b"], "gloss": ["en": "", "es": "x"]] }, "empty gloss")
        refused(try rule { $0["note"] = ["en": "x", "es": ""] }, "empty note")
        refused(try rule { $0["aliases"] = [String]() }, "no aliases")
        refused(try rule { $0["aliases"] = [String(repeating: "a", count: 41)] }, "alias too long")
        refused(try rule { $0["practice"] = [] }, "no practice")
        refused(try rule { $0["title"] = ["en": String(repeating: "a", count: 401), "es": "x"] }, "text too long")
        refused(try rule { $0["title"] = ["en": "bad\u{202E}text", "es": "x"] }, "bidirectional control")
        refused(try rule { $0["title"] = ["en": "bad\ntext", "es": "x"] }, "newline")
    }

    func testAPracticeItemOutOfShapeIsRefused() throws {
        refused(try item { $0["answer"] = 3 }, "answer out of range")
        refused(try item { $0["answer"] = -1 }, "negative answer")
        refused(try item { $0["options"] = ["in"]; $0["feedback"] = [["en": "a", "es": "b"]] }, "one option")
        refused(try item { $0["options"] = ["in", "in", "at"] }, "repeated option")
        refused(try item { $0["options"] = ["in", "on", ""] }, "empty option")
        refused(try item { $0["feedback"] = [["en": "a", "es": "b"]] }, "feedback count")
        refused(try item { $0["text"] = "No gap here." }, "no gap")
        refused(try item { $0["text"] = "___ and ___" }, "two gaps")
        refused(try item { $0["text"] = nil }, "gap item without text")
        refused(try item { $0["kind"] = "choose" }, "choose without ask")
        refused(try item { $0["kind"] = "choose"; $0["ask"] = ["en": "Pick.", "es": "Elige."]; $0["text"] = "" }, "choose with empty text")
        refused(try item { $0["level"] = "B2" }, "item level")
        refused(try item { $0["id"] = "A B" }, "item id")
    }

    func testDuplicatesAreRefused() throws {
        refused(try edited { json in
            var rules = json["rules"] as? [[String: Any]] ?? []
            rules[1]["id"] = rules[0]["id"]
            json["rules"] = rules
        }, "duplicate rule id")
        refused(try edited { json in
            var rules = json["rules"] as? [[String: Any]] ?? []
            let first = rules[0]["practice"] as? [[String: Any]] ?? []
            var second = rules[1]["practice"] as? [[String: Any]] ?? []
            second[0]["id"] = first[0]["id"]
            rules[1]["practice"] = second
            json["rules"] = rules
        }, "duplicate item id across rules")
        refused(try edited { json in
            var categories = json["categories"] as? [[String: Any]] ?? []
            categories[1]["id"] = categories[0]["id"]
            json["categories"] = categories
        }, "duplicate category id")
        refused(try edited { json in
            var categories = json["categories"] as? [[String: Any]] ?? []
            categories[0]["id"] = "Bad Id"
            json["categories"] = categories
        }, "category id")
        refused(try edited { json in
            var categories = json["categories"] as? [[String: Any]] ?? []
            categories[0]["title"] = ["en": "", "es": "x"]
            json["categories"] = categories
        }, "category title")
    }

    func testTheBundledRulesPassThroughSharedReadingTwice() {
        // `shared` is read once and is the same value every time.
        XCTAssertEqual(GrammarRules.shared.rules.map(\.id), GrammarRules.shared.rules.map(\.id))
        XCTAssertTrue(GrammarRules.isSlug("time-prepositions-1"))
        XCTAssertFalse(GrammarRules.isSlug(""))
    }

    // MARK: Search

    private var rules: [GrammarRule] { GrammarRules.shared.rules }

    private func ids(_ query: String) -> [String] { GrammarSearch.search(query, in: rules).map(\.id) }

    func testSearchIgnoresCaseAndAccents() {
        XCTAssertTrue(ids("pasado").contains("irregular-past"))
        XCTAssertEqual(ids("PASADO"), ids("pasado"))
        XCTAssertTrue(ids("había").contains("subject-it-there"))
        XCTAssertEqual(ids("habia"), ids("había"))
        XCTAssertEqual(GrammarSearch.words("Niño, DON'T-go! 5 mayo"), ["nino", "don", "t", "go", "5", "mayo"])
    }

    func testSearchNeedsEveryWordToStartAWord() {
        XCTAssertTrue(Set(ids("prepos")).isSuperset(of: ["place-prepositions", "time-prepositions"]))
        XCTAssertTrue(ids("past irreg").contains("irregular-past"))
        XCTAssertEqual(ids("irregular zzzz"), [])
        XCTAssertEqual(ids("zzzz"), [])
    }

    func testAnEmptyOrLongQueryIsHandled() {
        XCTAssertEqual(ids("").count, rules.count)
        XCTAssertEqual(ids("  ,, ").count, rules.count)
        XCTAssertEqual(ids(String(repeating: "a", count: 500)), [])
    }

    func testSearchFindsRulesByExampleAndAlias() {
        XCTAssertTrue(ids("lighthouse").isEmpty)
        XCTAssertTrue(ids("panadería").contains("present-s"))
        XCTAssertTrue(ids("nadie").contains("single-negative"))
    }
}

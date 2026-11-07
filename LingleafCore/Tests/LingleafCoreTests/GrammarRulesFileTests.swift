import CryptoKit
import XCTest

/// The content gate of `grammar-rules.json` (SPEC.md, Grammar rules data): the file is the one the
/// SPEC names (SHA-256) and every rule and practice item has the shape the Grammar tab relies on.
/// Written against the raw JSON so it holds before the decoder exists; identical intent in lingleaf-android.
final class GrammarRulesFileTests: XCTestCase {
    private static let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/LingleafCore/Resources/grammar-rules.json").standardizedFileURL

    private func data() throws -> Data { try Data(contentsOf: Self.url) }

    private func root() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try data()) as? [String: Any])
    }

    private func rules() throws -> [[String: Any]] {
        try XCTUnwrap(try root()["rules"] as? [[String: Any]])
    }

    private func texts(_ value: Any?) -> [String] {
        switch value {
        case let text as String: return [text]
        case let list as [Any]: return list.flatMap { texts($0) }
        case let object as [String: Any]: return object.values.flatMap { texts($0) }
        default: return []
        }
    }

    func testTheFileIsTheOneTheSpecNames() throws {
        let spec = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../SPEC.md").standardizedFileURL
        let text = try String(contentsOf: spec, encoding: .utf8)
        let hash = SHA256.hash(data: try data()).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(text.contains("`\(hash)`"), "SPEC.md must name the SHA-256 of grammar-rules.json: \(hash)")
        XCTAssertLessThanOrEqual(try data().count, 256 * 1024)
    }

    func testCategoriesAndRuleIdsAreUniqueAndKnown() throws {
        let root = try root()
        XCTAssertEqual(root["schema"] as? Int, 1)
        let categories = try XCTUnwrap(root["categories"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(categories).count, categories.count)
        let ids = try rules().compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, try rules().count)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate rule id")
        for rule in try rules() {
            XCTAssertTrue(categories.contains(rule["category"] as? String ?? ""), "unknown category in \(rule["id"] ?? "?")")
            XCTAssertTrue(["A1", "A2", "B1"].contains(rule["level"] as? String ?? ""))
        }
    }

    func testEveryRuleHasTheShapeOfThePage() throws {
        for rule in try rules() {
            let id = rule["id"] as? String ?? "?"
            let lines = try XCTUnwrap(rule["rule"] as? [String: [String]], id)
            XCTAssertTrue((1...4).contains(lines["en"]?.count ?? 0), "\(id): 1–4 rule lines")
            XCTAssertEqual(lines["en"]?.count, lines["es"]?.count, "\(id): same lines in both languages")
            let examples = try XCTUnwrap(rule["examples"] as? [[String: String]], id)
            XCTAssertTrue((2...4).contains(examples.count), "\(id): 2–4 examples")
            for example in examples {
                XCTAssertFalse(example["en"]?.isEmpty ?? true)
                XCTAssertFalse(example["es"]?.isEmpty ?? true)
            }
            let contrast = try XCTUnwrap(rule["contrast"] as? [String: Any], id)
            XCTAssertEqual((contrast["forms"] as? [String])?.count, 2, "\(id): two forms")
            XCTAssertFalse((rule["aliases"] as? [String] ?? []).isEmpty, "\(id): aliases for search")
            let books = try XCTUnwrap(rule["books"] as? [String: Any], "\(id): books")
            switch books["mode"] as? String {
            case "none": XCTAssertNil(books["patterns"], "\(id): none has no patterns")
            case "patterns": XCTAssertTrue((1...12).contains((books["patterns"] as? [String])?.count ?? 0), "\(id): 1–12 patterns")
            default: XCTFail("\(id): unknown books mode")
            }
        }
    }

    func testEveryPracticeItemIsAnswerableAndExplained() throws {
        for rule in try rules() {
            let items = try XCTUnwrap(rule["practice"] as? [[String: Any]])
            XCTAssertGreaterThanOrEqual(items.count, 6, "\(rule["id"] ?? "?"): a bank of at least 6 items")
            var seen = Set<String>()
            for item in items {
                let id = try XCTUnwrap(item["id"] as? String)
                XCTAssertTrue(seen.insert(id).inserted, "duplicate item \(id)")
                let options = try XCTUnwrap(item["options"] as? [String], id)
                XCTAssertTrue((2...4).contains(options.count), "\(id): 2–4 options")
                XCTAssertEqual(Set(options).count, options.count, "\(id): options differ")
                let answer = try XCTUnwrap(item["answer"] as? Int, id)
                XCTAssertTrue(options.indices.contains(answer), "\(id): answer in range")
                let feedback = try XCTUnwrap(item["feedback"] as? [[String: String]], id)
                XCTAssertEqual(feedback.count, options.count, "\(id): one feedback line per option")
                for line in feedback {
                    XCTAssertFalse(line["en"]?.isEmpty ?? true)
                    XCTAssertFalse(line["es"]?.isEmpty ?? true)
                }
                switch item["kind"] as? String {
                case "gap":
                    let text = try XCTUnwrap(item["text"] as? String, id)
                    XCTAssertEqual(text.components(separatedBy: "___").count, 2, "\(id): exactly one gap")
                    XCTAssertNil(item["ask"], "\(id): a gap item has no ask")
                case "choose":
                    XCTAssertNotNil(item["ask"] as? [String: String], "\(id): a choose item needs ask")
                    let stimulus = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    XCTAssertFalse(stimulus.isEmpty, "\(id): a choose item needs a visible stimulus")
                default:
                    XCTFail("\(id): unknown kind")
                }
            }
        }
    }

    func testTheRightAnswerIsSpreadOverThePositions() throws {
        var counts: [Int: Int] = [:]
        for rule in try rules() {
            for item in try XCTUnwrap(rule["practice"] as? [[String: Any]]) where (item["options"] as? [String])?.count == 3 {
                counts[item["answer"] as? Int ?? -1, default: 0] += 1
            }
        }
        let total = counts.values.reduce(0, +)
        XCTAssertGreaterThan(total, 30)
        for (position, count) in counts {
            XCTAssertLessThanOrEqual(Double(count) / Double(total), 0.4, "position \(position) holds too many right answers: \(counts)")
        }
    }

    func testTheSpecDoesNotWriteTheVerbCount() throws {
        let spec = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../SPEC.md").standardizedFileURL
        let text = try String(contentsOf: spec, encoding: .utf8)
        let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("| S24 |") })
        XCTAssertNil(row.range(of: #"\b\d{2,3} (irregular )?verbs\b"#, options: .regularExpression), "S24 must not hard-code a verb count")
    }

    func testNoTextIsLongAndRulesNeverShowTheWrongForms() throws {
        for text in texts(try root()) { XCTAssertLessThanOrEqual(text.count, 400) }
        // Rules, examples and contrasts show only correct English; wrong forms live in practice options and feedback.
        let wrong = ["goed", "taked", "seed ", "in Monday", "it's tail", "I have 25 years", "depend of", "am agree", "carrys", "telled", "comed", "bigs"]
        for rule in try rules() {
            let shown = texts(rule["rule"]) + texts(rule["examples"]) + texts(rule["contrast"]) + texts(rule["note"]) + texts(rule["spanish"])
            for form in wrong {
                XCTAssertFalse(shown.contains { $0.contains(form) }, "\(rule["id"] ?? "?") shows a wrong form: \(form)")
            }
        }
    }
}

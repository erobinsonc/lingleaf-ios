#if canImport(CryptoKit)
import CryptoKit
#endif
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
        // CryptoKit is Apple-only: on Linux the hash is checked by the CI of the Apple build.
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: try data()).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(text.contains("`\(hash)`"), "SPEC.md must name the SHA-256 of grammar-rules.json: \(hash)")
        #else
        XCTAssertTrue(text.contains("SHA-256"))
        #endif
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

    func testNoItemIsHarderThanItsRuleAndFixedOrderIsABoolean() throws {
        let rank = ["A1": 1, "A2": 2, "B1": 3]
        for rule in try rules() {
            let ruleRank = try XCTUnwrap(rank[rule["level"] as? String ?? ""])
            for item in try XCTUnwrap(rule["practice"] as? [[String: Any]]) {
                let id = item["id"] as? String ?? "?"
                XCTAssertLessThanOrEqual(try XCTUnwrap(rank[item["level"] as? String ?? ""], id), ruleRank, "\(id): above its rule's level")
                if let fixed = item["fixedOrder"] { XCTAssertTrue(fixed is Bool, "\(id): fixedOrder is true or false") }
            }
        }
    }

    /// The reference of SPEC.md, "Option order": the same function and vectors are in lingleaf-android.
    private func optionOrder(_ id: String, seen: Int, count: Int) -> [Int] {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(id)#\(seen)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        func next() -> UInt64 {
            hash = hash &+ 0x9E3779B97F4A7C15
            var z = hash
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        var order = Array(0..<count)
        if count > 1 {
            for i in stride(from: count - 1, through: 1, by: -1) { order.swapAt(i, Int(next() % UInt64(i + 1))) }
        }
        return order
    }

    func testTheOptionOrderMatchesTheSpecsVectors() {
        XCTAssertEqual(optionOrder("his-her-its-1", seen: 1, count: 3), [2, 0, 1])
        XCTAssertEqual(optionOrder("his-her-its-1", seen: 2, count: 3), [1, 2, 0])
        XCTAssertEqual(optionOrder("question-order-1", seen: 0, count: 3), [2, 0, 1])
        XCTAssertEqual(optionOrder("age-and-feelings-1", seen: 5, count: 3), [0, 2, 1])
        XCTAssertEqual(optionOrder("do-does-did-1", seen: 0, count: 3), [2, 0, 1])
        XCTAssertEqual(optionOrder("x", seen: 0, count: 2), [0, 1])
    }

    func testTheRightAnswerAsTheLearnerSeesItIsSpreadOverThePositions() throws {
        var counts: [Int: Int] = [:]
        for rule in try rules() {
            for item in try XCTUnwrap(rule["practice"] as? [[String: Any]]) {
                let options = try XCTUnwrap(item["options"] as? [String])
                guard options.count == 3, let answer = item["answer"] as? Int, let id = item["id"] as? String else { continue }
                for seen in 0..<10 {
                    let order = item["fixedOrder"] as? Bool == true ? [0, 1, 2] : optionOrder(id, seen: seen, count: 3)
                    counts[order.firstIndex(of: answer) ?? -1, default: 0] += 1
                }
            }
        }
        let total = counts.values.reduce(0, +)
        XCTAssertGreaterThan(total, 300)
        for (position, count) in counts {
            XCTAssertLessThanOrEqual(Double(count) / Double(total), 0.4, "position \(position) holds too many right answers: \(counts)")
        }
    }

    // MARK: The SPEC's other shared rules, checked against an independent reference

    /// SPEC "Day": whole days between 2001-01-01 and the local date of (instant - 4 hours).
    private func reviewDay(_ date: Date, calendar: Calendar) -> Int {
        let start = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1))!
        let shifted = calendar.startOfDay(for: date.addingTimeInterval(-4 * 3600))
        return calendar.dateComponents([.day], from: start, to: shifted).day!
    }

    func testTheDayStartsAtFourInTheLocalTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2001, month: 1, day: day, hour: hour, minute: minute))!
        }
        XCTAssertEqual(reviewDay(at(2, 3, 59), calendar: calendar), 0)
        XCTAssertEqual(reviewDay(at(2, 4, 0), calendar: calendar), 1)
        XCTAssertEqual(reviewDay(at(1, 2, 0), calendar: calendar), -1)
    }

    /// SPEC "Review selection", placement: rule item j goes after word ceil((j + 1) * W / (m + 1)).
    private func placements(words: Int, items: Int) -> [Int] {
        (0..<items).map { j in ((j + 1) * words + items) / (items + 1) }
    }

    func testRuleItemsAreSpreadAmongTheWordsAndNeverComeFirstWhenAWordIsDue() {
        XCTAssertEqual(placements(words: 10, items: 6), [2, 3, 5, 6, 8, 9])
        XCTAssertEqual(placements(words: 3, items: 2), [1, 2])
        XCTAssertEqual(placements(words: 1, items: 2), [1, 1])
        XCTAssertEqual(placements(words: 0, items: 4), [0, 0, 0, 0])
        for words in 1...20 { XCTAssertGreaterThanOrEqual(placements(words: words, items: 6).first ?? 1, 1, "\(words) words") }
    }

    /// SPEC "Progress", rightDays: a right answer is added when the list is empty or when its day and its item both differ.
    private func practiced(_ answers: [(day: Int, item: String)]) -> Bool {
        var entries: [(day: Int, item: String)] = []
        for answer in answers where entries.count < 2 {
            if entries.isEmpty || (answer.day != entries[0].day && answer.item != entries[0].item) { entries.append(answer) }
        }
        return entries.count == 2
    }

    /// SPEC "Review selection": the rules, then the items of a rule (references for the shared vectors).
    private struct RuleCandidate { let id: String; let due: Int; let position: Int; let isNew: Bool }
    private struct ItemCandidate {
        let id: String; let due: Int; let position: Int; let tryMiss: Int?; var spanishOnly = false
    }

    private func slots(words: Int) -> Int { max(0, min(20 - words, 6)) }

    private func chooseRules(_ rules: [RuleCandidate], slots: Int) -> [String] {
        var chosen: [String] = []
        var newTaken = false
        let limit = slots == 1 ? 1 : min(3, slots / 2)
        for rule in rules.sorted(by: { ($0.due, $0.position) < ($1.due, $1.position) }) where chosen.count < limit {
            if rule.isNew { if newTaken { continue }; newTaken = true }
            chosen.append(rule.id)
        }
        return chosen
    }

    private func candidates(_ items: [ItemCandidate], today: Int, spanish: Bool) -> [ItemCandidate] {
        items.filter { (spanish || !$0.spanishOnly) && ($0.due <= today || ($0.tryMiss.map { $0 < today } ?? false)) }
    }

    private func chooseItems(_ items: [ItemCandidate], today: Int, lastPair: Set<String>?, spanish: Bool = false) -> [String] {
        func flagged(_ item: ItemCandidate) -> Bool { item.tryMiss.map { $0 < today } ?? false }
        let candidates = self.candidates(items, today: today, spanish: spanish).sorted {
            let a = flagged($0), b = flagged($1)
            if a != b { return a }
            let dueA = a ? $0.tryMiss! : $0.due, dueB = b ? $1.tryMiss! : $1.due
            return (dueA, $0.due, $0.position) < (dueB, $1.due, $1.position)
        }
        var taken = Array(candidates.prefix(2))
        if taken.count == 2, candidates.count > 2, Set(taken.map(\.id)) == lastPair { taken = [candidates[0], candidates[2]] }
        return taken.map(\.id)
    }

    func testTheReviewSelectionMatchesTheSpecsVectors() {
        let rules = [RuleCandidate(id: "R1", due: 8, position: 3, isNew: true), RuleCandidate(id: "R2", due: 9, position: 1, isNew: true),
                     RuleCandidate(id: "R3", due: 10, position: 0, isNew: false), RuleCandidate(id: "R4", due: 11, position: 2, isNew: false)]
        XCTAssertEqual(chooseRules(rules, slots: 6), ["R1", "R3", "R4"], "a second new rule is skipped")
        XCTAssertEqual(chooseRules([RuleCandidate(id: "R2", due: 10, position: 5, isNew: false), RuleCandidate(id: "R3", due: 10, position: 0, isNew: false)], slots: 6), ["R3", "R2"])
        XCTAssertEqual(chooseRules(rules, slots: 1), ["R1"])
        let a = ItemCandidate(id: "a", due: 5, position: 2, tryMiss: nil), b = ItemCandidate(id: "b", due: 5, position: 1, tryMiss: nil)
        let c = ItemCandidate(id: "c", due: 9, position: 3, tryMiss: 4)
        XCTAssertEqual(chooseItems([a, b, c], today: 6, lastPair: nil), ["c", "b"])
        XCTAssertEqual(chooseItems([a, b, c], today: 6, lastPair: ["c", "b"]), ["c", "a"])
        let sameDay = ItemCandidate(id: "c", due: 9, position: 3, tryMiss: 6)
        XCTAssertEqual(chooseItems([a, b, sameDay], today: 6, lastPair: nil), ["b", "a"])
        // The Spanish filter: d needs Spanish; N counts the candidates left out.
        let d = ItemCandidate(id: "d", due: 4, position: 0, tryMiss: nil, spanishOnly: true)
        XCTAssertEqual(chooseItems([a, b, c, d], today: 6, lastPair: nil), ["c", "b"])
        XCTAssertEqual(candidates([a, b, c, d], today: 6, spanish: false).count - 2, 1, "N: a is left out")
        XCTAssertEqual(chooseItems([a, b, c, d], today: 6, lastPair: nil, spanish: true), ["c", "d"])
        XCTAssertEqual(candidates([a, b, c, d], today: 6, spanish: true).count - 2, 2, "N: a and b are left out")
    }

    func testTheSlotsForRuleItemsAndTheKeyOfAFlaggedRule() {
        XCTAssertEqual([10, 14, 15, 19, 20, 25].map { slots(words: $0) }, [6, 6, 5, 1, 0, 0])
        // A flagged item counts as due on the smaller of its miss day and its due day.
        func key(due: Int, tryMiss: Int?) -> Int { min(due, tryMiss ?? Int.max) }
        XCTAssertLessThan(key(due: 10, tryMiss: 3), key(due: 5, tryMiss: nil))
    }

    func testASpanishStimulusIsOnlyOnAChooseItemAndEveryRuleKeepsThreeOthers() throws {
        for rule in try rules() {
            let items = try XCTUnwrap(rule["practice"] as? [[String: Any]])
            var drawable = 0
            for item in items {
                if let language = item["textLang"] {
                    XCTAssertEqual(language as? String, "es", "\(item["id"] ?? "?"): textLang is es")
                    XCTAssertEqual(item["kind"] as? String, "choose", "\(item["id"] ?? "?"): only a choose item has a Spanish stimulus")
                } else {
                    drawable += 1
                }
            }
            XCTAssertGreaterThanOrEqual(drawable, 3, "\(rule["id"] ?? "?"): at least 3 items need no Spanish")
            XCTAssertNil(items.first?["textLang"], "\(rule["id"] ?? "?"): the pretest item needs no Spanish")
        }
    }

    func testPracticedNeedsTwoDaysAndTwoItems() {
        XCTAssertFalse(practiced([(5, "A")]))
        XCTAssertFalse(practiced([(5, "A"), (5, "B")]))
        XCTAssertFalse(practiced([(5, "A"), (6, "A")]))
        XCTAssertTrue(practiced([(5, "A"), (6, "B")]))
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
        let wrong = ["goed", "taked", "seed ", "in Monday", "it's tail", "I have 25 years", "depend of", "am agree", "carrys", "telled", "comed", "bigs", "have hunger", "have cold", "have thirsty", "have 20 years", "have saw", "hasn't eaten"]
        for rule in try rules() {
            let shown = texts(rule["rule"]) + texts(rule["examples"]) + texts(rule["contrast"]) + texts(rule["note"]) + texts(rule["spanish"])
            for form in wrong {
                XCTAssertFalse(shown.contains { $0.contains(form) }, "\(rule["id"] ?? "?") shows a wrong form: \(form)")
            }
        }
    }
}

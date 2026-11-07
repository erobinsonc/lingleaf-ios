import XCTest
@testable import LingleafCore

/// Local Grammar progress (schema 2): what is kept per rule and per item, the order of "Recent", the three
/// states, and how a saved file is brought into range.
final class GrammarProgressTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private func later(_ seconds: Double) -> Date { day.addingTimeInterval(seconds) }
    private var grammar: GrammarRules { GrammarRules.shared }
    private var time: GrammarRule { grammar.rule(id: "time-prepositions")! }

    func testRecentIsTheLastThreeOpenedNewestFirst() {
        var progress = GrammarProgress()
        XCTAssertEqual(progress.recent(), [])
        progress.opened("a", at: later(1))
        progress.opened("b", at: later(2))
        progress.opened("c", at: later(3))
        progress.opened("d", at: later(4))
        XCTAssertEqual(progress.recent(), ["d", "c", "b"])
        progress.opened("a", at: later(5))
        XCTAssertEqual(progress.recent(), ["a", "d", "c"])
        XCTAssertEqual(progress.recent(limit: 1), ["a"])
        progress.opened("x", at: later(5))
        XCTAssertEqual(progress.recent(limit: 2), ["a", "x"], "ties go by id")
    }

    func testAnswersAreCountedOnTheRuleAndTheItem() {
        var progress = GrammarProgress()
        XCTAssertEqual(progress[time.id], RuleProgress())
        let first = time.practice[0].id
        let second = time.practice[1].id
        progress.answered(time, item: second, right: false)
        XCTAssertFalse(progress[time.id].pretestDone, "only the first item is the pretest")
        progress.answered(time, item: second, right: true)
        progress.answered(time, item: first, right: true)
        XCTAssertTrue(progress[time.id].pretestDone)
        XCTAssertEqual(progress[time.id].attempts, 3)
        XCTAssertEqual(progress[time.id].rights, 2)
        XCTAssertEqual(progress[time.id].items[second]?.seen, 2)
        XCTAssertEqual(progress[time.id].items[second]?.missed, 1)
        XCTAssertEqual(progress[time.id].items[first]?.missed, 0)
        XCTAssertNil(progress[time.id].lastOpened)
        progress.answered(time, item: "not-an-item", right: true)
        XCTAssertEqual(progress[time.id].attempts, 3, "an item the rule doesn't have is ignored")
    }

    func testCountsAreCapped() {
        var progress = GrammarProgress()
        let item = time.practice[0].id
        for _ in 0..<(GrammarProgress.maxCount + 5) { progress.answered(time, item: item, right: false) }
        XCTAssertEqual(progress[time.id].attempts, GrammarProgress.maxCount)
        XCTAssertEqual(progress[time.id].items[item]?.seen, GrammarProgress.maxCount)
        XCTAssertEqual(progress[time.id].items[item]?.missed, GrammarProgress.maxCount)
        for _ in 0..<(GrammarProgress.maxCount + 5) { progress.answered(time, item: item, right: true) }
        XCTAssertEqual(progress[time.id].rights, GrammarProgress.maxCount)
    }

    func testTheThreeStates() {
        var progress = GrammarProgress()
        XCTAssertEqual(progress.state(of: time.id), .new)
        progress.opened(time.id, at: day)
        XCTAssertEqual(progress.state(of: time.id), .new, "opening alone doesn't make it practised")
        progress.answered(time, item: time.practice[0].id, right: false)
        XCTAssertEqual(progress.state(of: time.id), .practised)
        progress.setInReview(time.id, true)
        XCTAssertEqual(progress.state(of: time.id), .inReview)
        progress.setInReview(time.id, false)
        XCTAssertEqual(progress.state(of: time.id), .practised)
    }

    func testReviewSchedulesItsOwnBoxPerItem() {
        var progress = GrammarProgress()
        let item = time.practice[0].id
        progress.scheduled(time.id, item: item, box: 3, due: later(86_400))
        XCTAssertEqual(progress[time.id].items[item]?.box, 3)
        XCTAssertEqual(progress[time.id].items[item]?.due, later(86_400).timeIntervalSince1970)
        progress.scheduled(time.id, item: item, box: 99, due: nil)
        XCTAssertEqual(progress[time.id].items[item]?.box, GrammarProgress.maxBox)
        XCTAssertNil(progress[time.id].items[item]?.due)
        progress.scheduled(time.id, item: item, box: -4, due: nil)
        XCTAssertEqual(progress[time.id].items[item]?.box, 0)
        for index in 0..<(GrammarProgress.maxItems + 3) { progress.scheduled("r", item: "item-\(index)", box: 1, due: nil) }
        XCTAssertEqual(progress["r"].items.count, GrammarProgress.maxItems)
    }

    func testTheEntriesAreCappedAndTheOldestGoFirst() {
        var progress = GrammarProgress()
        for index in 0..<(GrammarProgress.maxEntries + 3) { progress.opened("rule-\(index)", at: later(Double(index))) }
        XCTAssertEqual(progress.rules.count, GrammarProgress.maxEntries)
        XCTAssertNil(progress.rules["rule-0"])
        XCTAssertNotNil(progress.rules["rule-\(GrammarProgress.maxEntries + 2)"])
        // An entry never opened counts as the oldest; the one just changed is kept.
        progress.setInReview("fresh", true)
        XCTAssertEqual(progress.rules.count, GrammarProgress.maxEntries)
        XCTAssertNotNil(progress.rules["fresh"])
    }

    func testProgressSurvivesBeingSavedAndRead() throws {
        var progress = GrammarProgress()
        progress.opened(time.id, at: later(10))
        progress.answered(time, item: time.practice[0].id, right: true)
        progress.answered(time, item: time.practice[1].id, right: false)
        progress.scheduled(time.id, item: time.practice[0].id, box: 2, due: later(86_400 * 3))
        progress.setInReview(time.id, true)
        progress.setInReview("place-prepositions", true)
        let data = try XCTUnwrap(progress.encoded(for: grammar))
        XCTAssertEqual(GrammarProgress.decode(data, known: grammar.knownItems, now: later(100)), progress)
        let onlyTime = [time.id: grammar.knownItems[time.id] ?? []]
        XCTAssertEqual(GrammarProgress.decode(data, known: onlyTime, now: later(100)).rules.keys.sorted(), [time.id])
    }

    func testNothingIsSavedWhenTheRulesDidNotLoad() {
        var progress = GrammarProgress()
        progress.opened("a", at: day)
        XCTAssertNil(progress.encoded(for: GrammarRules(categories: [], rules: [])), "keep the saved file")
        XCTAssertFalse(GrammarRules(categories: [], rules: []).isAvailable)
        XCTAssertTrue(grammar.isAvailable)
        XCTAssertEqual(progress.encoded(for: grammar), progress.encoded())
    }

    // MARK: Reading a saved file

    private let known: [String: Set<String>] = ["a": ["a-1", "a-2"], "b": ["b-1"]]

    private func decode(_ json: String, known: [String: Set<String>]? = nil) -> GrammarProgress {
        GrammarProgress.decode(Data(json.utf8), known: known ?? self.known, now: day)
    }

    func testAFileThatCannotBeTrustedGivesEmptyProgress() {
        XCTAssertEqual(decode("not json"), GrammarProgress())
        XCTAssertEqual(decode("[]"), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 1, "rules": {"a": {}}}"#), GrammarProgress(), "the old schema")
        XCTAssertEqual(decode(#"{"schema": 3, "rules": {"a": {}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2, "rules": [[[[[[[[[1]]]]]]]]]}"#), GrammarProgress())
        let big = Data(repeating: 0x20, count: GrammarProgress.maxBytes + 1)
        XCTAssertEqual(GrammarProgress.decode(big, known: known), GrammarProgress())
    }

    func testAWrongEntryIsDroppedOrBroughtIntoRange() {
        let read = decode(#"""
        {"schema": 2, "rules": {
          "a": {"attempts": 99999, "rights": 5000, "pretestDone": true, "inReview": true, "lastOpened": 1800000500,
                "items": {"a-1": {"box": 9, "seen": 4, "missed": 7, "due": 1800086400}, "a-2": {}, "gone": {"seen": 1}, "a-x": 5}},
          "b": {"attempts": 3},
          "gone": {"attempts": 1},
          "bad": "text"
        }}
        """#, known: known.merging(["bad": []]) { $1 })
        XCTAssertEqual(read.rules.keys.sorted(), ["a", "b"])
        XCTAssertEqual(read["a"].attempts, GrammarProgress.maxCount)
        XCTAssertEqual(read["a"].rights, GrammarProgress.maxCount)
        XCTAssertTrue(read["a"].inReview)
        XCTAssertEqual(read["a"].lastOpened, 1_800_000_500)
        XCTAssertEqual(read["a"].items.keys.sorted(), ["a-1", "a-2"])
        XCTAssertEqual(read["a"].items["a-1"]?.box, GrammarProgress.maxBox)
        XCTAssertEqual(read["a"].items["a-1"]?.seen, 4)
        XCTAssertEqual(read["a"].items["a-1"]?.missed, 4, "missed never above seen")
        XCTAssertEqual(read["a"].items["a-1"]?.due, 1_800_086_400)
        XCTAssertEqual(read["a"].items["a-2"], ItemProgress())
        XCTAssertEqual(read["b"].attempts, 3)
        XCTAssertFalse(read["b"].pretestDone)
    }

    func testRightsNeverExceedAttemptsAndNegativeCountsBecomeZero() {
        let read = decode(#"""
        {"schema": 2, "rules": {
          "a": {"attempts": 2, "rights": 9, "pretestDone": "yes", "items": {"a-1": {"seen": -3, "missed": "x", "box": -2}}},
          "b": {"attempts": -4, "rights": "x"}
        }}
        """#)
        XCTAssertEqual(read["a"].rights, 2)
        XCTAssertFalse(read["a"].pretestDone)
        XCTAssertEqual(read["a"].items["a-1"], ItemProgress())
        XCTAssertEqual(read["b"].attempts, 0)
        XCTAssertEqual(read["b"].rights, 0)
    }

    func testADateThatCannotBeRightIsDropped() {
        func opened(_ json: String) -> Double? { decode(#"{"schema": 2, "rules": {"a": {"lastOpened": \#(json)}}}"#)["a"].lastOpened }
        XCTAssertNil(opened("5"))
        XCTAssertNil(opened("4000000000"))
        XCTAssertNil(opened(#""yesterday""#))
        XCTAssertEqual(opened("1800000000"), 1_800_000_000)
        func due(_ json: String) -> Double? {
            decode(#"{"schema": 2, "rules": {"a": {"items": {"a-1": {"due": \#(json)}}}}}"#)["a"].items["a-1"]?.due
        }
        XCTAssertNil(due("5"))
        XCTAssertNil(due("1900000000"), "more than a year ahead")
        XCTAssertNil(due(#""soon""#))
        XCTAssertEqual(due("1800864000"), 1_800_864_000)
    }

    func testTooManyEntriesAreCutAtTheCap() {
        let count = GrammarProgress.maxEntries + 20
        let entries = (0..<count).map { "\"r\($0)\": {\"attempts\": 1}" }.joined(separator: ",")
        let many = Dictionary(uniqueKeysWithValues: (0..<count).map { ("r\($0)", Set<String>()) })
        let read = decode("{\"schema\": 2, \"rules\": {\(entries)}}", known: many)
        XCTAssertEqual(read.rules.count, GrammarProgress.maxEntries)
    }

    func testTooManyItemsAreCutAtTheCap() {
        let ids = (0..<(GrammarProgress.maxItems + 5)).map { "a-\($0)" }
        let items = ids.map { "\"\($0)\": {\"seen\": 1}" }.joined(separator: ",")
        let read = decode("{\"schema\": 2, \"rules\": {\"a\": {\"items\": {\(items)}}}}", known: ["a": Set(ids)])
        XCTAssertEqual(read["a"].items.count, GrammarProgress.maxItems)
    }

    func testTheLargestProgressStaysUnderTheCap() {
        var entries: [String: RuleProgress] = [:]
        var knownIDs: [String: Set<String>] = [:]
        for index in 0..<GrammarProgress.maxEntries {
            let id = String(repeating: "r", count: 37) + String(format: "%03d", index)
            var entry = RuleProgress()
            entry.attempts = GrammarProgress.maxCount
            entry.rights = GrammarProgress.maxCount
            entry.pretestDone = true
            entry.inReview = true
            entry.lastOpened = 1_800_000_000.123_456_7 + Double(index)
            var ids = Set<String>()
            for number in 0..<GrammarProgress.maxItems {
                let itemID = id + "-" + String(format: "%02d", number)
                var item = ItemProgress()
                item.box = GrammarProgress.maxBox
                item.seen = GrammarProgress.maxCount
                item.missed = GrammarProgress.maxCount
                item.due = 1_800_000_000.123_456_7
                entry.items[itemID] = item
                ids.insert(itemID)
            }
            entries[id] = entry
            knownIDs[id] = ids
        }
        let progress = GrammarProgress(rules: entries)
        let data = progress.encoded()
        XCTAssertLessThanOrEqual(data.count, GrammarProgress.maxBytes, "the largest possible file fits its cap")
        XCTAssertEqual(GrammarProgress.decode(data, known: knownIDs, now: later(1000)).rules.count, GrammarProgress.maxEntries,
                       "what is saved can be read back whole")
    }
}

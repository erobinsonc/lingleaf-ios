import XCTest
@testable import LingleafCore

/// Local Grammar progress: what is kept, the order of "Recent", and how a saved file is brought into range.
final class GrammarProgressTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private func later(_ seconds: Double) -> Date { day.addingTimeInterval(seconds) }

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

    func testAnswersAreCountedAndCapped() {
        var progress = GrammarProgress()
        XCTAssertEqual(progress["a"], RuleProgress())
        progress.answered("a", right: true)
        progress.answered("a", right: false)
        XCTAssertEqual(progress["a"].attempts, 2)
        XCTAssertEqual(progress["a"].rights, 1)
        XCTAssertTrue(progress["a"].pretestDone)
        XCTAssertNil(progress["a"].lastOpened)
        for _ in 0..<(GrammarProgress.maxCount + 5) { progress.answered("a", right: true) }
        XCTAssertEqual(progress["a"].attempts, GrammarProgress.maxCount)
        XCTAssertEqual(progress["a"].rights, GrammarProgress.maxCount)
        progress.setInReview("a", true)
        XCTAssertTrue(progress["a"].inReview)
        progress.setInReview("a", false)
        XCTAssertFalse(progress["a"].inReview)
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

    func testProgressSurvivesBeingSavedAndRead() {
        var progress = GrammarProgress()
        progress.opened("a", at: later(10))
        progress.answered("a", right: true)
        progress.answered("a", right: false)
        progress.setInReview("a", true)
        progress.setInReview("b", true)
        let read = GrammarProgress.decode(progress.encoded(), known: ["a", "b"], now: later(100))
        XCTAssertEqual(read, progress)
        XCTAssertEqual(GrammarProgress.decode(progress.encoded(), known: ["a"], now: later(100)).rules.keys.sorted(), ["a"])
    }

    private func decode(_ json: String, known: Set<String> = ["a"]) -> GrammarProgress {
        GrammarProgress.decode(Data(json.utf8), known: known, now: day)
    }

    func testAFileThatCannotBeTrustedGivesEmptyProgress() {
        XCTAssertEqual(decode("not json"), GrammarProgress())
        XCTAssertEqual(decode("[]"), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2, "rules": {"a": {}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 1}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 1, "rules": [[[[[[[[[1]]]]]]]]]}"#), GrammarProgress())
        let big = Data(repeating: 0x20, count: GrammarProgress.maxBytes + 1)
        XCTAssertEqual(GrammarProgress.decode(big, known: ["a"]), GrammarProgress())
    }

    func testAWrongEntryIsDroppedOrBroughtIntoRange() {
        let read = decode(#"""
        {"schema": 1, "rules": {
          "a": {"attempts": 99999, "rights": 5000, "pretestDone": true, "inReview": true, "lastOpened": 1800000500},
          "b": {"attempts": 3},
          "gone": {"attempts": 1},
          "bad": "text"
        }}
        """#, known: ["a", "b", "bad"])
        XCTAssertEqual(read.rules.keys.sorted(), ["a", "b"])
        XCTAssertEqual(read["a"].attempts, GrammarProgress.maxCount)
        XCTAssertEqual(read["a"].rights, GrammarProgress.maxCount)
        XCTAssertTrue(read["a"].inReview)
        XCTAssertEqual(read["a"].lastOpened, 1_800_000_500)
        XCTAssertEqual(read["b"].attempts, 3)
        XCTAssertFalse(read["b"].pretestDone)
    }

    func testRightsNeverExceedAttemptsAndNegativeCountsBecomeZero() {
        let read = decode(#"""
        {"schema": 1, "rules": {
          "a": {"attempts": 2, "rights": 9, "pretestDone": "yes"},
          "b": {"attempts": -4, "rights": "x"}
        }}
        """#, known: ["a", "b"])
        XCTAssertEqual(read["a"].rights, 2)
        XCTAssertFalse(read["a"].pretestDone)
        XCTAssertEqual(read["b"].attempts, 0)
        XCTAssertEqual(read["b"].rights, 0)
    }

    func testADateThatCannotBeRightIsDropped() {
        XCTAssertNil(decode(#"{"schema": 1, "rules": {"a": {"lastOpened": 5}}}"#)["a"].lastOpened)
        XCTAssertNil(decode(#"{"schema": 1, "rules": {"a": {"lastOpened": 4000000000}}}"#)["a"].lastOpened)
        XCTAssertNil(decode(#"{"schema": 1, "rules": {"a": {"lastOpened": "yesterday"}}}"#)["a"].lastOpened)
    }

    func testTooManyEntriesAreCutAtTheCap() {
        let entries = (0..<(GrammarProgress.maxEntries + 20)).map { "\"r\($0)\": {\"attempts\": 1}" }.joined(separator: ",")
        let known = Set((0..<(GrammarProgress.maxEntries + 20)).map { "r\($0)" })
        let read = decode("{\"schema\": 1, \"rules\": {\(entries)}}", known: known)
        XCTAssertEqual(read.rules.count, GrammarProgress.maxEntries)
    }
}

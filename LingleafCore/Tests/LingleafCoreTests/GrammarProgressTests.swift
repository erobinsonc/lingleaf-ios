import XCTest
@testable import LingleafCore

/// Local Grammar progress (schema 2, SPEC.md Grammar rules data, Progress): what is kept per rule and per item,
/// the Grammar day, the three states ("Practiced" boundary vectors) and Add to / Remove from Review.
/// Reading a saved file back is in `GrammarProgressReadingTests`.
final class GrammarProgressTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private func later(_ seconds: Double) -> Date { date.addingTimeInterval(seconds) }
    private var grammar: GrammarRules { GrammarRules.shared }
    private var time: GrammarRule { grammar.rule(id: "time-prepositions")! }
    private var first: String { time.practice[0].id }
    private var second: String { time.practice[1].id }
    private var third: String { time.practice[2].id }

    // MARK: The day

    func testTheDayStartsAtFourInTheLocalTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        let bogota = try XCTUnwrap(TimeZone(identifier: "America/Bogota"))
        calendar.timeZone = bogota
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2001, month: 1, day: day, hour: hour, minute: minute))!
        }
        XCTAssertEqual(GrammarDay.number(of: at(2, 3, 59), in: bogota), 0)
        XCTAssertEqual(GrammarDay.number(of: at(2, 4, 0), in: bogota), 1)
        XCTAssertEqual(GrammarDay.number(of: at(1, 2, 0), in: bogota), -1)
        XCTAssertEqual(GrammarDay.number(of: at(1, 4, 0), in: bogota), 0)
    }

    func testTheDayMatchesAnIndependentCalendarReferenceInManyZones() throws {
        func reference(_ date: Date, calendar: Calendar) -> Int {
            let start = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1))!
            let shifted = calendar.startOfDay(for: date.addingTimeInterval(-4 * 3600))
            return calendar.dateComponents([.day], from: start, to: shifted).day!
        }
        var seed: UInt64 = 42
        for name in ["America/Bogota", "America/New_York", "Pacific/Auckland", "Asia/Kolkata", "UTC"] {
            let zone = try XCTUnwrap(TimeZone(identifier: name))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            for _ in 0..<300 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                // 1990 to 2060, DST changes and leap days included along the way.
                let instant = Date(timeIntervalSince1970: Double(seed >> 33) / Double(1 << 31) * 2_207_520_000 - 630_000_000 + 631_152_000)
                XCTAssertEqual(GrammarDay.number(of: instant, in: zone), reference(instant, calendar: calendar), "\(name) \(instant)")
            }
        }
        // 2024-02-29 and 2100-03-01 (2100 is not a leap year), in UTC at noon.
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(GrammarDay.number(of: Date(timeIntervalSince1970: 1_709_208_000), in: utc), 8459)
        XCTAssertEqual(GrammarDay.number(of: Date(timeIntervalSince1970: 4_107_585_600), in: utc), 36_218)
    }

    // MARK: Answers, counts

    func testOpenedIsKeptInWholeSecondsAndNeverFromAnImpossibleDate() {
        var progress = GrammarProgress()
        progress.opened("a", at: Date(timeIntervalSince1970: 1_800_000_000.9))
        XCTAssertEqual(progress["a"].opened, 1_800_000_000)
        progress.opened("b", at: Date(timeIntervalSince1970: .infinity))
        progress.opened("b", at: Date(timeIntervalSince1970: 1e20))
        XCTAssertNil(progress.rules["b"])
    }

    func testAnItemIsCountedWhenShownAndAnAnswerCountsOnTheRuleAndTheItem() {
        var progress = GrammarProgress()
        XCTAssertEqual(progress[time.id], RuleProgress())
        progress.shown(time, item: second)
        progress.answered(time, item: second, right: false, day: 10, in: .tryIt)
        progress.shown(time, item: second)
        progress.answered(time, item: second, right: true, day: 10, in: .tryIt)
        XCTAssertFalse(progress[time.id].pretestDone, "only an answer given as the pretest sets it")
        progress.shown(time, item: first)
        progress.answered(time, item: first, right: true, day: 10, in: .pretest)
        XCTAssertTrue(progress[time.id].pretestDone)
        XCTAssertEqual(progress[time.id].attempts, 3)
        XCTAssertEqual(progress[time.id].rights, 2)
        XCTAssertEqual(progress[time.id].items[second]?.seen, 2)
        XCTAssertEqual(progress[time.id].items[second]?.missed, 1)
        XCTAssertEqual(progress[time.id].items[first]?.missed, 0)
        XCTAssertNil(progress[time.id].opened)
        progress.shown(time, item: "not-an-item")
        progress.answered(time, item: "not-an-item", right: true, day: 10, in: .tryIt)
        XCTAssertEqual(progress[time.id].attempts, 3, "an item the rule doesn't have is ignored")
        XCTAssertNil(progress[time.id].items["not-an-item"])
    }

    func testAMissedItemIsNeverMissedMoreOftenThanItWasSeen() {
        var progress = GrammarProgress()
        progress.answered(time, item: second, right: false, day: 3, in: .tryIt)
        XCTAssertEqual(progress[time.id].items[second]?.seen, 1)
        XCTAssertEqual(progress[time.id].items[second]?.missed, 1)
    }

    func testCountsAreCapped() {
        var progress = GrammarProgress()
        for _ in 0..<(GrammarProgress.maxCount + 5) {
            progress.shown(time, item: first)
            progress.answered(time, item: first, right: false, day: 1, in: .review)
        }
        XCTAssertEqual(progress[time.id].attempts, GrammarProgress.maxCount)
        XCTAssertEqual(progress[time.id].items[first]?.seen, GrammarProgress.maxCount)
        XCTAssertEqual(progress[time.id].items[first]?.missed, GrammarProgress.maxCount)
        for _ in 0..<(GrammarProgress.maxCount + 5) { progress.answered(time, item: first, right: true, day: 1, in: .review) }
        XCTAssertEqual(progress[time.id].rights, GrammarProgress.maxCount)
    }

    func testASkippedPretestIsKeptApart() {
        var progress = GrammarProgress()
        progress.skippedPretest(time.id)
        XCTAssertTrue(progress[time.id].pretestSkipped)
        XCTAssertFalse(progress[time.id].pretestDone)
    }

    // MARK: Try it flags and Review results

    func testOnlyAMissInTryItFlagsTheItem() {
        var progress = GrammarProgress()
        progress.answered(time, item: second, right: true, day: 4, in: .tryIt)
        XCTAssertNil(progress[time.id].items[second]?.tryMiss)
        progress.answered(time, item: second, right: false, day: 5, in: .review)
        XCTAssertNil(progress[time.id].items[second]?.tryMiss, "a Review miss goes back to box 0 instead")
        progress.answered(time, item: second, right: false, day: 6, in: .pretest)
        XCTAssertNil(progress[time.id].items[second]?.tryMiss)
        progress.answered(time, item: second, right: false, day: 7, in: .tryIt)
        XCTAssertEqual(progress[time.id].items[second]?.tryMiss, 7)
        progress.answered(time, item: second, right: false, day: 9, in: .tryIt)
        XCTAssertEqual(progress[time.id].items[second]?.tryMiss, 9, "the day of the last miss")
    }

    func testReviewSchedulesItsOwnBoxPerItemAndClearsTheFlag() {
        var progress = GrammarProgress()
        progress.answered(time, item: first, right: false, day: 4, in: .tryIt)
        XCTAssertEqual(progress[time.id].items[first]?.tryMiss, 4)
        XCTAssertEqual(progress[time.id].items[first]?.reviewed, false)
        progress.scheduled(time.id, item: first, box: 3, due: 20)
        XCTAssertEqual(progress[time.id].items[first]?.box, 3)
        XCTAssertEqual(progress[time.id].items[first]?.due, 20)
        XCTAssertNil(progress[time.id].items[first]?.tryMiss)
        XCTAssertEqual(progress[time.id].items[first]?.reviewed, true)
        progress.scheduled(time.id, item: first, box: 99, due: nil)
        XCTAssertEqual(progress[time.id].items[first]?.box, GrammarProgress.maxBox)
        XCTAssertNil(progress[time.id].items[first]?.due)
        progress.scheduled(time.id, item: first, box: -4, due: 6)
        XCTAssertEqual(progress[time.id].items[first]?.box, 0)
        XCTAssertEqual(progress[time.id].items[first]?.reviewed, true, "a wrong answer returns to box 0 and stays reviewed")
    }

    func testARuleHoldsAtMostTwelveItems() {
        var progress = GrammarProgress()
        for index in 0..<(GrammarProgress.maxItems + 3) { progress.scheduled("r", item: "item-\(index)", box: 1, due: 3) }
        XCTAssertEqual(progress["r"].items.count, GrammarProgress.maxItems)
        progress.scheduled("r", item: "item-0", box: 2, due: 3)
        XCTAssertEqual(progress["r"].items["item-0"]?.box, 2, "an item already there can still change")
    }

    func testTheLastPairIsSetAndCleared() {
        var progress = GrammarProgress()
        progress.setLastPair(time.id, ItemPair(first, second))
        XCTAssertTrue(try XCTUnwrap(progress[time.id].lastPair).contains([second, first]), "in any order")
        XCTAssertFalse(try XCTUnwrap(progress[time.id].lastPair).contains([first, third]))
        progress.setLastPair(time.id, nil)
        XCTAssertNil(progress[time.id].lastPair)
    }

    // MARK: The three states

    /// A new rule per case; `answers` are (day, item index among the rule's items after the pretest).
    private func state(_ answers: [(Int, Int)], context: GrammarAnswerContext = .tryIt) -> RuleState {
        var progress = GrammarProgress()
        for (day, index) in answers { progress.answered(time, item: time.practice[index].id, right: true, day: day, in: context) }
        return progress.state(of: time.id)
    }

    func testPracticedNeedsTwoRightAnswersOnTwoDaysToTwoItems() {
        // SPEC boundary vectors, with A = item 1 and B = item 2 (the pretest is item 0).
        XCTAssertEqual(state([(5, 1)]), .new)
        XCTAssertEqual(state([(5, 1), (5, 2)]), .new, "same day")
        XCTAssertEqual(state([(5, 1), (6, 1)]), .new, "same item")
        XCTAssertEqual(state([(5, 1), (6, 2)]), .practised)
        XCTAssertEqual(state([(5, 1), (6, 2)], context: .review), .practised, "Review counts too")
        XCTAssertEqual(state([(5, 0), (6, 2)], context: .pretest), .new, "the pretest does not count")
    }

    func testOnlyRightAnswersCountAndTheListNeverHoldsMoreThanTwo() {
        var progress = GrammarProgress()
        progress.answered(time, item: second, right: true, day: 5, in: .tryIt)
        progress.answered(time, item: third, right: false, day: 6, in: .tryIt)
        XCTAssertEqual(progress.state(of: time.id), .new, "a wrong answer is no entry")
        progress.answered(time, item: third, right: true, day: 5, in: .tryIt)
        XCTAssertEqual(progress[time.id].rightDays, [RightDay(day: 5, item: second)], "same day as the entry there")
        progress.answered(time, item: third, right: true, day: 6, in: .review)
        XCTAssertEqual(progress[time.id].rightDays, [RightDay(day: 5, item: second), RightDay(day: 6, item: third)])
        progress.answered(time, item: first, right: true, day: 9, in: .tryIt)
        XCTAssertEqual(progress[time.id].rightDays.count, 2)
        XCTAssertEqual(progress.state(of: time.id), .practised)
    }

    func testInReviewOverridesPracticedAndPractisedIsKeptWhenItLeaves() {
        var progress = GrammarProgress()
        progress.answered(time, item: second, right: true, day: 5, in: .tryIt)
        progress.answered(time, item: third, right: true, day: 6, in: .tryIt)
        progress.addToReview(time, today: 7)
        XCTAssertEqual(progress.state(of: time.id), .inReview)
        progress.removeFromReview(time.id)
        XCTAssertEqual(progress.state(of: time.id), .practised)
    }

    func testOpeningAloneDoesNotMakeARuleChangeState() {
        var progress = GrammarProgress()
        progress.opened(time.id, at: date)
        progress.answered(time, item: second, right: false, day: 3, in: .tryIt)
        XCTAssertEqual(progress.state(of: time.id), .new)
    }

    // MARK: Add to Review, Remove from Review and Undo

    func testAddToReviewPutsEveryItemInBoxZeroDueTomorrow() {
        var progress = GrammarProgress()
        progress.shown(time, item: first)
        progress.answered(time, item: second, right: false, day: 4, in: .tryIt)
        progress.addToReview(time, today: 10)
        XCTAssertTrue(progress[time.id].inReview)
        XCTAssertEqual(progress[time.id].items.count, time.practice.count)
        for item in time.practice {
            XCTAssertEqual(progress[time.id].items[item.id]?.box, 0)
            XCTAssertEqual(progress[time.id].items[item.id]?.due, 11)
            XCTAssertNil(progress[time.id].items[item.id]?.tryMiss)
        }
        XCTAssertEqual(progress[time.id].items[first]?.seen, 1, "counts stay")
        XCTAssertEqual(progress[time.id].items[second]?.missed, 1)
    }

    func testRemoveFromReviewClearsTheScheduleAndUndoPutsItBack() {
        var progress = GrammarProgress()
        progress.addToReview(time, today: 10)
        progress.scheduled(time.id, item: first, box: 2, due: 14)
        progress.shown(time, item: first)
        progress.answered(time, item: second, right: false, day: 12, in: .tryIt)
        progress.setLastPair(time.id, ItemPair(first, second))
        let before = progress[time.id]
        let undo = progress.removeFromReview(time.id)
        XCTAssertEqual(undo, before)
        XCTAssertFalse(progress[time.id].inReview)
        XCTAssertNil(progress[time.id].lastPair)
        for item in progress[time.id].items.values {
            XCTAssertEqual(item.box, 0)
            XCTAssertNil(item.due)
            XCTAssertNil(item.tryMiss)
        }
        XCTAssertEqual(progress[time.id].items[first]?.reviewed, true, "reviewed stays")
        XCTAssertEqual(progress[time.id].items[first]?.seen, 1)
        XCTAssertEqual(progress[time.id].items[second]?.missed, 1)
        progress.restore(time.id, to: undo)
        XCTAssertEqual(progress[time.id], before)
    }

    func testARuleAddedAgainStartsAtBoxZeroDueTomorrow() {
        var progress = GrammarProgress()
        progress.addToReview(time, today: 10)
        progress.scheduled(time.id, item: first, box: 5, due: nil)
        progress.setLastPair(time.id, ItemPair(first, second))
        progress.addToReview(time, today: 40)
        XCTAssertEqual(progress[time.id].items[first]?.box, 0)
        XCTAssertEqual(progress[time.id].items[first]?.due, 41)
        XCTAssertNil(progress[time.id].lastPair)
        XCTAssertEqual(progress[time.id].items[first]?.reviewed, true)
    }

    // MARK: Entries

    func testTheEntriesAreCappedAndTheOldestGoFirst() {
        var progress = GrammarProgress()
        for index in 0..<(GrammarProgress.maxEntries + 3) { progress.opened("rule-\(index)", at: later(Double(index))) }
        XCTAssertEqual(progress.rules.count, GrammarProgress.maxEntries)
        XCTAssertNil(progress.rules["rule-0"])
        XCTAssertNotNil(progress.rules["rule-\(GrammarProgress.maxEntries + 2)"])
        // An entry never opened counts as the oldest; the one just changed is kept.
        progress.skippedPretest("fresh")
        XCTAssertEqual(progress.rules.count, GrammarProgress.maxEntries)
        XCTAssertNotNil(progress.rules["fresh"])
    }

    func testNothingIsSavedWhenTheRulesDidNotLoad() {
        var progress = GrammarProgress()
        progress.opened("a", at: date)
        XCTAssertNil(progress.encoded(for: GrammarRules(categories: [], rules: [])), "keep the saved file")
        XCTAssertFalse(GrammarRules(categories: [], rules: []).isAvailable)
        XCTAssertTrue(grammar.isAvailable)
        XCTAssertEqual(progress.encoded(for: grammar), progress.encoded())
    }
}

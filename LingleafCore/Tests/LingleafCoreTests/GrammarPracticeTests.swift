import XCTest
@testable import LingleafCore

/// Try it and Practice (SPEC.md S22, Grammar rules data): the option order, the draw, the round size and label, the
/// pretest, and the daily counter `itemsAnswered`. Every vector of the SPEC is here.
final class GrammarPracticeTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private var grammar: GrammarRules { GrammarRules.shared }
    private var time: GrammarRule { grammar.rule(id: "time-prepositions")! }

    // MARK: Option order

    func testTheHashAndTheGeneratorMatchTheSpecVectors() {
        XCTAssertEqual(GrammarOptionOrder.fnv1a("a#0"), 0xe649_f919_048c_3037)
        var generator = GrammarOptionOrder.SplitMix64(seed: GrammarOptionOrder.fnv1a("a#0"))
        XCTAssertEqual(generator.next(), 0x0851_d3f5_70ff_7424)
        XCTAssertEqual(GrammarOptionOrder.fnv1a(""), 0xcbf2_9ce4_8422_2325, "the offset basis")
    }

    func testTheOrderMatchesTheSpecVectors() {
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "his-her-its-1", seen: 1, count: 3), [2, 0, 1])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "his-her-its-1", seen: 2, count: 3), [1, 2, 0])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "question-order-1", seen: 0, count: 3), [2, 0, 1])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "age-and-feelings-1", seen: 5, count: 3), [0, 2, 1])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "do-does-did-1", seen: 0, count: 3), [2, 0, 1])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "x", seen: 0, count: 2), [0, 1])
    }

    func testTheOrderIsAlwaysAPermutationAndNeverChangesForTheSameSeen() {
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "x", seen: 0, count: 0), [])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "x", seen: 0, count: -2), [])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "x", seen: 3, count: 1), [0])
        XCTAssertEqual(GrammarOptionOrder.order(itemID: "x", seen: -4, count: 4), GrammarOptionOrder.order(itemID: "x", seen: 0, count: 4))
        for item in grammar.rules.flatMap(\.practice) {
            for seen in 0..<12 {
                let order = GrammarOptionOrder.order(for: item, seen: seen)
                XCTAssertEqual(order.sorted(), Array(item.options.indices), "\(item.id) \(seen)")
                XCTAssertEqual(order, GrammarOptionOrder.order(for: item, seen: seen))
            }
        }
    }

    func testAnItemWithFixedOrderKeepsTheFilesOrder() throws {
        let fixed = grammar.rules.flatMap(\.practice).filter(\.fixedOrder)
        XCTAssertFalse(fixed.isEmpty, "the bundled rules have items that keep their order (a, an, the; in, on, at)")
        for item in fixed {
            for seen in 0..<5 { XCTAssertEqual(GrammarOptionOrder.order(for: item, seen: seen), Array(item.options.indices), item.id) }
        }
        let shuffled = try XCTUnwrap(grammar.rules.flatMap(\.practice).first { !$0.fixedOrder && $0.options.count == 3 })
        XCTAssertEqual(GrammarOptionOrder.order(for: shuffled, seen: 1), GrammarOptionOrder.order(itemID: shuffled.id, seen: 1, count: 3))
    }

    func testTheRightAnswersDoNotPileUpOnOnePosition() {
        var counts = [0, 0, 0]
        var total = 0
        for item in grammar.rules.flatMap(\.practice) where item.options.count == 3 && !item.fixedOrder {
            for seen in 0..<10 {
                let position = GrammarOptionOrder.order(for: item, seen: seen).firstIndex(of: item.answer) ?? 0
                counts[position] += 1
                total += 1
            }
        }
        XCTAssertGreaterThan(total, 0)
        for (position, count) in counts.enumerated() {
            XCTAssertLessThanOrEqual(Double(count) / Double(total), 0.40, "position \(position): \(counts)")
        }
    }

    // MARK: Draw

    private func item(_ id: String, level: String = "A1", textLang: String? = nil) -> PracticeItem {
        PracticeItem(
            id: id, level: level, kind: .choose, text: "text", ask: GrammarText(en: "ask", es: "ask"), options: ["a", "b"], answer: 0,
            feedback: [GrammarText(en: "f", es: "f"), GrammarText(en: "f", es: "f")], fixedOrder: false, textLang: textLang
        )
    }

    private func rule(level: String = "A1", _ items: [PracticeItem]) -> GrammarRule {
        GrammarRule(
            id: "r", category: "c", level: level, title: GrammarText(en: "t", es: "t"), lines: GrammarLines(en: ["l"], es: ["l"]),
            examples: [], contrast: GrammarContrast(forms: ["a", "b"], gloss: nil), note: nil, spanish: nil, aliases: ["x"],
            books: GrammarBooks(mode: .none, patterns: []), practice: items
        )
    }

    private func progress(_ seenMissed: [String: (Int, Int)]) -> RuleProgress {
        var result = RuleProgress()
        for (id, counts) in seenMissed {
            var saved = ItemProgress()
            saved.seen = counts.0
            saved.missed = counts.1
            result.items[id] = saved
        }
        return result
    }

    private func ids(_ items: [PracticeItem]) -> [String] { items.map(\.id) }

    /// Rule level A1, items i1...i6 in file order, all A1, seen/missed: i1 1/0, i2 1/1, i3 0/0, i4 2/1, i5 0/0, i6 0/0.
    private let specCounts: [String: (Int, Int)] = ["i1": (1, 0), "i2": (1, 1), "i3": (0, 0), "i4": (2, 1), "i5": (0, 0), "i6": (0, 0)]
    private var six: [PracticeItem] { (1...6).map { item("i\($0)") } }

    private func draw(
        _ rule: GrammarRule, _ progress: RuleProgress, spanish: Bool = false, excluding: Set<String> = [], _ count: Int
    ) -> [String] {
        ids(GrammarPractice.draw(rule: rule, progress: progress, spanishEligible: spanish, excluding: excluding, count: count))
    }

    func testTheDrawVectorsOfTheSpec() {
        let rule = rule(six)
        let seen = progress(specCounts)
        XCTAssertEqual(draw(rule, seen, 3), ["i3", "i5", "i6"])
        XCTAssertEqual(draw(rule, seen, 6), ["i3", "i5", "i6", "i2", "i1", "i4"], "seen 1 missed 1 before seen 1 missed 0; seen 2 last")
        XCTAssertEqual(draw(rule, seen, excluding: ["i3", "i5"], 3), ["i6", "i2", "i1"])
        XCTAssertEqual(draw(rule, seen, excluding: ["i1", "i2", "i3", "i4"], 3), ["i5", "i6"], "a short round")
        XCTAssertEqual(draw(rule, progress([:]), 3), ["i1", "i2", "i3"], "all 0/0: file order")
        XCTAssertEqual(draw(rule, seen, 0), [])
        XCTAssertEqual(draw(rule, seen, -1), [])
        XCTAssertEqual(draw(rule, seen, 9).sorted(), ["i1", "i2", "i3", "i4", "i5", "i6"], "each candidate once")
        XCTAssertEqual(draw(rule, seen, excluding: Set(["i1", "i2", "i3", "i4", "i5", "i6"]), 3), [], "no candidates")
    }

    func testAnItemAboveTheRulesLevelIsNeverDrawn() {
        var items = six
        items[2] = item("i3", level: "A2")
        XCTAssertEqual(draw(rule(items), progress(specCounts), 6), ["i5", "i6", "i2", "i1", "i4"])
        XCTAssertEqual(draw(rule(level: "A2", items), progress(specCounts), 6), ["i3", "i5", "i6", "i2", "i1", "i4"], "A2 is not above A2")
        XCTAssertEqual(draw(rule(level: "B1", items), progress(specCounts), 6).count, 6)
    }

    func testASpanishSentenceIsDrawnOnlyForASpanishLearner() {
        var items = six
        items[5] = item("i6", textLang: "es")
        XCTAssertEqual(draw(rule(items), progress(specCounts), spanish: false, 6), ["i3", "i5", "i2", "i1", "i4"])
        XCTAssertEqual(draw(rule(items), progress(specCounts), spanish: true, 6), ["i3", "i5", "i6", "i2", "i1", "i4"])
    }

    func testAnItemShownButNotAnsweredIsSeenOnce() {
        var counts = specCounts
        counts["i3"] = (1, 0)
        XCTAssertEqual(draw(rule(six), progress(counts), 6), ["i5", "i6", "i2", "i1", "i3", "i4"])
    }

    func testTheSameExclusionHoldsForASecondRoundOnTheSameOpening() {
        let rule = rule(six)
        var saved = progress([:])
        let excluded: Set<String> = ["i1"]
        let first = draw(rule, saved, excluding: excluded, 3)
        XCTAssertEqual(first, ["i2", "i3", "i4"])
        for id in first {
            var counts = saved.items[id] ?? ItemProgress()
            counts.seen += 1
            saved.items[id] = counts
        }
        let second = draw(rule, saved, excluding: excluded, 3)
        XCTAssertEqual(second, ["i5", "i6", "i2"])
        XCTAssertFalse(second.contains("i1"))
    }

    func testEveryBundledRuleKeepsEnoughItemsForTheDraw() throws {
        for rule in grammar.rules {
            let first = try XCTUnwrap(rule.practice.first)
            XCTAssertNil(first.textLang, "\(rule.id): the pretest has no Spanish text")
            XCTAssertLessThanOrEqual(GrammarLevel.rank(first.level), GrammarLevel.rank(rule.level), rule.id)
            XCTAssertTrue(rule.practice.allSatisfy { GrammarLevel.rank($0.level) <= GrammarLevel.rank(rule.level) }, rule.id)
            XCTAssertGreaterThanOrEqual(rule.practice.count, 6, rule.id)
            let english = rule.practice.filter { $0.textLang == nil }
            XCTAssertGreaterThanOrEqual(english.count, 4, "\(rule.id): 4 without textLang, 3 after the pretest item is excluded")
            let round = GrammarPractice.draw(
                rule: rule, progress: RuleProgress(), spanishEligible: false, excluding: [first.id], count: GrammarPractice.roundMax
            )
            XCTAssertEqual(round.count, 3, rule.id)
        }
    }

    // MARK: Round size and label

    func testTheRoundSizeIsThreeOrWhatRemainsOfSix() {
        XCTAssertEqual([0, 3, 4, 5, 6].map { GrammarPractice.roundSize(answeredToday: $0) }, [3, 3, 2, 1, 0])
        XCTAssertEqual(GrammarPractice.roundSize(answeredToday: 1), 3)
        XCTAssertEqual(GrammarPractice.roundSize(answeredToday: 2), 3)
        XCTAssertEqual(GrammarPractice.roundSize(answeredToday: 7), 0)
        XCTAssertEqual(GrammarPractice.roundSize(answeredToday: -4), 3, "a negative count is 0")
    }

    func testTheButtonIsTryItUntilAnItemOtherThanTheFirstHasBeenShown() {
        let rule = rule(six)
        XCTAssertEqual(GrammarPractice.label(for: rule, progress: RuleProgress()), .tryIt)
        XCTAssertEqual(GrammarPractice.label(for: rule, progress: progress(["i1": (1, 0)])), .tryIt, "only the first item seen")
        XCTAssertEqual(GrammarPractice.label(for: rule, progress: progress(["i1": (2, 0)])), .tryIt, "a pretest shown twice")
        XCTAssertEqual(GrammarPractice.label(for: rule, progress: progress(["i1": (2, 1), "i4": (0, 0)])), .tryIt)
        XCTAssertEqual(GrammarPractice.label(for: rule, progress: progress(["i2": (1, 0)])), .practice)
        XCTAssertEqual(GrammarPractice.label(for: rule, progress: progress(["i1": (1, 0), "i6": (1, 0)])), .practice)
    }

    // MARK: The pretest

    private var first: String { time.practice[0].id }

    func testAPretestAnsweredRightRecordsTheSpecCounters() {
        var progress = GrammarProgress()
        progress.shown(time, item: first)
        XCTAssertTrue(GrammarPretest.record(time, right: true, day: 10, in: &progress))
        let saved = progress[time.id]
        XCTAssertEqual(saved.attempts, 1)
        XCTAssertEqual(saved.rights, 1)
        XCTAssertEqual(saved.items[first]?.seen, 1)
        XCTAssertEqual(saved.items[first]?.missed, 0)
        XCTAssertEqual(saved.rightDays, [])
        XCTAssertNil(saved.items[first]?.tryMiss)
        XCTAssertNil(saved.itemsAnswered)
        XCTAssertTrue(saved.pretestDone)
        XCTAssertFalse(saved.pretestSkipped)
        XCTAssertEqual(GrammarPretest.result(time, progress: saved), GrammarPretest.Result(item: first, seen: 1, missed: 0))
        XCTAssertEqual(GrammarPretest.result(time, progress: saved)?.right, true)
        XCTAssertEqual(progress.state(of: time.id), .new, "the pretest never counts toward Practiced")
        XCTAssertEqual(saved.items[first]?.box, 0)
        XCTAssertNil(saved.items[first]?.due)
    }

    func testAPretestAnsweredWrongRecordsTheSpecCounters() {
        var progress = GrammarProgress()
        progress.shown(time, item: first)
        XCTAssertTrue(GrammarPretest.record(time, right: false, day: 10, in: &progress))
        let saved = progress[time.id]
        XCTAssertEqual(saved.attempts, 1)
        XCTAssertEqual(saved.rights, 0)
        XCTAssertEqual(saved.items[first]?.seen, 1)
        XCTAssertEqual(saved.items[first]?.missed, 1)
        XCTAssertNil(saved.items[first]?.tryMiss)
        XCTAssertNil(saved.itemsAnswered)
        XCTAssertTrue(saved.pretestDone)
        XCTAssertEqual(GrammarPretest.result(time, progress: saved)?.right, false)
    }

    func testAPretestIsRecordedOnlyOnceAndNeverAfterASkip() {
        var progress = GrammarProgress()
        progress.shown(time, item: first)
        XCTAssertTrue(GrammarPretest.record(time, right: true, day: 10, in: &progress))
        let once = progress
        XCTAssertFalse(GrammarPretest.record(time, right: false, day: 10, in: &progress), "never offered again")
        XCTAssertEqual(progress, once)
        var skipped = GrammarProgress()
        skipped.shown(time, item: first)
        skipped.skippedPretest(time.id)
        XCTAssertFalse(GrammarPretest.record(time, right: true, day: 10, in: &skipped))
        XCTAssertNil(GrammarPretest.result(time, progress: skipped[time.id]), "a skipped pretest is left out of the measurement")
        XCTAssertNil(GrammarPretest.result(time, progress: RuleProgress()), "not answered")
        var both = RuleProgress()
        both.pretestDone = true
        both.pretestSkipped = true
        XCTAssertNil(GrammarPretest.result(time, progress: both))
        XCTAssertEqual(GrammarPretest.item(of: time)?.id, first)
    }

    func testSkipThenARightAnswerIsANormalTryItAnswerAndCountsForTheDay() {
        var progress = GrammarProgress()
        progress.shown(time, item: first)
        progress.skippedPretest(time.id)
        progress.shown(time, item: first)
        progress.answered(time, item: first, right: true, day: 20, in: .tryIt)
        let saved = progress[time.id]
        XCTAssertTrue(saved.pretestSkipped)
        XCTAssertFalse(saved.pretestDone)
        XCTAssertEqual(saved.rightDays, [RightDay(day: 20, item: first)])
        XCTAssertEqual(saved.itemsAnswered, ItemsAnswered(day: 20, n: 1), "(d) n is 1")
        XCTAssertEqual(progress.answeredToday(time.id, today: 20), 1)
        let next = GrammarPractice.draw(rule: time, progress: saved, spanishEligible: false, excluding: [first], count: 3)
        XCTAssertFalse(next.map(\.id).contains(first), "(d) the next round on that opening does not contain it")
        XCTAssertFalse(GrammarPretest.record(time, right: true, day: 20, in: &progress), "(b) reopened: no pretest is offered")
    }

    func testLeavingWithoutAnsweringOffersThePretestAgain() {
        var progress = GrammarProgress()
        progress.shown(time, item: first)
        XCTAssertTrue(progress[time.id].pretestOffered, "(c)")
        progress.shown(time, item: first)
        XCTAssertEqual(progress[time.id].items[first]?.seen, 2)
        XCTAssertTrue(progress[time.id].pretestOffered)
    }

    // MARK: Items answered today

    func testOnlyTryItAndPracticeAnswersCountForTheDay() {
        var progress = GrammarProgress()
        progress.answered(time, item: first, right: true, day: 7, in: .pretest)
        progress.answered(time, item: time.practice[1].id, right: true, day: 7, in: .review)
        progress.answered(time, item: time.practice[1].id, right: false, day: 7, in: .review)
        XCTAssertNil(progress[time.id].itemsAnswered)
        XCTAssertEqual(progress.answeredToday(time.id, today: 7), 0)
        progress.shown(time, item: time.practice[2].id)
        XCTAssertNil(progress[time.id].itemsAnswered, "an item shown and not answered adds to seen only")
        progress.answered(time, item: time.practice[2].id, right: true, day: 7, in: .tryIt)
        progress.answered(time, item: time.practice[3].id, right: false, day: 7, in: .tryIt)
        XCTAssertEqual(progress[time.id].itemsAnswered, ItemsAnswered(day: 7, n: 2), "right and wrong (and Not sure, as wrong) both count")
        XCTAssertEqual(progress.answeredToday(time.id, today: 7), 2)
        XCTAssertEqual(progress.answeredToday(time.id, today: 8), 0)
        XCTAssertEqual(progress.answeredToday("no-such-rule", today: 7), 0)
    }

    func testTheCounterStopsAtSix() {
        var progress = GrammarProgress()
        for index in 0..<9 { progress.answered(time, item: time.practice[index % 3].id, right: true, day: 5, in: .tryIt) }
        XCTAssertEqual(progress[time.id].itemsAnswered, ItemsAnswered(day: 5, n: 6))
        XCTAssertEqual(GrammarPractice.roundSize(answeredToday: progress.answeredToday(time.id, today: 5)), 0)
    }

    private func utcDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTheDayChangesAtFourInTheMiddleOfARound() {
        // 9450 is 2026-11-16: days count from 2001-01-01 and a day starts at 04:00.
        XCTAssertEqual(GrammarDay.number(of: utcDate(16, 12, 0), in: utc), 9450)
        var progress = GrammarProgress()
        var entry = RuleProgress()
        entry.itemsAnswered = ItemsAnswered(day: 9450, n: 4)
        progress.restore(time.id, to: entry)
        let drawn = utcDate(17, 3, 58)
        XCTAssertEqual(GrammarDay.number(of: drawn, in: utc), 9450, "still day 9450")
        let drawnDay = GrammarDay.number(of: drawn, in: utc)
        XCTAssertEqual(GrammarPractice.roundSize(answeredToday: progress.answeredToday(time.id, today: drawnDay)), 2)
        let firstAnswer = GrammarDay.number(of: utcDate(17, 3, 59), in: utc)
        progress.answered(time, item: time.practice[1].id, right: true, day: firstAnswer, in: .tryIt)
        XCTAssertEqual(progress[time.id].itemsAnswered, ItemsAnswered(day: 9450, n: 5))
        let secondAnswer = GrammarDay.number(of: utcDate(17, 4, 1), in: utc)
        XCTAssertEqual(secondAnswer, 9451)
        progress.answered(time, item: time.practice[2].id, right: true, day: secondAnswer, in: .tryIt)
        XCTAssertEqual(progress[time.id].itemsAnswered, ItemsAnswered(day: 9451, n: 1))
    }

    func testAStoredDayAfterTodayCountsAsNothingUntilTheNextAnswerReplacesIt() {
        var progress = GrammarProgress()
        var entry = RuleProgress()
        entry.itemsAnswered = ItemsAnswered(day: 9451, n: 3)
        progress.restore(time.id, to: entry)
        XCTAssertEqual(progress.answeredToday(time.id, today: 9450), 0, "the clock moved back")
        progress.answered(time, item: time.practice[1].id, right: false, day: 9450, in: .tryIt)
        XCTAssertEqual(progress[time.id].itemsAnswered, ItemsAnswered(day: 9450, n: 1))
    }

    func testTheSavedFileCarriesTheCounterOnlyWhenItCanBeReadBack() throws {
        let now = utcDate(17, 12, 0)
        let today = GrammarDay.number(of: now, in: utc)
        var progress = GrammarProgress()
        progress.answered(time, item: time.practice[1].id, right: true, day: today, in: .tryIt)
        let data = try XCTUnwrap(progress.encoded(for: grammar))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""itemsAnswered":{"day":\#(today),"n":1}"#))
        XCTAssertEqual(GrammarProgress.decode(data, known: grammar.knownItems, now: now, in: utc), progress)
        var early = GrammarProgress()
        early.answered(time, item: time.practice[1].id, right: true, day: -3, in: .tryIt)
        XCTAssertEqual(early[time.id].itemsAnswered, ItemsAnswered(day: -3, n: 1), "kept in memory so the limit works in the session")
        let written = String(decoding: try XCTUnwrap(early.encoded(for: grammar)), as: UTF8.self)
        XCTAssertFalse(written.contains("itemsAnswered"), "a day before 2001 is not written")
    }
}

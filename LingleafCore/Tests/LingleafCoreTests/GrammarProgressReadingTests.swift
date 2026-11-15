import XCTest
@testable import LingleafCore

/// Reading `tips.json` back (SPEC.md, Grammar rules data, Progress): the largest file, a file that cannot be
/// trusted, and every bound: counts, day numbers, `opened`, `lastPair`, `rightDays`, ids and caps.
final class GrammarProgressReadingTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2027-01-15 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var today: Int { GrammarDay.number(of: now, in: utc) }
    private let known: [String: Set<String>] = ["a": ["a-1", "a-2", "a-3"], "b": ["b-1"]]
    private var grammar: GrammarRules { GrammarRules.shared }

    private func decode(_ json: String, known: [String: Set<String>]? = nil) -> GrammarProgress {
        GrammarProgress.decode(Data(json.utf8), known: known ?? self.known, now: now, in: utc)
    }

    /// The progress of the rule `a` for a saved entry written as JSON.
    private func rule(_ body: String) -> RuleProgress { decode(#"{"schema": 2, "rules": {"a": {\#(body)}}}"#)["a"] }

    private func item(_ body: String) -> ItemProgress? { rule(#""items": {"a-1": {\#(body)}}"#).items["a-1"] }

    func testTheTodayOfTheTestsIsTheDayOfTheSpec() {
        XCTAssertEqual(today, 9_510, "2001-01-01 to 2027-01-15, the instant being 04:00 on the 15th after the 4 hours")
    }

    // MARK: Round trip and size

    func testProgressSurvivesBeingSavedAndRead() throws {
        let time = try XCTUnwrap(grammar.rule(id: "time-prepositions"))
        var progress = GrammarProgress()
        progress.opened(time.id, at: now.addingTimeInterval(-10))
        progress.shown(time, item: time.practice[0].id)
        progress.answered(time, item: time.practice[0].id, right: true, day: today - 3, in: .pretest)
        progress.shown(time, item: time.practice[1].id)
        progress.answered(time, item: time.practice[1].id, right: true, day: today - 2, in: .tryIt)
        progress.answered(time, item: time.practice[2].id, right: true, day: today - 1, in: .tryIt)
        progress.answered(time, item: time.practice[3].id, right: false, day: today, in: .tryIt)
        progress.skippedPretest("place-prepositions")
        progress.addToReview(time, today: today)
        progress.scheduled(time.id, item: time.practice[0].id, box: 2, due: today + 3)
        progress.scheduled(time.id, item: time.practice[1].id, box: 5, due: nil)
        progress.setLastPair(time.id, ItemPair(time.practice[0].id, time.practice[1].id))
        let data = try XCTUnwrap(progress.encoded(for: grammar))
        XCTAssertEqual(GrammarProgress.decode(data, known: grammar.knownItems, now: now, in: utc), progress)
        let onlyTime = [time.id: grammar.knownItems[time.id] ?? []]
        XCTAssertEqual(GrammarProgress.decode(data, known: onlyTime, now: now, in: utc).rules.keys.sorted(), [time.id])
    }

    func testTheLargestProgressStaysUnderTheCapAndReadsBackWhole() throws {
        var entries: [String: RuleProgress] = [:]
        var knownIDs: [String: Set<String>] = [:]
        for index in 0..<GrammarProgress.maxEntries {
            let id = String(repeating: "r", count: 37) + String(format: "%03d", index)
            var entry = RuleProgress()
            entry.opened = 1_799_999_000 + index
            entry.attempts = GrammarProgress.maxCount
            entry.rights = GrammarProgress.maxCount
            // "false" is longer than "true": the largest file has every flag false.
            var ids: [String] = []
            for number in 0..<GrammarProgress.maxItems {
                let itemID = String(repeating: "i", count: 33) + String(format: "%03d", index) + "-" + String(format: "%03d", number)
                var item = ItemProgress()
                item.box = GrammarProgress.maxBox
                item.seen = GrammarProgress.maxCount
                item.missed = GrammarProgress.maxCount
                item.due = today + GrammarProgress.maxDueAhead
                item.tryMiss = today
                item.reviewed = false
                entry.items[itemID] = item
                ids.append(itemID)
            }
            entry.lastPair = ItemPair(ids[0], ids[1])
            entry.rightDays = [RightDay(day: today - 1, item: ids[2]), RightDay(day: today, item: ids[3])]
            entries[id] = entry
            knownIDs[id] = Set(ids)
        }
        let progress = GrammarProgress(rules: entries)
        let data = try XCTUnwrap(progress.encoded())
        XCTAssertGreaterThan(data.count, 370_000, "200 rules x 12 items, 40-char ids, compact JSON, absent values omitted: about 374 KB")
        XCTAssertLessThanOrEqual(data.count, GrammarProgress.maxBytes, "the most the other limits allow fits the 512 KB cap")
        XCTAssertEqual(GrammarProgress.decode(data, known: knownIDs, now: now, in: utc), progress, "what is saved can be read back whole")
    }

    // MARK: A file that cannot be trusted

    func testAFileThatCannotBeTrustedGivesEmptyProgress() {
        XCTAssertEqual(decode("not json"), GrammarProgress())
        XCTAssertEqual(decode(""), GrammarProgress())
        XCTAssertEqual(decode("[]"), GrammarProgress())
        XCTAssertEqual(decode("null"), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2, "rules": {"a": {"attempts": 1}"#), GrammarProgress(), "cut off")
        XCTAssertEqual(decode(#"{"schema": 1, "rules": {"a": {}}}"#), GrammarProgress(), "the old schema")
        XCTAssertEqual(decode(#"{"schema": 3, "rules": {"a": {}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": "2", "rules": {"a": {}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2.5, "rules": {"a": {}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"rules": {"a": {}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2, "rules": []}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2, "rules": "a"}"#), GrammarProgress())
        XCTAssertEqual(GrammarProgress.decode(Data([0xFF, 0xFE, 0x7B, 0x80]), known: known), GrammarProgress(), "not UTF-8")
        XCTAssertNotEqual(decode(#"{"schema": 2, "rules": {"a": {"attempts": 1}}}"#), GrammarProgress(), "the same file whole is read")
    }

    func testAFileOverTheCapOrNestedTooDeepGivesEmptyProgress() {
        let valid = #"{"schema": 2, "rules": {"a": {"attempts": 1}}}"#
        // The cap is on bytes: padded to exactly 512 KB it is read, one byte more it is not.
        let padding = GrammarProgress.maxBytes - valid.utf8.count
        XCTAssertEqual(decode(valid + String(repeating: " ", count: padding))["a"].attempts, 1)
        XCTAssertEqual(decode(valid + String(repeating: " ", count: padding + 1)), GrammarProgress())
        // Depth counts containers: the file is 3 deep; 8 is read, 9 is not.
        XCTAssertEqual(decode(#"{"schema": 2, "rules": {"a": {"attempts": 1, "x": \#(nested(5))}}}"#)["a"].attempts, 1, "8 deep")
        XCTAssertEqual(decode(#"{"schema": 2, "rules": {"a": {"attempts": 1, "x": \#(nested(6))}}}"#), GrammarProgress(), "9 deep")
        XCTAssertEqual(decode(#"{"schema": 2, "rules": [[[[[[[[[1]]]]]]]]]}"#), GrammarProgress())
        XCTAssertEqual(GrammarProgress.decode(Data(String(repeating: "[", count: 100_000).utf8), known: known), GrammarProgress())
    }

    private func nested(_ levels: Int) -> String { String(repeating: "[", count: levels) + String(repeating: "]", count: levels) }

    func testAKeyOutsideTheSchemaIsDroppedAndChangesNothing() {
        let plain = decode(#"{"schema": 2, "rules": {"a": {"attempts": 3, "items": {"a-1": {"seen": 2}}}}}"#)
        let extra = decode(#"""
        {"schema": 2, "x": 1, "rules": {"a": {"attempts": 3, "extra": [1, 2], "opened": "no",
          "items": {"a-1": {"seen": 2, "color": "red"}}}}}
        """#)
        XCTAssertEqual(extra, plain)
        XCTAssertEqual(plain["a"].attempts, 3)
    }

    // MARK: Rules and items

    func testARuleOrItemThatIsUnknownOrHasABadIdIsDropped() {
        let badKnown: [String: Set<String>] = ["a": ["a-1", "A-2", "a_3", String(repeating: "i", count: 41)], "A": [], "": [], "a b": []]
        let read = decode(#"""
        {"schema": 2, "rules": {"a": {"items": {"a-1": {"seen": 1}, "A-2": {"seen": 1}, "a_3": {"seen": 1}, "gone": {"seen": 1},
          "\#(String(repeating: "i", count: 41))": {"seen": 1}}},
          "A": {"attempts": 1}, "": {"attempts": 1}, "a b": {"attempts": 1}, "gone": {"attempts": 1}}}
        """#, known: badKnown)
        XCTAssertEqual(read.rules.keys.sorted(), ["a"])
        XCTAssertEqual(read["a"].items.keys.sorted(), ["a-1"])
        let longID = String(repeating: "r", count: 40)
        let atTheLimit = decode(#"{"schema": 2, "rules": {"\#(longID)": {"attempts": 4}}}"#, known: [longID: []])
        XCTAssertEqual(atTheLimit[longID].attempts, 4, "40 is the most")
        let tooLong = String(repeating: "r", count: 41)
        XCTAssertEqual(decode(#"{"schema": 2, "rules": {"\#(tooLong)": {"attempts": 4}}}"#, known: [tooLong: []]), GrammarProgress())
    }

    func testAnEntryOrItemOfTheWrongShapeIsDropped() {
        let read = decode(#"{"schema": 2, "rules": {"a": "text", "b": {"attempts": 3, "items": {"b-1": 5}}}}"#)
        XCTAssertEqual(read.rules.keys.sorted(), ["b"])
        XCTAssertEqual(read["b"].attempts, 3)
        XCTAssertTrue(read["b"].items.isEmpty)
        XCTAssertTrue(rule(#""items": [1, 2]"#).items.isEmpty)
        XCTAssertTrue(rule(#""items": "x""#).items.isEmpty)
        XCTAssertEqual(item(""), ItemProgress(), "an empty item is a fresh one")
    }

    func testTooManyEntriesAreCutAtTheCapKeepingTheNewest() {
        let count = GrammarProgress.maxEntries + 20
        let entries = (0..<count).map { "\"r\($0)\": {\"attempts\": 1, \"opened\": \(1_700_000_000 + $0)}" }.joined(separator: ",")
        let many = Dictionary(uniqueKeysWithValues: (0..<count).map { ("r\($0)", Set<String>()) })
        let read = decode("{\"schema\": 2, \"rules\": {\(entries)}}", known: many)
        XCTAssertEqual(read.rules.count, GrammarProgress.maxEntries)
        XCTAssertNil(read.rules["r0"], "opened longest ago goes first")
        XCTAssertNotNil(read.rules["r\(count - 1)"])
        XCTAssertNotNil(read.rules["r20"])
    }

    func testTooManyItemsAreCutAtTheCap() {
        let ids = (0..<(GrammarProgress.maxItems + 5)).map { "a-\($0)" }
        let items = ids.map { "\"\($0)\": {\"seen\": 1}" }.joined(separator: ",")
        let read = decode("{\"schema\": 2, \"rules\": {\"a\": {\"items\": {\(items)}}}}", known: ["a": Set(ids)])
        XCTAssertEqual(read["a"].items.count, GrammarProgress.maxItems)
    }

    // MARK: Counts and the box

    func testCountsAreBroughtIntoRangeWithoutOverflow() {
        XCTAssertEqual(rule(#""attempts": 0"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": 1000"#).attempts, 1000)
        XCTAssertEqual(rule(#""attempts": 1001"#).attempts, 1000)
        XCTAssertEqual(rule(#""attempts": 99999"#).attempts, 1000)
        XCTAssertEqual(rule(#""attempts": 9223372036854775807"#).attempts, 1000)
        XCTAssertEqual(rule(#""attempts": 18446744073709551616"#).attempts, 1000, "past Int")
        XCTAssertEqual(rule(#""attempts": 1e30"#).attempts, 1000)
        XCTAssertEqual(rule(#""attempts": -1e30"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": -4"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": -9223372036854775808"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": "7""#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": true"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": null"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": [3]"#).attempts, 0)
    }

    func testRightsNeverExceedAttemptsAndMissedNeverExceedsSeen() {
        XCTAssertEqual(rule(#""attempts": 2, "rights": 9"#).rights, 2)
        XCTAssertEqual(rule(#""attempts": 0, "rights": 9"#).rights, 0)
        XCTAssertEqual(rule(#""attempts": 5, "rights": 5"#).rights, 5)
        XCTAssertEqual(rule(#""rights": "x""#).rights, 0)
        XCTAssertEqual(item(#""seen": 4, "missed": 7"#)?.missed, 4)
        XCTAssertEqual(item(#""seen": 4, "missed": 4"#)?.missed, 4)
        XCTAssertEqual(item(#""seen": 0, "missed": 1"#)?.missed, 0)
        XCTAssertEqual(item(#""seen": -3, "missed": "x""#), ItemProgress())
    }

    func testTheBoxIsZeroToFive() {
        XCTAssertEqual(item(#""box": 5"#)?.box, 5)
        XCTAssertEqual(item(#""box": 6"#)?.box, 5)
        XCTAssertEqual(item(#""box": 9223372036854775807"#)?.box, 5)
        XCTAssertEqual(item(#""box": -1"#)?.box, 0)
        XCTAssertEqual(item(#""box": "3""#)?.box, 0)
    }

    func testFlagsThatAreNotBooleansAreFalse() {
        XCTAssertTrue(rule(#""inReview": true, "pretestDone": true, "pretestSkipped": true"#).inReview)
        XCTAssertTrue(rule(#""pretestDone": true"#).pretestDone)
        XCTAssertTrue(rule(#""pretestSkipped": true"#).pretestSkipped)
        for bad in ["1", "\"yes\"", "null", "[true]"] {
            let read = rule("\"inReview\": \(bad), \"pretestDone\": \(bad), \"pretestSkipped\": \(bad)")
            XCTAssertFalse(read.inReview || read.pretestDone || read.pretestSkipped, bad)
            XCTAssertEqual(item("\"reviewed\": \(bad)")?.reviewed, false, bad)
        }
        XCTAssertEqual(item(#""reviewed": true"#)?.reviewed, true)
    }

    // MARK: Day numbers and the time

    func testADueDayIsAnIntegerFromZeroToTodayPlusThirtyOne() {
        XCTAssertEqual(item(#""due": 0"#)?.due, 0)
        XCTAssertEqual(item(#""due": \#(today)"#)?.due, today)
        XCTAssertEqual(item(#""due": \#(today + 31)"#)?.due, today + 31)
        XCTAssertNil(item(#""due": \#(today + 32)"#)?.due)
        XCTAssertNil(item(#""due": -1"#)?.due)
        XCTAssertNil(item(#""due": 5.5"#)?.due, "not an integer")
        XCTAssertNil(item(#""due": "5""#)?.due)
        XCTAssertNil(item(#""due": true"#)?.due)
        XCTAssertNil(item(#""due": null"#)?.due)
        XCTAssertNil(item(#""due": 1e30"#)?.due, "dropped before any date conversion")
        XCTAssertNil(item(#""due": 9223372036854775807"#)?.due)
        XCTAssertNil(item(#""due": -9223372036854775808"#)?.due)
        XCTAssertNil(item(#""due": 18446744073709551616"#)?.due)
        XCTAssertNotNil(item(#""due": 5"#), "the item itself stays when only its day was wrong")
    }

    func testATryItMissDayIsAnIntegerFromZeroToToday() {
        XCTAssertEqual(item(#""tryMiss": 0"#)?.tryMiss, 0)
        XCTAssertEqual(item(#""tryMiss": \#(today)"#)?.tryMiss, today)
        XCTAssertNil(item(#""tryMiss": \#(today + 1)"#)?.tryMiss)
        XCTAssertNil(item(#""tryMiss": -1"#)?.tryMiss)
        XCTAssertNil(item(#""tryMiss": 2.5"#)?.tryMiss)
        XCTAssertNil(item(#""tryMiss": "3""#)?.tryMiss)
        XCTAssertNil(item(#""tryMiss": 1e30"#)?.tryMiss)
    }

    func testTheTodayOfTheReaderFollowsTheFourOClockDayInTheDeviceZone() throws {
        // 2027-01-15 03:00 in Bogota (UTC-5) still belongs to the 14th's day (9509); 04:00 starts the 15th's (9510).
        let bogota = try XCTUnwrap(TimeZone(identifier: "America/Bogota"))
        let json = Data(#"{"schema": 2, "rules": {"a": {"items": {"a-1": {"tryMiss": 9510}}}}}"#.utf8)
        XCTAssertNil(GrammarProgress.decode(json, known: known, now: now, in: bogota)["a"].items["a-1"]?.tryMiss, "03:00: today is 9509")
        let atFour = GrammarProgress.decode(json, known: known, now: now.addingTimeInterval(3600), in: bogota)
        XCTAssertEqual(atFour["a"].items["a-1"]?.tryMiss, 9510)
    }

    func testOpenedMustLieBetweenTwentyTwentyAndNow() {
        let nowSeconds = 1_800_000_000
        XCTAssertEqual(rule(#""opened": 1577836800"#).opened, 1_577_836_800)
        XCTAssertNil(rule(#""opened": 1577836799"#).opened)
        XCTAssertEqual(rule(#""opened": \#(nowSeconds)"#).opened, nowSeconds)
        XCTAssertNil(rule(#""opened": \#(nowSeconds + 1)"#).opened)
        XCTAssertNil(rule(#""opened": 0"#).opened)
        XCTAssertNil(rule(#""opened": -5"#).opened)
        XCTAssertNil(rule(#""opened": 1700000000.5"#).opened, "whole seconds only")
        XCTAssertNil(rule(#""opened": "1700000000""#).opened)
        XCTAssertNil(rule(#""opened": 1e30"#).opened)
        XCTAssertNil(rule(#""opened": 9223372036854775807"#).opened)
        XCTAssertEqual(rule(#""opened": 1700000000, "attempts": 2"#).attempts, 2, "a bad time keeps the rest of the entry")
        XCTAssertEqual(rule(#""opened": 5, "attempts": 2"#).attempts, 2)
    }

    // MARK: lastPair and rightDays

    func testALastPairIsTwoDifferentItemsOfTheRule() {
        XCTAssertEqual(rule(#""lastPair": ["a-1", "a-2"]"#).lastPair, ItemPair("a-1", "a-2"))
        XCTAssertEqual(rule(#""lastPair": ["a-2", "a-1"]"#).lastPair, ItemPair("a-2", "a-1"))
        for bad in [#"["a-1", "a-1"]"#, #"["a-1"]"#, "[]", #"["a-1", "a-2", "a-3"]"#, #"["a-1", "b-1"]"#, #"["a-1", "nope"]"#,
                    #"["a-1", 2]"#, #""a-1""#, #"{"a": 1}"#, "null", #"["a-1", null]"#] {
            let read = rule("\"lastPair\": \(bad), \"attempts\": 1")
            XCTAssertNil(read.lastPair, bad)
            XCTAssertEqual(read.attempts, 1, "the rest of the entry stays: \(bad)")
        }
    }

    func testRightDaysKeepAtMostTwoEntriesOnDifferentDaysToDifferentItems() {
        func days(_ list: String) -> [RightDay] { rule("\"rightDays\": \(list)").rightDays }
        let ok = [RightDay(day: 5, item: "a-1"), RightDay(day: 6, item: "a-2")]
        XCTAssertEqual(days(#"[{"day": 5, "item": "a-1"}, {"day": 6, "item": "a-2"}]"#), ok)
        XCTAssertEqual(days(#"[{"day": 5, "item": "a-1"}]"#), [RightDay(day: 5, item: "a-1")])
        XCTAssertEqual(days(#"[{"day": 5, "item": "a-1"}, {"day": 5, "item": "a-2"}]"#), [RightDay(day: 5, item: "a-1")], "same day")
        XCTAssertEqual(days(#"[{"day": 5, "item": "a-1"}, {"day": 6, "item": "a-1"}]"#), [RightDay(day: 5, item: "a-1")], "same item")
        XCTAssertEqual(days(#"[{"day": 5, "item": "a-1"}, {"day": 6, "item": "a-2"}, {"day": 7, "item": "a-3"}]"#), ok, "two at most")
        let firstFit = #"[{"day": 5, "item": "a-1"}, {"day": 5, "item": "a-2"}, {"day": 6, "item": "a-2"}]"#
        XCTAssertEqual(days(firstFit), ok, "the first fit is kept")
        XCTAssertEqual(days("[]"), [])
        XCTAssertEqual(days("null"), [])
        XCTAssertEqual(days(#"{"day": 5, "item": "a-1"}"#), [])
        XCTAssertEqual(days("5"), [])
    }

    func testARightDayThatCannotBeRightIsDropped() {
        func days(_ entry: String) -> [RightDay] { rule("\"rightDays\": [\(entry), {\"day\": 3, \"item\": \"a-3\"}]").rightDays }
        let last = [RightDay(day: 3, item: "a-3")]
        XCTAssertEqual(days(#"{"day": \#(today), "item": "a-1"}"#).first, RightDay(day: today, item: "a-1"))
        XCTAssertEqual(days(#"{"day": 0, "item": "a-1"}"#).first, RightDay(day: 0, item: "a-1"))
        XCTAssertEqual(days(#"{"day": \#(today + 1), "item": "a-1"}"#), last, "from the future")
        XCTAssertEqual(days(#"{"day": -1, "item": "a-1"}"#), last)
        XCTAssertEqual(days(#"{"day": 1.5, "item": "a-1"}"#), last)
        XCTAssertEqual(days(#"{"day": "5", "item": "a-1"}"#), last)
        XCTAssertEqual(days(#"{"day": 1e30, "item": "a-1"}"#), last)
        XCTAssertEqual(days(#"{"day": 5, "item": "nope"}"#), last, "an item the rule doesn't have")
        XCTAssertEqual(days(#"{"day": 5, "item": "b-1"}"#), last, "an item of another rule")
        XCTAssertEqual(days(#"{"day": 5, "item": 7}"#), last)
        XCTAssertEqual(days(#"{"day": 5}"#), last)
        XCTAssertEqual(days(#"{"item": "a-1"}"#), last)
        XCTAssertEqual(days("7"), last)
        XCTAssertEqual(days("null"), last)
    }

    func testAReadRuleIsPracticedOnlyWithTwoEntries() {
        let two = decode(#"{"schema": 2, "rules": {"a": {"rightDays": [{"day": 5, "item": "a-1"}, {"day": 6, "item": "a-2"}]}}}"#)
        XCTAssertEqual(two.state(of: "a"), .practised)
        let same = decode(#"{"schema": 2, "rules": {"a": {"rightDays": [{"day": 5, "item": "a-1"}, {"day": 5, "item": "a-2"}]}}}"#)
        XCTAssertEqual(same.state(of: "a"), .new)
    }

    // MARK: Never a crash

    func testDamagedBytesNeverCrashAndNeverGiveMoreThanTheCaps() throws {
        var progress = GrammarProgress()
        for rule in grammar.rules.prefix(8) {
            progress.opened(rule.id, at: now.addingTimeInterval(-60))
            for item in rule.practice.prefix(4) {
                progress.shown(rule, item: item.id)
                progress.answered(rule, item: item.id, right: item.id.hashValue % 2 == 0, day: today - 1, in: .tryIt)
            }
            progress.addToReview(rule, today: today)
            progress.setLastPair(rule.id, ItemPair(rule.practice[0].id, rule.practice[1].id))
        }
        let original = try XCTUnwrap(progress.encoded(for: grammar))
        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        for _ in 0..<400 {
            var bytes = Array(original)
            for _ in 0...(next() % 6) {
                switch next() % 3 {
                case 0: bytes[next() % bytes.count] = UInt8(truncatingIfNeeded: next())
                case 1: bytes.remove(at: next() % bytes.count)
                default: bytes.insert(contentsOf: Array("9999999999999999999999".utf8.prefix(next() % 22)), at: next() % bytes.count)
                }
            }
            let read = GrammarProgress.decode(Data(bytes), known: grammar.knownItems, now: now, in: utc)
            XCTAssertLessThanOrEqual(read.rules.count, GrammarProgress.maxEntries)
            for (id, entry) in read.rules {
                XCTAssertNotNil(grammar.knownItems[id])
                XCTAssertLessThanOrEqual(entry.rights, entry.attempts)
                XCTAssertLessThanOrEqual(entry.attempts, GrammarProgress.maxCount)
                XCTAssertLessThanOrEqual(entry.rightDays.count, 2)
                for (itemID, item) in entry.items {
                    XCTAssertTrue(grammar.knownItems[id]?.contains(itemID) == true)
                    XCTAssertLessThanOrEqual(item.missed, item.seen)
                    XCTAssertTrue((0...GrammarProgress.maxBox).contains(item.box))
                    XCTAssertTrue(item.due.map { (0...(today + 31)).contains($0) } ?? true)
                    XCTAssertTrue(item.tryMiss.map { (0...today).contains($0) } ?? true)
                }
            }
        }
    }
}

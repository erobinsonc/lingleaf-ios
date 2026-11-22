import XCTest
@testable import LingleafCore

/// The vectors of SPEC.md, Grammar rules data, that both platforms must reproduce: the day across time changes,
/// the search's 100 code points and lower-casing, the type policy of saved progress, and the pretest.
final class GrammarContractTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let known: [String: Set<String>] = ["a": ["a-1", "a-2", "a-3"], "b": ["b-1"]]
    private var grammar: GrammarRules { GrammarRules.shared }

    private func decode(_ json: String, now: Date? = nil) -> GrammarProgress {
        GrammarProgress.decode(Data(json.utf8), known: known, now: now ?? self.now, in: utc)
    }

    private func rule(_ body: String) -> RuleProgress { decode(#"{"schema": 2, "rules": {"a": {\#(body)}}}"#)["a"] }

    private func item(_ body: String) -> ItemProgress? { rule(#""items": {"a-1": {\#(body)}}"#).items["a-1"] }

    // MARK: Day across time changes

    /// Expected values are derived by hand from the UTC offsets, not with the "minus 4 hours" rule of the code.
    /// Day numbers: 2001-01-01 to 2025-01-01 is 24 years = 8,760 days + 6 leap days (2004, 08, 12, 16, 20, 24) = 8,766;
    /// 2025-03-01 is +59 = 8,825, so 2025-03-08 = 8,832 and 03-09 = 8,833; 2025-11-01 is +304 = 9,070, so 11-02 = 9,071.
    func testTheDayAcrossTimeChangesFollowsElapsedSecondsNotTheWallClock() throws {
        func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // Spring forward 2025-03-09, 02:00 EST (UTC-5) = 07:00 UTC becomes 03:00 EDT (UTC-4).
        // 08:59:59 UTC - 14,400 s = 04:59:59 UTC = 2025-03-08 23:59:59 EST (UTC-5, before the change): the 8th.
        // 09:00:00 UTC - 14,400 s = 05:00:00 UTC = 2025-03-09 00:00:00 EST: the 9th. So on that day the day starts at
        // 05:00 EDT, not 04:00.
        XCTAssertEqual(GrammarDay.number(of: instant("2025-03-09T08:59:59Z"), in: newYork), 8832)
        XCTAssertEqual(GrammarDay.number(of: instant("2025-03-09T09:00:00Z"), in: newYork), 8833)
        // Fall back 2025-11-02, 02:00 EDT (UTC-4) = 06:00 UTC becomes 01:00 EST (UTC-5).
        // 07:59:59 UTC - 14,400 s = 03:59:59 UTC = 2025-11-01 23:59:59 EDT (UTC-4): the 1st.
        // 08:00:00 UTC - 14,400 s = 04:00:00 UTC = 2025-11-02 00:00:00 EDT: the 2nd. The day starts at 03:00 EST.
        XCTAssertEqual(GrammarDay.number(of: instant("2025-11-02T07:59:59Z"), in: newYork), 9070)
        XCTAssertEqual(GrammarDay.number(of: instant("2025-11-02T08:00:00Z"), in: newYork), 9071)
    }

    /// A zone whose time change is at midnight: Sao Paulo (before 2019), 2018-11-04 00:00 -03 (03:00 UTC) became 01:00 -02,
    /// so local midnight did not exist. 2001-01-01 to 2018-01-01 is 17 years = 6,205 + 4 leap days = 6,209;
    /// 2018-11-01 is +304 = 6,513, so 11-03 = 6,515 and 11-04 = 6,516.
    func testTheDayInAZoneWhoseTimeChangeIsAtMidnight() throws {
        let saoPaulo = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
        // 06:59:59 UTC - 14,400 s = 02:59:59 UTC = 2018-11-03 23:59:59 (-03, before the change): the 3rd.
        // 07:00:00 UTC - 14,400 s = 03:00:00 UTC = the change: 2018-11-04 01:00:00 (-02): the 4th.
        XCTAssertEqual(GrammarDay.number(of: instant("2018-11-04T06:59:59Z"), in: saoPaulo), 6515)
        XCTAssertEqual(GrammarDay.number(of: instant("2018-11-04T07:00:00Z"), in: saoPaulo), 6516)
    }

    // MARK: Search

    private func matches(_ query: String) -> Bool {
        GrammarSearch.matches(grammar.rule(id: "time-prepositions")!, query: query)
    }

    func testOnlyTheFirstHundredCodePointsOfAQueryAreUsed() {
        let supplementary = "\u{1D400}" // a letter outside the BMP: 2 UTF-16 units, 1 code point
        XCTAssertTrue(matches("in"))
        // The letter is the 100th code point: it is used, and no rule has that word.
        XCTAssertFalse(matches("in" + String(repeating: " ", count: 97) + supplementary), "100 code points: used")
        // It is the 101st: cut, so only "in" is left. (Kotlin: codePoints().limit(100), not take(100): take(100) counts
        // UTF-16 units and would cut the first query inside the letter at unit 100, leaving "in" and matching.)
        XCTAssertTrue(matches("in" + String(repeating: " ", count: 98) + supplementary), "101 code points: cut")
        XCTAssertEqual("in\(String(repeating: " ", count: 97))\(supplementary)".unicodeScalars.count, 100)
    }

    func testLowercasingOfIAndFinalSigma() {
        // U+0130 lower-cases to "i" + U+0307 (full mapping), and the dot is a combining mark that is dropped.
        XCTAssertEqual(Array("\u{130}".lowercased().unicodeScalars).map(\.value), [0x69, 0x307])
        XCTAssertEqual(GrammarSearch.words("\u{130}stanbul"), ["istanbul"])
        XCTAssertTrue(matches("\u{130}N"), "İN finds the words that start with in")
        // A final capital sigma: Swift's lowercased() maps each scalar alone (σ); Java's toLowerCase(Locale.ROOT) uses the
        // final-sigma context (ς). Both are letters; the bundled texts hold no Greek, so no search result differs.
        let sigma = GrammarSearch.words("\u{391}\u{3A3}")
        XCTAssertEqual(sigma.count, 1)
        XCTAssertTrue(sigma == ["\u{3B1}\u{3C3}"] || sigma == ["\u{3B1}\u{3C2}"], "the last letter is sigma, final or not")
    }

    // MARK: Type policy of saved progress

    func testCountsTruncateTowardZeroThenSaturate() {
        XCTAssertEqual(rule(#""attempts": 3.7"#).attempts, 3)
        XCTAssertEqual(rule(#""attempts": 3.0"#).attempts, 3, "a count may be written 3.0")
        XCTAssertEqual(rule(#""attempts": 2e2"#).attempts, 200)
        XCTAssertEqual(rule(#""attempts": -0.5"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": 999.99"#).attempts, 999)
        XCTAssertEqual(rule(#""attempts": 1e30"#).attempts, 1000)
        XCTAssertEqual(rule(#""attempts": -1e30"#).attempts, 0)
        XCTAssertEqual(rule(#""attempts": 18446744073709551616"#).attempts, 1000)
        XCTAssertEqual(item(#""seen": 5.9, "missed": 2.2"#)?.seen, 5)
        XCTAssertEqual(item(#""seen": 5.9, "missed": 2.2"#)?.missed, 2)
        XCTAssertEqual(item(#""box": 4.9"#)?.box, 4)
    }

    func testDaysSchemaAndOpenedAreIntegersOnlyWhenWrittenAsIntegerLiterals() {
        XCTAssertNil(item(#""due": 5.0"#)?.due)
        XCTAssertNil(item(#""due": 1e1"#)?.due)
        XCTAssertNil(item(#""due": 1E1"#)?.due)
        XCTAssertNil(item(#""tryMiss": 5.0"#)?.tryMiss)
        XCTAssertNil(item(#""tryMiss": 1e0"#)?.tryMiss)
        XCTAssertEqual(item(#""due": 5, "tryMiss": 3"#)?.due, 5)
        XCTAssertNil(item(#""due": 5.0"#)?.due, "an escaped key cannot hide it")
        XCTAssertEqual(item(#""due": 5"#)?.due, 5)
        XCTAssertNil(rule(#""opened": 1700000000.0"#).opened)
        XCTAssertNil(rule(#""opened": 1.7e9"#).opened)
        XCTAssertEqual(rule(#""opened": 1700000000"#).opened, 1_700_000_000)
        let mixed = #""rightDays": [{"day": 5.0, "item": "a-1"}, {"day": 6, "item": "a-2"}]"#
        XCTAssertEqual(rule(mixed).rightDays, [RightDay(day: 6, item: "a-2")])
        XCTAssertEqual(rule(#""rightDays": [{"day": 1e1, "item": "a-1"}]"#).rightDays, [])
        XCTAssertEqual(decode(#"{"schema": 2.0, "rules": {"a": {"attempts": 1}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2e0, "rules": {"a": {"attempts": 1}}}"#), GrammarProgress())
        XCTAssertEqual(decode(#"{"schema": 2, "rules": {"a": {"attempts": 1}}}"#)["a"].attempts, 1)
        // The rest of the entry stays when only a day was written as a non-integer.
        XCTAssertEqual(rule(#""opened": 1.7e9, "attempts": 4"#).attempts, 4)
    }

    func testAValueOfTheWrongTypeReadsAsZeroFalseOrNoneAndOnlyAnEntryThatIsNotAnObjectIsDropped() {
        XCTAssertEqual(rule(#""attempts": null, "inReview": null, "opened": null"#), RuleProgress())
        let both = decode(#"{"schema": 2, "rules": {"a": {"attempts": 2}, "b": 5}}"#)
        XCTAssertEqual(both["a"].attempts, 2, "a rule that is not an object is dropped alone")
        XCTAssertNil(both.rules["b"])
        let items = rule(#""items": {"a-1": {"seen": 2}, "a-2": 7, "a-3": null}"#).items
        XCTAssertEqual(items["a-1"]?.seen, 2)
        XCTAssertEqual(items.count, 1, "an item that is not an object is dropped alone")
        let days = rule(#""rightDays": [3, null, {"day": 5, "item": "a-1"}, "x"]"#).rightDays
        XCTAssertEqual(days, [RightDay(day: 5, item: "a-1")])
    }

    func testRightDaysAreReadInFileOrderSkippingWhatDoesNotFit() {
        let list = #"[{"day": 5, "item": "a-1"}, {"day": 5, "item": "a-2"}, {"day": 6, "item": "a-2"}]"#
        XCTAssertEqual(rule("\"rightDays\": \(list)").rightDays, [RightDay(day: 5, item: "a-1"), RightDay(day: 6, item: "a-2")])
        let invalidFirst = #"""
        [{"day": 5, "item": "nope"}, {"day": 99999, "item": "a-1"}, {"day": 5, "item": "a-1"}, {"day": 6, "item": "a-2"}]
        """#
        XCTAssertEqual(rule("\"rightDays\": \(invalidFirst)").rightDays, [RightDay(day: 5, item: "a-1"), RightDay(day: 6, item: "a-2")])
    }

    // MARK: The file as bytes

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    private func read(_ data: Data) -> GrammarProgress { GrammarProgress.decode(data, known: known, now: now, in: utc) }

    func testAFileThatIsNotUTF8GivesEmptyProgress() {
        let json = #"{"schema": 2, "rules": {"a": {"attempts": 3}}}"#
        XCTAssertEqual(read(bytes(json))["a"].attempts, 3)
        XCTAssertEqual(read(Data([0xEF, 0xBB, 0xBF]) + bytes(json))["a"].attempts, 3, "a UTF-8 BOM is ignored")
        XCTAssertEqual(read(bytes(" \n\t\r" + json))["a"].attempts, 3, "leading white space")
        let utf16 = Data([0xFF, 0xFE]) + (json.data(using: .utf16LittleEndian) ?? Data())
        XCTAssertEqual(read(utf16), GrammarProgress(), "UTF-16 with a BOM")
        XCTAssertEqual(read(json.data(using: .utf16LittleEndian) ?? Data()), GrammarProgress(), "UTF-16 without one")
        XCTAssertEqual(read(json.data(using: .utf32LittleEndian) ?? Data()), GrammarProgress(), "UTF-32")
        XCTAssertEqual(read(bytes(json + "\u{0}")), GrammarProgress(), "a 0x00 byte")
        XCTAssertEqual(read(bytes("x" + json)), GrammarProgress(), "does not start with {")
        XCTAssertEqual(read(Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + bytes(json)), GrammarProgress(), "a second BOM")
        XCTAssertEqual(read(bytes(json) + Data([0xC3])), GrammarProgress(), "an invalid sequence")
    }

    func testARawControlCharacterInsideAStringGivesEmptyProgress() {
        for control in [UInt8(0x01), 0x1F, 0x0A, 0x09] {
            let char = String(UnicodeScalar(control))
            let inKey = #"{"schema": 2, "rules": {"a": {"att\#(char)empts": 3, "attempts": 3}}}"#
            let inValue = #"{"schema": 2, "rules": {"a": {"items": {"a-1": {}}, "rightDays": [{"day": 5, "item": "a\#(char)-1"}]}}}"#
            let topKey = #"{"sch\#(char)ema": 2, "schema": 2, "rules": {}}"#
            let topValue = #"{"schema": 2, "rules": {"a": {}}, "x": "v\#(char)w"}"#
            let underItems = #"{"schema": 2, "rules": {"a": {"items": {"a-1\#(char)": {"seen": 1}}}}}"#
            for text in [inKey, inValue, topKey, topValue, underItems] {
                XCTAssertEqual(read(bytes(text)), GrammarProgress(), "0x\(String(control, radix: 16))")
            }
        }
        let escaped = #"{"schema": 2, "rules": {"a": {"attempts": 3, "note": "tab\there \u0001"}}}"#
        XCTAssertEqual(read(bytes(escaped))["a"].attempts, 3, "the same characters written as escapes are fine")
    }

    // MARK: A clock that is not a clock

    func testANowThatIsNotANumberGivesEmptyProgressAndNeverTraps() {
        let json = #"{"schema": 2, "rules": {"a": {"attempts": 3}}}"#
        for bad in [Double.nan, .infinity] {
            let moment = Date(timeIntervalSince1970: bad)
            XCTAssertEqual(GrammarProgress.decode(bytes(json), known: known, now: moment, in: utc), GrammarProgress())
        }
    }

    func testAClockBeforeTwoThousandOneNeverTraps() {
        let file = #"""
        {"schema": 2, "rules": {"a": {"opened": 1700000000, "rightDays": [{"day": 0, "item": "a-1"}, {"day": 3, "item": "a-2"}],
        "items": {"a-1": {"due": 0, "tryMiss": 0, "seen": 1}, "a-2": {"due": 5, "tryMiss": -3}}}}}
        """#
        for seconds: Double in [0, -1_000_000_000, 978_307_199, 978_307_200, -1e15, 1e18] {
            let moment = Date(timeIntervalSince1970: seconds)
            let read = decode(file, now: moment)
            XCTAssertLessThanOrEqual(read["a"].rightDays.count, 2)
        }
        let epoch = decode(file, now: Date(timeIntervalSince1970: 0))
        XCTAssertLessThan(GrammarDay.number(of: Date(timeIntervalSince1970: 0), in: utc), 0, "today is negative")
        XCTAssertEqual(epoch["a"].rightDays, [], "no day can be 0...today")
        XCTAssertNil(epoch["a"].items["a-1"]?.due)
        XCTAssertNil(epoch["a"].items["a-1"]?.tryMiss)
        XCTAssertEqual(epoch["a"].items["a-1"]?.seen, 1)
        XCTAssertNil(epoch["a"].opened, "after now")
    }

    // MARK: Pretest

    func testASkippedPretestThenARightAnswerOnTheSamePageIsANormalTryItAnswer() throws {
        let time = try XCTUnwrap(grammar.rule(id: "time-prepositions"))
        var progress = GrammarProgress()
        progress.opened(time.id, at: now)
        XCTAssertTrue(progress[time.id].pretestOffered)
        progress.shown(time, item: time.practice[0].id)
        progress.skippedPretest(time.id)
        progress.answered(time, item: time.practice[0].id, right: true, day: 5, in: .tryIt)
        let saved = progress[time.id]
        XCTAssertTrue(saved.pretestSkipped)
        XCTAssertFalse(saved.pretestDone, "no pretest result")
        XCTAssertEqual(saved.rightDays, [RightDay(day: 5, item: time.practice[0].id)], "a normal Try it answer, which counts")
        XCTAssertEqual(saved.items[time.practice[0].id]?.seen, 1)
        XCTAssertEqual(saved.attempts, 1)
    }

    func testAfterASkipTheReopenedRuleOffersNoPretestButLeavingUnansweredDoes() throws {
        let time = try XCTUnwrap(grammar.rule(id: "time-prepositions"))
        var skipped = GrammarProgress()
        skipped.skippedPretest(time.id)
        skipped.opened(time.id, at: now)
        XCTAssertFalse(skipped[time.id].pretestOffered, "after a skip it is never offered again")
        var answered = GrammarProgress()
        answered.shown(time, item: time.practice[0].id)
        answered.answered(time, item: time.practice[0].id, right: false, day: 5, in: .pretest)
        XCTAssertFalse(answered[time.id].pretestOffered)
        XCTAssertEqual(answered[time.id].items[time.practice[0].id]?.seen, 1, "a shown item has seen 1: Practice must not draw it again")
        var left = GrammarProgress()
        left.shown(time, item: time.practice[0].id)
        left.opened(time.id, at: now)
        let reopened = GrammarProgress.decode(try XCTUnwrap(left.encoded(for: grammar)), known: grammar.knownItems, now: now, in: utc)
        XCTAssertTrue(reopened[time.id].pretestOffered, "left without answering or skipping: offered again")
        let skippedBack = GrammarProgress.decode(try XCTUnwrap(skipped.encoded(for: grammar)), known: grammar.knownItems, now: now, in: utc)
        XCTAssertFalse(skippedBack[time.id].pretestOffered)
    }

    func testAnOpenedTimeBeforeTwentyTwentyIsNotWritten() {
        var progress = GrammarProgress()
        progress.opened("a", at: Date(timeIntervalSince1970: 1_577_836_799))
        XCTAssertNil(progress.rules["a"])
        progress.opened("a", at: Date(timeIntervalSince1970: 1_577_836_800))
        XCTAssertEqual(progress["a"].opened, 1_577_836_800)
        progress.opened("b", at: Date(timeIntervalSince1970: .nan))
        XCTAssertNil(progress.rules["b"])
    }

    // MARK: The rules file as bytes

    func testTheRulesFileRefusesAControlCharacterANullAndAnIntegerWrittenAsADecimal() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/LingleafCore/Resources/grammar-rules.json").standardizedFileURL
        let text = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        XCTAssertNoThrow(try GrammarRules.load(Data(text.utf8)))
        let broken = text.replacingOccurrences(of: #""id": "his-her-its""#, with: "\"id\": \"his-her-\u{01}its\"")
        XCTAssertNotEqual(broken, text)
        XCTAssertThrowsError(try GrammarRules.load(Data(broken.utf8)), "a raw control character")
        let schema = text.replacingOccurrences(of: #""schema": 1"#, with: #""schema": 1.0"#)
        XCTAssertNotEqual(schema, text)
        XCTAssertThrowsError(try GrammarRules.load(Data(schema.utf8)), "schema written as 1.0")
        let answer = text.replacingOccurrences(of: #""answer": 0"#, with: #""answer": 0.0"#)
        XCTAssertNotEqual(answer, text)
        XCTAssertThrowsError(try GrammarRules.load(Data(answer.utf8)), "answer written as 0.0")
        let null = text.replacingOccurrences(of: #""schema": 1"#, with: #""schema": 1, "extra": null"#)
        XCTAssertThrowsError(try GrammarRules.load(Data(null.utf8)), "a null anywhere")
    }
}

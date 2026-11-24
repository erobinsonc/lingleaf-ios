import XCTest
@testable import LingleafCore

/// The writer of `tips.json` never emits what the reader drops, a file at the theoretical largest still fits the cap,
/// and a count set far out of range in memory cannot trap (security review of the store).
final class GrammarWriterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var today: Int { GrammarDay.number(of: now, in: utc) }
    private var grammar: GrammarRules { GrammarRules.shared }
    private var time: GrammarRule { grammar.rule(id: "time-prepositions")! }

    private func text(_ progress: GrammarProgress, today: Int? = nil) throws -> String {
        String(decoding: try XCTUnwrap(progress.encoded(for: grammar, today: today)), as: UTF8.self)
    }

    private func readBack(_ progress: GrammarProgress, today: Int? = nil) throws -> GrammarProgress {
        let data = try XCTUnwrap(progress.encoded(for: grammar, today: today))
        return GrammarProgress.decode(data, known: grammar.knownItems, now: now, in: utc)
    }

    // MARK: Writer and reader agree

    func testADayTheReaderWouldDropIsNotWritten() throws {
        let item = time.practice[1].id, other = time.practice[2].id
        var entry = RuleProgress()
        var saved = ItemProgress()
        saved.tryMiss = -1
        saved.due = -2
        entry.items[item] = saved
        entry.rightDays = [RightDay(day: -5, item: item), RightDay(day: 3, item: other)]
        entry.itemsAnswered = ItemsAnswered(day: -1, n: 2)
        let progress = GrammarProgress(rules: [time.id: entry])
        let json = try text(progress)
        XCTAssertFalse(json.contains("tryMiss"), json)
        XCTAssertFalse(json.contains("\"due\""), json)
        XCTAssertFalse(json.contains("itemsAnswered"), json)
        XCTAssertTrue(json.contains(#""day":3"#) && !json.contains("-5"), "only the valid right day is written")
        let read = try readBack(progress)[time.id]
        XCTAssertNil(read.items[item]?.tryMiss)
        XCTAssertNil(read.items[item]?.due)
        XCTAssertEqual(read.rightDays, [RightDay(day: 3, item: other)])
    }

    func testADayAfterTodayOrADueTooFarAheadIsNotWrittenWhenTodayIsKnown() throws {
        let item = time.practice[1].id
        var entry = RuleProgress()
        var saved = ItemProgress()
        saved.tryMiss = today + 1
        saved.due = today + GrammarProgress.maxDueAhead + 1
        entry.items[item] = saved
        entry.rightDays = [RightDay(day: today + 2, item: item)]
        entry.itemsAnswered = ItemsAnswered(day: today + 1, n: 1)
        let progress = GrammarProgress(rules: [time.id: entry])
        let json = try text(progress, today: today)
        for field in ["tryMiss", "\"due\"", "itemsAnswered", "\"day\""] { XCTAssertFalse(json.contains(field), "\(field) in \(json)") }
        // At the limits they are written.
        saved.tryMiss = today
        saved.due = today + GrammarProgress.maxDueAhead
        entry.items[item] = saved
        entry.rightDays = [RightDay(day: today, item: item)]
        entry.itemsAnswered = ItemsAnswered(day: today, n: 6)
        let kept = try readBack(GrammarProgress(rules: [time.id: entry]), today: today)[time.id]
        XCTAssertEqual(kept.items[item]?.tryMiss, today)
        XCTAssertEqual(kept.items[item]?.due, today + GrammarProgress.maxDueAhead)
        XCTAssertEqual(kept.rightDays, [RightDay(day: today, item: item)])
        XCTAssertEqual(kept.itemsAnswered, ItemsAnswered(day: today, n: 6))
    }

    func testALastPairIsWrittenOnlyAsTwoDifferentItemsOfTheRule() throws {
        let first = time.practice[0].id, second = time.practice[1].id
        func lastPair(_ pair: ItemPair?) throws -> ItemPair? {
            var entry = RuleProgress()
            entry.lastPair = pair
            return try readBack(GrammarProgress(rules: [time.id: entry]))[time.id].lastPair
        }
        XCTAssertEqual(try lastPair(ItemPair(first, second)), ItemPair(first, second))
        XCTAssertNil(try lastPair(ItemPair(first, first)))
        XCTAssertNil(try lastPair(ItemPair(first, "not-an-item")))
        XCTAssertNil(try lastPair(nil))
        var entry = RuleProgress()
        entry.lastPair = ItemPair(first, first)
        XCTAssertFalse(try text(GrammarProgress(rules: [time.id: entry])).contains("lastPair"))
        var progress = GrammarProgress()
        progress.setLastPair(time.id, ItemPair(first, first))
        XCTAssertNil(progress[time.id].lastPair, "set time: two different items, or nothing")
        progress.setLastPair(time.id, ItemPair(first, second))
        XCTAssertEqual(progress[time.id].lastPair, ItemPair(first, second))
    }

    func testARightDayForAnItemOutsideTheRuleIsNotWritten() throws {
        var entry = RuleProgress()
        entry.rightDays = [RightDay(day: 3, item: "not-an-item"), RightDay(day: 4, item: time.practice[1].id)]
        XCTAssertEqual(try readBack(GrammarProgress(rules: [time.id: entry]))[time.id].rightDays, [RightDay(day: 4, item: time.practice[1].id)])
        XCTAssertFalse(try text(GrammarProgress(rules: [time.id: entry])).contains("not-an-item"))
    }

    func testWhatIsWrittenReadsBackAsItIsAndWritingItAgainChangesNothing() throws {
        var progress = GrammarProgress()
        let items = time.practice.map(\.id)
        progress.opened(time.id, at: now.addingTimeInterval(-5))
        progress.answered(time, item: items[1], right: true, day: today - 2, in: .tryIt)
        progress.answered(time, item: items[2], right: false, day: today - 1, in: .tryIt)
        progress.addToReview(time, today: today)
        progress.setLastPair(time.id, ItemPair(items[1], items[2]))
        let first = try XCTUnwrap(progress.encoded(for: grammar, today: today))
        let read = GrammarProgress.decode(first, known: grammar.knownItems, now: now, in: utc)
        XCTAssertEqual(read, progress)
        XCTAssertEqual(try XCTUnwrap(read.encoded(for: grammar, today: today)), first)
    }

    // MARK: The largest file

    /// Every field at the most the writer can emit: 200 rules, 12 items, 40-character ids, the largest numbers, flags
    /// false, every optional present. It must fit the cap the reader (and the file writer) enforce.
    func testTheTheoreticalWorstCaseFitsUnderTheCapAndIsAcceptedByTheFile() throws {
        var entries: [String: RuleProgress] = [:]
        let big = 999_999_999_999_999
        for index in 0..<GrammarProgress.maxEntries {
            let id = String(repeating: "r", count: 37) + String(format: "%03d", index)
            var entry = RuleProgress()
            entry.opened = big
            entry.attempts = GrammarProgress.maxCount
            entry.rights = GrammarProgress.maxCount
            var ids: [String] = []
            for number in 0..<GrammarProgress.maxItems {
                let itemID = String(repeating: "i", count: 33) + String(format: "%03d", index) + "-" + String(format: "%03d", number)
                var item = ItemProgress()
                item.box = GrammarProgress.maxBox
                item.seen = GrammarProgress.maxCount
                item.missed = GrammarProgress.maxCount
                item.due = big
                item.tryMiss = big
                entry.items[itemID] = item
                ids.append(itemID)
            }
            entry.lastPair = ItemPair(ids[0], ids[1])
            entry.rightDays = [RightDay(day: big, item: ids[2]), RightDay(day: big - 1, item: ids[3])]
            entry.itemsAnswered = ItemsAnswered(day: big, n: GrammarProgress.maxItemsAnswered)
            entries[id] = entry
        }
        let data = try XCTUnwrap(GrammarProgress(rules: entries).encoded())
        XCTAssertLessThan(data.count, GrammarProgress.maxBytes, "even with 15-digit days (more than the reader accepts): \(data.count)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grammar-worst-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(GrammarProgressFile(directory: directory).write(data), "the file accepts it: a save cannot fail silently for size")
    }

    func testAFileOverTheCapIsRefusedByTheWriterAndTheStoreSaysSo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grammar-over-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(GrammarProgressFile(directory: directory).write(Data(count: GrammarProgress.maxBytes + 1)))
    }

    // MARK: Counts far out of range

    func testAStoredCountFarOutOfRangeNeverTraps() {
        for stored in [Int.max, Int.max - 1, Int.min, -1, 7, 6] {
            var progress = GrammarProgress()
            var entry = RuleProgress()
            entry.itemsAnswered = ItemsAnswered(day: 5, n: stored)
            progress.restore(time.id, to: entry)
            XCTAssertLessThanOrEqual(progress.answeredToday(time.id, today: 5), GrammarProgress.maxItemsAnswered, "\(stored)")
            progress.answered(time, item: time.practice[1].id, right: true, day: 5, in: .tryIt)
            let n = progress[time.id].itemsAnswered?.n ?? -1
            XCTAssertTrue((1...GrammarProgress.maxItemsAnswered).contains(n), "\(stored) gives \(n)")
        }
    }

    // MARK: A string cut off in the middle of an escape

    func testATruncatedStringEndingInABackslashIsRefusedNotRead() {
        for cut in [#"{"a": "abc\"#, #"{"a\"#, #"{"d\u00"#, #"{"a": "x\\\"#, "{\"a\": \"\\"] {
            let result = GrammarJSON.scrubbed(Data(cut.utf8), integerKeys: ["day"], policy: .tolerant)
            XCTAssertNil(result, cut)
            XCTAssertNil(GrammarJSON.scrubbed(Data(cut.utf8), integerKeys: ["day"], policy: .strict), cut)
        }
        XCTAssertNil(GrammarProgress.decode(Data(#"{"schema": 2, "rules": {"a": "x\"#.utf8), known: [:]).rules.first)
    }
}

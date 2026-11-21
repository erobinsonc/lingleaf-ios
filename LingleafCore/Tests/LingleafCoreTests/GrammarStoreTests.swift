import XCTest
@testable import LingleafCore

/// `tips.json` on disk and the store that keeps it (SPEC.md, Grammar rules data, Progress; S22 saves): a bounded read,
/// an atomic write, and a save after each change.
final class GrammarStoreTests: XCTestCase {
    private var grammar: GrammarRules { GrammarRules.shared }
    private var time: GrammarRule { grammar.rule(id: "time-prepositions")! }
    private var directory: URL!
    private var moment = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("grammar-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(_ rules: GrammarRules? = nil) -> GrammarStore {
        GrammarStore(grammar: rules ?? grammar, directory: directory, clock: { self.moment }, zone: utc)
    }

    private var file: URL { directory.appendingPathComponent("tips.json") }

    // MARK: The file

    func testTheFileHasItsPlainNameAndTheProtectionTheSpecAsks() {
        XCTAssertEqual(GrammarProgressFile.name, "tips.json")
        XCTAssertTrue(StorageNames.isSafe(GrammarProgressFile.name))
        XCTAssertEqual(GrammarProgressFile.writeOptions, [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        XCTAssertEqual(GrammarProgressFile.maxRead, GrammarProgress.maxBytes + 1)
    }

    func testAFileWritesAndReadsBackAndAMissingOneReadsAsNothing() {
        let tips = GrammarProgressFile(directory: directory)
        XCTAssertNil(tips.read())
        XCTAssertTrue(tips.write(Data("{}".utf8)))
        XCTAssertEqual(tips.read(), Data("{}".utf8))
        XCTAssertTrue(tips.write(Data("[]".utf8)), "replaced whole")
        XCTAssertEqual(tips.read(), Data("[]".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["tips.json"], "no temporary file left behind")
    }

    func testTheReadStopsOneByteOverTheCapWhateverTheFileHolds() throws {
        let tips = GrammarProgressFile(directory: directory)
        try Data(repeating: 0x20, count: GrammarProgress.maxBytes * 4).write(to: file)
        XCTAssertEqual(tips.read()?.count, GrammarProgress.maxBytes + 1, "a large file is never read whole")
        try Data(repeating: 0x20, count: GrammarProgress.maxBytes).write(to: file)
        XCTAssertEqual(tips.read()?.count, GrammarProgress.maxBytes)
    }

    func testNothingEmptyOrTooLargeIsEverWritten() throws {
        let tips = GrammarProgressFile(directory: directory)
        XCTAssertTrue(tips.write(Data("{}".utf8)))
        XCTAssertFalse(tips.write(Data()), "empty data would replace the file with nothing")
        XCTAssertFalse(tips.write(Data(repeating: 0x20, count: GrammarProgress.maxBytes + 1)), "the reader would refuse it")
        XCTAssertEqual(tips.read(), Data("{}".utf8), "the saved file stays as it was")
        XCTAssertTrue(tips.write(Data(repeating: 0x20, count: GrammarProgress.maxBytes)))
    }

    func testOnlyAPlainNameIsAccepted() {
        for name in ["../tips.json", "a/b.json", "", ".hidden", "..", String(repeating: "a", count: 200)] {
            let bad = GrammarProgressFile(directory: directory, name: name)
            XCTAssertFalse(bad.write(Data("{}".utf8)), name)
            XCTAssertNil(bad.read(), name)
        }
        let outside = directory.deletingLastPathComponent().appendingPathComponent("tips.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    func testAnUnwritableLocationFailsWithoutCrashing() throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory)
        XCTAssertFalse(GrammarProgressFile(directory: directory).write(Data("{}".utf8)), "a file stands where the folder should be")
    }

    // MARK: The store

    func testAFreshStoreIsEmptyAndWritesNothingUntilSomethingChanges() {
        let fresh = store()
        XCTAssertEqual(fresh.progress, GrammarProgress())
        XCTAssertFalse(fresh.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(fresh.today, GrammarDay.number(of: moment, in: utc))
    }

    func testEachChangeIsSavedAtOnceAndReadBackByTheNextStore() throws {
        let first = try XCTUnwrap(GrammarPretest.item(of: time))
        let second = time.practice[1]
        let session = store()
        session.opened(time)
        var onDisk = GrammarProgress.decode(try XCTUnwrap(Data(contentsOf: file)), known: grammar.knownItems, now: moment, in: utc)
        XCTAssertEqual(onDisk[time.id].opened, 1_800_000_000, "saved when the rule page opened")
        session.shown(time, item: first)
        onDisk = GrammarProgress.decode(try Data(contentsOf: file), known: grammar.knownItems, now: moment, in: utc)
        XCTAssertEqual(onDisk[time.id].items[first.id]?.seen, 1, "saved at show, before any answer")
        XCTAssertTrue(session.answeredPretest(time, right: false))
        onDisk = GrammarProgress.decode(try Data(contentsOf: file), known: grammar.knownItems, now: moment, in: utc)
        XCTAssertTrue(onDisk[time.id].pretestDone)
        XCTAssertEqual(onDisk[time.id].items[first.id]?.missed, 1, "saved at the answer")
        session.shown(time, item: second)
        session.answeredPractice(time, item: second, right: true)
        XCTAssertEqual(session.progress[time.id].itemsAnswered, ItemsAnswered(day: session.today, n: 1))
        XCTAssertFalse(session.hasUnsavedChanges)
        let later = store()
        XCTAssertEqual(later.progress, session.progress, "a store made later reads what was saved")
    }

    func testPretestAndSkipAreRecordedThroughTheStore() {
        let session = store()
        session.shown(time, item: time.practice[0])
        session.skippedPretest(time)
        XCTAssertTrue(session.progress[time.id].pretestSkipped)
        XCTAssertFalse(session.answeredPretest(time, right: true), "a skipped pretest is never recorded")
        session.answeredPractice(time, item: time.practice[0], right: true)
        XCTAssertEqual(store().progress[time.id].rightDays.count, 1, "after a skip the answer is a normal one")
    }

    func testAnUpdateGetsTodayAndIsSaved() {
        let session = store()
        var seenDay = -1
        session.update { progress, day in
            seenDay = day
            progress.addToReview(self.time, today: day)
        }
        XCTAssertEqual(seenDay, session.today)
        XCTAssertTrue(store().progress[time.id].inReview)
    }

    func testTheDayComesFromTheClockAtTheMomentOfTheAnswer() {
        let session = store()
        session.update { progress, day in progress.answered(self.time, item: self.time.practice[1].id, right: true, day: day, in: .tryIt) }
        let before = session.today
        moment = moment.addingTimeInterval(86_400)
        XCTAssertEqual(session.today, before + 1)
        session.answeredPractice(time, item: time.practice[2], right: true)
        XCTAssertEqual(session.progress[time.id].itemsAnswered, ItemsAnswered(day: before + 1, n: 1), "a new day starts the count again")
    }

    func testAFileThatCannotBeTrustedGivesEmptyProgressAndTheNextSaveReplacesIt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: file)
        let session = store()
        XCTAssertEqual(session.progress, GrammarProgress())
        try Data(repeating: 0x20, count: GrammarProgress.maxBytes + 100).write(to: file)
        XCTAssertEqual(store().progress, GrammarProgress(), "over the cap")
        session.opened(time)
        XCTAssertEqual(store().progress[time.id].opened, 1_800_000_000)
    }

    func testWithNoRulesNothingIsWrittenAndTheSavedFileStays() throws {
        let real = store()
        real.opened(time)
        let saved = try Data(contentsOf: file)
        let none = store(GrammarRules(categories: [], rules: []))
        none.update { progress, _ in progress.opened("time-prepositions", at: self.moment) }
        XCTAssertEqual(try Data(contentsOf: file), saved, "the learner's progress is not overwritten with nothing")
        XCTAssertTrue(none.hasUnsavedChanges)
        XCTAssertFalse(none.save())
    }

    func testAFailedSaveIsTriedAgainByFlush() throws {
        // A file stands where the folder should be: the first saves cannot be written.
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory)
        let session = store()
        session.opened(time)
        XCTAssertTrue(session.hasUnsavedChanges)
        session.flush()
        XCTAssertTrue(session.hasUnsavedChanges, "still failing")
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session.flush()
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(store().progress[time.id].opened, 1_800_000_000, "what the failed save left behind reached the file")
        session.flush()
        XCTAssertFalse(session.hasUnsavedChanges, "a flush with nothing to save writes nothing")
    }
}

import Foundation

/// `tips.json`, the learner's Grammar progress, in the app's own folder under its plain name (SPEC.md, Grammar rules
/// data, Progress). The file is the learner's own but may come from a restored backup or a damaged disk, so it is
/// read bounded (at most `maxBytes + 1` bytes, never a whole large file into memory) and written atomically, encrypted
/// by Data Protection until the device is first unlocked after a restart. Nothing about it leaves the device.
public struct GrammarProgressFile: Sendable {
    public static let name = "tips.json"
    /// What a write asks of the file system: atomic (never a half-written file) and Data Protection.
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    /// The most that is ever read: one byte over the cap, so a file over it is seen to be over it.
    static let maxRead = GrammarProgress.maxBytes + 1

    private let url: URL?

    /// `name` must be a plain name (`StorageNames.isSafe`): anything else reads and writes nothing, so a name read from
    /// elsewhere can't reach outside the folder.
    public init(directory: URL, name: String = GrammarProgressFile.name) {
        url = StorageNames.isSafe(name) ? directory.appendingPathComponent(name) : nil
        if url != nil { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    /// The saved bytes, at most `maxBytes + 1` of them; nil when there is no file or it cannot be read.
    public func read() -> Data? {
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: Self.maxRead)
    }

    /// Writes the bytes whole or not at all. Empty data (which would replace the file with nothing) and data the
    /// reader would refuse (over `maxBytes`) are never written. Returns whether the file was written.
    @discardableResult
    public func write(_ data: Data) -> Bool {
        guard let url, !data.isEmpty, data.count <= GrammarProgress.maxBytes else { return false }
        do {
            try data.write(to: url, options: Self.writeOptions)
            return true
        } catch {
            return false
        }
    }
}

/// The Grammar progress and its saving (SPEC.md S20-S22): it is read once when the store is made and saved at once
/// after each change (an item shown, an answer, a skip, a rule page opened), and again by `flush()` (the app calls it
/// when it leaves the foreground) when a save did not go through. Not thread-safe: use it from one actor (the main
/// one). The bundled rules decide which saved entries are known; when they did not load nothing is written, so the
/// saved file stays as it is (`GrammarProgress.encoded(for:)`).
public final class GrammarStore {
    public let grammar: GrammarRules
    public private(set) var progress: GrammarProgress
    /// A change has not reached the file yet (the disk was full or unavailable): `flush()` tries again.
    public private(set) var hasUnsavedChanges = false

    private let file: GrammarProgressFile
    private let clock: () -> Date
    private let zone: TimeZone

    /// Reads the saved progress (empty when there is none or it cannot be trusted).
    public init(
        grammar: GrammarRules = .shared, directory: URL, clock: @escaping () -> Date = Date.init,
        zone: TimeZone = .autoupdatingCurrent
    ) {
        self.grammar = grammar
        self.clock = clock
        self.zone = zone
        file = GrammarProgressFile(directory: directory)
        progress = file.read().map { GrammarProgress.decode($0, known: grammar.knownItems, now: clock(), in: zone) } ?? GrammarProgress()
    }

    /// The Grammar day number now (a day starts at 04:00 in the device's time zone).
    public var today: Int { GrammarDay.number(of: clock(), in: zone) }

    // MARK: Changes (each is saved at once)

    /// The rule page appeared (an opening, S20): the rule moves to the front of "Recent".
    public func opened(_ rule: GrammarRule) {
        change { $0.opened(rule.id, at: clock()) }
    }

    /// An item is shown, before any answer: `seen` + 1 (an app closed in the middle of an item has already counted it).
    public func shown(_ rule: GrammarRule, item: PracticeItem) {
        change { $0.shown(rule, item: item.id) }
    }

    /// The answer to the pretest. Returns whether it was recorded (it is offered once, S22).
    @discardableResult
    public func answeredPretest(_ rule: GrammarRule, right: Bool) -> Bool {
        var recorded = false
        let day = today
        change { recorded = GrammarPretest.record(rule, right: right, day: day, in: &$0) }
        return recorded
    }

    /// "Skip" on the pretest.
    public func skippedPretest(_ rule: GrammarRule) {
        change { $0.skippedPretest(rule.id) }
    }

    /// An answer in Try it or Practice ("Not sure" is `right: false`), on the day of the moment it is given.
    public func answeredPractice(_ rule: GrammarRule, item: PracticeItem, right: Bool) {
        let day = today
        change { $0.answered(rule, item: item.id, right: right, day: day, in: .tryIt) }
    }

    /// Any other change (Add to Review and the like, in later slices), saved the same way. `change` gets the progress and
    /// today's day number.
    public func update(_ change: (inout GrammarProgress, Int) -> Void) {
        let day = today
        self.change { change(&$0, day) }
    }

    // MARK: Saving

    /// Saves now. Returns whether the file now holds the progress (false when nothing could be written: no rules loaded,
    /// or the disk refused; the changes stay and `flush()` tries again).
    @discardableResult
    public func save() -> Bool {
        guard let data = progress.encoded(for: grammar), file.write(data) else {
            hasUnsavedChanges = true
            return false
        }
        hasUnsavedChanges = false
        return true
    }

    /// Saves what a failed save left behind; the app calls it when it goes to the background.
    public func flush() {
        if hasUnsavedChanges { save() }
    }

    private func change(_ change: (inout GrammarProgress) -> Void) {
        change(&progress)
        save()
    }
}

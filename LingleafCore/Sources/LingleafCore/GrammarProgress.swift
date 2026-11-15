import Foundation

/// What the learner has done with one practice item (SPEC.md, Grammar rules data, Progress): its Review box
/// (S25, 0 = the first), the day it is next due, how often it was shown and missed, and the day of a Try it miss.
public struct ItemProgress: Equatable, Sendable {
    public var box = 0
    /// Day number (`GrammarDay`); nil when not scheduled (not in Review, or past the last box).
    public var due: Int?
    public var seen = 0
    public var missed = 0
    /// The day of a miss in Try it, flagging the item for the rule's next Review visit; nil when not flagged.
    public var tryMiss: Int?
    /// Answered at least once in Review (box 0 alone does not say it: a wrong answer also returns to box 0).
    public var reviewed = false

    public init() {}
}

/// A right answer on a review day: two of them on different days to different items make a rule "Practiced".
public struct RightDay: Equatable, Sendable {
    public var day: Int
    public var item: String

    public init(day: Int, item: String) {
        self.day = day
        self.item = item
    }
}

/// The two items of a rule's last Review visit.
public struct ItemPair: Equatable, Sendable {
    public var first: String
    public var second: String

    public init(_ first: String, _ second: String) {
        self.first = first
        self.second = second
    }

    public func contains(_ ids: Set<String>) -> Bool { Set([first, second]) == ids }
}

/// The three states a rule shows in the list (S20): no percentage, no streak.
public enum RuleState: Equatable, Sendable {
    case new, practised, inReview
}

/// Where an answer was given: the pretest never counts toward "Practiced" (S20, S22).
public enum GrammarAnswerContext: Equatable, Sendable {
    case pretest, tryIt, review
}

/// What the learner has done with one rule.
public struct RuleProgress: Equatable, Sendable {
    /// When the rule page was last opened (Unix time, whole seconds); nil if never.
    public var opened: Int?
    /// Display only: answers given and right ones, over all the rule's items.
    public var attempts = 0
    public var rights = 0
    /// "Add to Review" was pressed and not undone.
    public var inReview = false
    /// The rule's first item (its pretest) has been answered.
    public var pretestDone = false
    /// "Skip to the rule" was pressed on the pretest; kept out of the local measurement.
    public var pretestSkipped = false
    public var lastPair: ItemPair?
    /// The pretest is offered while the rule has not been shown: neither answered nor skipped (S22). Leaving the
    /// page without doing either offers it again; after either it is never offered again for the rule.
    public var pretestOffered: Bool { !pretestDone && !pretestSkipped }
    /// At most 2 right answers on different days to different items; with 2 the rule is Practiced.
    public var rightDays: [RightDay] = []
    public var items: [String: ItemProgress] = [:]

    public init() {}
}

/// Local Grammar progress (`tips.json`, schema 2, SPEC.md Grammar rules data). Bounded when read back,
/// also from a restored backup: see `GrammarProgress.decode`. Nothing about it leaves the device.
public struct GrammarProgress: Equatable, Sendable {
    public static let maxEntries = 200
    public static let maxItems = 12
    public static let maxBytes = 512 * 1024
    public static let maxCount = 1000
    public static let maxBox = 5
    /// Rules kept in "Recent".
    public static let recentCount = 3
    /// How far ahead a due day can be: the longest Review interval plus a day.
    public static let maxDueAhead = 31
    static let schemaVersion = 2
    /// 2020-01-01 (Unix seconds): no saved `opened` can be earlier.
    static let earliest = 1_577_836_800

    public private(set) var rules: [String: RuleProgress]

    public init(rules: [String: RuleProgress] = [:]) { self.rules = rules }

    public subscript(id: String) -> RuleProgress { rules[id] ?? RuleProgress() }

    /// In Review once added; Practiced after 2 right answers on 2 different days to 2 different items; else New (S20).
    public func state(of id: String) -> RuleState {
        let progress = self[id]
        if progress.inReview { return .inReview }
        return progress.rightDays.count >= 2 ? .practised : .new
    }

    /// Opening a rule page moves it to the front of "Recent". A time before 2020-01-01 (a clock that was never
    /// set) or not a number is ignored: reading would drop it anyway, so the entry would only change on reload.
    public mutating func opened(_ id: String, at date: Date) {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= Double(Self.earliest), seconds < 1e15 else { return }
        update(id) { $0.opened = Int(seconds) }
    }

    /// An item is shown (before any answer): `seen` goes up by 1. An item the rule doesn't have is ignored.
    public mutating func shown(_ rule: GrammarRule, item: String) {
        guard rule.practice.contains(where: { $0.id == item }) else { return }
        update(rule.id) {
            guard var progress = Self.entry(&$0, item) else { return }
            progress.seen = min(progress.seen + 1, Self.maxCount)
            $0.items[item] = progress
        }
    }

    /// One answer to an item of `rule` on review day `day`. Counted on the rule (display only) and on the item
    /// (`missed`); a right answer outside the pretest may add a `rightDays` entry; a miss in Try it flags the item
    /// (`tryMiss`). The rule's first item is its pretest: only an answer given as `.pretest` sets `pretestDone`.
    public mutating func answered(_ rule: GrammarRule, item: String, right: Bool, day: Int, in context: GrammarAnswerContext) {
        guard rule.practice.contains(where: { $0.id == item }) else { return }
        update(rule.id) {
            guard var progress = Self.entry(&$0, item) else { return }
            $0.attempts = min($0.attempts + 1, Self.maxCount)
            if right { $0.rights = min($0.rights + 1, Self.maxCount) } else { progress.missed = min(progress.missed + 1, Self.maxCount) }
            if context == .pretest { $0.pretestDone = true }
            if right, context != .pretest, Self.accepts(RightDay(day: day, item: item), after: $0.rightDays) {
                $0.rightDays.append(RightDay(day: day, item: item))
            }
            if !right, context == .tryIt { progress.tryMiss = day }
            progress.seen = max(progress.seen, progress.missed)
            $0.items[item] = progress
        }
    }

    /// The first right answer is kept; a second one only on another day and for another item. Two are the most kept.
    static func accepts(_ answer: RightDay, after entries: [RightDay]) -> Bool {
        guard let first = entries.first else { return true }
        return entries.count < 2 && answer.day != first.day && answer.item != first.item
    }

    /// "Skip to the rule" on the pretest.
    public mutating func skippedPretest(_ id: String) {
        update(id) { $0.pretestSkipped = true }
    }

    /// Review's result for an item: its box (0–5), the day it is next due (nil past the last box); the item has been
    /// reviewed and its Try it flag is cleared (right or wrong, S25).
    public mutating func scheduled(_ id: String, item: String, box: Int, due: Int?) {
        update(id) {
            guard var progress = Self.entry(&$0, item) else { return }
            progress.box = min(max(box, 0), Self.maxBox)
            progress.due = due
            progress.tryMiss = nil
            progress.reviewed = true
            $0.items[item] = progress
        }
    }

    /// The items of the rule's last Review visit; nil when the visit had fewer than 2 items.
    public mutating func setLastPair(_ id: String, _ pair: ItemPair?) {
        update(id) { $0.lastPair = pair }
    }

    /// "Add to Review" (S25): every item gets box 0 and is due tomorrow (`today` + 1); counts and `reviewed` stay.
    public mutating func addToReview(_ rule: GrammarRule, today: Int) {
        update(rule.id) {
            $0.inReview = true
            $0.lastPair = nil
            for item in rule.practice {
                guard var progress = Self.entry(&$0, item.id) else { continue }
                progress.box = 0
                progress.due = today + 1
                progress.tryMiss = nil
                $0.items[item.id] = progress
            }
        }
    }

    /// "Remove from Review": boxes, due days, Try it flags and `lastPair` are cleared; `reviewed`, seen and missed stay.
    /// Returns the entry as it was, for Undo (`restore`).
    @discardableResult
    public mutating func removeFromReview(_ id: String) -> RuleProgress {
        let before = self[id]
        update(id) {
            $0.inReview = false
            $0.lastPair = nil
            for key in $0.items.keys {
                $0.items[key]?.box = 0
                $0.items[key]?.due = nil
                $0.items[key]?.tryMiss = nil
            }
        }
        return before
    }

    /// Puts a rule's entry back as it was (Undo).
    public mutating func restore(_ id: String, to entry: RuleProgress) {
        update(id) { $0 = entry }
    }

    /// The last rules opened, newest first (ties by id, so the order is stable).
    public func recent(limit: Int = recentCount) -> [String] {
        rules.compactMap { id, progress in progress.opened.map { (id, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
            .map(\.0)
    }

    /// The item's entry for a change, or nil when the rule already holds the most items and this one is new.
    private static func entry(_ rule: inout RuleProgress, _ item: String) -> ItemProgress? {
        guard rule.items[item] != nil || rule.items.count < maxItems else { return nil }
        return rule.items[item] ?? ItemProgress()
    }

    private mutating func update(_ id: String, _ change: (inout RuleProgress) -> Void) {
        var progress = rules[id] ?? RuleProgress()
        change(&progress)
        rules[id] = progress
        // Over the cap, the entries opened longest ago go first (never the one just changed).
        while rules.count > Self.maxEntries {
            let oldest = rules.filter { $0.key != id }.min { ($0.value.opened ?? 0, $0.key) < ($1.value.opened ?? 0, $1.key) }
            guard let key = oldest?.key else { break }
            rules[key] = nil
        }
    }

    // MARK: Saved form

    /// What to save, or nil when the bundled rules did not load: with no rules every saved entry would
    /// read as unknown, so saving would overwrite the learner's progress with nothing. Keep the file.
    public func encoded(for grammar: GrammarRules) -> Data? {
        grammar.isAvailable ? encoded() : nil
    }

    /// The saved bytes, or nil when they could not be made: never empty data, which would replace the file.
    func encoded() -> Data? {
        var object: [String: Any] = [:]
        for (id, progress) in rules {
            var items: [String: Any] = [:]
            for (itemID, item) in progress.items {
                var entry: [String: Any] = ["box": item.box, "seen": item.seen, "missed": item.missed, "reviewed": item.reviewed]
                if let due = item.due { entry["due"] = due }
                if let tryMiss = item.tryMiss { entry["tryMiss"] = tryMiss }
                items[itemID] = entry
            }
            var entry: [String: Any] = [
                "attempts": progress.attempts, "rights": progress.rights, "inReview": progress.inReview,
                "pretestDone": progress.pretestDone, "pretestSkipped": progress.pretestSkipped,
                "rightDays": progress.rightDays.map { ["day": $0.day, "item": $0.item] as [String: Any] }, "items": items,
            ]
            if let opened = progress.opened { entry["opened"] = opened }
            if let pair = progress.lastPair { entry["lastPair"] = [pair.first, pair.second] }
            object[id] = entry
        }
        let root: [String: Any] = ["schema": Self.schemaVersion, "rules": object]
        return try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

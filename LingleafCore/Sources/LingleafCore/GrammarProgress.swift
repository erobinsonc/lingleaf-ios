import Foundation

/// What the learner has done with one practice item: its Review box (S25, 0 = not in a box yet), when it is
/// next due, and how often it was seen and missed.
public struct ItemProgress: Equatable, Sendable {
    public var box = 0
    /// Seconds since 1970; nil when not scheduled.
    public var due: Double?
    public var seen = 0
    public var missed = 0

    public init() {}
}

/// The three states a rule shows in the list (S20): no percentage, no streak.
public enum RuleState: Equatable, Sendable {
    case new, practised, inReview
}

/// What the learner has done with one rule.
public struct RuleProgress: Equatable, Sendable {
    /// When the rule page was last opened (seconds since 1970); nil if never.
    public var lastOpened: Double?
    /// Display only: answers given and right ones, over all the rule's items.
    public var attempts = 0
    public var rights = 0
    /// The rule's first item (its pretest) has been answered.
    public var pretestDone = false
    /// "Add to Review" was pressed and not undone.
    public var inReview = false
    public var items: [String: ItemProgress] = [:]

    public init() {}
}

/// Local Grammar progress (`tips.json`, schema 2, SPEC.md Grammar rules data). Bounded when read back,
/// also from a restored backup: unknown rules and items are dropped, counts brought into range, a date that
/// can't be right becomes none. Nothing about it leaves the device.
public struct GrammarProgress: Equatable, Sendable {
    public static let maxEntries = 200
    public static let maxItems = 12
    public static let maxBytes = 384 * 1024
    public static let maxCount = 1000
    public static let maxBox = 5
    /// Rules kept in "Recent".
    public static let recentCount = 3
    static let schemaVersion = 2
    /// 2020-01-01: no saved date can be earlier.
    static let earliest = 1_577_836_800.0

    public private(set) var rules: [String: RuleProgress]

    public init(rules: [String: RuleProgress] = [:]) { self.rules = rules }

    public subscript(id: String) -> RuleProgress { rules[id] ?? RuleProgress() }

    /// New until an item was answered, In Review once added (S20).
    public func state(of id: String) -> RuleState {
        let progress = self[id]
        if progress.inReview { return .inReview }
        return progress.attempts > 0 ? .practised : .new
    }

    /// Opening a rule page moves it to the front of "Recent".
    public mutating func opened(_ id: String, at date: Date) {
        update(id) { $0.lastOpened = date.timeIntervalSince1970 }
    }

    /// One answer to an item of `rule`: counted on the rule and on the item. The rule's first item is its
    /// pretest, so `pretestDone` is set only by answering that one. An item the rule doesn't have is ignored.
    public mutating func answered(_ rule: GrammarRule, item: String, right: Bool) {
        guard rule.practice.contains(where: { $0.id == item }) else { return }
        let isFirst = rule.practice.first?.id == item
        update(rule.id) {
            $0.attempts = min($0.attempts + 1, Self.maxCount)
            if right { $0.rights = min($0.rights + 1, Self.maxCount) }
            if isFirst { $0.pretestDone = true }
            var progress = $0.items[item] ?? ItemProgress()
            progress.seen = min(progress.seen + 1, Self.maxCount)
            if !right { progress.missed = min(progress.missed + 1, Self.maxCount) }
            $0.items[item] = progress
        }
    }

    /// Review's result for an item: its box (0–5) and when it is next due.
    public mutating func scheduled(_ id: String, item: String, box: Int, due: Date?) {
        update(id) {
            guard $0.items[item] != nil || $0.items.count < Self.maxItems else { return }
            var progress = $0.items[item] ?? ItemProgress()
            progress.box = min(max(box, 0), Self.maxBox)
            progress.due = due?.timeIntervalSince1970
            $0.items[item] = progress
        }
    }

    public mutating func setInReview(_ id: String, _ value: Bool) {
        update(id) { $0.inReview = value }
    }

    /// The last rules opened, newest first (ties by id, so the order is stable).
    public func recent(limit: Int = recentCount) -> [String] {
        rules.compactMap { id, progress in progress.lastOpened.map { (id, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
            .map(\.0)
    }

    private mutating func update(_ id: String, _ change: (inout RuleProgress) -> Void) {
        var progress = rules[id] ?? RuleProgress()
        change(&progress)
        rules[id] = progress
        // Over the cap, the entries opened longest ago go first (never the one just changed).
        while rules.count > Self.maxEntries {
            let oldest = rules.filter { $0.key != id }.min { ($0.value.lastOpened ?? 0, $0.key) < ($1.value.lastOpened ?? 0, $1.key) }
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

    func encoded() -> Data {
        var object: [String: Any] = [:]
        for (id, progress) in rules {
            var items: [String: Any] = [:]
            for (itemID, item) in progress.items {
                var entry: [String: Any] = ["box": item.box, "seen": item.seen, "missed": item.missed]
                if let due = item.due { entry["due"] = due }
                items[itemID] = entry
            }
            var entry: [String: Any] = [
                "attempts": progress.attempts, "rights": progress.rights,
                "pretestDone": progress.pretestDone, "inReview": progress.inReview, "items": items,
            ]
            if let opened = progress.lastOpened { entry["lastOpened"] = opened }
            object[id] = entry
        }
        let root: [String: Any] = ["schema": Self.schemaVersion, "rules": object]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    /// Reads saved progress. Anything wrong with the file as a whole (too large, too deep, not an object,
    /// another schema) gives empty progress; a wrong entry is dropped or brought into range. `known` maps
    /// the rule ids of the bundled rules to their item ids (`GrammarRules.knownItems`).
    public static func decode(_ data: Data, known: [String: Set<String>], now: Date = Date()) -> GrammarProgress {
        guard data.count <= maxBytes, JSONGuard.isShallow(data, maxDepth: 8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["schema"] as? Int == schemaVersion,
              let entries = root["rules"] as? [String: Any] else { return GrammarProgress() }
        var result: [String: RuleProgress] = [:]
        for (id, value) in entries.sorted(by: { $0.key < $1.key }) where result.count < maxEntries {
            guard let itemIDs = known[id], let entry = value as? [String: Any] else { continue }
            result[id] = rule(from: entry, itemIDs: itemIDs, now: now)
        }
        return GrammarProgress(rules: result)
    }

    private static func rule(from entry: [String: Any], itemIDs: Set<String>, now: Date) -> RuleProgress {
        var progress = RuleProgress()
        progress.attempts = count(entry["attempts"])
        progress.rights = min(count(entry["rights"]), progress.attempts)
        progress.pretestDone = entry["pretestDone"] as? Bool ?? false
        progress.inReview = entry["inReview"] as? Bool ?? false
        // A last-opened date from the future or before 2020 can't be right.
        progress.lastOpened = date(entry["lastOpened"], latest: now.timeIntervalSince1970 + 86_400)
        let items = entry["items"] as? [String: Any] ?? [:]
        for (itemID, value) in items.sorted(by: { $0.key < $1.key }) where progress.items.count < maxItems {
            guard itemIDs.contains(itemID), let raw = value as? [String: Any] else { continue }
            var item = ItemProgress()
            item.box = min(count(raw["box"]), maxBox)
            item.seen = count(raw["seen"])
            item.missed = min(count(raw["missed"]), item.seen)
            // A due date is ahead of now, but not by more than a year.
            item.due = date(raw["due"], latest: now.timeIntervalSince1970 + 366 * 86_400)
            progress.items[itemID] = item
        }
        return progress
    }

    private static func date(_ value: Any?, latest: Double) -> Double? {
        guard let seconds = value as? Double, seconds >= earliest, seconds <= latest else { return nil }
        return seconds
    }

    private static func count(_ value: Any?) -> Int {
        guard let number = value as? Int else { return 0 }
        return min(max(number, 0), maxCount)
    }
}

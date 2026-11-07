import Foundation

/// What the learner has done with one rule.
public struct RuleProgress: Equatable, Sendable {
    /// When the rule page was last opened (seconds since 1970); nil if never.
    public var lastOpened: Double?
    public var attempts = 0
    public var rights = 0
    public var pretestDone = false
    /// "Add to Review" was pressed and not undone.
    public var inReview = false

    public init() {}
}

/// Local Grammar progress (`tips.json`, SPEC.md Grammar rules data). Bounded when read back, also
/// from a restored backup: unknown rules are dropped, counts brought into range, a date that
/// can't be read becomes none. Nothing about it leaves the device.
public struct GrammarProgress: Equatable, Sendable {
    public static let maxEntries = 400
    public static let maxBytes = 64 * 1024
    public static let maxCount = 1000
    /// Rules kept in "Recent".
    public static let recentCount = 3
    static let schemaVersion = 1

    public private(set) var rules: [String: RuleProgress]

    public init(rules: [String: RuleProgress] = [:]) { self.rules = rules }

    public subscript(id: String) -> RuleProgress { rules[id] ?? RuleProgress() }

    /// Opening a rule page moves it to the front of "Recent".
    public mutating func opened(_ id: String, at date: Date) {
        update(id) { $0.lastOpened = date.timeIntervalSince1970 }
    }

    /// One answer: counts every attempt and every right one; the first answer of a rule is its pretest.
    public mutating func answered(_ id: String, right: Bool) {
        update(id) {
            $0.attempts = min($0.attempts + 1, Self.maxCount)
            if right { $0.rights = min($0.rights + 1, Self.maxCount) }
            $0.pretestDone = true
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
            var entry: [String: Any] = [
                "attempts": progress.attempts, "rights": progress.rights,
                "pretestDone": progress.pretestDone, "inReview": progress.inReview,
            ]
            if let opened = progress.lastOpened { entry["lastOpened"] = opened }
            object[id] = entry
        }
        let root: [String: Any] = ["schema": Self.schemaVersion, "rules": object]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    /// Reads saved progress. Anything wrong with the file as a whole (too large, too deep, not an
    /// object, another schema) gives empty progress; a wrong entry is dropped or brought into range.
    /// `known` are the rule ids of the bundled rules.
    public static func decode(_ data: Data, known: Set<String>, now: Date = Date()) -> GrammarProgress {
        guard data.count <= maxBytes, JSONGuard.isShallow(data, maxDepth: 8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["schema"] as? Int == schemaVersion,
              let entries = root["rules"] as? [String: Any] else { return GrammarProgress() }
        var result: [String: RuleProgress] = [:]
        for (id, value) in entries.sorted(by: { $0.key < $1.key }) where known.contains(id) && result.count < maxEntries {
            guard let entry = value as? [String: Any] else { continue }
            var progress = RuleProgress()
            progress.attempts = count(entry["attempts"])
            progress.rights = min(count(entry["rights"]), progress.attempts)
            progress.pretestDone = entry["pretestDone"] as? Bool ?? false
            progress.inReview = entry["inReview"] as? Bool ?? false
            // A date from the future or before 2020 can't be right.
            if let opened = entry["lastOpened"] as? Double, opened >= 1_577_836_800, opened <= now.timeIntervalSince1970 + 86_400 {
                progress.lastOpened = opened
            }
            result[id] = progress
        }
        return GrammarProgress(rules: result)
    }

    private static func count(_ value: Any?) -> Int {
        guard let number = value as? Int else { return 0 }
        return min(max(number, 0), maxCount)
    }
}

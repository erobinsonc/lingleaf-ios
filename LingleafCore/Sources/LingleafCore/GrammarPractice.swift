import Foundation

/// CEFR levels in order, for "not above" and "easiest first".
enum GrammarLevel {
    private static let order = ["A1", "A2", "B1", "B2", "C1", "C2"]

    /// 0 for A1 up to 5 for C2; a level that is not one is above all of them.
    static func rank(_ level: String) -> Int { order.firstIndex(of: level) ?? order.count }
}

/// Try it / Practice rounds (SPEC.md S22, Grammar rules data, "Draw"): which items a round holds, how many, and
/// what the button says. Nothing here touches progress; the screens record shown items and answers.
public enum GrammarPractice {
    /// Items in a round, at most.
    public static let roundMax = 3
    /// Practice items answered per rule and day, at most.
    public static let dailyMax = 6

    /// What the rule page's button says: "Try it" while every item of the rule except the first has `seen` 0,
    /// else "Practice" (a pretest shown twice does not change it).
    public enum Label: Equatable, Sendable { case tryIt, practice }

    /// The size of a round with `answeredToday` items already answered today: min(3, 6 - n); none at 6 or more.
    /// `answeredToday` is `GrammarProgress.answeredToday`, which is never negative or above 6.
    public static func roundSize(answeredToday: Int) -> Int {
        max(0, min(roundMax, dailyMax - max(answeredToday, 0)))
    }

    public static func label(for rule: GrammarRule, progress: RuleProgress) -> Label {
        let untouched = rule.practice.dropFirst().allSatisfy { (progress.items[$0.id]?.seen ?? 0) == 0 }
        return untouched ? .tryIt : .practice
    }

    /// The round, by `seen` ascending, then `missed` descending, then file position; the first `count`. Candidates:
    /// the rule's items that are not in `excluding`, whose level is not above the rule's and, unless
    /// `spanishEligible` (the translation language or the interface language is Spanish), that have no
    /// `textLang: "es"`. Fewer candidates make a short round and an item is never twice in a round. `excluding` is
    /// view state (the pretest item once answered, or the item left on the page after "Skip", once answered, on
    /// this opening of the rule page); it is never stored.
    public static func draw(
        rule: GrammarRule, progress: RuleProgress, spanishEligible: Bool, excluding: Set<String>, count: Int
    ) -> [PracticeItem] {
        guard count > 0 else { return [] }
        let ceiling = GrammarLevel.rank(rule.level)
        let candidates = rule.practice.enumerated().filter { _, item in
            !excluding.contains(item.id) && GrammarLevel.rank(item.level) <= ceiling && (spanishEligible || item.textLang != "es")
        }
        let ordered = candidates.sorted { lhs, rhs in
            let left = progress.items[lhs.element.id] ?? ItemProgress()
            let right = progress.items[rhs.element.id] ?? ItemProgress()
            if left.seen != right.seen { return left.seen < right.seen }
            if left.missed != right.missed { return left.missed > right.missed }
            return lhs.offset < rhs.offset
        }
        return ordered.prefix(count).map(\.element)
    }
}

/// The result of a rule's pretest (SPEC.md S22): read from the item's `seen` and `missed` only, right after the
/// answer, before any practice. The counters are cumulative, so they cannot give a first try back later.
public enum GrammarPretest {
    /// The pretest item: the rule's first.
    public static func item(of rule: GrammarRule) -> PracticeItem? { rule.practice.first }

    /// Records the answer to the pretest and nothing else (`GrammarProgress.answered`, `.pretest`): the rule's
    /// `attempts` +1, `rights` +1 when right, the item's `missed` +1 when wrong, `pretestDone`; never a right day,
    /// `tryMiss`, `itemsAnswered` or a Review box. The item's `seen` +1 was counted when it was shown. Nothing is
    /// recorded when the pretest is not offered (already answered or skipped, S22) or the rule has no items.
    /// Returns whether it was recorded.
    @discardableResult
    public static func record(_ rule: GrammarRule, right: Bool, day: Int, in progress: inout GrammarProgress) -> Bool {
        guard progress[rule.id].pretestOffered, let item = item(of: rule) else { return false }
        progress.answered(rule, item: item.id, right: right, day: day, in: .pretest)
        return true
    }

    public struct Result: Equatable, Sendable {
        public let item: String
        public let seen: Int
        public let missed: Int
        /// Right when the item was never missed: before the pretest nothing could have missed it.
        public var right: Bool { missed == 0 }
    }

    /// The pretest's result: only for a rule whose pretest was answered (`pretestDone`) and not skipped, and only
    /// meaningful right after it. A skipped or unanswered pretest is left out of the measurement (nil).
    public static func result(_ rule: GrammarRule, progress: RuleProgress) -> Result? {
        guard progress.pretestDone, !progress.pretestSkipped, let item = item(of: rule) else { return nil }
        let saved = progress.items[item.id] ?? ItemProgress()
        return Result(item: item.id, seen: saved.seen, missed: saved.missed)
    }
}

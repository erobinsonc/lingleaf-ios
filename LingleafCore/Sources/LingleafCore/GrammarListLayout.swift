import Foundation

/// How the Grammar list is laid out (SPEC.md S20) and which rules "Recent" shows.
public enum GrammarListLayout: Equatable, Sendable {
    /// 0 to 25 rules: the categories as sections, each with its rules sorted by level.
    case a
    /// 26 rules or more: one row per category with its rule count; a category opens a page with its rules as in A.
    case b

    /// Most rules the list shows directly.
    public static let maxDirect = 25

    public static func layout(ruleCount: Int) -> GrammarListLayout { ruleCount <= maxDirect ? .a : .b }

    public struct Section: Equatable, Sendable {
        public let category: GrammarCategory
        public let rules: [GrammarRule]
    }

    /// The categories in file order, each with its rules by level (A1, A2, B1), file order inside a level. A
    /// category without rules is left out.
    public static func sections(in grammar: GrammarRules) -> [Section] {
        grammar.categories.compactMap { category in
            let rules = sorted(grammar.rules(in: category.id))
            return rules.isEmpty ? nil : Section(category: category, rules: rules)
        }
    }

    /// Rules by level, stable: file order inside a level.
    public static func sorted(_ rules: [GrammarRule]) -> [GrammarRule] {
        rules.enumerated().sorted { lhs, rhs in
            let left = GrammarLevel.rank(lhs.element.level), right = GrammarLevel.rank(rhs.element.level)
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// "Recent" (SPEC.md S20): the 3 rules with the greatest `opened`, the greatest first, equal values in file order.
/// It shows only once 3 rules have been opened.
public enum GrammarRecent {
    public static func rules(
        progress: GrammarProgress, in grammar: GrammarRules, limit: Int = GrammarProgress.recentCount
    ) -> [GrammarRule] {
        let opened = grammar.rules.enumerated().compactMap { position, rule in
            progress[rule.id].opened.map { (position: position, rule: rule, opened: $0) }
        }
        guard opened.count >= GrammarProgress.recentCount else { return [] }
        let ordered = opened.sorted { $0.opened != $1.opened ? $0.opened > $1.opened : $0.position < $1.position }
        return ordered.prefix(max(limit, 0)).map(\.rule)
    }
}

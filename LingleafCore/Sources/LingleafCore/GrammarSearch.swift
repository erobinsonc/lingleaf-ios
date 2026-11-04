import Foundation

/// Search in the Grammar list (SPEC.md S20): ignores case and accents, looks in the title, rule lines,
/// examples and aliases of both languages, and needs every word of the query to start a word there.
public enum GrammarSearch {
    /// Longest query looked at, in characters.
    static let maxQuery = 100

    /// The words of `text`: lower-case, without accents, split on anything that is not a letter or digit.
    public static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Every word a rule can be found by.
    static func searchWords(_ rule: GrammarRule) -> Set<String> {
        var texts = [rule.title.en, rule.title.es] + rule.lines.en + rule.lines.es + rule.aliases
        for example in rule.examples { texts += [example.en, example.es] }
        return Set(texts.flatMap(words))
    }

    public static func matches(_ rule: GrammarRule, query: String) -> Bool {
        let wanted = words(String(query.prefix(maxQuery)))
        guard !wanted.isEmpty else { return true }
        let have = searchWords(rule)
        return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
    }

    /// The rules that match, in their order; an empty query matches all.
    public static func search(_ query: String, in rules: [GrammarRule]) -> [GrammarRule] {
        rules.filter { matches($0, query: query) }
    }
}

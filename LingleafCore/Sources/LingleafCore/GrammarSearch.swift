import Foundation

/// Search in the Grammar list (SPEC.md S20): ignores case and accents, looks in the title, rule lines,
/// examples and aliases of both languages, and needs every word of the query to start a word there.
public enum GrammarSearch {
    /// Longest query looked at, in code points.
    static let maxQuery = 100

    /// The words of `text` (SPEC.md S20, Search): lower-cased with the locale-independent `lowercased()`, accents
    /// stripped (NFD, no combining marks), split on every character that is not a letter (Unicode category L).
    public static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                current.append(scalar)
            default:
                if !current.isEmpty { words.append(String(current)); current = String.UnicodeScalarView() }
            }
        }
        if !current.isEmpty { words.append(String(current)) }
        return words
    }

    /// Every word a rule can be found by.
    static func searchWords(_ rule: GrammarRule) -> Set<String> {
        var texts = [rule.title.en, rule.title.es] + rule.lines.en + rule.lines.es + rule.aliases
        for example in rule.examples { texts += [example.en, example.es] }
        return Set(texts.flatMap(words))
    }

    public static func matches(_ rule: GrammarRule, query: String) -> Bool {
        let wanted = words(String(String.UnicodeScalarView(query.unicodeScalars.prefix(maxQuery))))
        guard !wanted.isEmpty else { return true }
        let have = searchWords(rule)
        return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
    }

    /// The rules that match, in their order; an empty query matches all.
    public static func search(_ query: String, in rules: [GrammarRule]) -> [GrammarRule] {
        rules.filter { matches($0, query: query) }
    }
}

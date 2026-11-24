import Foundation

/// The irregular-verb list order (SPEC.md S24, "Verb search"): the table's pattern groups in their order, most used
/// first inside a group (`freq`, absent counts as 0), ties by `base` in code-point order.
public enum IrregularVerbOrder {
    public struct Section: Equatable, Sendable {
        public let group: VerbGroup
        public let verbs: [IrregularVerb]
    }

    public static func ordered(_ table: IrregularVerbs) -> [IrregularVerb] {
        sections(table).flatMap(\.verbs)
    }

    /// One section per group that has verbs: the group's title and example are the section header.
    public static func sections(_ table: IrregularVerbs) -> [Section] {
        table.groups.compactMap { group in
            let verbs = table.verbs.filter { $0.group == group.id }.sorted(by: before)
            return verbs.isEmpty ? nil : Section(group: group, verbs: verbs)
        }
    }

    /// Inside one group.
    static func before(_ lhs: IrregularVerb, _ rhs: IrregularVerb) -> Bool {
        let left = lhs.freq ?? 0, right = rhs.freq ?? 0
        return left != right ? left > right : lhs.base.unicodeScalars.lexicographicallyPrecedes(rhs.base.unicodeScalars)
    }
}

/// Search in the irregular-verb list (SPEC.md S24, Grammar rules data, "Verb search"): case, accent and letter-form
/// blind as `GrammarSearch`, by any form or by its Spanish meaning.
public enum IrregularVerbSearch {
    /// Longest query looked at, in code points.
    static let maxQuery = GrammarSearch.maxQuery

    /// A verb's form words: its base, every past, participle, -ing and -s form and those of its homonym.
    static func formWords(_ verb: IrregularVerb) -> Set<String> {
        var forms = [verb.base, verb.ing, verb.s] + verb.past + verb.participle
        if let homonym = verb.homonym { forms += [homonym.ing, homonym.s] + homonym.past + homonym.participle }
        return Set(forms.flatMap(GrammarSearch.words))
    }

    /// The comma-separated parts of the Spanish meanings of the verb and of its homonym, each as its words joined
    /// by single spaces ("encontrarse (un lugar)" is "encontrarse un lugar"). `nounEs` does not count.
    static func meaningEntries(_ verb: IrregularVerb) -> [[String]] {
        (verb.es + (verb.homonym?.es ?? [])).flatMap { $0.split(separator: ",", omittingEmptySubsequences: true) }
            .map { GrammarSearch.words(String($0)) }.filter { !$0.isEmpty }
    }

    /// The verb's rank for the query words, or nil when a word matches nothing. A word is 0 when equal to a form
    /// word, 1 when a prefix of one, 3 when a prefix of (or equal to) a meaning word; the rank is the worst of its
    /// words, except that when the whole folded query equals one whole meaning entry the rank is 2 (only when the
    /// words alone gave 3; it never worsens a 0 or 1).
    static func rank(_ verb: IrregularVerb, words query: [String]) -> Int? {
        let forms = formWords(verb)
        let entries = meaningEntries(verb)
        let meaningWords = Set(entries.joined())
        var worst = 0
        for word in query {
            if forms.contains(word) {
                continue
            } else if forms.contains(where: { $0.hasPrefix(word) }) {
                worst = max(worst, 1)
            } else if meaningWords.contains(where: { $0.hasPrefix(word) }) {
                worst = max(worst, 3)
            } else {
                return nil
            }
        }
        return worst == 3 && entries.contains(query) ? 2 : worst
    }

    /// The verbs that match, by rank and then the list order; no match for an empty query.
    public static func search(_ query: String, in table: IrregularVerbs) -> [IrregularVerb] {
        let words = GrammarSearch.words(String(String.UnicodeScalarView(query.unicodeScalars.prefix(maxQuery))))
        guard !words.isEmpty else { return [] }
        let ranked = IrregularVerbOrder.ordered(table).enumerated().compactMap { position, verb in
            rank(verb, words: words).map { (position: position, rank: $0, verb: verb) }
        }
        return ranked.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.position < $1.position }.map(\.verb)
    }
}

/// The two lines of a verb row (SPEC S24): every form of each slot, and the Spanish meanings.
public enum IrregularVerbLine {
    /// "take · took · taken"; a slot with two forms shows both: "learn · learned / learnt · learned / learnt".
    public static func forms(_ verb: IrregularVerb) -> String {
        [VerbFormSlot.base, .past, .participle].map { GrammarSpeech.forms(of: verb, slot: $0).joined(separator: " / ") }.joined(separator: " · ")
    }

    /// The table's Spanish meanings, each entry as the table has it ("tomar, llevar"), the entries apart by "; ".
    public static func meanings(_ verb: IrregularVerb) -> String { verb.es.joined(separator: "; ") }

    /// The hint under the past participle: "have taken".
    public static func participleHint(_ verb: IrregularVerb) -> String { "have " + (verb.participle.first ?? verb.base) }
}

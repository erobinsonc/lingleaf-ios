import Foundation

/// A helper verb ("did" in "did not go") or a modal verb ("will" in "will go") found in a
/// sentence. Alone these words mean little or something misleading ("did" → "hizo"), so the
/// word card shows what they do in the sentence and translates the verb group instead.
/// Same rules as `FunctionWords` in lingleaf-android.
public struct FunctionWord: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// do / does / did used to make a negative or a question.
        case helper
        /// can, could, will, would, shall, should, must, may, might.
        case modal
    }

    /// What the word does in this sentence; the card explains it with one short note.
    public enum Use: Equatable, Sendable {
        case pastNegative, presentNegative, pastQuestion, presentQuestion
        /// The modal's base form ("will" for "won't").
        case modal(String)
    }

    public let kind: Kind
    /// The base form: "do" for "did" and "didn't", "will" for "won't".
    public let base: String
    public let use: Use
    /// The verb group in the sentence ("did not go", "Can you help"); nil when it can't be
    /// told reliably (a question whose subject is not a pronoun).
    public let chunk: WordRange?
}

public enum FunctionWords {
    private static let doForms: [String: (base: String, past: Bool)] = [
        "do": ("do", false), "does": ("do", false), "did": ("do", true),
        "don't": ("do", false), "doesn't": ("do", false), "didn't": ("do", true),
    ]

    private static let modals: [String: String] = [
        "can": "can", "cannot": "can", "can't": "can",
        "could": "could", "couldn't": "could",
        "will": "will", "won't": "will",
        "would": "would", "wouldn't": "would",
        "shall": "shall", "shan't": "shall",
        "should": "should", "shouldn't": "should",
        "must": "must", "mustn't": "must",
        "may": "may",
        "might": "might", "mightn't": "might",
    ]

    private static let pronouns: Set<String> = ["i", "you", "he", "she", "it", "we", "they"]
    private static let questionWords: Set<String> = ["what", "where", "when", "why", "how", "who", "whom", "whose", "which"]
    /// Before a modal these make it a noun: "a can of beans", "his will", "free will".
    private static let determiners: Set<String> = [
        "a", "an", "the", "my", "your", "his", "her", "its", "our", "their", "free", "good", "ill",
    ]

    /// What the word at `range` of `sentence` does, or nil for an ordinary word
    /// (including "do" as a main verb: "I did my homework").
    public static func analyze(_ sentence: String, _ range: WordRange) -> FunctionWord? {
        let words = TextTools.wordRanges(sentence)
        guard let index = words.firstIndex(of: range) else { return nil }
        let surface = TextTools.substring(sentence, range)
        let tokens = words.map { TextTools.normalize(TextTools.substring(sentence, $0)) }
        let token = tokens[index]
        let next = index + 1 < tokens.count ? tokens[index + 1] : nil
        let isQuestion = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " \"”’)]")).hasSuffix("?")

        /// The verb group: the word, "not", a pronoun subject in a question
        /// ("Can you help", "didn't you come"), then the next word.
        let groupEnd: Int? = {
            var last = index
            if next == "not" { last += 1 }
            if isQuestion, last + 1 < tokens.count, pronouns.contains(tokens[last + 1]) { last += 1 }
            last += 1
            return last < words.count ? last : nil
        }()
        let group = groupEnd.map { WordRange(range.start, words[$0].end) }

        if let form = doForms[token] {
            if token.hasSuffix("n't") || next == "not" {
                return FunctionWord(kind: .helper, base: form.base, use: form.past ? .pastNegative : .presentNegative, chunk: group)
            }
            let opensQuestion = index == 0 || questionWords.contains(tokens[index - 1])
            guard isQuestion, opensQuestion else { return nil }
            let withPronoun = next.map { pronouns.contains($0) } ?? false
            return FunctionWord(
                kind: .helper, base: form.base,
                use: form.past ? .pastQuestion : .presentQuestion,
                chunk: withPronoun ? group : nil
            )
        }

        guard let base = modals[token] else { return nil }
        if index > 0, determiners.contains(tokens[index - 1]) { return nil }
        // "May" and "Will" capitalized mid-sentence are a month and a name.
        if index > 0, token == "may" || token == "will", surface.first?.isUppercase == true { return nil }
        return FunctionWord(kind: .modal, base: base, use: .modal(base), chunk: group)
    }
}

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
        /// "Don't touch that.": telling someone not to do something.
        case prohibition
        /// "You went, didn't you?": asks the listener to agree, like "right?".
        case questionTag
        /// The modal's base form ("will" for "won't").
        case modal(String)
    }

    public let kind: Kind
    /// The base form: "do" for "did" and "didn't", "will" for "won't".
    public let base: String
    public let use: Use
    /// The verb group in the sentence ("did not go", "should have known", "Can you help");
    /// nil when it can't be told reliably (a question whose subject is not a pronoun, or a
    /// sentence that ends right after the word: "Yes, I can.").
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
    /// Skipped on the way to the main verb: "should have known", "will never be able".
    private static let inGroup: Set<String> = [
        "have", "be", "been", "being", "never", "always", "ever", "really", "just", "also",
        "still", "even", "only", "already", "probably", "certainly", "surely", "often",
    ]
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
        /// ("Can you help", "didn't you come"), have/be and adverbs ("should have known"),
        /// then the main verb; up to the sentence's end if it comes first.
        let groupEnd: Int? = {
            var last = index
            if next == "not" { last += 1 }
            if isQuestion, last + 1 < tokens.count, pronouns.contains(tokens[last + 1]) { last += 1 }
            var skipped = 0
            while last + 1 < tokens.count, inGroup.contains(tokens[last + 1]), skipped < 4 {
                last += 1
                skipped += 1
            }
            if last + 1 < tokens.count { return last + 1 }
            return last > index ? last : nil
        }()
        let group = groupEnd.map { WordRange(range.start, words[$0].end) }

        // A question tag: ", didn't you?" / ", can't she?" closing the sentence.
        let before = index > 0 ? TextTools.substring(sentence, WordRange(words[index - 1].end, range.start)) : ""
        if isQuestion, index > 0, before.contains(","), index == tokens.count - 2, pronouns.contains(tokens[index + 1]) {
            if let form = doForms[token] { return FunctionWord(kind: .helper, base: form.base, use: .questionTag, chunk: nil) }
            if let base = modals[token] { return FunctionWord(kind: .modal, base: base, use: .questionTag, chunk: nil) }
        }

        if let form = doForms[token] {
            if token.hasSuffix("n't") || next == "not" {
                // "Don't touch that." / "Do not touch": first word, no subject → a prohibition.
                if index == 0, !form.past, token != "doesn't", token != "does", !isQuestion {
                    return FunctionWord(kind: .helper, base: form.base, use: .prohibition, chunk: group)
                }
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

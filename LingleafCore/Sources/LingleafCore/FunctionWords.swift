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
        /// A pronoun and a short verb: "it's" (= "it is"), "let's" (= "let us").
        case contraction
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
        /// have/has + past participle: "has seen".
        case presentPerfect
        /// had + past participle: "had left".
        case pastPerfect
        /// "had better" / "'d better" + verb: strong advice.
        case hadBetter
        /// A pronoun contraction that is not a helper here: "it's cold" (= "it is").
        case contraction
    }

    public let kind: Kind
    /// The base form: "do" for "did" and "didn't", "will" for "won't".
    public let base: String
    public let use: Use
    /// The verb group in the sentence ("did not go", "should have known", "Can you help");
    /// nil when it can't be told reliably (a question whose subject is not a pronoun, or a
    /// sentence that ends right after the word: "Yes, I can.").
    public let chunk: WordRange?
    /// A negative modal: "mustn't", "cannot", "will not". Its note says so, since the
    /// meaning can flip ("must" = necessary, "mustn't" = not allowed).
    public var negative = false
    /// For a pronoun contraction, what it stands for ("it is" for "it's", "I will" for
    /// "I'll"); also its base form. Nil for other words.
    public var expansion: String?
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

    private static let haveForms: [String: Bool] = [
        "have": false, "has": false, "had": true, "haven't": false, "hasn't": false, "hadn't": true,
    ]

    /// Pronoun contractions and their expansions; "'s" and "'d" have two (see `expand`).
    private static let contractions: [String: (pronoun: String, verb: String)] = {
        var table: [String: (pronoun: String, verb: String)] = [:]
        func add(_ pronouns: [String], _ suffix: String, _ verb: String) {
            for pronoun in pronouns { table[pronoun + suffix] = (pronoun == "i" ? "I" : pronoun, verb) }
        }
        add(["i"], "'m", "am")
        add(["you", "we", "they", "what", "who"], "'re", "are")
        add(["he", "she", "it", "that", "there", "here", "what", "who", "where", "how"], "'s", "is")
        add(["i", "you", "we", "they", "who"], "'ve", "have")
        add(["i", "you", "he", "she", "it", "we", "they", "that", "there", "who"], "'ll", "will")
        add(["i", "you", "he", "she", "it", "we", "they", "that", "there", "who"], "'d", "would")
        table["let's"] = ("let", "us")
        return table
    }()

    /// Adverbs between a helper and its participle: "has never seen".
    private static let adverbs: Set<String> = [
        "never", "always", "ever", "really", "just", "also", "still", "even", "only", "already",
        "probably", "certainly", "surely", "often", "not", "recently", "finally", "almost", "nearly",
        "before", "once", "yet",
    ]

    /// Before a noun subject in a question or a condition: "Has the post arrived?".
    private static let subjectDeterminers: Set<String> = [
        "the", "a", "an", "my", "your", "his", "her", "our", "their", "this", "that", "these", "those",
    ]

    private static let pronouns: Set<String> = ["i", "you", "he", "she", "it", "we", "they"]
    private static let questionWords: Set<String> = ["what", "where", "when", "why", "how", "who", "whom", "whose", "which"]
    /// Words that may come before a prohibition: "Please don't go", "And don't forget".
    private static let leadIns: Set<String> = ["please", "oh", "now", "so", "and", "but", "then", "well", "no", "yes", "just"]
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
            if haveForms[token] != nil { return FunctionWord(kind: .helper, base: "have", use: .questionTag, chunk: nil) }
            if let base = modals[token] { return FunctionWord(kind: .modal, base: base, use: .questionTag, chunk: nil) }
        }

        /// The index of the past participle after the helper at `index` ("has never seen"),
        /// past a pronoun subject in a question ("Have you seen"), adverbs ("had evidently
        /// heard"); one more word after "been" when it is -ing or a participle ("has been
        /// reading"), so "has been here" is "has been". `baseLike` as in `Verbs`.
        func participle(subject: Bool, baseLike: Bool = true) -> Int? {
            var at = index + 1
            // "Have you seen…?", "Has the post arrived?", and "Had they known, …" (a condition).
            if subject, isQuestion || index == 0, at < tokens.count {
                if pronouns.contains(tokens[at]) {
                    at += 1
                } else if subjectDeterminers.contains(tokens[at]), at + 1 < tokens.count {
                    at += 2
                }
            }
            var skipped = 0
            while at < tokens.count, adverbs.contains(tokens[at]) || tokens[at].hasSuffix("ly"), skipped < 4 {
                at += 1
                skipped += 1
            }
            // Part of a hyphenated word ("read-only") is not a verb form.
            func verbForm(_ at: Int) -> Bool {
                words[at].end >= (sentence as NSString).length || (sentence as NSString).character(at: words[at].end) != 0x2D
            }
            guard at < tokens.count, Verbs.isParticiple(tokens[at], baseLike: baseLike), verbForm(at) else { return nil }
            if tokens[at] == "been", at + 1 < tokens.count {
                let after = tokens[at + 1]
                if after.hasSuffix("ing") || Verbs.isParticiple(after), verbForm(at + 1) { return at + 1 }
            }
            return at
        }
        /// "had better go" / "had better not": the index of the group's last word, or nil.
        let betterVerb: Int? = {
            guard next == "better", index + 2 < tokens.count else { return nil }
            if tokens[index + 2] == "not" {
                return index + 3 < tokens.count && Verbs.isBase(tokens[index + 3]) ? index + 3 : index + 2
            }
            return Verbs.isBase(tokens[index + 2]) ? index + 2 : nil
        }()
        func through(_ end: Int) -> WordRange { WordRange(range.start, words[end].end) }

        if let contraction = contractions[token] {
            let pronoun = contraction.pronoun
            func expanded(_ verb: String) -> String { "\(pronoun) \(verb)" }
            switch contraction.verb {
            case "is" where ["been", "gone", "had"].contains(next ?? ""):
                let end = participle(subject: false) ?? index + 1
                return FunctionWord(kind: .helper, base: expanded("has"), use: .presentPerfect, chunk: through(end), expansion: expanded("has"))
            case "is" where next == "got":
                return FunctionWord(kind: .contraction, base: expanded("has"), use: .contraction, chunk: range, expansion: expanded("has"))
            case "have":
                guard let end = participle(subject: false) else { break }
                return FunctionWord(kind: .helper, base: expanded("have"), use: .presentPerfect, chunk: through(end), expansion: expanded("have"))
            case "would":
                if let verb = betterVerb {
                    return FunctionWord(kind: .helper, base: expanded("had"), use: .hadBetter, chunk: through(verb), expansion: expanded("had"))
                }
                if let end = participle(subject: false, baseLike: false) {
                    return FunctionWord(kind: .helper, base: expanded("had"), use: .pastPerfect, chunk: through(end), expansion: expanded("had"))
                }
                // "He'd put", "she'd run": had or would, only the context tells; the card says both.
                if let end = participle(subject: false) {
                    let both = "\(expanded("had")) / \(expanded("would"))"
                    return FunctionWord(kind: .contraction, base: both, use: .contraction, chunk: through(end), expansion: both)
                }
                // Up to the sentence's end if it comes first: "…, she'd."
                return FunctionWord(kind: .modal, base: expanded("would"), use: .modal("would"), chunk: group ?? range, negative: next == "not", expansion: expanded("would"))
            case "will":
                return FunctionWord(kind: .modal, base: expanded("will"), use: .modal("will"), chunk: group ?? range, negative: next == "not", expansion: expanded("will"))
            case "us":
                // "Let's go": the suggestion with its verb.
                let chunk = index + 1 < tokens.count ? through(index + 1) : range
                return FunctionWord(kind: .contraction, base: expanded("us"), use: .contraction, chunk: chunk, expansion: expanded("us"))
            default:
                break
            }
            return FunctionWord(kind: .contraction, base: expanded(contraction.verb), use: .contraction, chunk: range, expansion: expanded(contraction.verb))
        }

        if let past = haveForms[token] {
            if past, token == "had", let verb = betterVerb {
                return FunctionWord(kind: .helper, base: "have", use: .hadBetter, chunk: through(verb))
            }
            guard let end = participle(subject: true) else { return nil }
            let negative = token.hasSuffix("n't") || next == "not"
            return FunctionWord(kind: .helper, base: "have", use: past ? .pastPerfect : .presentPerfect, chunk: through(end), negative: negative)
        }

        if let form = doForms[token] {
            if token.hasSuffix("n't") || next == "not" {
                // "Don't touch that." / "Please don't go": no subject before it → a prohibition.
                if tokens[..<index].allSatisfy({ leadIns.contains($0) }), !form.past, token != "doesn't", token != "does", !isQuestion {
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
        let negative = token.hasSuffix("n't") || token == "cannot" || next == "not"
        return FunctionWord(kind: .modal, base: base, use: .modal(base), chunk: group, negative: negative)
    }
}

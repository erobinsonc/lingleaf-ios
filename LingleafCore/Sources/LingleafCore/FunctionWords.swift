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
        guard let context = Context(sentence, range) else { return nil }
        if let tag = questionTag(context) { return tag }
        if let contraction = contractions[context.token] { return contracted(contraction, context) }
        if let past = haveForms[context.token] { return perfect(past: past, context) }
        if let form = doForms[context.token] { return helper(form, context) }
        return modal(context)
    }

    /// The tapped word and its sentence, split into words.
    private struct Context {
        let sentence: String
        let range: WordRange
        let words: [WordRange]
        let tokens: [String]
        let index: Int
        let token: String
        let next: String?
        let isQuestion: Bool

        init?(_ sentence: String, _ range: WordRange) {
            words = TextTools.wordRanges(sentence)
            guard let index = words.firstIndex(of: range) else { return nil }
            self.sentence = sentence
            self.range = range
            self.index = index
            tokens = words.map { TextTools.normalize(TextTools.substring(sentence, $0)) }
            token = tokens[index]
            next = index + 1 < tokens.count ? tokens[index + 1] : nil
            isQuestion = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " \"”’)]")).hasSuffix("?")
        }

        /// From the tapped word to the word at `end`.
        func through(_ end: Int) -> WordRange { WordRange(range.start, words[end].end) }

        /// The verb group: the word, "not", a pronoun subject in a question
        /// ("Can you help", "didn't you come"), have/be and adverbs ("should have known"),
        /// then the main verb; up to the sentence's end if it comes first.
        var group: WordRange? {
            var last = index
            if next == "not" { last += 1 }
            if isQuestion, last + 1 < tokens.count, FunctionWords.pronouns.contains(tokens[last + 1]) { last += 1 }
            var skipped = 0
            while last + 1 < tokens.count, FunctionWords.inGroup.contains(tokens[last + 1]), skipped < 4 {
                last += 1
                skipped += 1
            }
            if last + 1 < tokens.count { return through(last + 1) }
            return last > index ? through(last) : nil
        }

        /// The index of the past participle after the helper ("has never seen"), past a
        /// pronoun subject in a question ("Have you seen"), adverbs ("had evidently heard");
        /// one more word after "been" when it is -ing or a participle ("has been reading"),
        /// so "has been here" is "has been". `baseLike` as in `Verbs`.
        func participle(subject: Bool, baseLike: Bool = true) -> Int? {
            var at = index + 1
            // "Have you seen…?", "Has the post arrived?", and "Had they known, …" (a condition).
            if subject, isQuestion || index == 0, at < tokens.count {
                if FunctionWords.pronouns.contains(tokens[at]) {
                    at += 1
                } else if FunctionWords.subjectDeterminers.contains(tokens[at]), at + 1 < tokens.count {
                    at += 2
                }
            }
            var skipped = 0
            while at < tokens.count, FunctionWords.adverbs.contains(tokens[at]) || tokens[at].hasSuffix("ly"), skipped < 4 {
                at += 1
                skipped += 1
            }
            guard at < tokens.count, Verbs.isParticiple(tokens[at], baseLike: baseLike), isVerbForm(at) else {
                return nil
            }
            if tokens[at] == "been", at + 1 < tokens.count {
                let after = tokens[at + 1]
                if after.hasSuffix("ing") || Verbs.isParticiple(after), isVerbForm(at + 1) { return at + 1 }
            }
            return at
        }

        /// Part of a hyphenated word ("read-only") is not a verb form.
        private func isVerbForm(_ at: Int) -> Bool {
            let text = sentence as NSString
            return words[at].end >= text.length || text.character(at: words[at].end) != 0x2D
        }

        /// "had better go" / "had better not": the index of the group's last word, or nil.
        var betterVerb: Int? {
            guard next == "better", index + 2 < tokens.count else { return nil }
            if tokens[index + 2] == "not" {
                return index + 3 < tokens.count && Verbs.isBase(tokens[index + 3]) ? index + 3 : index + 2
            }
            return Verbs.isBase(tokens[index + 2]) ? index + 2 : nil
        }
    }

    /// A question tag: ", didn't you?" / ", can't she?" closing the sentence.
    private static func questionTag(_ context: Context) -> FunctionWord? {
        let index = context.index, words = context.words, tokens = context.tokens
        guard context.isQuestion, index > 0, index == tokens.count - 2, pronouns.contains(tokens[index + 1]) else { return nil }
        let before = TextTools.substring(context.sentence, WordRange(words[index - 1].end, context.range.start))
        guard before.contains(",") else { return nil }
        if let form = doForms[context.token] { return FunctionWord(kind: .helper, base: form.base, use: .questionTag, chunk: nil) }
        if haveForms[context.token] != nil { return FunctionWord(kind: .helper, base: "have", use: .questionTag, chunk: nil) }
        if let base = modals[context.token] { return FunctionWord(kind: .modal, base: base, use: .questionTag, chunk: nil) }
        return nil
    }

    /// A pronoun contraction: what it stands for and, when it is a helper here, what it does.
    private static func contracted(_ contraction: (pronoun: String, verb: String), _ context: Context) -> FunctionWord {
        let next = context.next
        func word(
            _ kind: FunctionWord.Kind, _ verb: String, _ use: FunctionWord.Use, _ chunk: WordRange?, expansion: String? = nil
        ) -> FunctionWord {
            let expansion = expansion ?? "\(contraction.pronoun) \(verb)"
            let negative = next == "not" && kind == .modal
            return FunctionWord(kind: kind, base: expansion, use: use, chunk: chunk, negative: negative, expansion: expansion)
        }
        switch contraction.verb {
        case "is" where ["been", "gone", "had"].contains(next ?? ""):
            return word(.helper, "has", .presentPerfect, context.through(context.participle(subject: false) ?? context.index + 1))
        case "is" where next == "got":
            return word(.contraction, "has", .contraction, context.range)
        case "have":
            if let end = context.participle(subject: false) { return word(.helper, "have", .presentPerfect, context.through(end)) }
        case "would":
            if let end = context.betterVerb { return word(.helper, "had", .hadBetter, context.through(end)) }
            if let end = context.participle(subject: false, baseLike: false) {
                return word(.helper, "had", .pastPerfect, context.through(end))
            }
            // "He'd put", "she'd run": had or would, only the sentence tells. The card says both
            // and, without a verb group, translates the whole sentence, which settles it.
            if context.participle(subject: false) != nil {
                let pronoun = contraction.pronoun
                return word(.contraction, "would", .contraction, nil, expansion: "\(pronoun) had / \(pronoun) would")
            }
            // Up to the sentence's end if it comes first: "…, she'd."
            return word(.modal, "would", .modal("would"), context.group ?? context.range)
        case "will":
            return word(.modal, "will", .modal("will"), context.group ?? context.range)
        case "us":
            // "Let's go": the suggestion with its verb.
            let chunk = context.index + 1 < context.tokens.count ? context.through(context.index + 1) : context.range
            return word(.contraction, "us", .contraction, chunk)
        default:
            break
        }
        return word(.contraction, contraction.verb, .contraction, context.range)
    }

    /// have/has/had + past participle ("has seen"), or "had better" + verb; else an ordinary word.
    private static func perfect(past: Bool, _ context: Context) -> FunctionWord? {
        if past, context.token == "had", let end = context.betterVerb {
            return FunctionWord(kind: .helper, base: "have", use: .hadBetter, chunk: context.through(end))
        }
        guard let end = context.participle(subject: true) else { return nil }
        let negative = context.token.hasSuffix("n't") || context.next == "not"
        let use: FunctionWord.Use = past ? .pastPerfect : .presentPerfect
        return FunctionWord(kind: .helper, base: "have", use: use, chunk: context.through(end), negative: negative)
    }

    /// do / does / did making a negative, a prohibition or a question; else an ordinary word.
    private static func helper(_ form: (base: String, past: Bool), _ context: Context) -> FunctionWord? {
        let token = context.token, tokens = context.tokens, index = context.index
        if token.hasSuffix("n't") || context.next == "not" {
            // "Don't touch that." / "Please don't go": no subject before it → a prohibition.
            let leadOnly = tokens[..<index].allSatisfy { leadIns.contains($0) }
            if leadOnly, !form.past, token != "doesn't", token != "does", !context.isQuestion {
                return FunctionWord(kind: .helper, base: form.base, use: .prohibition, chunk: context.group)
            }
            return FunctionWord(kind: .helper, base: form.base, use: form.past ? .pastNegative : .presentNegative, chunk: context.group)
        }
        let opensQuestion = index == 0 || questionWords.contains(tokens[index - 1])
        guard context.isQuestion, opensQuestion else { return nil }
        let withPronoun = context.next.map { pronouns.contains($0) } ?? false
        return FunctionWord(
            kind: .helper, base: form.base,
            use: form.past ? .pastQuestion : .presentQuestion,
            chunk: withPronoun ? context.group : nil
        )
    }

    /// can, will, must…; nil for lookalikes ("a can of beans", "in May").
    private static func modal(_ context: Context) -> FunctionWord? {
        let token = context.token, index = context.index
        guard let base = modals[token] else { return nil }
        if index > 0, determiners.contains(context.tokens[index - 1]) { return nil }
        // "May" and "Will" capitalized mid-sentence are a month and a name.
        let surface = TextTools.substring(context.sentence, context.range)
        if index > 0, token == "may" || token == "will", surface.first?.isUppercase == true { return nil }
        let negative = token.hasSuffix("n't") || token == "cannot" || context.next == "not"
        return FunctionWord(kind: .modal, base: base, use: .modal(base), chunk: context.group, negative: negative)
    }
}

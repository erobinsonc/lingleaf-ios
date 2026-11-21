import Foundation
@testable import LingleafCore

/// The content rules of `irregular-verb-sentences.json` (SPEC.md, Verb sentences data) beyond the reader's: the
/// bold form, the label-fit cues, same-form time cues, `perfectq` against `perfect`, `spoken`, length by level, the
/// `context` sentence, the S3 no-contradiction check, the cue rule of lie and hang and, for release pull requests,
/// completeness. Test code: it lives in the test target and is never shipped in the app. Each problem is one line that
/// starts with a stable code ("bold-twice: take didnt"); an empty list
/// means the file passes. The content rules that need a reader (originality, Spanish, natural wording, the
/// `wordfreq` band) are reviewed, not tested here.
enum VerbSentencesLint {
    /// Words in `en` by level (SPEC.md: A1 4-8, A2 5-10, B1 6-12, B2 7-14, C1 and C2 8-16).
    static let wordRange: [String: ClosedRange<Int>] = [
        "A1": 4...8, "A2": 5...10, "B1": 6...12, "B2": 7...14, "C1": 8...16, "C2": 8...16,
    ]

    /// Every problem of the file: the reader's first, then the content rules, in file order.
    static func problems(in file: VerbSentences, table: IrregularVerbs = .shared) -> [String] {
        var out = VerbSentences.problems(in: file, table: table)
        for entry in file.verbs {
            guard let verb = table.verb(base: entry.base) else { continue }
            for sentence in entry.sentences { out += lint(sentence, verb: verb, table: table) }
            for sense in [0, 1] { out += lintSense(entry.sentences(senseIndex: sense), sense: sense, verb: verb) }
        }
        return out
    }

    // MARK: A sentence

    private static func lint(_ sentence: VerbSentence, verb: IrregularVerb, table: IrregularVerbs) -> [String] {
        let tag = "\(verb.base) \(sentence.slot.rawValue)"
        let view = SentenceView(sentence.en)
        var out: [String] = []
        if let range = wordRange[sentence.level], !range.contains(view.tokens.count) {
            out.append("length: \(tag) has \(view.tokens.count) words, \(sentence.level) takes \(range.lowerBound)-\(range.upperBound)")
        }
        let (found, problems) = occurrence(of: sentence, in: view, verb: verb)
        out += problems.map { "\($0): \(tag)" }
        guard let index = found else { return out }
        out += cueProblems(sentence, view: view, index: index, verb: verb).map { "\($0): \(tag)" }
        out += cueProblem(sentence, view: view, index: index, verb: verb).map { "\($0): \(tag)" }
        out += spokenProblems(sentence, view: view, index: index, verb: verb).map { "\($0): \(tag)" }
        if !resolves(sentence, view: view, index: index, verb: verb, table: table) {
            out.append("s3: \(tag) S3 proves \"\(view.tokens[index])\" is not \(verb.base) sense \(sentence.senseIndex)")
        }
        return out
    }

    // MARK: Bold form

    /// Verbs whose own forms are the auxiliary of the position's construction (SPEC.md, bold-form rule, exception b).
    private static func auxiliaries(of base: String, slot: VerbSlot) -> Set<String> {
        let position = slot.position
        switch base {
        case "have" where [7, 9].contains(position) || slot == .perfectq: return ["have", "has", "had"]
        case "be" where [3, 7, 8, 9].contains(position): return ["am", "is", "are", "was", "were", "been", "being"]
        case "do" where [6, 7, 9].contains(position): return ["do", "does", "did"]
        default: return []
        }
    }

    /// What may come right before the base of the verb without being counted (exception a).
    private static let baseLicensers: Set<String> = [
        "didn't", "don't", "doesn't", "did", "do", "does", "should", "shouldn't", "can", "can't", "cannot", "could", "couldn't",
        "will", "won't", "would", "wouldn't", "shall", "may", "might", "must", "mustn't",
    ]

    /// The index of the word at the position of `form` (the one the app bolds) and the problems: `form` once as a
    /// whole word outside the auxiliary exception, and no other form of the verb (or of its homonym) except the base
    /// after didn't, should or another modal.
    private static func occurrence(of sentence: VerbSentence, in view: SentenceView, verb: IrregularVerb) -> (Int?, [String]) {
        let aux = auxiliaries(of: verb.base, slot: sentence.slot)
        let hits = view.tokens.indices.filter { view.tokens[$0] == sentence.form }
        var out: [String] = []
        if hits.isEmpty { return (nil, ["bold-missing"]) }
        // With the auxiliary exception the main verb is the last occurrence ("I had had enough").
        let counted = hits[hits.count - 1]
        if hits.count > 1 && !(aux.contains(sentence.form)) { out.append("bold-twice") }
        let others = Set([verb.base] + verb.forms).subtracting([sentence.form])
        for (k, token) in view.tokens.enumerated() where k != counted && others.contains(token) && !aux.contains(token) {
            if token == verb.base && isLicensed(view.tokens, k) { continue }
            out.append("bold-other-form(\(token))")
        }
        return (counted, out)
    }

    private static func isLicensed(_ tokens: [String], _ k: Int) -> Bool {
        guard k > 0 else { return false }
        if baseLicensers.contains(tokens[k - 1]) { return true }
        return k > 1 && ["not", "never"].contains(tokens[k - 1]) && baseLicensers.contains(tokens[k - 2])
    }

    // MARK: Cues

    private static let timeWords: Set<String> = [
        "yesterday", "last", "ago", "then", "when", "already", "just", "before", "since", "for",
    ]
    private static let months: Set<String> = [
        "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december",
    ]
    private static let datePattern = try! NSRegularExpression(
        pattern: "\\b(?:[12][0-9]{3}|[0-9]{1,2}[/.-][0-9]{1,2}(?:[/.-][0-9]{2,4})?)\\b"
    )

    /// The one list of time cues: the listed words, "a year", or a date (a month's name, "May" only capitalised in
    /// the middle of a sentence, a year of four digits or a numeric date).
    static func hasTimeCue(_ view: SentenceView) -> Bool {
        let tokens = view.tokens
        if tokens.contains(where: timeWords.contains) || tokens.contains(where: months.contains) { return true }
        if zip(tokens, tokens.dropFirst()).contains(where: { $0 == "a" && $1 == "year" }) { return true }
        if let may = tokens.firstIndex(of: "may"), may > 0, view.words.titlecase(may) { return true }
        let ns = view.text as NSString
        return datePattern.firstMatch(in: view.text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func cueProblems(_ sentence: VerbSentence, view: SentenceView, index: Int, verb: IrregularVerb) -> [String] {
        let before = Array(view.tokens[..<index])
        let ends = view.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
        func has(_ words: Set<String>, suffixes: [String] = []) -> Bool {
            before.contains { words.contains($0) || suffixes.contains(where: $0.hasSuffix) }
        }
        var out: [String] = []
        func need(_ ok: Bool, _ code: String) { if !ok { out.append(code) } }
        switch sentence.slot {
        case .now: need(has(["am", "is", "are"], suffixes: ["'m", "'s", "'re"]), "cue-now")
        case .past: need(hasTimeCue(view), "cue-past")
        case .story: need(view.tokens.contains { ["and", "then", "after", "when"].contains($0) }, "cue-story")
        case .didnt: need(has(["didn't"]) || zip(before, before.dropFirst()).contains { $0 == "did" && $1 == "not" }, "cue-didnt")
        case .perfect: need(has(["have", "has"], suffixes: ["'ve"]) && !ends, "cue-perfect")
        case .passive: need(has(["was", "were", "is", "are", "be", "been"]), "cue-passive")
        case .state: need(has(["is", "are", "was", "were"]), "cue-state")
        case .perfectq: need(ends && has(["have", "has"]), "cue-perfectq")
            need(view.tokens.contains { ["ever", "yet", "already"].contains($0) }, "perfectq-shape")
        case .pastperfect: need(has(["had"], suffixes: ["'d"]), "cue-pastperfect")
        case .advice: need(view.tokens.contains("should"), "cue-advice")
        case .habit, .third, .gerund: break
        }
        // Same-form: the form is also the base, so a time cue tells the learner which form it is.
        if [4, 7, 9].contains(sentence.slot.position), sentence.form == verb.base, !hasTimeCue(view) { out.append("same-form-cue") }
        return out
    }

    // MARK: spoken

    /// `spoken` is present exactly when the table respells the form's slot, and is `en` with that respelling at the
    /// form (capitalised like the word it replaces).
    private static func spokenProblems(_ sentence: VerbSentence, view: SentenceView, index: Int, verb: IrregularVerb) -> [String] {
        let respelling = sentence.senseIndex == 0 ? verb.spokenAs[sentence.slot.formClass.rawValue] : nil
        guard let respelling else { return sentence.spoken == nil ? [] : ["spoken-unexpected"] }
        let range = view.words.ranges[index].nsRange
        let ns = view.text as NSString
        var word = respelling
        if view.words.surface(index).unicodeScalars.first?.properties.isUppercase == true {
            word = word.prefix(1).uppercased() + word.dropFirst()
        }
        let expected = ns.replacingCharacters(in: range, with: word)
        return sentence.spoken == expected ? [] : ["spoken-wrong"]
    }

    // MARK: S3 (no contradiction)

    /// What S3 makes of the word at the form's position, against what the file says (`base`, `senseIndex`).
    enum Reading3 { case contradicts, agrees, unsure }

    /// A no-contradiction check, not a resolution check (SPEC.md, bold-form rule): the file says which verb and sense a
    /// sentence is; S3 only reads a tapped word of a book. S3's reading of the word at the position of `form` may be
    /// unsure, ordinary, or none (a gerund, the base, an -s or -ing form it leaves ordinary): all accepted. It must never
    /// be proved as another verb, another sense of this verb, a noun or a name. For have, be and do, a reading as the
    /// verb's own auxiliary in the construction of the position is accepted. The sense of lie and hang is the cue rule's.
    static func s3Reading(
        _ sentence: VerbSentence, view: SentenceView, index: Int, verb: IrregularVerb, table: IrregularVerbs
    ) -> Reading3 {
        let word = view.tokens[index]
        if auxiliaries(of: verb.base, slot: sentence.slot).contains(word) { return .agrees }
        let wantsHomonym = sentence.senseIndex == 1
        func judge(_ reading: Reading?) -> Reading3 {
            guard let reading else { return .unsure }
            switch reading.kind {
            case .noun: return .contradicts
            case .verb, .homonym: return reading.base == verb.base && (reading.kind == .homonym) == wantsHomonym ? .agrees : .contradicts
            case .word, .expression, .unsure: return .unsure
            }
        }
        if table.homographs[word] != nil { return judge(table.resolve(view.words, index)) }
        guard let entry = table.tableForms[word] else { return .unsure }
        if entry.base != verb.base { return .contradicts }
        if entry.kind == .certain { return (entry.sense == Sense.homonym) == wantsHomonym ? .agrees : .contradicts }
        return judge(table.resolve(view.words, index))
    }

    static func resolves(
        _ sentence: VerbSentence, view: SentenceView, index: Int, verb: IrregularVerb, table: IrregularVerbs
    ) -> Bool {
        s3Reading(sentence, view: view, index: index, verb: verb, table: table) != .contradicts
    }

    /// The sentences S3 leaves unsure or ordinary (accepted; reported for the reviewer): "base sense slot: en".
    static func unsureReadings(in file: VerbSentences, table: IrregularVerbs = .shared) -> [String] {
        var out: [String] = []
        for entry in file.verbs {
            guard let verb = table.verb(base: entry.base) else { continue }
            for sentence in entry.sentences {
                let view = SentenceView(sentence.en)
                guard let index = occurrence(of: sentence, in: view, verb: verb).0 else { continue }
                if s3Reading(sentence, view: view, index: index, verb: verb, table: table) == .unsure {
                    out.append("\(entry.base) \(sentence.senseIndex) \(sentence.slot.rawValue): \(sentence.en)")
                }
            }
        }
        return out
    }

    // MARK: A verb's sense

    /// The rules across the sentences of one verb and sense: `perfect` and `perfectq` have different subjects and
    /// exactly one `context` sentence, in position 1, 6 or 10 (so its form is the base, which the bold rule finds in it).
    private static func lintSense(_ sentences: [VerbSentence], sense: Int, verb: IrregularVerb) -> [String] {
        guard !sentences.isEmpty else { return [] }
        let tag = "\(verb.base) sense \(sense)"
        var out: [String] = []
        let marked = sentences.filter(\.context)
        if marked.count != 1 {
            out.append("context-count: \(tag) has \(marked.count) context sentences")
        } else if let sentence = marked.first {
            if ![VerbSlot.habit, .didnt, .advice].contains(sentence.slot) { out.append("context-slot: \(tag)") }
        }
        let statement = sentences.first { $0.slot == .perfect }
        if let statement, let question = sentences.first(where: { $0.slot == .perfectq }) {
            let asked = questionSubject(SentenceView(question.en).tokens)
            let said = statementSubject(SentenceView(statement.en).tokens)
            if asked == nil || said == nil || asked == said { out.append("perfect-subject: \(tag) perfect and perfectq share a subject") }
        }
        return out
    }

    /// The word after have or has in a question ("Have you ever had a dog?" → "you").
    private static func questionSubject(_ tokens: [String]) -> String? {
        guard let k = tokens.firstIndex(where: { ["have", "has"].contains($0) }), k + 1 < tokens.count else { return nil }
        return tokens[k + 1]
    }

    /// The word before have, has or 've in a statement ("I have had" → "i", "She's" is not have).
    private static func statementSubject(_ tokens: [String]) -> String? {
        for (k, token) in tokens.enumerated() {
            if ["have", "has"].contains(token) { return k > 0 ? tokens[k - 1] : nil }
            if token.hasSuffix("'ve") { return String(token.dropLast(3)) }
        }
        return nil
    }

    // MARK: Completeness (release pull requests only)

    /// What a complete file also holds: every verb of the table, for sense 0 a sentence or an `omitted` entry for each
    /// position (only 3 and 10 may be omitted), the five past or participle positions (4, 5, 7, 8, 9) always, and for
    /// a verb with a homonym exactly the positions 4, 7, 8 and one of 1, 6 or 10 of sense 1. The reader's and the
    /// content rules are in `problems(in:)`; this is the rest.
    static func completenessProblems(in file: VerbSentences, table: IrregularVerbs = .shared) -> [String] {
        var out: [String] = []
        for verb in table.verbs {
            guard let entry = file.entry(base: verb.base) else {
                out.append("complete-missing: \(verb.base)")
                continue
            }
            let present = Set(entry.sentences(senseIndex: 0).map(\.slot.position))
            let omitted = Set(entry.omitted.map { $0.slot == "now" ? 3 : 10 })
            for position in 1...10 where !present.contains(position) && !omitted.contains(position) {
                out.append("complete-position: \(verb.base) has nothing for position \(position)")
            }
            for position in [1, 2, 4, 5, 6, 7, 8, 9] where !present.contains(position) {
                out.append("complete-required: \(verb.base) position \(position) cannot be omitted")
            }
            let second = Set(entry.sentences(senseIndex: 1).map(\.slot.position))
            let wanted: Set<Int>? = verb.homonym == nil ? nil : [4, 7, 8]
            if let wanted {
                let bases = second.intersection([1, 6, 10])
                if second.subtracting(bases) != wanted || bases.count != 1 {
                    out.append("complete-sense-one: \(verb.base) sense 1 needs positions 4, 7, 8 and one of 1, 6 or 10")
                }
            }
        }
        return out
    }
}

/// A sentence split into words once: lower-case tokens as the table reads them (SPEC.md: a word is a run of letters
/// with its inner apostrophes, so "didn't" and "I've" are one word and digits are not words).
struct SentenceView {
    let text: String
    let words: Words
    let tokens: [String]

    init(_ text: String) {
        self.text = text
        let words = Words(text as NSString)
        self.words = words
        tokens = (0..<words.count).map { words.token($0) }
    }
}

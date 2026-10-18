import Foundation

/// Which word a saved spelling is (SPEC S4): the verb, the noun, or a verb's regular homonym
/// ("lied": "lie", "mentir"). A word saved without one behaves as before senses existed.
public enum Sense {
    public static let verb = "verb"
    public static let noun = "noun"
    public static let homonym = "homonym"
    public static let all: Set<String> = [verb, noun, homonym]
}

/// One reading of a word saved unsure, as its card showed it: "to leave — irse, salir".
public struct SavedMeaning: Codable, Hashable, Sendable {
    /// "to leave", "the left".
    public var label: String
    public var sense: String
    public var base: String
    /// The meaning in `language`; empty until translated.
    public var text: String
    public var language: String?

    public init(label: String, sense: String, base: String, text: String, language: String?) {
        self.label = label
        self.sense = sense
        self.base = base
        self.text = text
        self.language = language
    }

    static let maxLabel = 60
    static let maxText = 200

    /// Within bounds, or nil when it can't be one of a card's readings (a restored or edited file).
    func bounded() -> SavedMeaning? {
        guard Sense.all.contains(sense), IrregularVerbs.isForm(base) else { return nil }
        var meaning = self
        meaning.label = TextTools.cleanLabel(label)
        meaning.text = TextTools.truncated(TextTools.cleanLabel(text), Self.maxText)
        meaning.label = TextTools.truncated(meaning.label, Self.maxLabel)
        meaning.language = language.flatMap { $0.count <= 20 ? $0 : nil }
        return meaning.label.isEmpty ? nil : meaning
    }
}

/// A reading the learner can choose on the card of a word whose sentence doesn't tell (SPEC S3).
public struct ReadingChoice: Equatable, Sendable, Identifiable {
    public let kind: Reading.Kind
    public let base: String
    public let sense: String

    public var id: String { "\(sense):\(base)" }

    /// "to leave", "the left": what the row shows and what is translated for its meaning.
    public var label: String { kind == .noun ? "the \(base)" : "to \(base)" }

    /// The reading, to look the word up and to read it aloud.
    public var reading: Reading { Reading(kind: kind, base: base, step: .unsure) }
}

extension IrregularVerbs {
    /// The two readings of an unsure homograph at `range` of `text`, most common first; empty when
    /// the sentence tells. A verb is "to {base}", a noun "the {noun}"; "lay" after I/you/we/they is
    /// "to lie" or "to lay"; a form with no noun has its two verbs ("to find", "to found").
    public func choices(in text: String, at range: WordRange) -> [ReadingChoice] {
        let words = Words(text as NSString)
        guard let i = words.index(of: range) else { return [] }
        return choices(words, i)
    }

    func choices(_ words: Words, _ i: Int) -> [ReadingChoice] {
        let form = words.token(i)
        guard let h = homographs[form], resolve(words, i)?.kind == .unsure else { return [] }
        let twoVerbs: Bool
        if form == "lay", let head = words.head(before: i, skip: context.skip) {
            twoVerbs = ["i", "you", "we", "they"].contains(head.token)
        } else {
            twoVerbs = h.noun == nil
        }
        if twoVerbs, let other = h.baseVerb, other != h.verb {
            return [
                ReadingChoice(kind: .verb, base: h.verb, sense: Sense.verb),
                ReadingChoice(kind: .verb, base: other, sense: Sense.verb),
            ]
        }
        guard let noun = h.noun else { return [ReadingChoice(kind: .verb, base: h.verb, sense: Sense.verb)] }
        let verbChoice = ReadingChoice(kind: .verb, base: h.verb, sense: Sense.verb)
        let nounChoice = ReadingChoice(kind: .noun, base: noun, sense: Sense.noun)
        // Most common first: the noun when the verb's base is used more often as a noun ("wind").
        return verb(base: h.verb)?.nounFirst == true ? [nounChoice, verbChoice] : [verbChoice, nounChoice]
    }

    /// The sense of a certain reading of a homograph; nil for a name or an unsure one.
    public func sense(of reading: Reading) -> String? {
        switch reading.kind {
        case .verb: Sense.verb
        case .noun: reading.step == .name ? nil : Sense.noun
        case .unsure: nil
        }
    }

    /// The sense a form of the table links to: the homonym's for its own forms ("lied"), any for
    /// forms both share ("lying": nil), else the verb's.
    func linkSense(_ form: String) -> String? {
        if homonymOnlyForms.contains(form) { return Sense.homonym }
        return sharedHomonymForms.contains(form) ? nil : Sense.verb
    }

    /// The table's Spanish meanings of a verb (or its homonym's): all of them joined with " · ",
    /// or only the first group; nil for a verb the table doesn't have.
    public func spanishMeaning(of base: String, sense: String = Sense.verb, all: Bool = true) -> String? {
        guard let entry = verb(base: base) else { return nil }
        let es = sense == Sense.homonym ? entry.homonym?.es ?? entry.es : entry.es
        return all ? es.joined(separator: " · ") : es.first
    }

    /// The slots `form` fills in the verb `base` ("read": base, past, participle).
    func slots(of form: String, in base: String) -> [String] {
        guard let entry = verb(base: base) else { return [] }
        return [
            form == entry.base ? "base" : nil, entry.past.contains(form) ? "past" : nil,
            entry.participle.contains(form) ? "participle" : nil, form == entry.ing ? "ing" : nil, form == entry.s ? "s" : nil,
        ].compactMap { $0 }
    }

    /// A slot value of `form` as the verb `base` the learner chose: only when every slot the form
    /// fills has the same one ("wound": past and participle; not "read": base and past).
    private func agreed(_ form: String, _ base: String, _ values: (IrregularVerb) -> [String: String]) -> String? {
        guard let entry = verb(base: base) else { return nil }
        let all = slots(of: form, in: base).map { values(entry)[$0] }
        guard let first = all.first, all.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The table's IPA of `form` as the chosen verb `base` ("/waʊnd/"), on the same terms as its respelling.
    public func ipa(of form: String, verb base: String) -> String? {
        agreed(TextTools.normalize(form), base) { $0.ipa }.map { "/\($0)/" }
    }

    /// The table's IPA of the verb `base` itself, for a headword read as that verb ("/waɪnd/").
    public func baseIPA(_ base: String) -> String? {
        verb(base: base)?.ipa["base"].map { "/\($0)/" }
    }

    /// What Listen says for the tapped form as a chosen reading: a verb's respelling when every slot
    /// the form fills agrees, else the form as written.
    public func spokenForm(of form: String, as choice: ReadingChoice) -> String {
        guard choice.kind == .verb, let spoken = agreed(TextTools.normalize(form), choice.base, { $0.spokenAs }) else { return form }
        return spoken
    }

    /// What the card's Listen says (SPEC S6): the headword, then the word as in the text when it
    /// differs ("wind", "wound"), each respelled for its proven slot (a verb's headword is its base);
    /// unsure with nothing chosen, the tapped form in each reading in the rows' order, once when
    /// they sound the same; once chosen, only that reading.
    public func listenText(headword: String, in text: String, at range: WordRange, chosen: ReadingChoice?) -> String {
        let ns = text as NSString
        guard range.start >= 0, range.start < range.end, range.end <= ns.length else { return headword }
        let form = ns.substring(with: range.nsRange)
        let rows = choices(in: text, at: range)
        if !rows.isEmpty {
            let spoken = (chosen.map { [$0] } ?? rows).map { spokenForm(of: form, as: $0) }
            return spoken.reduce(into: [String]()) { out, word in if !out.contains(word) { out.append(word) } }
                .joined(separator: ", ")
        }
        let formSpoken = spokenForm(in: text, at: range)
        guard TextTools.normalize(headword) != TextTools.normalize(form) else { return formSpoken }
        let isVerb = resolve(text, range).map { $0.kind == .verb } ?? (base(in: text, at: range) != nil)
        let head = isVerb ? verb(base: TextTools.normalize(headword))?.spokenAs["base"] ?? headword : headword
        return "\(head), \(formSpoken)"
    }
}

/// Saved words being learned, arranged to tell quickly whether a word of the text is one of
/// them (SPEC S4): words without a sense by their forms as before; a word with a sense only where
/// the text reads it as that sense; a word saved unsure by its exact spelling.
public struct LearningIndex: Equatable, Sendable {
    var plain: Set<String> = []
    var sensed: Set<String> = []
    var sensedBases: Set<String> = []
    var exact: Set<String> = []

    public init() {}

    /// The index of `words`, all of them whatever their state.
    public init(_ words: [VocabWord]) {
        for word in words where word.kind == nil {
            if let sense = word.sense {
                sensed.insert("\(word.word)#\(sense)")
                sensedBases.insert(word.word)
            } else if word.meanings != nil {
                exact.insert(word.word)
            } else {
                plain.insert(word.word)
            }
        }
        // A saved group of words ("did not go") is matched as a group: as before, by its text.
        plain.formUnion(words.filter { $0.kind != nil }.map(\.word))
    }

    public var isEmpty: Bool { plain.isEmpty && sensed.isEmpty && exact.isEmpty }

    func matches(_ occurrence: Occurrence) -> Bool {
        !occurrence.keys.isDisjoint(with: plain) || exact.contains(occurrence.form)
            || occurrence.senses.contains { sensed.contains("\($0.key)#\($0.value)") }
            || !occurrence.anySense.isDisjoint(with: sensedBases)
    }
}

/// A word of a text as saved words see it: its match keys, the bases it is certainly a sense of,
/// and the bases it may be any sense of.
struct Occurrence {
    let form: String
    let keys: Set<String>
    let senses: [String: String]
    let anySense: Set<String>
}

extension TextTools {
    static func occurrence(_ words: Words, _ i: Int) -> Occurrence {
        let w = words.token(i)
        let table = IrregularVerbs.shared
        let keys = matchKeys(words, i)
        if let homograph = table.homographs[w] {
            if let reading = table.resolve(words, i), reading.kind != .unsure {
                let senses = table.sense(of: reading).map { [reading.base: $0] } ?? [:]
                return Occurrence(form: w, keys: keys, senses: senses, anySense: [])
            }
            // Unsure: only a base both readings share (tears → tear) can be either sense.
            let shared: Set<String> = homograph.noun == homograph.verb ? [homograph.verb] : []
            return Occurrence(form: w, keys: keys, senses: [:], anySense: shared)
        }
        var anySense = keys
        var senses: [String: String] = [:]
        if let link = table.formToBase[w], !table.isName(words, i) {
            if let sense = table.linkSense(w) {
                anySense.remove(link)
                senses[link] = sense
            }
        }
        return Occurrence(form: w, keys: keys, senses: senses, anySense: anySense)
    }

    /// Whether each word of `text` (`words`: its `wordRanges`) is a form of a word in `index`,
    /// read in its sentence, in one pass. Untrusted ranges are found in the text's own words.
    public static func learningMatches(in text: String, words ranges: [WordRange], index: LearningIndex) -> [Bool] {
        guard !index.isEmpty else { return ranges.map { _ in false } }
        let ns = text as NSString
        let inside = { (range: WordRange) in range.start >= 0 && range.start < range.end && range.end <= ns.length }
        let ordered = ranges.indices.allSatisfy { k in inside(ranges[k]) && (k == 0 || ranges[k - 1].end <= ranges[k].start) }
        if ordered {
            let words = Words(ns, ranges: ranges)
            return words.ranges.indices.map { index.matches(occurrence(words, $0)) }
        }
        let words = Words(ns)
        return ranges.map { range in words.index(of: range).map { index.matches(occurrence(words, $0)) } ?? false }
    }

    /// Where a saved word appears in `sentence`, read in it (SPEC S4, S7): a word with a sense only
    /// where it is that sense; a word saved unsure by its spelling; a group of words as a group.
    public static func occurrences(of word: VocabWord, in sentence: String) -> [WordRange] {
        guard word.kind == nil, !word.word.contains(" ") else { return occurrences(of: word.word, in: sentence) }
        let index = LearningIndex([word])
        let words = Words(sentence as NSString)
        return words.ranges.indices.filter { index.matches(occurrence(words, $0)) }.map { words.ranges[$0] }
    }
}

/// Turning a reading into the text to translate and back (SPEC S3): a verb is translated as
/// "to {base}", a noun as "the {noun}", and the infinitive marker or article the translator may
/// keep is taken off again; in Spanish, a verb of the table uses the table's meanings.
public enum ReadingTranslation {
    /// What to translate for a saved word with a sense: "to leave", "the left"; else the word.
    public static func source(word: String, sense: String?) -> String {
        if sense == Sense.noun { return "the \(word)" }
        return sense == Sense.verb || sense == Sense.homonym ? "to \(word)" : word
    }

    public static func isSpanish(_ language: String?) -> Bool {
        language == "es" || language?.hasPrefix("es-") == true
    }

    /// Leading articles (a noun) and infinitive markers (a verb) a translation may keep, by
    /// language (same lists as lingleaf-android).
    private static let articles: [String: [String]] = [
        "es": ["el", "la", "los", "las", "lo"],
        "pt": ["o", "a", "os", "as"],
        "fr": ["le", "la", "les", "l'", "l’"],
        "it": ["il", "lo", "la", "i", "gli", "le", "l'", "l’"],
        "de": ["der", "die", "das"],
        "nl": ["de", "het"],
        "ca": ["el", "la", "els", "les", "l'", "l’"],
    ]
    private static let markers: [String: [String]] = [
        "de": ["zu"], "nl": ["te"], "sv": ["att"], "da": ["at"], "nb": ["å"], "no": ["å"],
    ]

    /// A translation of "the …" or "to …" without what only the query needed: an English "the"/"to"
    /// the translator kept, and the language's leading article (a noun) or infinitive marker (a
    /// verb): "la izquierda" → "izquierda", "zu verlassen" → "verlassen".
    public static func cleaned(_ translation: String, noun: Bool, language: String?) -> String {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = String(trimmed.reversed().drop { $0 == "." || $0 == "。" }.reversed()).trimmingCharacters(in: .whitespaces)
        let english = noun ? "the " : "to "
        if text.lowercased().hasPrefix(english) { text = String(text.dropFirst(english.count)).trimmingCharacters(in: .whitespaces) }
        let code = language.map { String($0.prefix { $0 != "-" }).lowercased() }
        let leading = code.flatMap { noun ? articles[$0] : markers[$0] } ?? []
        for word in leading where text.count > word.count && text.lowercased().hasPrefix(word.lowercased()) {
            let rest = String(text.dropFirst(word.count))
            // "l'" joins the noun; other words are followed by a space.
            if word.hasSuffix("'") || word.hasSuffix("’") || rest.hasPrefix(" ") {
                text = rest.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return text.isEmpty ? trimmed : text
    }
}

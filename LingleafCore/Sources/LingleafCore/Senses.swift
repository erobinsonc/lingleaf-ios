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

    static let maxText = 200

    /// Within bounds, or nil when it can't be one of a card's readings (a restored or edited file).
    func bounded() -> SavedMeaning? {
        guard Sense.all.contains(sense), IrregularVerbs.isForm(base) else { return nil }
        var meaning = self
        // Made from the sense and base, never taken from the file.
        meaning.label = sense == Sense.noun ? "the \(base)" : "to \(base)"
        meaning.text = TextTools.truncated(TextTools.cleanLabel(text), Self.maxText)
        meaning.language = language.flatMap { $0.count <= 20 ? $0 : nil }
        return meaning
    }
}

/// A reading the learner can choose on the card of a word whose sentence doesn't tell (SPEC S3).
public struct ReadingChoice: Equatable, Sendable, Identifiable {
    public let kind: Reading.Kind
    public let base: String
    public let sense: String
    /// The form as tapped, when its slot changes the verb's meaning ("lies": "estar, encontrarse").
    public let form: String?

    public init(kind: Reading.Kind, base: String, sense: String, form: String? = nil) {
        self.kind = kind
        self.base = base
        self.sense = sense
        self.form = form
    }

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
        guard let reading = resolve(words, i), reading.kind == .unsure else { return [] }
        guard let h = homographs[form] else {
            guard let entry = tableForms[form] else { return [] }
            let verbRow = ReadingChoice(kind: .verb, base: entry.base, sense: Sense.verb, form: form)
            switch reading.step {
            // "She tells lies": the twin's noun or the verb ("the lie — mentira" / "to lie — estar, encontrarse").
            case .unsureNoun: return [ReadingChoice(kind: .noun, base: entry.shared?.noun ?? form, sense: Sense.noun), verbRow]
            // "The bell rings": the verb or the word as a noun ("to ring" / "the rings").
            case .unsureNounFirst: return [verbRow, ReadingChoice(kind: .noun, base: form, sense: Sense.noun)]
            default:
                // "lying", "lies", "hanging", "hangs" the next word doesn't tell: the verb and its twin.
                guard entry.shared != nil else { return [] }
                return [
                    ReadingChoice(kind: .verb, base: entry.base, sense: Sense.verb),
                    ReadingChoice(kind: .homonym, base: entry.base, sense: Sense.homonym),
                ]
            }
        }
        // "lay" after a plural subject (they, "two men"): "to lie" or "to lay".
        let twoVerbs = form == "lay" ? reading.layVerbs : h.noun == nil
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
        case .homonym: Sense.homonym
        case .noun: reading.step == .name ? nil : Sense.noun
        case .word, .expression, .unsure: nil
        }
    }

    /// What Listen in Review and Words says for a saved word (SPEC S7): a verb or the regular twin
    /// with the table's spoken base ("tare" for "tear"), a noun or a word without a sense as written.
    public func spokenHeadword(_ word: String, sense: String?) -> String {
        guard sense == Sense.verb || sense == Sense.homonym else { return word }
        return verb(base: TextTools.normalize(word))?.spokenAs["base"] ?? word
    }

    /// What Listen in Review and Words says for a saved word (SPEC S7): a word saved unsure, its
    /// form in each saved reading (once when they sound the same), as on the card; else
    /// `spokenHeadword`.
    public func spokenSaved(_ word: VocabWord) -> String {
        guard word.isUnsure, let meanings = word.meanings else { return spokenHeadword(word.word, sense: word.sense) }
        let form = word.form ?? word.word
        let spoken = meanings.map { meaning in
            let kind: Reading.Kind = meaning.sense == Sense.noun ? .noun : meaning.sense == Sense.homonym ? .homonym : .verb
            return spokenForm(of: form, as: ReadingChoice(kind: kind, base: meaning.base, sense: meaning.sense))
        }
        return spoken.reduce(into: [String]()) { out, said in if !out.contains(said) { out.append(said) } }.joined(separator: ", ")
    }

    /// Whether a word saved with a sense is always named by it in Words and Review ("to wind",
    /// "the left", "to lie"; SPEC S4): a homograph of the table, a base used mostly as a noun
    /// (`nounFirst`) or one with a regular twin.
    public func namesItsSense(_ word: String) -> Bool {
        let w = TextTools.normalize(word)
        let entry = verb(base: w)
        return homographs[w] != nil || entry?.nounFirst == true || entry?.homonym != nil
    }

    /// Whether the homograph `form`'s noun is pronounced as its sentence says (`nounIpa`: tear, lead, wind).
    public func hasNounIPA(_ form: String) -> Bool {
        homographs[TextTools.normalize(form)].map { !$0.nounIpa.isEmpty } ?? false
    }

    /// How the homograph at `range` of `text` is pronounced as a noun in its sentence ("tears in her
    /// eyes" → tɪr; "a tear in my shirt" → tɛr; "made of lead" → lɛd), or nil when nothing proves it.
    public func nounIPA(in text: String, at range: WordRange) -> String? {
        let words = Words(text as NSString)
        return words.index(of: range).flatMap { nounIPA(words, $0) }
    }

    func nounIPA(_ words: Words, _ i: Int) -> String? {
        guard let h = homographs[words.token(i)], !h.nounIpa.isEmpty else { return nil }
        let before = i >= 1 && words.gapOK(i - 1, i) ? words.token(i - 1) : nil
        let after = i + 1 < words.count && words.gapOK(i, i + 1) ? words.token(i + 1) : nil
        let sentence = Set(words.ranges.indices.filter { $0 != i }.map(words.token))
        for rule in h.nounIpa {
            if let allowed = rule.after, !(before.map(allowed.contains) ?? false) { continue }
            if let allowed = rule.before, !(after.map(allowed.contains) ?? false) { continue }
            if let near = rule.near, near.isDisjoint(with: sentence) { continue }
            return rule.ipa
        }
        return nil
    }

    /// The table's Spanish meaning of a reading (SPEC S3): a verb's (the -s form's own when `form`
    /// is it: "lies" "estar, encontrarse"), the twin's, an expression's ("bound for") or the twin's
    /// noun's ("lie": "mentira"); all joined with " · ", or only the first; nil when the table has none.
    public func tableMeaning(_ kind: Reading.Kind, base: String, form: String? = nil, first: Bool = false) -> String? {
        let meanings: [String] = switch kind {
        case .verb: sEs(base, form: form).map { [$0] } ?? verb(base: base)?.es ?? []
        case .homonym: verb(base: base).map { $0.homonym?.es ?? $0.es } ?? []
        case .expression: expression(base)?.es ?? []
        case .noun: twinNounEs(base) ?? []
        case .word, .unsure: []
        }
        guard let head = meanings.first else { return nil }
        return first ? head : meanings.joined(separator: " · ")
    }

    /// The -s form's Spanish meaning of the verb `base` ("lies": "estar, encontrarse"), when `form` is that form.
    func sEs(_ base: String, form: String?) -> String? {
        guard let form, let entry = verb(base: base), entry.s == TextTools.normalize(form) else { return nil }
        return entry.sEs
    }

    /// The twin's noun meanings in Spanish ("lie": ["mentira"]), when `noun` is a twin's noun.
    public func twinNounEs(_ noun: String) -> [String]? {
        verbs.lazy.compactMap { $0.homonym?.noun == noun ? $0.homonym?.nounEs : nil }.first
    }

    /// The expression `unit` is ("bound for"), if the table has it.
    func expression(_ unit: String) -> Homograph.Expression? {
        let parts = unit.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return homographs[parts[0]]?.expressions.first { $0.next == parts[1] }
    }

    /// The English text to translate for a reading outside Spanish: the sense's own query ("to lie
    /// down", "to tell a lie", "heading for"), else "to {base}" / "the {noun}".
    public func query(_ kind: Reading.Kind, base: String) -> String {
        let entry = verb(base: base)
        switch kind {
        case .noun: return "the \(base)"
        case .homonym: return entry?.homonym?.query ?? "to \(base)"
        case .expression: return expression(base)?.query ?? base
        default: return entry?.query ?? "to \(base)"
        }
    }

    /// The sense's short English gloss ("recline", "say what isn't true"), to tell two rows apart.
    public func gloss(_ kind: Reading.Kind, base: String) -> String? {
        switch kind {
        case .verb: verb(base: base)?.gloss
        case .homonym: verb(base: base)?.homonym?.gloss
        case .expression: expression(base)?.gloss
        default: nil
        }
    }

    /// The two rows' meanings told apart (SPEC S3): when both come out the same ("mentir" /
    /// "mentir"), each adds its sense's gloss ("mentir (say what isn't true)"); a noun adds none.
    public func distinguished(_ rows: [ReadingChoice], _ meanings: [String?]) -> [String?] {
        guard rows.count == 2, meanings.count == 2, let a = meanings[0], let b = meanings[1],
              a.lowercased() == b.lowercased() else { return meanings }
        return zip(rows, meanings).map { row, meaning in
            gloss(row.kind, base: row.base).map { "\(meaning ?? "") (\($0))" } ?? meaning
        }
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
        guard choice.kind != .noun, let spoken = agreed(TextTools.normalize(form), choice.base, { $0.spokenAs }) else { return form }
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
        let reading = resolve(text, range)
        // An expression ("bound for") is said as the unit.
        if reading?.kind == .expression { return headword }
        let isVerb = reading?.isVerb ?? false
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
        let isHomograph = table.homographs[w] != nil
        guard let reading = table.resolve(words, i) else {
            // An ordinary word: any sense of its forms.
            return Occurrence(form: w, keys: keys, senses: [:], anySense: keys)
        }
        // A certain reading: its sense of its base; the spelling itself may be any sense ("stolen").
        if let sense = table.sense(of: reading) {
            let anySense = isHomograph ? [] : keys.subtracting([reading.base])
            return Occurrence(form: w, keys: keys, senses: [reading.base: sense], anySense: anySense)
        }
        // Unsure: no word saved with a sense, whatever the bases (SPEC Shared logic). A name or an
        // ordinary word ("the lights"): no sense of the table's verb ("light"), as written otherwise.
        switch reading.kind {
        // An expression ("bound for") marks only words saved without a sense.
        case .unsure, .expression: return Occurrence(form: w, keys: keys, senses: [:], anySense: [])
        default:
            let verbBase: Set<String> = table.tableForms[w].map { [$0.base] } ?? []
            return Occurrence(form: w, keys: keys, senses: [:], anySense: isHomograph ? [] : keys.subtracting(verbBase))
        }
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
    /// What to translate for a saved word with a sense: its sense's English query ("to leave",
    /// "to lie down", "the left"); an expression saved as a unit, its query ("heading for"); else the word.
    public static func source(word: String, sense: String?) -> String {
        let table = IrregularVerbs.shared
        switch sense {
        case Sense.noun: return table.query(.noun, base: word)
        case Sense.verb: return table.query(.verb, base: word)
        case Sense.homonym: return table.query(.homonym, base: word)
        default: return table.expression(word) == nil ? word : table.query(.expression, base: word)
        }
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

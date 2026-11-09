import Foundation

/// How one word, or a group of words, is used at one place in a bundled story (SPEC S19): its base
/// form, part of speech, IPA and Spanish meaning in that sentence, so the word card never shows a
/// gloss that is false there ("free" in "my oven is free" is "libre", not "gratis").
public struct StorySense: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// An ordinary word.
        case word
        /// A phrasal verb, idiom or other group of words; the entry's group says where it is.
        case chunk
        /// A name that is also a word ("Mr. Long", "The Blue Table", "Cape Town").
        case name
        /// A word from another language ("Bunica", "Amma", "san").
        case foreign
    }

    /// Where a word or meaning is used: US-only, UK-only or local ("first floor").
    public enum Variety: String, Sendable {
        case american = "AmE"
        case british = "BrE"
        case local
    }

    public let lemma: String
    public let partOfSpeech: String
    /// IPA without slashes; nil when there is none.
    public let ipa: String?
    /// The meaning in this place, in Spanish.
    public let spanish: String
    public let kind: Kind
    public let variety: Variety?
    /// A Spanish remark on the sense ("en inglés británico … es el primer piso").
    public let note: String?
    /// A short English gloss written with the sense ("a level of a building"), which is what the card
    /// translates outside Spanish for a bare word that needs one; nil when the sense has none.
    public let english: String?

    /// The IPA as the card shows it: between slashes.
    public var displayIPA: String? { ipa.map { "/\($0)/" } }

    /// The dictionary's part of speech that this sense's definition would have, or nil when the card
    /// shows no definition: a name, a word from another language, a group of words and a lemma of
    /// several words have none.
    public var definitionPartOfSpeech: String? {
        guard kind == .word || kind == .chunk, !lemma.contains(" ") else { return nil }
        switch partOfSpeech {
        case "noun", "verb", "adjective", "adverb", "preposition", "interjection": return partOfSpeech
        case "modal": return "verb"
        default: return nil
        }
    }

    /// Whether the voice should be told how the word sounds: a base form of one word only (a group is said as text).
    public var speaksIPA: Bool { ipa != nil && !lemma.contains(" ") }
}

/// The group of words an entry belongs to, in the paragraph's UTF-16 units ("his face went red").
public struct StoryGroup: Equatable, Sendable {
    public let range: WordRange
    public let text: String
    /// The group's meaning in this sentence, in Spanish.
    public let spanish: String
}

/// A tapped word's entry: its sense and, when it belongs to a group of words, the group.
public struct StorySenseHit: Equatable, Sendable {
    /// The sense's key in the story's file.
    public let id: String
    public let sense: StorySense
    public let group: StoryGroup?
    /// The story has another sense of the same base form: a bare translation of the word could pick the wrong one.
    public let siblings: Bool
}

/// The senses of one bundled story, read strictly and checked against the story's own text (SPEC S19).
/// A file that breaks any rule is refused whole, and the story behaves as if it had none.
public struct StorySenses: Sendable {
    /// Largest file accepted, in bytes (the largest shipped one is about 85 KB).
    public static let maxBytes = 256 * 1024
    /// Deepest nesting accepted (the format nests 4 levels).
    static let maxDepth = 8
    static let schemaVersion = 1
    static let maxSenses = 2000
    static let maxEntries = 5000
    static let maxLemma = 60
    static let maxMeaning = 140
    static let maxGroup = 120
    static let maxNote = 200
    static let maxEnglish = 60
    static let maxIPA = 80
    static let maxWord = 40
    static let maxParagraphs = 1000
    static let partsOfSpeech: Set<String> = [
        "noun", "verb", "adjective", "adverb", "preposition", "phrasal verb", "phrase", "proper noun", "modal",
        "interjection", "suffix",
    ]
    /// The IPA letters the irregular-verb table allows, a space (a group has several words) and the
    /// letters of the Japanese reading in "A Number in Osaka".
    static let ipaScalars: Set<Unicode.Scalar> = {
        var set = IrregularVerbs.ipaScalars
        for scalar in " ɕɴɯ".unicodeScalars { set.insert(scalar) }
        return set
    }()

    /// The story's id, as its file and the shelf name it.
    public let story: String
    public let senses: [String: StorySense]

    private struct Place: Hashable {
        let paragraph: Int
        let start: Int
        let end: Int
    }

    private let entries: [Place: StorySenseHit]
    private let byParagraph: [Int: [(range: WordRange, hit: StorySenseHit)]]

    /// The entry of the word at `range` of paragraph `paragraph`, if the story has one.
    public func hit(paragraph: Int, range: WordRange) -> StorySenseHit? {
        entries[Place(paragraph: paragraph, start: range.start, end: range.end)]
    }

    /// How many words have an entry.
    public var count: Int { entries.count }

    /// Every entry, by paragraph and start, for tests and tools.
    public var places: [(paragraph: Int, range: WordRange, hit: StorySenseHit)] {
        entries.map { (paragraph: $0.key.paragraph, range: WordRange($0.key.start, $0.key.end), hit: $0.value) }
            .sorted { ($0.paragraph, $0.range.start) < ($1.paragraph, $1.range.start) }
    }

    // MARK: Loading

    /// `load`, but only for the text the file was made for: nil unless the book's `paragraphs` are those of
    /// `bundledText`, so a book that has a story's title and author with other text gets no senses.
    public static func load(_ data: Data, story: String, paragraphs: [String], bundledText: String) -> StorySenses? {
        guard TextTools.splitParagraphs(bundledText) == paragraphs else { return nil }
        return try? load(data, story: story, paragraphs: paragraphs)
    }

    /// Reads the senses file of story `story` (`Data` of a `<story>.senses.json`) against the story's
    /// `paragraphs` (as `TextTools.splitParagraphs` splits its text), refusing the whole file at the
    /// first problem.
    public static func load(_ data: Data, story: String, paragraphs: [String]) throws -> StorySenses {
        guard data.count <= maxBytes else { throw StorySensesError.tooLarge }
        guard JSONGuard.isShallow(data, maxDepth: maxDepth) else { throw StorySensesError.tooDeep }
        let file = try JSONDecoder().decode(SensesFile.self, from: data)
        func check(_ ok: Bool, _ problem: @autoclosure () -> String) throws {
            if !ok { throw StorySensesError.invalid(problem()) }
        }
        try check(file.story == story, "story \(file.story)")
        try check(isID(file.story, dashes: true) && file.story.utf8.count <= maxLemma, "story id")
        try check(file.senses.count <= maxSenses && file.entries.count <= maxEntries, "too many senses or entries")
        try check(paragraphs.count <= maxParagraphs, "too many paragraphs")
        var senses: [String: StorySense] = [:]
        for (key, raw) in file.senses {
            try check(isID(key, dashes: false) && key.utf8.count <= 40, "sense key \(key)")
            senses[key] = try raw.sense(key)
        }
        // Base forms that have more than one sense in this story ("get", "still", "floor").
        var seen: Set<String> = []
        var siblingLemmas: Set<String> = []
        for sense in senses.values {
            let lemma = sense.lemma.lowercased()
            if !seen.insert(lemma).inserted { siblingLemmas.insert(lemma) }
        }
        var places: [Place: StorySenseHit] = [:]
        var ranges: [Int: [WordRange]] = [:]
        for entry in file.entries {
            let key = "\(entry.p):\(entry.start)"
            try check(paragraphs.indices.contains(entry.p), "\(key): no such paragraph")
            let paragraph = paragraphs[entry.p] as NSString
            // The entry's word is a whole word of the paragraph, spelled as the entry says.
            let words = ranges[entry.p] ?? TextTools.wordRanges(paragraph as String)
            ranges[entry.p] = words
            let range = WordRange(entry.start, entry.end)
            try check(words.contains(range), "\(key): not a word")
            try check(isShort(entry.text, max: maxWord) && paragraph.substring(with: range.nsRange) == entry.text, "\(key): text")
            guard let sense = senses[entry.sense] else { throw StorySensesError.invalid("\(key): unknown sense") }
            var group: StoryGroup?
            if let raw = entry.chunk {
                let span = WordRange(raw.start, raw.end)
                // Starts and ends on whole words, holds the entry's word, and is what it says it is.
                try check(words.contains { $0.start == span.start } && words.contains { $0.end == span.end }, "\(key): group edges")
                try check(span.start <= range.start && range.end <= span.end && span.end <= paragraph.length, "\(key): group range")
                try check(isShort(raw.text, max: maxGroup) && paragraph.substring(with: span.nsRange) == raw.text, "\(key): group text")
                try check(isMeaning(raw.es), "\(key): group meaning")
                group = StoryGroup(range: span, text: raw.text, spanish: raw.es)
            }
            let place = Place(paragraph: entry.p, start: entry.start, end: entry.end)
            try check(places[place] == nil, "\(key): twice")
            let siblings = siblingLemmas.contains(sense.lemma.lowercased())
            places[place] = StorySenseHit(id: entry.sense, sense: sense, group: group, siblings: siblings)
        }
        var byParagraph: [Int: [(range: WordRange, hit: StorySenseHit)]] = [:]
        for (place, hit) in places { byParagraph[place.paragraph, default: []].append((WordRange(place.start, place.end), hit)) }
        return StorySenses(story: file.story, senses: senses, entries: places, byParagraph: byParagraph)
    }

    /// Lower-case letters and digits (and dashes in a story id, underscores in a sense key), nothing else.
    static func isID(_ s: String, dashes: Bool) -> Bool {
        guard !s.isEmpty else { return false }
        let bytes = Array(s.utf8)
        let separator: UInt8 = dashes ? 0x2D : 0x5F
        for (i, b) in bytes.enumerated() {
            let alnum = (0x61...0x7A).contains(b) || (0x30...0x39).contains(b)
            if alnum { continue }
            // A dash joins words: never first, last or doubled. An underscore may be anywhere.
            if b == separator, dashes ? (i > 0 && i < bytes.count - 1 && bytes[i - 1] != separator) : true { continue }
            return false
        }
        return true
    }

    /// Characters no story text may hold: controls, invisible formatting (bidi, zero-width) and line breaks.
    private static let invisible: [Unicode.GeneralCategory] = [
        .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate,
    ]

    /// Text with no control or format character, at most `max` code points.
    static func isShort(_ s: String, max: Int) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.unicodeScalars.count <= max
            && !s.unicodeScalars.contains { invisible.contains($0.properties.generalCategory) }
            // Already what `cleanText` would make of it: no blank fillers, extra accents or doubled spaces.
            && TextTools.cleanText(s) == s
    }

    /// A Spanish meaning: text with no surrounding space.
    static func isMeaning(_ s: String) -> Bool {
        isShort(s, max: maxMeaning) && s.trimmingCharacters(in: .whitespacesAndNewlines) == s
    }

    /// A lemma: ASCII letters and digits, then those and spaces, apostrophes, hyphens and "?".
    static func isLemma(_ s: String) -> Bool {
        guard (1...maxLemma).contains(s.unicodeScalars.count), let first = s.unicodeScalars.first else { return false }
        func alnum(_ c: Unicode.Scalar) -> Bool { c.isASCII && (c.properties.isAlphabetic || (0x30...0x39).contains(c.value)) }
        return alnum(first) && s.unicodeScalars.allSatisfy { alnum($0) || " '’?-".unicodeScalars.contains($0) }
    }

    /// An IPA transcription: 1–80 allowed characters, already in NFC.
    static func isIPA(_ s: String) -> Bool {
        let count = s.unicodeScalars.count
        return (1...maxIPA).contains(count) && s.unicodeScalars.allSatisfy(ipaScalars.contains)
            && s.unicodeScalars.contains { $0 != " " }
            && s.precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual(s.unicodeScalars)
    }
}

public enum StorySensesError: Error, Equatable {
    case tooLarge
    case tooDeep
    case malformed(String)
    case invalid(String)
}

// MARK: Strict decoding

/// Any key, so a container can list every key of an object, also the unknown ones.
private struct SenseKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension Decoder {
    /// The object's container, refusing a key outside `required` + `optional` or a missing required one.
    func strict(_ required: Set<String>, optional: Set<String> = []) throws -> KeyedDecodingContainer<SenseKey> {
        let keyed = try self.container(keyedBy: SenseKey.self)
        let keys = Set(keyed.allKeys.map(\.stringValue))
        if let unknown = keys.subtracting(required).subtracting(optional).min() {
            throw StorySensesError.malformed("unknown key \(unknown)")
        }
        if let missing = required.subtracting(keys).min() { throw StorySensesError.malformed("missing key \(missing)") }
        return keyed
    }
}

private extension KeyedDecodingContainer where K == SenseKey {
    func value<T: Decodable>(_ key: String) throws -> T { try decode(T.self, forKey: SenseKey(key)) }
    func optional<T: Decodable>(_ key: String) throws -> T? { try decodeIfPresent(T.self, forKey: SenseKey(key)) }
}

private struct SensesFile: Decodable {
    let story: String
    let senses: [String: RawSense]
    let entries: [RawEntry]

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["schemaVersion", "story", "senses", "entries"])
        let version: Int = try c.value("schemaVersion")
        guard version == StorySenses.schemaVersion else { throw StorySensesError.malformed("schema version \(version)") }
        story = try c.value("story")
        entries = try c.value("entries")
        let keyed = try c.nestedContainer(keyedBy: SenseKey.self, forKey: SenseKey("senses"))
        var senses: [String: RawSense] = [:]
        for key in keyed.allKeys {
            senses[key.stringValue] = try keyed.decode(RawSense.self, forKey: key)
        }
        self.senses = senses
    }
}

private struct RawSense: Decodable {
    let lemma: String
    let pos: String
    let ipa: String?
    let es: String
    let kind: String
    let variety: String?
    let note: String?
    let en: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["lemma", "pos", "ipa", "es", "kind"], optional: ["variety", "note", "en"])
        lemma = try c.value("lemma")
        pos = try c.value("pos")
        // "ipa" is required but may be null.
        ipa = try c.decode(String?.self, forKey: SenseKey("ipa"))
        es = try c.value("es")
        kind = try c.value("kind")
        variety = try c.optional("variety")
        note = try c.optional("note")
        en = try c.optional("en")
    }

    func sense(_ key: String) throws -> StorySense {
        func check(_ ok: Bool, _ problem: String) throws {
            if !ok { throw StorySensesError.invalid("sense \(key): \(problem)") }
        }
        try check(StorySenses.isLemma(lemma), "lemma")
        try check(StorySenses.partsOfSpeech.contains(pos), "part of speech")
        try check(ipa.map(StorySenses.isIPA) ?? true, "ipa")
        try check(StorySenses.isMeaning(es), "meaning")
        guard let kind = StorySense.Kind(rawValue: kind) else { throw StorySensesError.invalid("sense \(key): kind") }
        var parsedVariety: StorySense.Variety?
        if let variety {
            guard let known = StorySense.Variety(rawValue: variety) else { throw StorySensesError.invalid("sense \(key): variety") }
            parsedVariety = known
        }
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines) == note
            try check(StorySenses.isShort(note, max: StorySenses.maxNote) && trimmed, "note")
        }
        if let en {
            let trimmed = en.trimmingCharacters(in: .whitespacesAndNewlines) == en
            try check(StorySenses.isShort(en, max: StorySenses.maxEnglish) && trimmed, "english gloss")
        }
        return StorySense(lemma: lemma, partOfSpeech: pos, ipa: ipa, spanish: es, kind: kind, variety: parsedVariety, note: note, english: en)
    }
}

private struct RawEntry: Decodable {
    let p: Int
    let start: Int
    let end: Int
    let text: String
    let sense: String
    let chunk: RawChunk?

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["p", "start", "end", "text", "sense"], optional: ["chunk"])
        p = try c.value("p")
        start = try c.value("start")
        end = try c.value("end")
        text = try c.value("text")
        sense = try c.value("sense")
        chunk = try c.optional("chunk")
        guard (0..<StorySenses.maxParagraphs).contains(p), start >= 0, start < end, end <= TextTools.maxParagraph else {
            throw StorySensesError.invalid("entry \(p):\(start) out of range")
        }
    }
}

private struct RawChunk: Decodable {
    let start: Int
    let end: Int
    let text: String
    let es: String

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["start", "end", "text", "es"])
        start = try c.value("start")
        end = try c.value("end")
        text = try c.value("text")
        es = try c.value("es")
        guard start >= 0, start < end, end <= TextTools.maxParagraph else { throw StorySensesError.invalid("group out of range") }
    }
}

// MARK: What the card shows

/// The small label under a story sense's headword (SPEC S19).
public enum StoryLabel: Equatable, Sendable {
    case name
    case foreign
    case american
    case british
    case local
}

extension StorySenseHit {
    /// The label: a name or a word from another language first, else where the word or meaning is used.
    public var label: StoryLabel? {
        switch sense.kind {
        case .name: return .name
        case .foreign: return .foreign
        case .word, .chunk:
            switch sense.variety {
            case .american: return .american
            case .british: return .british
            case .local: return .local
            case nil: return nil
            }
        }
    }

    /// What the card translates into a language that is not Spanish (the file's meaning is in Spanish).
    /// A name and a word from another language are not translated; a group of words is, as the group.
    /// A bare word is translated from the sense's English gloss; without one, from its group if it has
    /// one, else from its base form, but never when the story has another sense of that base form or the
    /// Spanish meaning warns against a false friend (`no "gratis"`): a bare translation would give its most
    /// common meaning ("floor": piso, suelo). The card then shows the translated sentence instead.
    public var translationSource: String? {
        switch sense.kind {
        case .name, .foreign: return nil
        case .chunk: return group?.text ?? sense.lemma
        case .word:
            if let english = sense.english { return english }
            if let group { return group.text }
            return siblings || sense.spanish.contains("no \"") ? nil : sense.lemma
        }
    }
}

// MARK: Underlining saved story senses

extension StorySenses {
    /// The words of paragraph `paragraph` to underline as words being learned (SPEC S19), given the ranges
    /// `generic` that saved words mark by their forms (S4). A word saved from a story sense marks, in this
    /// story, only the places that have that same sense, a group as a whole ("went red"); a place of the
    /// same base form with another sense is not marked. Everywhere else (a word with no entry here, another
    /// book) the generic underline stands. `words` are the paragraph's word ranges; `saved` the saved words.
    public func underlines(paragraph: Int, generic: Set<WordRange>, words: [WordRange], saved: [VocabWord]) -> Set<WordRange> {
        let mine = saved.filter { !$0.learned && Sense.isStory($0.sense) && $0.story == story }
        guard !mine.isEmpty, let here = byParagraph[paragraph] else { return generic }
        // "sense key" and the base form it was saved under: a word is only that sense of that base form.
        let keys = Set(mine.compactMap { word in Sense.storyKey(word.sense).map { "\($0)#\(word.word)" } })
        let lemmas = Set(mine.map(\.word))
        var out = generic
        for (range, hit) in here {
            if keys.contains("\(hit.id)#\(TextTools.key(hit.sense.lemma))") {
                let span = hit.group?.range ?? range
                out.formUnion(words.filter { span.start <= $0.start && $0.end <= span.end })
            } else if lemmas.contains(TextTools.key(hit.sense.lemma)) {
                out.remove(range)
            }
        }
        return out
    }
}

import Foundation

/// IPA and an English definition from the free, open dictionaryapi.dev.
public struct DictionaryEntry: Equatable, Sendable {
    public let word: String
    public let phonetic: String?
    public let partOfSpeech: String?
    public let definition: String?
    /// Whether `definition` was cut to `maxDefinition`, so the card can say it is shortened
    /// (Wiktionary's CC BY-SA asks to say when the text was changed).
    public let definitionTruncated: Bool
    /// Every pronunciation the entry gives (US and UK), to tell its etymology apart ("wind" /waɪnd/).
    public let phonetics: [String]

    public init(
        word: String, phonetic: String?, partOfSpeech: String?, definition: String?, definitionTruncated: Bool = false,
        phonetics: [String] = []
    ) {
        self.word = word
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.definitionTruncated = definitionTruncated
        self.phonetics = phonetics
    }

    /// Longest field kept from an answer. Real definitions are a sentence or two; a hostile
    /// answer can't make the card or the inflection search work through megabytes of text.
    static let maxDefinition = 500
    static let maxShortField = 100

    /// Entries, and meanings of each, kept from one answer (same limits as lingleaf-android).
    static let maxEntries = 10
    static let maxMeanings = 10

    /// Outside text made safe to show (`TextTools.cleanText`: no bidi, zero-width or other format
    /// characters, a few accents per letter at most), then cut to `max`; `cut` says whether
    /// anything was cut. At most `4 × max` units are cleaned, so a huge answer costs little.
    static func clean(_ text: String, _ max: Int) -> (text: String, cut: Bool) {
        let window = max * 4
        let cleaned = TextTools.cleanText(TextTools.truncated(text, window))
        return (TextTools.truncated(cleaned, max), cleaned.utf16.count > max || text.utf16.count > window)
    }

    /// A short field (IPA, part of speech) made safe; nil when nothing is left.
    private static func short(_ text: String?) -> String? {
        text.map { clean($0, maxShortField).text }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The first entry's first meaning (what the card showed before readings).
    static func parse(_ json: [String: Any]) -> DictionaryEntry? { parseAll([json]).first }

    /// Every meaning of every entry, in order, each with its own entry's word and IPA, so a
    /// reading can take the first meaning of its part of speech ("verb", "noun"). An element that
    /// is not an entry is skipped, not the whole answer.
    static func parseAll(_ answer: [Any]) -> [DictionaryEntry] {
        var out: [DictionaryEntry] = []
        for json in answer.prefix(maxEntries).compactMap({ $0 as? [String: Any] }) {
            guard let word = (json["word"] as? String).map({ TextTools.truncated($0, maxShortField) }) else { continue }
            var phonetic = short(json["phonetic"] as? String)
            if phonetic == nil {
                phonetic = (json["phonetics"] as? [[String: Any]])?
                    .compactMap { short($0["text"] as? String) }
                    .first
            }
            let pronunciations = pronunciations(json)
            let meanings = ((json["meanings"] as? [Any]) ?? []).prefix(maxMeanings).compactMap { $0 as? [String: Any] }
            if meanings.isEmpty {
                out.append(DictionaryEntry(word: word, phonetic: phonetic, partOfSpeech: nil, definition: nil, phonetics: pronunciations))
            }
            for meaning in meanings {
                let raw = ((meaning["definitions"] as? [Any])?.first as? [String: Any])?["definition"] as? String
                let definition = raw.map { clean($0, maxDefinition) }.flatMap { $0.text.isEmpty ? nil : $0 }
                out.append(DictionaryEntry(
                    word: word,
                    phonetic: phonetic,
                    partOfSpeech: short(meaning["partOfSpeech"] as? String),
                    definition: definition?.text,
                    definitionTruncated: definition?.cut ?? false,
                    phonetics: pronunciations
                ))
            }
        }
        return out
    }

    /// The entry's pronunciations: its phonetic, then each in its phonetics, at most `maxMeanings`.
    private static func pronunciations(_ json: [String: Any]) -> [String] {
        let texts = ((json["phonetics"] as? [Any]) ?? []).prefix(maxMeanings).compactMap { ($0 as? [String: Any])?["text"] as? String }
        var out: [String] = []
        for text in [json["phonetic"] as? String].compactMap({ $0 }) + texts {
            guard let kept = short(text), !out.contains(kept) else { continue }
            out.append(kept)
        }
        return Array(out.prefix(maxMeanings))
    }

    /// The same IPA: compared in NFC without slashes, brackets, stress marks, dots or spaces, and
    /// with r for ɹ and g for ɡ (same as lingleaf-android); an empty one matches nothing.
    static func sameIPA(_ a: String, _ b: String) -> Bool {
        let key = ipaKey(a)
        return !key.isEmpty && key == ipaKey(b)
    }

    private static func ipaKey(_ ipa: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in ipa.precomposedStringWithCanonicalMapping.unicodeScalars where !"/[]()ˈˌ. ".unicodeScalars.contains(scalar) {
            out.append(scalar == "ɹ" ? "r" : scalar == "ɡ" ? "g" : scalar)
        }
        return String(out)
    }
}

private let inflectionOf = try! NSRegularExpression(
    pattern: "(?:plural|past tense|past participle|present participle|third-person singular|simple past|comparative|superlative)[^.;]*?\\bof\\s+([a-z]+)",
    options: [.caseInsensitive]
)

public actor DictionaryClient {
    private let http: HttpFetcher
    private var cache: [String: [DictionaryEntry]?] = [:]

    public init(http: HttpFetcher) { self.http = http }

    /// Looks `word` up, resolving inflected forms: "walked" → "walk", "animals" → "animal".
    /// With a reading of the word in its sentence (`IrregularVerbs.resolve`), a verb or a noun
    /// looks its base up first ("stole" → "steal", "leaves" → "leaf"), without following "past
    /// tense of …" (a noun "left" is not "leave"), and takes the first meaning of the reading's part
    /// of speech, from the entry whose IPA is the table's for a verb's base ("wind" /waɪnd/), else
    /// nothing; when the base has none of that part of speech, the word as tapped, else nothing
    /// (never another part of speech's). The regular twin's sense has no definition; unsure or an ordinary word is as
    /// without a reading.
    /// A noun of tear, lead or wind takes the entry pronounced `nounIPA` (its sentence's,
    /// `IrregularVerbs.nounIPA`), none when nothing proves it; the twin's noun ("lies": a lie) has
    /// none; an expression ("bound for"), the adjective's definition of the word.
    public func lookup(_ word: String, reading: Reading? = nil, nounIPA: String? = nil) async -> DictionaryEntry? {
        let w = TextTools.normalize(word)
        let table = IrregularVerbs.shared
        if let reading, reading.kind == .homonym { return nil }
        // The reading's base is a key like the word: lower case, composed.
        let reading = reading.map { Reading(kind: $0.kind, base: TextTools.normalize($0.base), step: $0.step) }
        if let reading, reading.kind == .noun, table.twinNounEs(reading.base) != nil { return nil }
        if let reading, reading.kind == .expression {
            return await get(w)?.first { $0.partOfSpeech?.lowercased() == "adjective" }
        }
        if let reading, reading.kind == .noun, table.hasNounIPA(w) {
            guard let nounIPA else { return nil }
            return await get(TextTools.normalize(reading.base))?.first { entry in
                entry.partOfSpeech?.lowercased() == "noun" && entry.phonetics.contains { DictionaryEntry.sameIPA($0, nounIPA) }
            }
        }
        if let reading, reading.kind == .verb || reading.kind == .noun {
            let partOfSpeech = reading.kind == .verb ? "verb" : "noun"
            let ipa = reading.kind == .verb ? table.verb(base: reading.base)?.ipa["base"] : nil
            let matching = (await get(reading.base) ?? []).filter { $0.partOfSpeech?.lowercased() == partOfSpeech }
            if !matching.isEmpty {
                // The table's IPA says which entry: none pronounced so, no definition (the card shows the table's IPA).
                guard let ipa else { return matching.first }
                return matching.first { $0.phonetics.contains { DictionaryEntry.sameIPA($0, ipa) } }
            }
            // The tapped form only when the base has no entry of this part of speech at all.
            guard reading.base != w else { return nil }
            return await get(w)?.first { $0.partOfSpeech?.lowercased() == partOfSpeech }
        }
        if let direct = await get(w)?.first {
            if let definition = direct.definition,
               let match = inflectionOf.firstMatch(in: definition, range: NSRange(location: 0, length: (definition as NSString).length)),
               match.numberOfRanges > 1 {
                let base = (definition as NSString).substring(with: match.range(at: 1)).lowercased()
                if base != w { return await get(base)?.first ?? direct }
            }
            return direct
        }
        for candidate in TextTools.baseFormCandidates(w) {
            if let entry = await get(candidate)?.first { return entry }
        }
        return nil
    }

    /// The first meaning of `word`, a base form as a story's sense gives it (SPEC S19), whose part of
    /// speech is `partOfSpeech`; nothing when it has none: never another part of speech's.
    public func lookup(base word: String, partOfSpeech: String) async -> DictionaryEntry? {
        await get(TextTools.normalize(word))?.first { $0.partOfSpeech?.lowercased() == partOfSpeech }
    }

    /// Longest word looked up, in UTF-16 units (the longest English word has 45 letters).
    static let maxLookupWord = 50
    private static let lookupWord = try! NSRegularExpression(pattern: "^\\p{Latin}(?:\\p{Latin}|\\p{M}|['’])*\\z")

    /// Whether `word` (normalized) may be sent to the dictionary: a Latin-script word, with or
    /// without accents ("café", "naïve", "résumé", "Joaquín"), of a sane length. Another script
    /// ("привет", "你好", "مرحبا"), a mixed one or a hostile one is never sent: the English
    /// dictionary has no entry for it, and nothing the learner didn't tap as a word leaves the device.
    static func canLookUp(_ word: String) -> Bool {
        let length = (word as NSString).length
        guard length > 0, length <= maxLookupWord else { return false }
        return lookupWord.firstMatch(in: word, range: NSRange(location: 0, length: length)) != nil
    }

    /// Every meaning of `word`'s answer; nil when there is none (missing, offline, refused).
    private func get(_ word: String) async -> [DictionaryEntry]? {
        guard Self.canLookUp(word) else { return nil }
        if let cached = cache[word] { return cached }
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .asciiAlphanumerics) ?? word
        guard let response = try? await http.get("https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else { return nil }
        if response.status == 404 { cache[word] = .some(nil) }
        guard response.status == 200 else { return nil }
        guard JSONGuard.isShallow(response.body) else { return nil }
        let parsed = (try? JSONSerialization.jsonObject(with: response.body) as? [Any]).map(DictionaryEntry.parseAll)
        let entries = parsed.flatMap { $0.isEmpty ? nil : $0 }
        cache[word] = .some(entries)
        return entries
    }
}

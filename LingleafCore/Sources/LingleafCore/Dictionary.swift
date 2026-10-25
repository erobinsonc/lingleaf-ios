import Foundation

/// IPA and an English definition from the free, open dictionaryapi.dev.
public struct DictionaryEntry: Equatable, Sendable {
    public let word: String
    public let phonetic: String?
    public let partOfSpeech: String?
    public let definition: String?

    public init(word: String, phonetic: String?, partOfSpeech: String?, definition: String?) {
        self.word = word
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.definition = definition
    }

    /// Longest field kept from an answer. Real definitions are a sentence or two; a hostile
    /// answer can't make the card or the inflection search work through megabytes of text.
    static let maxDefinition = 500
    static let maxShortField = 100

    /// Entries, and meanings of each, kept from one answer (same limits as lingleaf-android).
    static let maxEntries = 10
    static let maxMeanings = 10

    /// The first entry's first meaning (what the card showed before readings).
    static func parse(_ json: [String: Any]) -> DictionaryEntry? { parseAll([json]).first }

    /// Every meaning of every entry, in order, each with its own entry's word and IPA, so a
    /// reading can take the first meaning of its part of speech ("verb", "noun").
    static func parseAll(_ entries: [[String: Any]]) -> [DictionaryEntry] {
        var out: [DictionaryEntry] = []
        for json in entries.prefix(maxEntries) {
            guard let word = (json["word"] as? String).map({ TextTools.truncated($0, maxShortField) }) else { continue }
            var phonetic = (json["phonetic"] as? String).flatMap { $0.isEmpty ? nil : TextTools.truncated($0, maxShortField) }
            if phonetic == nil {
                phonetic = (json["phonetics"] as? [[String: Any]])?
                    .compactMap { $0["text"] as? String }
                    .first { !$0.isEmpty }
                    .map { TextTools.truncated($0, maxShortField) }
            }
            let meanings = (json["meanings"] as? [[String: Any]]) ?? []
            if meanings.isEmpty { out.append(DictionaryEntry(word: word, phonetic: phonetic, partOfSpeech: nil, definition: nil)) }
            for meaning in meanings.prefix(maxMeanings) {
                let definition = (meaning["definitions"] as? [[String: Any]])?.first
                out.append(DictionaryEntry(
                    word: word,
                    phonetic: phonetic,
                    partOfSpeech: (meaning["partOfSpeech"] as? String).map { TextTools.truncated($0, maxShortField) },
                    definition: (definition?["definition"] as? String).map { TextTools.truncated($0, maxDefinition) }
                ))
            }
        }
        return out
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
    /// of speech, from the entry whose IPA is the table's for a verb's base ("wind" /waɪnd/); with
    /// none of that part of speech, the word as tapped, else nothing (never another part of
    /// speech's). The regular twin's sense has no definition; unsure or an ordinary word is as
    /// without a reading.
    public func lookup(_ word: String, reading: Reading? = nil) async -> DictionaryEntry? {
        let w = TextTools.normalize(word)
        if let reading, reading.kind == .homonym { return nil }
        if let reading, reading.kind == .verb || reading.kind == .noun {
            let partOfSpeech = reading.kind == .verb ? "verb" : "noun"
            let ipa = reading.kind == .verb ? IrregularVerbs.shared.verb(base: reading.base)?.ipa["base"] : nil
            if let entries = await get(reading.base), let entry = Self.first(partOfSpeech, ipa: ipa, in: entries) { return entry }
            guard reading.base != w else { return nil }
            return await get(w).flatMap { Self.first(partOfSpeech, ipa: nil, in: $0) }
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

    /// The first meaning that is `partOfSpeech`, from an entry pronounced `ipa` when one is.
    private static func first(_ partOfSpeech: String, ipa: String?, in entries: [DictionaryEntry]) -> DictionaryEntry? {
        let matching = entries.filter { $0.partOfSpeech?.lowercased() == partOfSpeech }
        if let ipa, let pronounced = matching.first(where: { $0.phonetic.map(Self.bareIPA) == Self.bareIPA(ipa) }) {
            return pronounced
        }
        return matching.first
    }

    /// An IPA transcription without slashes, brackets, stress marks, dots or spaces, and with
    /// Wiktionary's "ɹ" as the table's "r", to compare.
    static func bareIPA(_ ipa: String) -> String {
        let kept = ipa.unicodeScalars.filter { !"/[]()ˈˌ. ".unicodeScalars.contains($0) }.map { $0 == "ɹ" ? "r" : Character($0) }
        return String(kept).lowercased()
    }

    /// Every meaning of `word`'s answer; nil when there is none (missing, offline, refused).
    private func get(_ word: String) async -> [DictionaryEntry]? {
        if let cached = cache[word] { return cached }
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? word
        guard let response = try? await http.get("https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else { return nil }
        if response.status == 404 { cache[word] = .some(nil) }
        guard response.status == 200 else { return nil }
        guard JSONGuard.isShallow(response.body) else { return nil }
        let parsed = (try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]]).map(DictionaryEntry.parseAll)
        let entries = parsed.flatMap { $0.isEmpty ? nil : $0 }
        cache[word] = .some(entries)
        return entries
    }
}

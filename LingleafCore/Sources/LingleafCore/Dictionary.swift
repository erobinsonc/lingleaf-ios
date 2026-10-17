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

    static func parse(_ json: [String: Any]) -> DictionaryEntry? {
        guard let word = (json["word"] as? String).map({ TextTools.truncated($0, maxShortField) }) else { return nil }
        var phonetic = (json["phonetic"] as? String).flatMap { $0.isEmpty ? nil : TextTools.truncated($0, maxShortField) }
        if phonetic == nil {
            phonetic = (json["phonetics"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }
                .first { !$0.isEmpty }
                .map { TextTools.truncated($0, maxShortField) }
        }
        let meaning = (json["meanings"] as? [[String: Any]])?.first
        let definition = (meaning?["definitions"] as? [[String: Any]])?.first
        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            partOfSpeech: (meaning?["partOfSpeech"] as? String).map { TextTools.truncated($0, maxShortField) },
            definition: (definition?["definition"] as? String).map { TextTools.truncated($0, maxDefinition) }
        )
    }
}

private let inflectionOf = try! NSRegularExpression(
    pattern: "(?:plural|past tense|past participle|present participle|third-person singular|simple past|comparative|superlative)[^.;]*?\\bof\\s+([a-z]+)",
    options: [.caseInsensitive]
)

public actor DictionaryClient {
    private let http: HttpFetcher
    private var cache: [String: DictionaryEntry?] = [:]

    public init(http: HttpFetcher) { self.http = http }

    /// Looks `word` up, resolving inflected forms: "walked" → "walk", "animals" → "animal".
    public func lookup(_ word: String) async -> DictionaryEntry? {
        let w = TextTools.normalize(word)
        if let direct = await get(w) {
            if let definition = direct.definition,
               let match = inflectionOf.firstMatch(in: definition, range: NSRange(location: 0, length: (definition as NSString).length)),
               match.numberOfRanges > 1 {
                let base = (definition as NSString).substring(with: match.range(at: 1)).lowercased()
                if base != w { return await get(base) ?? direct }
            }
            return direct
        }
        for candidate in TextTools.baseFormCandidates(w) {
            if let entry = await get(candidate) { return entry }
        }
        return nil
    }

    private func get(_ word: String) async -> DictionaryEntry? {
        if let cached = cache[word] { return cached }
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? word
        guard let response = try? await http.get("https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else { return nil }
        if response.status == 404 { cache[word] = .some(nil) }
        guard response.status == 200 else { return nil }
        guard JSONGuard.isShallow(response.body) else { return nil }
        let entry = (try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]])?
            .first
            .flatMap(DictionaryEntry.parse)
        cache[word] = .some(entry)
        return entry
    }
}

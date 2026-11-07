import Foundation
import os

/// The Grammar tab's content (`Resources/grammar-rules.json`, identical in lingleaf-android): rules,
/// examples and practice items bundled in the app. Read once and strictly (SPEC.md, Grammar rules
/// data): anything unexpected refuses the whole file.
public struct GrammarRules: Sendable {
    /// Largest file accepted, in bytes (the first wave is about 43 KB).
    static let maxBytes = 256 * 1024
    static let maxDepth = 8
    static let schemaVersion = 1
    static let levels: Set<String> = ["A1", "A2", "B1"]
    /// Longest text of any field, in characters.
    static let maxText = 400
    static let maxAlias = 40
    static let maxRules = 200
    static let maxCategories = 20
    static let gap = "___"

    /// The shipped rules, read once. A file that is missing, unreadable or refused stops debug builds
    /// and tests; a release build gets no rules instead (the tab then says there is nothing yet).
    public static let shared: GrammarRules = {
        do {
            guard let url = Bundle.module.url(forResource: "grammar-rules", withExtension: "json") else {
                throw GrammarRulesError.invalid("grammar-rules.json is missing")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try load(handle.read(upToCount: maxBytes + 1) ?? Data())
        } catch {
            // A static message: nothing from the file reaches the log.
            Logger(subsystem: "app.lingleaf", category: "GrammarRules").fault("grammar-rules.json refused; using no rules")
            assertionFailure("grammar-rules.json: \(error)")
            return GrammarRules(categories: [], rules: [])
        }
    }()

    public let categories: [GrammarCategory]
    public let rules: [GrammarRule]

    /// False when the bundled file was refused and there are no rules: progress must then not be saved
    /// (see `GrammarProgress.encoded(for:)`).
    public var isAvailable: Bool { !rules.isEmpty }

    /// The item ids of every rule, to read saved progress against.
    public var knownItems: [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.id, Set($0.practice.map(\.id))) })
    }

    public func rule(id: String) -> GrammarRule? { rules.first { $0.id == id } }

    public func rules(in category: String) -> [GrammarRule] { rules.filter { $0.category == category } }

    // MARK: Loading

    /// Reads the rules, refusing the file whole at the first problem.
    static func load(_ data: Data) throws -> GrammarRules {
        guard data.count <= maxBytes else { throw GrammarRulesError.tooLarge }
        guard JSONGuard.isShallow(data, maxDepth: maxDepth) else { throw GrammarRulesError.tooDeep }
        let file = try JSONDecoder().decode(GrammarFile.self, from: data)
        let result = GrammarRules(categories: file.categories, rules: file.rules)
        try result.validate()
        return result
    }

    private static func check(_ ok: Bool, _ problem: @autoclosure () -> String) throws {
        if !ok { throw GrammarRulesError.invalid(problem()) }
    }

    private func validate() throws {
        try Self.check(categories.count <= Self.maxCategories && rules.count <= Self.maxRules, "too many categories or rules")
        let categoryIDs = Set(categories.map(\.id))
        try Self.check(categoryIDs.count == categories.count, "duplicate category")
        for category in categories {
            try Self.check(Self.isSlug(category.id), "category \(category.id)")
            try Self.check(Self.isText(category.title.en) && Self.isText(category.title.es), "category \(category.id) title")
        }
        try Self.check(Set(rules.map(\.id)).count == rules.count, "duplicate rule id")
        var itemIDs = Set<String>()
        for rule in rules {
            try Self.validate(rule, categoryIDs: categoryIDs)
            for item in rule.practice {
                try Self.check(itemIDs.insert(item.id).inserted, "duplicate item id \(item.id)")
                try Self.validate(item)
            }
        }
    }

    private static func validate(_ rule: GrammarRule, categoryIDs: Set<String>) throws {
        let id = rule.id
        try check(isSlug(id), "rule id \(id)")
        try check(categoryIDs.contains(rule.category), "\(id): unknown category")
        try check(levels.contains(rule.level), "\(id): unknown level")
        try check(isText(rule.title.en) && isText(rule.title.es), "\(id): title")
        let lineCount = rule.lines.en.count
        try check((1...4).contains(lineCount) && lineCount == rule.lines.es.count, "\(id): 1–4 rule lines in both languages")
        try check((rule.lines.en + rule.lines.es).allSatisfy(isText), "\(id): rule line")
        try check((2...4).contains(rule.examples.count), "\(id): 2–4 examples")
        try check(rule.examples.allSatisfy { isText($0.en) && isText($0.es) }, "\(id): example")
        try check(rule.contrast.forms.count == 2 && rule.contrast.forms.allSatisfy(isText), "\(id): contrast needs two forms")
        try check(isPair(rule.contrast.gloss), "\(id): contrast gloss")
        try check(isPair(rule.note) && isPair(rule.spanish), "\(id): note or Spanish-speaker line")
        try validate(books: rule.books, id)
        try check((1...20).contains(rule.aliases.count), "\(id): 1–20 aliases")
        try check(rule.aliases.allSatisfy { isText($0) && $0.unicodeScalars.count <= maxAlias }, "\(id): alias")
        try check((3...12).contains(rule.practice.count), "\(id): 3–12 practice items")
    }

    /// `none` has no patterns; `patterns` has 1–12, each of 1–5 words made of a–z, `|` (alternatives) and `*` (any word).
    private static func validate(books: GrammarBooks, _ id: String) throws {
        switch books.mode {
        case .none:
            try check(books.patterns.isEmpty, "\(id): books none has no patterns")
        case .patterns:
            try check((1...12).contains(books.patterns.count), "\(id): 1–12 book patterns")
            for pattern in books.patterns {
                let words = pattern.split(separator: " ", omittingEmptySubsequences: false)
                let letters: (Substring) -> Bool = { word in
                    !word.isEmpty && word.utf8.allSatisfy { (0x61...0x7A).contains($0) || $0 == 0x7C || $0 == 0x2A }
                }
                try check((1...5).contains(words.count) && words.allSatisfy(letters) && pattern.utf8.count <= 80, "\(id): book pattern \(pattern)")
            }
        }
    }

    private static func validate(_ item: PracticeItem) throws {
        try check(isSlug(item.id), "item id \(item.id)")
        try check(levels.contains(item.level), "\(item.id): unknown level")
        let optionCount = item.options.count
        try check((2...4).contains(optionCount) && Set(item.options).count == optionCount, "\(item.id): 2–4 distinct options")
        try check(item.options.allSatisfy(isText), "\(item.id): option")
        try check(item.options.indices.contains(item.answer), "\(item.id): answer out of range")
        try check(item.feedback.count == item.options.count, "\(item.id): one feedback line per option")
        try check(item.feedback.allSatisfy { isText($0.en) && isText($0.es) }, "\(item.id): feedback")
        try check(isPair(item.ask), "\(item.id): ask")
        switch item.kind {
        case .gap:
            try check(item.ask == nil, "\(item.id): a gap item has no ask")
            try check(item.text.map { isText($0) && $0.components(separatedBy: gap).count == 2 } ?? false, "\(item.id): one gap")
        case .choose:
            try check(item.ask != nil, "\(item.id): choose needs ask")
            try check(item.text.map(isText) ?? false, "\(item.id): a choose item needs a visible stimulus")
        }
    }

    /// An absent pair is fine; a present one needs both texts.
    private static func isPair(_ pair: GrammarText?) -> Bool {
        pair.map { isText($0.en) && isText($0.es) } ?? true
    }

    /// Lower-case a–z, digits and hyphens, 1–40 bytes: the stable ids saved progress refers to.
    static func isSlug(_ text: String) -> Bool {
        (1...40).contains(text.utf8.count)
            && text.utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D }
    }

    /// Characters no text may hold: controls, invisible formatting (bidi, zero-width), line and paragraph
    /// separators and private use. Same set as the irregular-verb table's texts.
    private static let forbidden: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator, .privateUse]

    /// Not blank, at most `maxText` code points (as on Android: a combining mark counts), none forbidden.
    static func isText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.unicodeScalars.count <= maxText
            && !text.unicodeScalars.contains { forbidden.contains($0.properties.generalCategory) }
    }
}

enum GrammarRulesError: Error, Equatable {
    case tooLarge
    case tooDeep
    case malformed(String)
    case invalid(String)
}

/// A pair of texts, one per interface language.
public struct GrammarText: Equatable, Sendable {
    public let en: String
    public let es: String

    /// The text in `language` ("es" → Spanish; any other language reads the English text).
    public func text(for language: String) -> String { language == "es" ? es : en }
}

public struct GrammarCategory: Equatable, Sendable {
    public let id: String
    public let title: GrammarText
}

public struct GrammarLines: Equatable, Sendable {
    public let en: [String]
    public let es: [String]

    public func lines(for language: String) -> [String] { language == "es" ? es : en }
}

public struct GrammarExample: Equatable, Sendable {
    public let en: String
    public let es: String
}

/// The "Don't mix up" line: two correct forms and an optional gloss of what each means.
public struct GrammarContrast: Equatable, Sendable {
    public let forms: [String]
    public let gloss: GrammarText?
}

/// How "In your books" finds sentences for a rule (SPEC.md S23): none, or word patterns ("on monday|tuesday",
/// "there is|are"; `|` lists alternatives, `*` is any word).
public struct GrammarBooks: Equatable, Sendable {
    public enum Mode: String, Sendable { case none, patterns }

    public let mode: Mode
    public let patterns: [String]
}

public struct PracticeItem: Equatable, Sendable {
    public enum Kind: String, Sendable { case gap, choose }

    public let id: String
    public let level: String
    public let kind: Kind
    /// A sentence with one "___" (`gap`); the visible stimulus of a `choose` item (a situation, a question or a Spanish sentence).
    public let text: String?
    /// The instruction of a `choose` item ("Choose the question.").
    public let ask: GrammarText?
    public let options: [String]
    public let answer: Int
    /// One line per option, in the options' order: why it is right or not.
    public let feedback: [GrammarText]

    public var correct: String { options[answer] }

    public func isRight(_ option: Int) -> Bool { option == answer }

    /// The sentence with the option in the gap (`gap`), else the option.
    public func filled(with option: Int) -> String {
        guard options.indices.contains(option) else { return "" }
        guard kind == .gap, let text else { return options[option] }
        return text.replacingOccurrences(of: GrammarRules.gap, with: options[option])
    }
}

public struct GrammarRule: Equatable, Sendable {
    public let id: String
    public let category: String
    public let level: String
    public let title: GrammarText
    public let lines: GrammarLines
    public let examples: [GrammarExample]
    public let contrast: GrammarContrast
    public let note: GrammarText?
    /// A line for Spanish speakers where Spanish interferes (S21).
    public let spanish: GrammarText?
    public let aliases: [String]
    public let books: GrammarBooks
    /// The first item is the pretest of a first visit.
    public let practice: [PracticeItem]
}

// MARK: Strict decoding

private struct GrammarKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension Decoder {
    /// The object's container, refusing a key outside `required` + `optional` or a missing required one.
    func strictObject(_ required: Set<String>, optional: Set<String> = []) throws -> KeyedDecodingContainer<GrammarKey> {
        let keyed = try self.container(keyedBy: GrammarKey.self)
        let keys = Set(keyed.allKeys.map(\.stringValue))
        if let unknown = keys.subtracting(required).subtracting(optional).min() {
            throw GrammarRulesError.malformed("unknown key \(unknown)")
        }
        if let missing = required.subtracting(keys).min() { throw GrammarRulesError.malformed("missing key \(missing)") }
        return keyed
    }
}

private extension KeyedDecodingContainer where K == GrammarKey {
    func value<T: Decodable>(_ key: String) throws -> T { try decode(T.self, forKey: GrammarKey(key)) }
    func optional<T: Decodable>(_ key: String) throws -> T? { try decodeIfPresent(T.self, forKey: GrammarKey(key)) }
}

private struct GrammarFile: Decodable {
    let categories: [GrammarCategory]
    let rules: [GrammarRule]

    init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["schema", "categories", "rules"])
        // First: a future schema is refused as such, whatever else it holds.
        let version: Int = try c.value("schema")
        guard version == GrammarRules.schemaVersion else { throw GrammarRulesError.invalid("schema \(version)") }
        categories = try c.value("categories")
        rules = try c.value("rules")
    }
}

extension GrammarText: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["en", "es"])
        en = try c.value("en")
        es = try c.value("es")
    }
}

extension GrammarCategory: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["id", "title"])
        id = try c.value("id")
        title = try c.value("title")
    }
}

extension GrammarLines: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["en", "es"])
        en = try c.value("en")
        es = try c.value("es")
    }
}

extension GrammarExample: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["en", "es"])
        en = try c.value("en")
        es = try c.value("es")
    }
}

extension GrammarContrast: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["forms"], optional: ["gloss"])
        forms = try c.value("forms")
        gloss = try c.optional("gloss")
    }
}

extension GrammarBooks.Mode: Decodable {}

extension GrammarBooks: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["mode"], optional: ["patterns"])
        mode = try c.value("mode")
        patterns = try c.optional("patterns") ?? []
        // `patterns: []` for mode none is the same as no key; mode patterns is checked in validation.
    }
}

extension PracticeItem.Kind: Decodable {}

extension PracticeItem: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["id", "level", "kind", "options", "answer", "feedback"], optional: ["text", "ask"])
        id = try c.value("id")
        level = try c.value("level")
        kind = try c.value("kind")
        text = try c.optional("text")
        ask = try c.optional("ask")
        options = try c.value("options")
        answer = try c.value("answer")
        feedback = try c.value("feedback")
    }
}

extension GrammarRule: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(
            ["id", "category", "level", "title", "rule", "examples", "contrast", "aliases", "books", "practice"], optional: ["note", "spanish"]
        )
        id = try c.value("id")
        category = try c.value("category")
        level = try c.value("level")
        title = try c.value("title")
        lines = try c.value("rule")
        examples = try c.value("examples")
        contrast = try c.value("contrast")
        note = try c.optional("note")
        spanish = try c.optional("spanish")
        aliases = try c.value("aliases")
        books = try c.value("books")
        practice = try c.value("practice")
    }
}

import Foundation

public struct Book: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let fileName: String
    public let paragraphCount: Int
    public var level: String?
    public var gutenbergID: Int?
    public let addedAt: Date
    public var lastOpenedAt: Date?
    public var progressParagraph: Int

    public var progress: Double {
        guard paragraphCount > 1 else { return 0 }
        return min(1, max(0, Double(progressParagraph) / Double(paragraphCount - 1)))
    }
}

/// A word the user chose to learn or marked as known. `word` is the lowercased base form.
public struct VocabWord: Codable, Identifiable, Hashable, Sendable {
    public let word: String
    public var translation: String
    /// Language `translation` is in ("es", "zh-Hans"); nil when unknown (older data).
    public var translationLanguage: String?
    public var phonetic: String
    public var context: String
    /// The translation of `context`, when the card had it at save time.
    public var contextTranslation: String?
    public var source: String
    public var learned: Bool
    public var box: Int
    public let createdAt: Date
    public var nextReview: Date

    public var id: String { word }

    public func isDue(_ now: Date) -> Bool { !learned && nextReview <= now }
}

public struct Settings: Codable, Equatable, Sendable {
    public var dailyGoalMinutes = 10
    public var fontSize = 20.0
    /// AVSpeechUtterance rate (0…1, 0.5 is normal).
    public var speechRate = 0.45
    public var targetLanguage: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        dailyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? defaults.dailyGoalMinutes
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? defaults.speechRate
        targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage)
    }
}

public struct BundledStory: Sendable {
    public let title: String
    public let level: String
    public let text: String

    public init(title: String, level: String, text: String) {
        self.title = title
        self.level = level
        self.text = text
    }
}

public struct LibraryState: Equatable, Sendable {
    public var books: [Book] = []
    public var words: [VocabWord] = []
    public var readingLog: [String: Int] = [:]
    public var settings = Settings()

    public init() {}

    /// Base forms of words being learned.
    public var learningWords: Set<String> { Set(words.filter { !$0.learned }.map(\.word)) }

    public func word(_ base: String) -> VocabWord? {
        let key = TextTools.normalize(base)
        return words.first { $0.word == key }
    }

    public var lastOpened: Book? {
        books.filter { $0.lastOpenedAt != nil }.max { $0.lastOpenedAt! < $1.lastOpenedAt! }
    }
}

/// Why a file could not be imported.
public enum ImportError: Error, Equatable {
    /// The file has no text once the Gutenberg header and footer are removed.
    case empty
}

/// Where files live. The app maps it to Application Support; tests to memory.
public protocol Storage {
    func read(_ name: String) -> String?
    func write(_ name: String, _ content: String)
    func delete(_ name: String)
}

/// Books, words, reading time and settings, persisted as small JSON files;
/// each book's text lives in its own file. Mirrors `Library` in lingleaf-android.
public final class Library {
    public private(set) var state = LibraryState() {
        didSet { onChange?(state) }
    }

    /// Called after every change, e.g. to refresh the UI.
    public var onChange: ((LibraryState) -> Void)?

    private let storage: Storage
    private let now: () -> Date
    private let calendar: Calendar
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let maxSessionSeconds = 3600

    public init(storage: Storage, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.storage = storage
        self.now = now
        self.calendar = calendar
    }

    public func load() {
        var loaded = LibraryState()
        loaded.books = decode([Book].self, "books.json") ?? []
        loaded.words = decode([VocabWord].self, "words.json") ?? []
        loaded.readingLog = decode([String: Int].self, "reading-log.json") ?? [:]
        loaded.settings = decode(Settings.self, "settings.json") ?? Settings()
        state = loaded
    }

    /// Adds the bundled stories the first time the app runs.
    public func seedIfNeeded(_ stories: () -> [BundledStory]) {
        guard storage.read("seeded") == nil else { return }
        for story in stories() { addBook(title: story.title, author: "Lingleaf", text: story.text, level: story.level) }
        storage.write("seeded", "1")
    }

    // MARK: Books

    @discardableResult
    public func addBook(title: String, author: String, text: String, level: String? = nil, gutenbergID: Int? = nil) -> Book {
        let id = "\(Int(now().timeIntervalSince1970 * 1000))-\(state.books.count)"
        let book = Book(
            id: id, title: title, author: author, fileName: "book-\(id).txt",
            paragraphCount: TextTools.splitParagraphs(text).count,
            level: level, gutenbergID: gutenbergID, addedAt: now(), lastOpenedAt: nil, progressParagraph: 0
        )
        storage.write(book.fileName, text)
        state.books.append(book)
        saveBooks()
        return book
    }

    /// Title for an imported file: the file name without its last extension,
    /// trimmed ("my.story.TXT" → "my.story"); "Book" when nothing is left.
    public static func importTitle(fileName: String) -> String {
        let base = fileName.lastIndex(of: ".").map { String(fileName[..<$0]) } ?? fileName
        let title = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Book" : title
    }

    /// Adds an imported plain-text file: the Gutenberg header and footer are removed
    /// and the author is "—". Throws, adding nothing, when no text is left.
    /// The 10 MB size check happens before the file is read (see `Limits.maxBytes`).
    @discardableResult
    public func importText(fileName: String, text: String) throws -> Book {
        let body = GutenbergClient.stripBoilerplate(text)
        guard !body.isEmpty else { throw ImportError.empty }
        return addBook(title: Self.importTitle(fileName: fileName), author: "—", text: body)
    }

    public func deleteBook(_ id: String) {
        guard let book = state.books.first(where: { $0.id == id }) else { return }
        storage.delete(book.fileName)
        state.books.removeAll { $0.id == id }
        saveBooks()
    }

    /// Marks the book as opened and returns its paragraphs.
    public func openBook(_ id: String) -> [String] {
        guard let index = state.books.firstIndex(where: { $0.id == id }) else { return [] }
        state.books[index].lastOpenedAt = now()
        saveBooks()
        return TextTools.splitParagraphs(storage.read(state.books[index].fileName) ?? "")
    }

    /// Updates progress in memory; call `flush()` to persist (e.g. when leaving the reader).
    public func updateProgress(_ id: String, paragraph: Int) {
        guard let index = state.books.firstIndex(where: { $0.id == id }),
              state.books[index].progressParagraph != paragraph else { return }
        state.books[index].progressParagraph = paragraph
    }

    public func flush() { saveBooks() }

    // MARK: Words

    public func dueWords() -> [VocabWord] {
        let now = now()
        return state.words.filter { $0.isDue(now) }.sorted { $0.nextReview < $1.nextReview }
    }

    /// Today's review session: at most `Srs.sessionLimit` due words, interleaved by book.
    public func reviewSession() -> [VocabWord] { Srs.session(dueWords()) }

    /// Words being learned that are due by the end of tomorrow, for "12 more tomorrow".
    public func dueByEndOfTomorrow() -> Int {
        let end = Srs.startOfDay(2, after: now(), calendar: calendar)
        return state.words.filter { !$0.learned && $0.nextReview < end }.count
    }

    public func isLearning(_ token: String) -> Bool {
        let learning = state.learningWords
        return !learning.isEmpty && !TextTools.matchKeys(token).isDisjoint(with: learning)
    }

    /// Saves the word as being learned or as known and returns the record it
    /// replaced (nil when the word was new), so the change can be undone with
    /// `restoreWord`. A blank translation, phonetic, context or source keeps the saved one.
    @discardableResult
    public func saveWord(
        _ word: String, learned: Bool, translation: String? = nil, translationLanguage: String? = nil,
        phonetic: String? = nil, context: String = "", contextTranslation: String? = nil, source: String = ""
    ) -> VocabWord? {
        let key = TextTools.normalize(word)
        let existing = state.words.first { $0.word == key }
        var entry = existing ?? VocabWord(
            word: key, translation: "", translationLanguage: nil, phonetic: "", context: "", source: "",
            learned: learned, box: 0, createdAt: now(), nextReview: now()
        )
        // A new word is first reviewed tomorrow, after a night's sleep (S7).
        if !learned, existing == nil || existing?.learned == true {
            entry.box = 0
            entry.nextReview = Srs.startOfDay(1, after: now(), calendar: calendar)
        }
        entry.learned = learned
        if let translation, !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.translation = translation
            entry.translationLanguage = translationLanguage
        }
        if let phonetic, !phonetic.isEmpty { entry.phonetic = phonetic }
        if !context.isEmpty {
            if context != entry.context { entry.contextTranslation = nil }
            entry.context = context
        }
        if let contextTranslation, !contextTranslation.isEmpty { entry.contextTranslation = contextTranslation }
        if !source.isEmpty { entry.source = source }
        replace(entry)
        return existing
    }

    /// Undo: puts back exactly `previous` (what `saveWord` returned, or the word
    /// before it was deleted); nil removes the word.
    public func restoreWord(_ word: String, previous: VocabWord?) {
        if let previous {
            replace(previous)
        } else {
            deleteWord(TextTools.normalize(word))
        }
    }

    /// Records a translation that arrived after the word was saved. Does nothing
    /// when the word no longer exists, the text is blank, or the word already has
    /// a translation in that language.
    public func setTranslation(_ word: String, _ text: String, language: String) {
        let key = TextTools.normalize(word)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, var entry = state.words.first(where: { $0.word == key }),
              entry.translation.isEmpty || entry.translationLanguage != language else { return }
        entry.translation = text
        entry.translationLanguage = language
        replace(entry)
    }

    /// Words to translate into `target`: no translation yet, or one recorded in
    /// another language (or in an unknown one).
    public func wordsNeedingTranslation(_ target: String) -> [VocabWord] {
        state.words.filter { $0.translation.isEmpty || $0.translationLanguage != target }
    }

    public func answerReview(_ word: String, correct: Bool) {
        guard var entry = state.words.first(where: { $0.word == word }) else { return }
        let result = Srs.review(box: entry.box, correct: correct, now: now(), calendar: calendar)
        entry.box = result.box
        entry.nextReview = result.nextReview
        entry.learned = result.learned
        replace(entry)
    }

    public func setLearned(_ word: String, _ learned: Bool) {
        guard var entry = state.words.first(where: { $0.word == word }) else { return }
        entry.learned = learned
        if !learned {
            entry.box = 0
            entry.nextReview = now()
        }
        replace(entry)
    }

    public func deleteWord(_ word: String) {
        state.words.removeAll { $0.word == word }
        save(state.words, "words.json")
    }

    private func replace(_ entry: VocabWord) {
        var words = state.words.filter { $0.word != entry.word }
        words.append(entry)
        state.words = words.sorted { $0.createdAt > $1.createdAt }
        save(state.words, "words.json")
    }

    // MARK: Reading time and settings

    public func secondsToday() -> Int { state.readingLog[dayKey(now(), calendar: calendar)] ?? 0 }

    public func streak() -> Int {
        readingStreak(state.readingLog, goalSeconds: state.settings.dailyGoalMinutes * 60, today: now(), calendar: calendar)
    }

    public func addReadingTime(_ seconds: Int) {
        let add = min(max(seconds, 0), Self.maxSessionSeconds)
        guard add > 0 else { return }
        state.readingLog[dayKey(now(), calendar: calendar), default: 0] += add
        save(state.readingLog, "reading-log.json")
    }

    public func updateSettings(_ transform: (inout Settings) -> Void) {
        transform(&state.settings)
        save(state.settings, "settings.json")
    }

    // MARK: Persistence

    private func saveBooks() { save(state.books, "books.json") }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        storage.write(name, String(decoding: data, as: UTF8.self))
    }

    /// A file that exists but can't be read is kept as `<name>.corrupt` before the
    /// next save replaces it, so a damaged library or word list can be recovered.
    private func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let text = storage.read(name) else { return nil }
        guard let value = try? decoder.decode(type, from: Data(text.utf8)) else {
            storage.write("\(name).corrupt", text)
            return nil
        }
        return value
    }
}

/// Files in a directory, written atomically.
public struct FileStorage: Storage {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func read(_ name: String) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    public func write(_ name: String, _ content: String) {
        try? content.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    public func delete(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

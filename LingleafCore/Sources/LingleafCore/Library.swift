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
    public internal(set) var word: String
    public var translation: String
    /// Language `translation` is in ("es", "zh-Hans"); nil when unknown (older data).
    public var translationLanguage: String?
    public var phonetic: String
    public var context: String
    /// The translation of `context`, and the language it is in; filled in later when the
    /// card didn't have it, and again when the translation language changes.
    public var contextTranslation: String?
    public var contextTranslationLanguage: String?

    /// `contextTranslation` when it is in `language`.
    public func contextTranslation(in language: String?) -> String? {
        contextTranslationLanguage == language ? contextTranslation : nil
    }
    public var source: String
    public var learned: Bool
    public var box: Int
    public internal(set) var createdAt: Date
    public var nextReview: Date
    /// Set when `word` is the verb group of a helper or modal verb ("did not go"): what is
    /// learned and translated, since the helper alone means little. Nil for other words.
    public var kind: FunctionWord.Kind?
    /// The helper or modal verb's base form ("do" for "did not go").
    public var base: String?
    /// Which word `word` is when the spelling is two (SPEC S4): `Sense.verb`, `.noun` or
    /// `.homonym`; nil for a word saved without one.
    public var sense: String?
    /// The form tapped in `context` and where it is (UTF-16 offsets), to bold only it in review.
    public var form: String?
    public var formStart: Int?
    public var formEnd: Int?
    /// A word saved while its sentence didn't tell: the card's two readings with their meanings;
    /// `word` is then the tapped form.
    public var meanings: [SavedMeaning]?
    /// A corrected word waiting for its meaning (SPEC S18): not due until it has one.
    public var waitsForMeaning: Bool?

    /// One spelling is saved once per sense.
    public var id: String { Self.id(word, sense) }

    public static func id(_ word: String, _ sense: String?) -> String {
        sense.map { "\(word)#\($0)" } ?? word
    }

    /// Saved while its sentence didn't tell which word it is.
    public var isUnsure: Bool { meanings != nil && sense == nil }

    /// The tapped form's range in `context`, when it is still there.
    public var formRange: WordRange? {
        guard let formStart, let formEnd else { return nil }
        return WordRange(formStart, formEnd)
    }

    /// Fields a restored or edited file may hold out of bounds, made safe: an unknown sense is
    /// dropped, a range that doesn't hold the form in the sentence too, at most two readings.
    /// Longest saved word (UTF-16 units): a verb group without one is its sentence, at most
    /// `TextTools.maxSentence`; its id ("…#homonym") is then always short enough for the
    /// corrections cursor to read back.
    static let maxWord = TextTools.maxSentence
    /// Dates a saved word can have (2000–2100); others are brought inside.
    static let dateRange = Date(timeIntervalSince1970: 946_684_800)...Date(timeIntervalSince1970: 4_102_444_800)

    func bounded() -> VocabWord {
        var word = self
        word.word = TextTools.truncated(self.word, Self.maxWord)
        word.createdAt = min(max(createdAt, Self.dateRange.lowerBound), Self.dateRange.upperBound)
        word.nextReview = min(max(nextReview, Self.dateRange.lowerBound), Self.dateRange.upperBound)
        word.context = TextTools.truncated(context, TextTools.maxSentence)
        if let sense, !Sense.all.contains(sense) { word.sense = nil }
        if let form, form.utf16.count > 40 || TextTools.wordRanges(form) != [WordRange(0, (form as NSString).length)] {
            word.form = nil
        }
        let ns = word.context as NSString
        let rangeHoldsForm = word.form.flatMap { form in
            formRange.map { range in
                range.start >= 0 && range.start < range.end && range.end <= ns.length
                    && TextTools.normalize(ns.substring(with: range.nsRange)) == TextTools.normalize(form)
            }
        } ?? false
        if !rangeHoldsForm {
            word.formStart = nil
            word.formEnd = nil
        }
        if let meanings {
            let kept = meanings.prefix(2).compactMap { $0.bounded() }
            word.meanings = kept.isEmpty ? nil : kept
        }
        // A word that has its meaning waits for nothing, however it got it.
        if word.waitsForMeaning == true, word.hasMeaning { word.waitsForMeaning = nil }
        return word
    }

    /// It has a meaning to review with: its translation (a word saved unsure has one once every
    /// reading has its meaning).
    public var hasMeaning: Bool { !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public func isDue(_ now: Date) -> Bool { !learned && nextReview <= now && waitsForMeaning != true }
}

public struct Settings: Codable, Equatable, Sendable {
    public var dailyGoalMinutes = 10
    public var fontSize = 20.0
    /// AVSpeechUtterance rate (0…1, 0.5 is normal).
    public var speechRate = 0.45
    public var targetLanguage: String?

    public init() {}

    /// Within the ranges Settings offers: a restored or edited settings file can't make the
    /// streak count forever (a goal of 0) or the reader unreadable.
    public func bounded() -> Settings {
        var settings = self
        settings.dailyGoalMinutes = min(max(dailyGoalMinutes, 5), 60)
        settings.fontSize = fontSize.isFinite ? min(max(fontSize, 14), 34) : Settings().fontSize
        settings.speechRate = speechRate.isFinite ? min(max(speechRate, 0.3), 0.6) : Settings().speechRate
        return settings
    }

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

/// A story shipped with the app: its resource file name (without ".txt"), title and level.
public struct ShelfStory: Hashable, Sendable {
    public let resource: String
    public let title: String
    public let level: String

    public init(resource: String, title: String, level: String) {
        self.resource = resource
        self.title = title
        self.level = level
    }
}

extension BundledStory {
    /// The original stories shipped with the app (resource file name, title, level), easiest first.
    /// Discover lists them under their level too, so no level of the filter is empty.
    public static let shelf: [ShelfStory] = [
        ShelfStory(resource: "the-red-boat", title: "The Red Boat", level: "A1"),
        ShelfStory(resource: "a-day-at-the-market", title: "A Day at the Market", level: "A2"),
        ShelfStory(resource: "the-lighthouse-keeper", title: "The Lighthouse Keeper", level: "B1"),
    ]

    /// The author the bundled stories are saved with.
    public static let author = "Lingleaf"

    /// Shelf stories at `level`, in order; a nil level keeps every story.
    public static func shelf(level: String?) -> [ShelfStory] {
        guard let level else { return shelf }
        return shelf.filter { $0.level == level }
    }

    /// The library's copy of the bundled story titled `title`, if the learner still has it.
    public static func libraryCopy(of title: String, in books: [Book]) -> Book? {
        books.first { $0.title == title && $0.author == author && $0.gutenbergID == nil }
    }
}

public struct LibraryState: Equatable, Sendable {
    public var books: [Book] = []
    public var readingLog: [String: Int] = [:]
    public var settings = Settings()
    /// Words corrected to match their sentences, shown on Words until closed (SPEC S18).
    public var corrections: [Correction] = []

    public init() {}

    public var words: [VocabWord] = [] {
        didSet {
            let learning = words.filter { !$0.learned }
            learningWords = Set(learning.map(\.word))
            learningIndex = LearningIndex(learning)
        }
    }

    /// Base forms of words being learned, kept up to date with `words`: the reader asks for
    /// every word it shows, so it must not rebuild the set each time.
    public private(set) var learningWords: Set<String> = []
    /// The words being learned, by form and sense, for the underline.
    public private(set) var learningIndex = LearningIndex()

    /// The saved word spelled `base`: the one without a sense first, else the first saved.
    public func word(_ base: String) -> VocabWord? {
        let key = TextTools.normalize(base)
        return words.first { $0.word == key && $0.sense == nil } ?? words.first { $0.word == key }
    }

    /// The saved word spelled `base` with exactly `sense`.
    public func word(_ base: String, sense: String?) -> VocabWord? {
        let id = VocabWord.id(TextTools.normalize(base), sense)
        return words.first { $0.id == id }
    }

    /// The record a word saved as `sense` is: that one, else the same spelling saved before senses
    /// existed (it becomes this sense when saved again).
    public func saved(_ base: String, sense: String?) -> VocabWord? {
        word(base, sense: sense) ?? sense.flatMap { _ in word(base, sense: nil).flatMap { $0.isUnsure ? nil : $0 } }
    }

    /// How Words and Review name `word` (SPEC S4): its spelling, or "to wind" / "the wind" when
    /// another sense of the spelling is saved too, or always for a spelling that is also another
    /// word (a homograph, a base mostly a noun, a verb with a twin). Two verb senses add their first
    /// meaning: "to lie (estar acostado, tumbarse)" / "to lie (mentir)" (the table's in Spanish, else
    /// the first group of the translated one), except `withMeaning` false (Review's prompt).
    public func displayName(_ word: VocabWord, withMeaning: Bool = true) -> String {
        guard let sense = word.sense else { return word.word }
        let others = words.filter { $0.word == word.word && $0.sense != nil && $0.id != word.id }
        guard !others.isEmpty || IrregularVerbs.shared.namesItsSense(word.word) else { return word.word }
        if sense == Sense.noun { return "the \(word.word)" }
        // Review's prompt names it without its meaning: recall comes first (SPEC S7).
        guard withMeaning, others.contains(where: { $0.sense != Sense.noun }) else { return "to \(word.word)" }
        let translated = word.translation.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let meaning = ReadingTranslation.isSpanish(settings.targetLanguage)
            ? IrregularVerbs.shared.spanishMeaning(of: word.word, sense: sense, all: false)
            : translated.isEmpty ? nil : translated
        return meaning.map { "to \(word.word) (\($0))" } ?? "to \(word.word)"
    }

    /// Whether Review's prompt also shows the saved sentence, without its translation (SPEC S7): the
    /// label alone doesn't tell the sense, because two senses of the spelling are saved or because it
    /// is a verb with a regular twin (lie, hang) saved as the verb or as the twin.
    public func promptShowsSentence(_ word: VocabWord) -> Bool {
        guard let sense = word.sense, !word.context.isEmpty, TextTools.normalize(word.context) != word.word else { return false }
        if words.filter({ $0.word == word.word && $0.sense != nil }).count >= 2 { return true }
        return (sense == Sense.verb || sense == Sense.homonym) && IrregularVerbs.shared.verb(base: word.word)?.homonym != nil
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
    public internal(set) var state = LibraryState() {
        didSet { onChange?(state) }
    }

    /// Called after every change, e.g. to refresh the UI.
    public var onChange: ((LibraryState) -> Void)?

    let storage: Storage
    let now: () -> Date
    let calendar: Calendar
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
        // Progress stays inside the book, whatever a restored file says.
        loaded.books = (decode([Book].self, "books.json") ?? []).map { book in
            var book = book
            book.progressParagraph = min(max(book.progressParagraph, 0), max(book.paragraphCount - 1, 0))
            return book
        }
        // Saved before contexts were capped, or restored from a backup: within bounds, once per id.
        var ids: Set<String> = []
        loaded.words = (decode([VocabWord].self, "words.json") ?? []).map { $0.bounded() }.filter { ids.insert($0.id).inserted }
        loaded.readingLog = decode([String: Int].self, "reading-log.json") ?? [:]
        loaded.settings = (decode(Settings.self, "settings.json") ?? Settings()).bounded()
        loaded.corrections = loadCorrections()?.corrections ?? []
        state = loaded
    }

    /// Adds the bundled stories the first time the app runs.
    public func seedIfNeeded(_ stories: () -> [BundledStory]) {
        guard storage.read("seeded") == nil else { return }
        for story in stories() { addBook(title: story.title, author: BundledStory.author, text: story.text, level: story.level) }
        storage.write("seeded", "1")
    }

    // MARK: Books

    @discardableResult
    public func addBook(title: String, author: String, text: String, level: String? = nil, gutenbergID: Int? = nil) -> Book {
        let id = "\(Int(now().timeIntervalSince1970 * 1000))-\(state.books.count)"
        let book = Book(
            id: id, title: TextTools.cleanLabel(title), author: TextTools.cleanLabel(author), fileName: "book-\(id).txt",
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

    /// Words being learned that come due before the end of tomorrow (not those due now),
    /// for "12 more tomorrow".
    public func dueByEndOfTomorrow() -> Int {
        let now = now()
        let end = Srs.startOfDay(2, after: now, calendar: calendar)
        return state.words.filter { !$0.learned && $0.nextReview > now && $0.nextReview < end }.count
    }

    /// Whether the word at `range` of `text` is a form of a word being learned, read in its
    /// sentence ("leave" marks "she left", not "turn left").
    public func isLearning(_ text: String, _ range: WordRange) -> Bool {
        learningRanges(text, TextTools.wordRanges(text)).contains(range)
    }

    /// The words of `text` (`words`: its `wordRanges`) that are forms of words being learned,
    /// read in their sentences, in one pass over the paragraph.
    public func learningRanges(_ text: String, _ words: [WordRange]) -> Set<WordRange> {
        let index = state.learningIndex
        guard !index.isEmpty else { return [] }
        let matches = TextTools.learningMatches(in: text, words: words, index: index)
        return Set(zip(words, matches).filter { $0.1 }.map { $0.0 })
    }

    /// Saves the word as being learned or as known and returns the record it
    /// replaced (nil when the word was new), so the change can be undone with
    /// `restoreWord`. A blank translation, phonetic, context or source keeps the saved one.
    /// For a helper or modal verb, `word` is its verb group and `kind`/`base` say what it is.
    /// A word read in its sentence has a `sense` (SPEC S4); one saved while its sentence didn't
    /// tell is the tapped form with `meanings`. Saving a sense of a form saved unsure (`form`)
    /// replaces that record, keeping its review progress (undo with `undoChange`).
    @discardableResult
    public func saveWord(
        _ word: String, learned: Bool, translation: String? = nil, translationLanguage: String? = nil,
        phonetic: String? = nil, context: String = "", contextTranslation: String? = nil, source: String = "",
        kind: FunctionWord.Kind? = nil, base: String? = nil,
        sense: String? = nil, form: String? = nil, formRange: WordRange? = nil, meanings: [SavedMeaning]? = nil
    ) -> VocabWord? {
        let key = TextTools.truncated(TextTools.normalize(word), VocabWord.maxWord)
        let sense = kind == nil ? sense.flatMap { Sense.all.contains($0) ? $0 : nil } : nil
        let existing = kind == nil ? state.saved(key, sense: sense) : state.word(key, sense: nil)
        // The same form saved unsure, now saved as one of its readings: it takes its place.
        let unsure = sense == nil ? nil : form
            .flatMap { state.word(TextTools.normalize($0), sense: nil) }
            .flatMap { $0.isUnsure ? $0 : nil }
        var entry = existing ?? unsure.map { previous in
            var carried = VocabWord(
                word: key, translation: "", translationLanguage: nil, phonetic: "", context: "", source: "",
                learned: previous.learned, box: previous.box, createdAt: previous.createdAt, nextReview: previous.nextReview
            )
            carried.context = previous.context
            carried.contextTranslation = previous.contextTranslation
            carried.contextTranslationLanguage = previous.contextTranslationLanguage
            carried.source = previous.source
            return carried
        } ?? VocabWord(
            word: key, translation: "", translationLanguage: nil, phonetic: "", context: "", source: "",
            learned: learned, box: 0, createdAt: now(), nextReview: now()
        )
        // A new word is first reviewed tomorrow, after a night's sleep (S7).
        if !learned, unsure == nil, existing == nil || existing?.learned == true {
            entry.box = 0
            entry.nextReview = Srs.startOfDay(1, after: now(), calendar: calendar)
        }
        if let unsure, unsure.id != VocabWord.id(key, sense) { state.words.removeAll { $0.id == unsure.id } }
        // A word saved before senses existed becomes this sense.
        if let existing, existing.id != VocabWord.id(key, sense) { state.words.removeAll { $0.id == existing.id } }
        entry.learned = learned
        entry.kind = kind
        entry.base = kind == nil ? nil : base
        entry.sense = sense
        if kind == nil, let form {
            entry.form = form
            entry.formStart = formRange?.start
            entry.formEnd = formRange?.end
        }
        if kind == nil, sense == nil, let meanings { entry.meanings = Array(meanings.prefix(2)) }
        if let translation, !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.translation = translation
            entry.translationLanguage = translationLanguage
        }
        if let phonetic, !phonetic.isEmpty { entry.phonetic = phonetic }
        if !context.isEmpty {
            if context != entry.context {
                entry.contextTranslation = nil
                entry.contextTranslationLanguage = nil
            }
            entry.context = context
        }
        if let contextTranslation, !contextTranslation.isEmpty {
            entry.contextTranslation = contextTranslation
            entry.contextTranslationLanguage = translationLanguage
        }
        if !source.isEmpty { entry.source = source }
        replace(entry)
        return existing
    }

    /// Undo: puts back exactly `previous` (what `saveWord` returned, or the word
    /// before it was deleted); nil removes the word.
    public func restoreWord(_ word: String, previous: VocabWord?, sense: String? = nil) {
        if let previous {
            replace(previous)
        } else {
            deleteWord(TextTools.normalize(word), sense: sense)
        }
    }

    /// Undo of several changes at once: puts back exactly `words` (a copy of `state.words`).
    public func restoreWords(_ words: [VocabWord]) {
        state.words = words.map { $0.bounded() }
        save(state.words, "words.json")
    }

    /// Undo of one change on the card (`before` and `after` are `state.words` around it): takes out
    /// the records it added or changed and puts back the ones it replaced (a word saved unsure that
    /// a reading took the place of), leaving every other word as it is now.
    public func undoChange(before: [VocabWord], after: [VocabWord]) {
        let old = Set(before)
        let new = Set(after)
        let added = Set(after.filter { !old.contains($0) }.map(\.id))
        var words = state.words.filter { !added.contains($0.id) }
        for previous in before where !new.contains(previous) && !words.contains(where: { $0.id == previous.id }) {
            words.append(previous.bounded())
        }
        state.words = words.sorted { $0.createdAt > $1.createdAt }
        save(state.words, "words.json")
    }

    /// Records a translation that arrived after the word was saved. Does nothing
    /// when the word no longer exists, the text is blank, or the word already has
    /// a translation in that language.
    public func setTranslation(_ word: String, _ text: String, language: String, sense: String? = nil) {
        let id = VocabWord.id(TextTools.normalize(word), sense)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, var entry = state.words.first(where: { $0.id == id }),
              entry.translation.isEmpty || entry.translationLanguage != language else { return }
        entry.translation = text
        entry.translationLanguage = language
        entry.waitsForMeaning = nil
        replace(entry)
    }

    /// Records the translation of a word's sentence that arrived after it was saved.
    public func setContextTranslation(_ word: String, _ text: String, language: String, sense: String? = nil) {
        let id = VocabWord.id(TextTools.normalize(word), sense)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var entry = state.words.first(where: { $0.id == id }), !entry.context.isEmpty else { return }
        entry.contextTranslation = text
        entry.contextTranslationLanguage = language
        replace(entry)
    }

    /// Words whose sentence has no translation into `target` yet.
    public func contextsNeedingTranslation(_ target: String) -> [VocabWord] {
        state.words.filter { !$0.context.isEmpty && $0.contextTranslation(in: target) == nil }
    }

    /// Words to translate into `target`: no translation yet, or one recorded in
    /// another language (or in an unknown one).
    public func wordsNeedingTranslation(_ target: String) -> [VocabWord] {
        // A word saved unsure is translated by its readings (`meaningsNeedingTranslation`).
        state.words.filter { !$0.isUnsure && ($0.translation.isEmpty || $0.translationLanguage != target) }
    }

    public func answerReview(_ word: String, sense: String? = nil, correct: Bool) {
        let id = VocabWord.id(word, sense)
        guard var entry = state.words.first(where: { $0.id == id }) else { return }
        let result = Srs.review(box: entry.box, correct: correct, now: now(), calendar: calendar)
        entry.box = result.box
        entry.nextReview = result.nextReview
        entry.learned = result.learned
        replace(entry)
    }

    public func setLearned(_ word: String, _ learned: Bool, sense: String? = nil) {
        let id = VocabWord.id(word, sense)
        guard var entry = state.words.first(where: { $0.id == id }) else { return }
        entry.learned = learned
        if !learned {
            entry.box = 0
            entry.nextReview = now()
        }
        replace(entry)
    }

    public func deleteWord(_ word: String, sense: String? = nil) {
        let id = VocabWord.id(word, sense)
        state.words.removeAll { $0.id == id }
        save(state.words, "words.json")
    }

    /// A translation can be longer than its sentence; twice the sentence's limit.
    private static let maxContextTranslation = 2 * TextTools.maxSentence

    func replace(_ entry: VocabWord) {
        // Every saved word passes here: whatever a caller hands in, nothing huge is kept.
        var entry = entry.bounded()
        entry.contextTranslation = entry.contextTranslation.map { TextTools.truncated($0, Self.maxContextTranslation) }
        var words = state.words.filter { $0.id != entry.id }
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

    func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        storage.write(name, String(decoding: data, as: UTF8.self))
    }

    /// A file that exists but can't be read is kept as `<name>.corrupt` before the
    /// next save replaces it, so a damaged library or word list can be recovered.
    func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let text = storage.read(name) else { return nil }
        guard JSONGuard.isShallow(Data(text.utf8)), let value = try? decoder.decode(type, from: Data(text.utf8)) else {
            storage.write("\(name).corrupt", text)
            return nil
        }
        return value
    }
}

/// Names a `Storage` accepts: the plain names the app makes ("books.json", "book-<id>.txt").
/// A name read back from a restored backup can't reach outside the app's folder.
public enum StorageNames {
    public static func isSafe(_ name: String) -> Bool {
        !name.contains("..") && name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z"#, options: .regularExpression) != nil
    }
}

/// Files in a directory, written atomically. Only `StorageNames.isSafe` names.
public struct FileStorage: Storage {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func read(_ name: String) -> String? {
        guard StorageNames.isSafe(name) else { return nil }
        return try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    public func write(_ name: String, _ content: String) {
        guard StorageNames.isSafe(name) else { return }
        // Atomic, and encrypted by Data Protection until the device is first unlocked after a restart.
        try? Data(content.utf8).write(
            to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    public func delete(_ name: String) {
        guard StorageNames.isSafe(name) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

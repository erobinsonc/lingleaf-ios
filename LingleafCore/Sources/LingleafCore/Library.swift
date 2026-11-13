import Foundation

public struct Book: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let fileName: String
    public internal(set) var paragraphCount: Int
    public var level: String?
    public var gutenbergID: Int?
    public let addedAt: Date
    public var lastOpenedAt: Date?
    /// Where to resume: the paragraph at the top of the screen.
    public var progressParagraph: Int
    /// The furthest paragraph that has been on screen (SPEC S2), which only grows. Nil in a book saved before it
    /// existed: its `progressParagraph` stands in.
    public var furthestParagraph: Int?

    /// How much has been read, 0...1: up to the furthest paragraph seen, so a book whose last paragraph has
    /// been on screen is at 100%. A one-paragraph book is 0 until opened, then 1.
    public var progress: Double {
        guard paragraphCount > 0 else { return 0 }
        let reached = max(furthestParagraph ?? 0, progressParagraph)
        guard paragraphCount > 1 else { return furthestParagraph == nil ? 0 : 1 }
        return min(1, max(0, Double(reached) / Double(paragraphCount - 1)))
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
    /// A word saved from a bundled story's own sense (`sense` is "s:" and the sense's key, S19): the
    /// story's id, and the group of words it was saved with ("went red") where it is in `context` (UTF-16).
    public var story: String?
    /// What to translate to give a story sense its meaning in another language (an English gloss, the group of
    /// words or the base form); nil when there is none to give (S19), and then nothing is translated.
    public var translationSource: String?
    public var groupStart: Int?
    public var groupEnd: Int?

    /// One spelling is saved once per sense.
    public var id: String { Self.id(word, sense) }

    public static func id(_ word: String, _ sense: String?) -> String {
        sense.map { "\(word)#\($0)" } ?? word
    }

    /// Saved while its sentence didn't tell which word it is.
    public var isUnsure: Bool { meanings != nil && sense == nil }

    /// The group of words a story sense was saved with, in `context`, when it is still there.
    public var groupRange: WordRange? {
        guard let groupStart, let groupEnd else { return nil }
        return WordRange(groupStart, groupEnd)
    }

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
    static let maxWord = TextTools.maxKey

    /// The id-forming key of a spelling (`TextTools.key`): the same wherever an id is derived.
    static func key(_ word: String) -> String { TextTools.key(word) }
    /// Dates a saved word can have (2000–2100); others are brought inside.
    static let dateRange = Date(timeIntervalSince1970: 946_684_800)...Date(timeIntervalSince1970: 4_102_444_800)
    /// A translation can be longer than what it translates (a verb group or sentence); twice the sentence's limit.
    static let maxTranslation = 2 * TextTools.maxSentence

    func bounded() -> VocabWord {
        var word = self
        word.word = TextTools.truncated(self.word, Self.maxWord)
        word.createdAt = min(max(createdAt, Self.dateRange.lowerBound), Self.dateRange.upperBound)
        word.nextReview = min(max(nextReview, Self.dateRange.lowerBound), Self.dateRange.upperBound)
        // Without invisible formatting (bidi overrides, zero-width): it is shown and read aloud.
        word.context = TextTools.truncated(TextTools.stripFormat(context), TextTools.maxSentence)
        // Same limits as where each comes from: the dictionary's IPA, a translation, a book title.
        word.phonetic = TextTools.truncated(phonetic, DictionaryEntry.maxShortField)
        word.translation = TextTools.truncated(translation, Self.maxTranslation)
        word.contextTranslation = contextTranslation.map { TextTools.truncated($0, Self.maxTranslation) }
        word.source = TextTools.truncated(source, TextTools.maxLabel)
        if let sense, !Sense.isValid(sense) { word.sense = nil }
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
        // A story sense's story and group: only for a word saved from one, the group holding the tapped form.
        let fromStory = Sense.isStory(word.sense) && word.kind == nil && word.meanings == nil
        let storyIsValid = story.map { StorySenses.isID($0, dashes: true) && $0.utf8.count <= 60 } ?? false
        if !fromStory || !storyIsValid { word.story = nil }
        // A '#' in a word would make its id read as another word's sense.
        word.word = word.word.replacingOccurrences(of: "#", with: "")
        word.translationSource = fromStory
            ? translationSource.map { TextTools.truncated(TextTools.cleanText($0), 120) }.flatMap { $0.isEmpty ? nil : $0 } : nil
        var groupIsValid = false
        // A context that was cut or cleaned no longer matches where the group was.
        if fromStory, context == word.context, let group = groupRange, group.start >= 0, group.start < group.end, group.end <= ns.length {
            groupIsValid = word.formRange.map { group.start <= $0.start && $0.end <= group.end } ?? true
        }
        if !groupIsValid {
            word.groupStart = nil
            word.groupEnd = nil
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
        let key = VocabWord.key(base)
        return words.first { $0.word == key && $0.sense == nil } ?? words.first { $0.word == key }
    }

    /// The saved word spelled `base` with exactly `sense`.
    public func word(_ base: String, sense: String?) -> VocabWord? {
        let id = VocabWord.id(VocabWord.key(base), sense)
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
        // Two senses of one story word are told apart by their meanings: "get (ponerse)" / "get (agarrar)".
        if Sense.isStory(sense) {
            guard withMeaning, !others.isEmpty else { return word.word }
            let first = word.translation.components(separatedBy: " · ").first ?? ""
            let short = first.prefix { $0 != "," && $0 != "(" }.trimmingCharacters(in: .whitespaces)
            return short.isEmpty ? word.word : "\(word.word) (\(short))"
        }
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
            book.furthestParagraph = book.furthestParagraph.map { min(max($0, 0), max(book.paragraphCount - 1, 0)) }
            return book
        }
        // Saved before contexts were capped, or restored from a backup: within bounds, once per id.
        var ids: Set<String> = []
        loaded.words = (decode([VocabWord].self, "words.json") ?? []).map { $0.bounded() }
            .filter { !$0.word.isEmpty && ids.insert($0.id).inserted }
        loaded.readingLog = decode([String: Int].self, "reading-log.json") ?? [:]
        loaded.settings = (decode(Settings.self, "settings.json") ?? Settings()).bounded()
        loaded.corrections = loadCorrections()?.corrections ?? []
        state = loaded
    }

    /// Adds the bundled stories the first time the app runs. `stories` is in the order the Library should
    /// show them, top to bottom; the Library lists the newest book first, so they are added in reverse.
    public func seedIfNeeded(_ stories: () -> [BundledStory]) {
        guard storage.read("seeded") == nil else { return }
        for story in stories().reversed() {
            addBook(title: story.title, author: BundledStory.author, text: story.text, level: story.level)
        }
        storage.write("seeded", "1")
        storage.write(Self.storiesV2Key, "1")
    }

    static let storiesV2Key = "seeded-stories-v2"

    /// Once, for an install that was seeded before the 18 stories with senses (SPEC S1): adds only those
    /// 18 (never the first three), below the learner's books, in the order A1 to C2, as ordinary books
    /// that can be deleted. The books the learner has keep their places. A story already in the library
    /// is not added again.
    public func addNewStoriesIfNeeded(_ stories: () -> [BundledStory]) {
        guard storage.read(Self.storiesV2Key) == nil, storage.read("seeded") != nil else { return }
        let new = stories().filter(\.hasSenses)
        // The mark is written once the books are saved, and only when there was something to add: a failed
        // launch (or a story list that did not load) tries again at the next one.
        guard !new.isEmpty else { return }
        let before = state.books.count
        for story in new.reversed() where BundledStory.libraryCopy(of: story.title, in: state.books) == nil {
            addBook(title: story.title, author: BundledStory.author, text: story.text, level: story.level)
        }
        // The new books went to the end of the list, which the Library shows first: move them to the start.
        let added = state.books[before...]
        state.books = Array(added) + state.books[..<before]
        saveBooks()
        storage.write(Self.storiesV2Key, "1")
    }

    // MARK: Books

    @discardableResult
    public func addBook(title: String, author: String, text original: String, level: String? = nil, gutenbergID: Int? = nil) -> Book {
        // Without invisible formatting characters (bidi overrides, zero-width, byte-order mark): the
        // text is shown, read aloud and cut into words and sentences.
        let text = TextTools.stripFormat(original)
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
        // A text that can't be read (missing, too large, locked) shows nothing and changes nothing:
        // neither the count nor the place in the book is made up from an empty text.
        guard let stored = storage.read(state.books[index].fileName) else { return [] }
        state.books[index].lastOpenedAt = now()
        let text = TextTools.stripFormat(stored)
        let paragraphs = TextTools.splitParagraphs(text)
        // A book stored before invisible formatting was stripped: when that changes its text, the
        // text is stored again once, and only if that is confirmed the count and the place follow.
        if text != stored {
            storage.write(state.books[index].fileName, text)
            if storage.read(state.books[index].fileName) == text {
                followStrippedText(index, stored: stored, count: paragraphs.count)
            }
        }
        saveBooks()
        return paragraphs
    }

    /// The book at `index` now has `count` paragraphs because its stored text lost invisible
    /// characters. The place in the book moves back by the paragraphs before it that were made only
    /// of them (a place on one of them goes to the next paragraph, one past the end to the last).
    private func followStrippedText(_ index: Int, stored: String, count: Int) {
        let all = TextTools.splitParagraphs(stored)
        func moved(_ place: Int) -> Int {
            let removed = all.prefix(max(place, 0)).filter {
                TextTools.stripFormat($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            return min(max(place - removed, 0), max(count - 1, 0))
        }
        state.books[index].paragraphCount = count
        state.books[index].progressParagraph = moved(state.books[index].progressParagraph)
        state.books[index].furthestParagraph = state.books[index].furthestParagraph.map(moved)
    }

    /// Updates progress in memory; call `flush()` to persist (e.g. when leaving the reader).
    public func updateProgress(_ id: String, paragraph: Int) {
        guard let index = state.books.firstIndex(where: { $0.id == id }),
              state.books[index].progressParagraph != paragraph else { return }
        state.books[index].progressParagraph = paragraph
        // What has been on screen includes where the reader is.
        raiseFurthest(index, paragraph)
    }

    /// A paragraph of the book has been on screen (SPEC S2): the furthest seen only grows, and stays inside
    /// the book. In memory; `flush()` persists.
    public func markSeen(_ id: String, paragraph: Int) {
        guard let index = state.books.firstIndex(where: { $0.id == id }) else { return }
        raiseFurthest(index, paragraph)
    }

    private func raiseFurthest(_ index: Int, _ paragraph: Int) {
        let last = max(state.books[index].paragraphCount - 1, 0)
        let seen = min(max(paragraph, 0), last)
        if seen > (state.books[index].furthestParagraph ?? -1) { state.books[index].furthestParagraph = seen }
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

    /// Whether a word of a story sense of this kind may be saved: not a name or a word from another language.
    public static func canSave(storyKind: StorySense.Kind?) -> Bool { storyKind != .name && storyKind != .foreign }

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
        sense: String? = nil, form: String? = nil, formRange: WordRange? = nil, meanings: [SavedMeaning]? = nil,
        story: String? = nil, groupRange: WordRange? = nil, translationSource: String? = nil, storyKind: StorySense.Kind? = nil
    ) -> VocabWord? {
        // A name or a word from another language is spelled like a common word ("Long" in "Mr. Long"): never saved.
        // Callers ask `canSave(storyKind:)` first: a refusal is not "no previous word" (which Undo would delete).
        if !Self.canSave(storyKind: storyKind) { return nil }
        let key = VocabWord.key(word)
        let sense = kind == nil ? sense.flatMap { Sense.isValid($0) ? $0 : nil } : nil
        let existing = kind == nil ? state.saved(key, sense: sense) : state.word(key, sense: nil)
        // The same form saved unsure, now saved as one of its readings: it takes its place.
        let unsure = sense == nil ? nil : form
            .flatMap { state.word(VocabWord.key($0), sense: nil) }
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
        // A story sense keeps its story and the group it was saved with (the sentence may change, the range follows it).
        let fromStory = Sense.isStory(sense)
        // A word saved before as a plain word and now as a story sense loses the old meaning, which was for the
        // spelling and may be the false one ("free": "gratis"); it is filled again from the sense.
        if fromStory, let existing, existing.sense == nil {
            entry.translation = ""
            entry.translationLanguage = nil
            entry.phonetic = ""
        }
        entry.story = fromStory ? story : nil
        entry.translationSource = fromStory ? translationSource : nil
        entry.groupStart = fromStory ? groupRange?.start : nil
        entry.groupEnd = fromStory ? groupRange?.end : nil
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
            deleteWord(VocabWord.key(word), sense: sense)
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
        let id = VocabWord.id(VocabWord.key(word), sense)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, var entry = state.words.first(where: { $0.id == id }),
              entry.translation.isEmpty || entry.translationLanguage != language else { return }
        entry.translation = text
        entry.translationLanguage = language
        entry.waitsForMeaning = nil
        replace(entry)
    }

    /// Records the translation of a word's sentence that arrived after it was saved.
    public func setContextTranslation(_ word: String, _ text: String, language: String, sense: String? = nil) {
        let id = VocabWord.id(VocabWord.key(word), sense)
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
        // A story sense is translated from its own source, and from nothing when it has none (S19).
        state.words.filter {
            !$0.isUnsure && ($0.translation.isEmpty || $0.translationLanguage != target)
                && (!Sense.isStory($0.sense) || $0.translationSource != nil)
        }
    }

    /// A story sense with no source to translate has no meaning in another language than the one it was
    /// saved in: the old meaning (Spanish, say) is cleared when the language changes, so a wrong one is not
    /// shown under another language. Review then keeps the translated sentence.
    public func clearUntranslatableStoryMeanings(_ target: String) {
        var changed = false
        let words = state.words.map { word -> VocabWord in
            guard Sense.isStory(word.sense), word.translationSource == nil, !word.translation.isEmpty,
                  word.translationLanguage != target else { return word }
            var cleared = word
            cleared.translation = ""
            cleared.translationLanguage = nil
            changed = true
            return cleared
        }
        guard changed else { return }
        state.words = words
        save(state.words, "words.json")
    }

    public func answerReview(_ word: String, sense: String? = nil, correct: Bool) {
        let id = VocabWord.id(VocabWord.key(word), sense)
        guard var entry = state.words.first(where: { $0.id == id }) else { return }
        let result = Srs.review(box: entry.box, correct: correct, now: now(), calendar: calendar)
        entry.box = result.box
        entry.nextReview = result.nextReview
        entry.learned = result.learned
        replace(entry)
    }

    public func setLearned(_ word: String, _ learned: Bool, sense: String? = nil) {
        let id = VocabWord.id(VocabWord.key(word), sense)
        guard var entry = state.words.first(where: { $0.id == id }) else { return }
        entry.learned = learned
        if !learned {
            entry.box = 0
            entry.nextReview = now()
        }
        replace(entry)
    }

    public func deleteWord(_ word: String, sense: String? = nil) {
        let id = VocabWord.id(VocabWord.key(word), sense)
        state.words.removeAll { $0.id == id }
        save(state.words, "words.json")
    }

    func replace(_ entry: VocabWord) {
        // Every saved word passes here: whatever a caller hands in, nothing huge is kept.
        let entry = entry.bounded()
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
    private let maxBytes: Int

    public init(directory: URL, maxBytes: Int = Limits.maxBytes) {
        self.directory = directory
        self.maxBytes = maxBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Reads at most `maxBytes`: a larger file (a restored backup, a file put there by hand) is
    /// refused rather than read into memory whole.
    public func read(_ name: String) -> String? {
        guard StorageNames.isSafe(name),
              let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent(name)) else { return nil }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            return nil
        }
        guard data.count <= maxBytes else { return nil }
        return String(data: data, encoding: .utf8)
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

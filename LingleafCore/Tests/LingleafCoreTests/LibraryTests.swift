import XCTest
@testable import LingleafCore

final class MemoryStorage: Storage {
    var files: [String: String] = [:]

    func read(_ name: String) -> String? { files[name] }
    func write(_ name: String, _ content: String) { files[name] = content }
    func delete(_ name: String) { files[name] = nil }
}

final class LibraryTests: XCTestCase {
    private let storage = MemoryStorage()
    private var now = ISO8601DateFormatter().date(from: "2026-10-09T09:00:00Z")!
    private let stories = [
        BundledStory(title: "The Red Boat", level: "A1", text: "All animals are equal.\n\nThe end."),
        BundledStory(title: "A Day at the Market", level: "A2", text: "A short story."),
    ]
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func library() -> Library {
        let library = Library(storage: storage, now: { [unowned self] in self.now }, calendar: calendar)
        library.load()
        return library
    }

    func testKeepsACopyOfAFileThatCannotBeRead() {
        storage.files["words.json"] = "not json"
        let library = library()
        XCTAssertTrue(library.state.words.isEmpty)
        XCTAssertEqual(storage.files["words.json.corrupt"], "not json")
    }

    func testSeedsBundledStoriesOnce() {
        let library = library()
        library.seedIfNeeded { stories }
        library.seedIfNeeded { stories }
        XCTAssertEqual(library.state.books.map(\.title), ["The Red Boat", "A Day at the Market"])
        XCTAssertEqual(library.state.books.first?.level, "A1")
        XCTAssertEqual(library.state.books.first?.paragraphCount, 2)

        let reloaded = self.library()
        reloaded.seedIfNeeded { stories }
        XCTAssertEqual(reloaded.state.books.count, 2, "books persist and are not seeded twice")
    }

    func testOpenProgressAndDeleteABook() {
        let library = library()
        let book = library.addBook(title: "Alice", author: "Lewis Carroll", text: "One.\n\nTwo.\n\nThree.", level: "B2", gutenbergID: 11)
        XCTAssertEqual(library.openBook(book.id), ["One.", "Two.", "Three."])
        XCTAssertEqual(library.state.lastOpened?.id, book.id)

        library.updateProgress(book.id, paragraph: 2)
        library.flush()
        XCTAssertEqual(self.library().state.books.first?.progress, 1)

        library.deleteBook(book.id)
        XCTAssertTrue(library.state.books.isEmpty)
        XCTAssertNil(storage.read(book.fileName))
        XCTAssertEqual(library.openBook("missing"), [])
        library.deleteBook("missing")
    }

    func testLearningWordsHighlightInflectedFormsAndSurviveRestart() {
        let library = library()
        var changes = 0
        library.onChange = { _ in changes += 1 }
        library.saveWord("Animal", learned: false, translation: "animal", context: "All animals are equal.", source: "The Red Boat")
        XCTAssertGreaterThan(changes, 0)
        XCTAssertTrue(library.isLearning("animals"))
        XCTAssertFalse(library.isLearning("equal"))
        XCTAssertTrue(library.dueWords().isEmpty, "a new word is first reviewed tomorrow")
        now = ISO8601DateFormatter().date(from: "2026-10-10T04:00:00Z")!
        XCTAssertEqual(library.dueWords().map(\.word), ["animal"], "due from 04:00 the next day")

        library.saveWord("animal", learned: true, translation: " ")
        XCTAssertFalse(library.isLearning("animals"))
        let saved = self.library().state.word("animal")
        XCTAssertEqual(saved?.learned, true)
        XCTAssertEqual(saved?.translation, "animal", "blank values don't overwrite saved ones")
        XCTAssertEqual(saved?.context, "All animals are equal.")
    }

    func testReviewAnswersScheduleTheNextReview() {
        let library = library()
        library.saveWord("equal", learned: false)
        now = now.addingTimeInterval(86_400)
        XCTAssertEqual(library.dueWords().first?.box, 0)
        library.answerReview("equal", correct: true)
        XCTAssertTrue(library.dueWords().isEmpty)
        now = now.addingTimeInterval(86_400)
        XCTAssertEqual(library.dueWords().first?.box, 1)

        library.answerReview("equal", correct: false)
        XCTAssertEqual(library.dueWords().first?.box, 0)
        library.answerReview("missing", correct: true)
    }

    func testMarkingLearnedAndBackAndDeletingWords() {
        let library = library()
        library.saveWord("bay", learned: false)
        library.setLearned("bay", true)
        XCTAssertTrue(library.dueWords().isEmpty)
        library.setLearned("bay", false)
        XCTAssertEqual(library.dueWords().map(\.word), ["bay"])
        library.setLearned("missing", true)
        library.deleteWord("bay")
        XCTAssertTrue(library.state.words.isEmpty)
    }

    func testSavingAKnownWordPutsItBackToReview() {
        let library = library()
        library.saveWord("bay", learned: false)
        library.answerReview("bay", correct: true)
        library.saveWord("bay", learned: true)
        now = now.addingTimeInterval(60)
        library.saveWord("bay", learned: false)
        let saved = library.state.word("bay")
        XCTAssertEqual(saved?.learned, false)
        XCTAssertEqual(saved?.box, 0)
        XCTAssertEqual(saved?.nextReview, ISO8601DateFormatter().date(from: "2026-10-10T04:00:00Z"), "back to a first review tomorrow")
    }

    func testReviewSessionInterleavesBooksAndCountsTomorrow() {
        let library = library()
        for word in ["a1", "a2", "a3"] { library.saveWord(word, learned: false, source: "A") }
        for word in ["b1", "b2"] { library.saveWord(word, learned: false, source: "B") }
        library.saveWord("known", learned: true, source: "A")
        XCTAssertEqual(library.dueByEndOfTomorrow(), 5)
        now = now.addingTimeInterval(86_400)
        XCTAssertEqual(Set(library.reviewSession().prefix(2).map(\.source)), ["A", "B"], "one book doesn't fill the session")
        XCTAssertEqual(library.reviewSession().count, 5)
        XCTAssertEqual(Srs.session(library.dueWords(), limit: 3).count, 3)
        for word in library.reviewSession() { library.answerReview(word.word, correct: true) }
        XCTAssertEqual(library.dueByEndOfTomorrow(), 5, "answered words are due again tomorrow")
    }

    func testSessionHoldsAtMostTwentyWords() {
        let library = library()
        for index in 0..<25 { library.saveWord("w\(index)", learned: false) }
        now = now.addingTimeInterval(86_400)
        XCTAssertEqual(library.reviewSession().count, Srs.sessionLimit)
    }

    func testContextTranslationIsKeptWithItsSentence() {
        let library = library()
        library.saveWord("sea", learned: false, translationLanguage: "es", context: "By the sea.", contextTranslation: "Junto al mar.")
        library.saveWord("sea", learned: false, contextTranslation: nil)
        XCTAssertEqual(library.state.word("sea")?.contextTranslation, "Junto al mar.")
        library.saveWord("sea", learned: false, context: "The sea is blue.")
        XCTAssertNil(library.state.word("sea")?.contextTranslation, "a new sentence drops the old translation")
        XCTAssertEqual(library.contextsNeedingTranslation("es").map(\.word), ["sea"])
        library.setContextTranslation("sea", "El mar es azul.", language: "es")
        library.setContextTranslation("sea", " ", language: "es")
        library.setContextTranslation("missing", "x", language: "es")
        let sea = self.library().state.word("sea")
        XCTAssertEqual(sea?.contextTranslation(in: "es"), "El mar es azul.")
        XCTAssertNil(sea?.contextTranslation(in: "pt"), "another language needs its own translation")
        XCTAssertTrue(library.contextsNeedingTranslation("es").isEmpty)
        XCTAssertEqual(library.contextsNeedingTranslation("pt").map(\.word), ["sea"])
    }

    func testSaveWordReturnsThePreviousRecordAndRestoreWordPutsItBack() {
        let library = library()
        XCTAssertNil(library.saveWord("Beach", learned: false, translation: "playa", translationLanguage: "es"), "a new word")
        library.restoreWord("Beach", previous: nil)
        XCTAssertNil(library.state.word("beach"), "undo of a new word removes it")

        library.saveWord("beach", learned: false, translation: "playa", translationLanguage: "es", context: "On the beach.")
        let learning = library.state.word("beach")
        now = now.addingTimeInterval(60)
        let previous = library.saveWord("beach", learned: true)
        XCTAssertEqual(previous, learning)
        XCTAssertEqual(library.state.word("beach")?.learned, true)
        library.restoreWord("beach", previous: previous)
        XCTAssertEqual(library.state.word("beach"), learning, "undo restores exactly the previous record")
        XCTAssertEqual(self.library().state.word("beach"), learning, "and persists it")

        library.deleteWord("beach")
        library.restoreWord("beach", previous: learning)
        XCTAssertEqual(library.state.word("beach"), learning, "undo of a delete")
    }

    func testSaveWordRecordsTheTranslationLanguage() {
        let library = library()
        library.saveWord("sea", learned: false, translation: "mar", translationLanguage: "es")
        XCTAssertEqual(library.state.word("sea")?.translationLanguage, "es")
        library.saveWord("sea", learned: false, translation: nil, translationLanguage: "pt")
        XCTAssertEqual(library.state.word("sea")?.translationLanguage, "es", "no translation, no change")
        library.saveWord("sea", learned: false, translation: "mar", translationLanguage: "pt")
        XCTAssertEqual(library.state.word("sea")?.translationLanguage, "pt")
    }

    func testSetTranslationFillsAMissingOrOtherLanguageTranslation() {
        let library = library()
        library.setTranslation("missing", "x", language: "es")
        XCTAssertTrue(library.state.words.isEmpty, "no-op when the word doesn't exist")

        library.saveWord("Dog", learned: false)
        library.setTranslation("dog", " ", language: "es")
        XCTAssertEqual(library.state.word("dog")?.translation, "", "blank text is ignored")
        library.setTranslation("Dog", "perro", language: "es")
        XCTAssertEqual(library.state.word("dog")?.translation, "perro")
        XCTAssertEqual(library.state.word("dog")?.translationLanguage, "es")
        library.setTranslation("dog", "can", language: "es")
        XCTAssertEqual(library.state.word("dog")?.translation, "perro", "no-op when already translated in that language")
        library.setTranslation("dog", "cachorro", language: "pt")
        XCTAssertEqual(library.state.word("dog")?.translation, "cachorro", "another language replaces it")
        XCTAssertEqual(self.library().state.word("dog")?.translationLanguage, "pt")
    }

    func testWordsNeedingTranslation() {
        let library = library()
        library.saveWord("one", learned: false)
        library.saveWord("two", learned: false, translation: "dos", translationLanguage: "es")
        library.saveWord("three", learned: true, translation: "três", translationLanguage: "pt")
        library.saveWord("four", learned: false, translation: "cuatro")
        XCTAssertEqual(Set(library.wordsNeedingTranslation("es").map(\.word)), ["one", "three", "four"])
        XCTAssertEqual(Set(library.wordsNeedingTranslation("pt").map(\.word)), ["one", "two", "four"])
    }

    func testWordsSavedBeforeTranslationLanguageDecode() throws {
        storage.files["words.json"] = #"[{"word": "cat", "translation": "gato", "phonetic": "", "context": "", "source": "", "#
            + #""learned": false, "box": 0, "createdAt": "2026-10-01T09:00:00Z", "nextReview": "2026-10-01T09:00:00Z"}]"#
        let word = try XCTUnwrap(library().state.word("cat"))
        XCTAssertEqual(word.translation, "gato")
        XCTAssertNil(word.translationLanguage)
        XCTAssertNil(word.kind)
        XCTAssertNil(word.base)
    }

    func testHelperAndModalVerbsAreSavedAsTheirVerbGroup() throws {
        let library = library()
        library.saveWord("did not go", learned: false, translation: "no fue", translationLanguage: "es", kind: .helper, base: "do")
        library.saveWord("doesn't like", learned: false, kind: .helper, base: "do")
        library.saveWord("Do", learned: true, translation: "hacer", translationLanguage: "es")
        let reloaded = self.library()
        let past = try XCTUnwrap(reloaded.state.word("Did not go"))
        XCTAssertEqual(past.kind, .helper)
        XCTAssertEqual(past.base, "do")
        XCTAssertEqual(past.translation, "no fue", "each verb group is its own record")
        XCTAssertEqual(reloaded.state.word("doesn't like")?.base, "do")
        XCTAssertNil(reloaded.state.word("do")?.kind, "\"do\" as a word stays separate")
        XCTAssertEqual(library.wordsNeedingTranslation("es").map(\.word), ["doesn't like"])
        XCTAssertFalse(library.isLearning("did"), "a verb group doesn't underline the helper everywhere")
    }

    func testReadingTimeFeedsTodayAndTheStreak() {
        let library = library()
        library.addReadingTime(240)
        XCTAssertEqual(library.secondsToday(), 240)
        XCTAssertEqual(library.streak(), 0)
        library.addReadingTime(360)
        XCTAssertEqual(library.streak(), 1)
        library.addReadingTime(0)
        library.addReadingTime(99_999)
        XCTAssertEqual(self.library().secondsToday(), 600 + 3600, "a session counts at most one hour")
    }

    func testSettingsPersistAndCorruptFilesFallBackToDefaults() {
        let library = library()
        library.updateSettings {
            $0.dailyGoalMinutes = 20
            $0.targetLanguage = "pt"
        }
        XCTAssertEqual(self.library().state.settings.dailyGoalMinutes, 20)

        storage.files["settings.json"] = "{broken"
        XCTAssertEqual(self.library().state.settings, Settings())
        storage.files["settings.json"] = "{}"
        XCTAssertEqual(self.library().state.settings, Settings())
    }

    // S10 Import: the file picker can't be driven by UI tests, so the import rules are covered here.
    func testImportTitleIsTheFileNameWithoutItsExtension() {
        XCTAssertEqual(Library.importTitle(fileName: "Alice.txt"), "Alice")
        XCTAssertEqual(Library.importTitle(fileName: "my.story.TXT"), "my.story")
        XCTAssertEqual(Library.importTitle(fileName: ".txt"), "Book")
        XCTAssertEqual(Library.importTitle(fileName: "  Notes .txt"), "Notes")
    }

    func testImportTextStripsBoilerplateAndAddsTheBook() throws {
        let library = library()
        let raw = "The Project Gutenberg eBook\n*** START OF THE PROJECT GUTENBERG EBOOK ALICE ***\n"
            + "Chapter 1\n\nDown the rabbit hole.\n*** END OF THE PROJECT GUTENBERG EBOOK ALICE ***\nLicense text."
        let book = try library.importText(fileName: "Alice.txt", text: raw)
        XCTAssertEqual(book.title, "Alice")
        XCTAssertEqual(book.author, "—")
        XCTAssertEqual(book.paragraphCount, 2)
        XCTAssertEqual(library.state.books.map(\.id), [book.id])
        XCTAssertEqual(library.openBook(book.id), ["Chapter 1", "Down the rabbit hole."])
    }

    func testImportTextRefusesEmptyOrBoilerplateOnlyText() {
        let library = library()
        XCTAssertThrowsError(try library.importText(fileName: "empty.txt", text: "  \n\n ")) {
            XCTAssertEqual($0 as? ImportError, .empty)
        }
        let boilerplateOnly = "Header\n*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\n"
            + "*** END OF THE PROJECT GUTENBERG EBOOK X ***\nFooter"
        XCTAssertThrowsError(try library.importText(fileName: "x.txt", text: boilerplateOnly))
        XCTAssertTrue(library.state.books.isEmpty, "nothing is added")
        XCTAssertNil(storage.files["books.json"], "nothing is saved")
    }

    func testStorageAcceptsOnlyTheAppsOwnFileNames() throws {
        for name in ["books.json", "book-1760000000000-0.txt", "words.json.corrupt", "seeded"] {
            XCTAssertTrue(StorageNames.isSafe(name), name)
        }
        for name in ["../secret", "a/b", ".hidden", "", "book-..txt", String(repeating: "a", count: 200)] {
            XCTAssertFalse(StorageNames.isSafe(name), name)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let outside = dir.deletingLastPathComponent().appendingPathComponent("lingleaf-outside.txt")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        XCTAssertNil(FileStorage(directory: dir).read("../lingleaf-outside.txt"), "a restored book can't name a file outside")
    }

    func testAHugeSavedContextIsCutWhenLoaded() {
        library().saveWord("sea", learned: false, context: String(repeating: "sea ", count: 5_000))
        XCTAssertEqual(library().state.word("sea")?.context.utf16.count, TextTools.maxSentence)
    }

    func testLearningWordsFollowTheSavedWords() {
        let library = library()
        library.saveWord("sea", learned: false)
        library.saveWord("boat", learned: true)
        XCTAssertEqual(library.state.learningWords, ["sea"])
    }

    func testFileStorageRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = FileStorage(directory: dir)
        XCTAssertNil(files.read("a.txt"))
        files.write("a.txt", "hello")
        XCTAssertEqual(files.read("a.txt"), "hello")
        files.delete("a.txt")
        XCTAssertNil(files.read("a.txt"))
    }
}

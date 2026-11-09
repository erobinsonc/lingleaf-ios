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

    /// Whether the first `word` of `sentence` is underlined as a word being learned.
    private func learning(_ library: Library, _ word: String, in sentence: String) -> Bool {
        let found = (sentence as NSString).range(of: word)
        XCTAssertNotEqual(found.location, NSNotFound, "\(word) not in \(sentence)")
        return library.isLearning(sentence, WordRange(found.location, found.location + found.length))
    }

    func testRestoredSettingsAndBooksAreBroughtBackIntoRange() {
        storage.files["settings.json"] = #"{"dailyGoalMinutes": 0, "fontSize": 900, "speechRate": -3}"#
        let library = library()
        XCTAssertEqual(library.state.settings.dailyGoalMinutes, 5, "a goal of 0 would make every day count")
        XCTAssertEqual(library.state.settings.fontSize, 34)
        XCTAssertEqual(library.state.settings.speechRate, 0.3)
        XCTAssertLessThanOrEqual(library.streak(), maxStreakDays, "the streak always ends")
        XCTAssertEqual(readingStreak([:], goalSeconds: 0, today: now, calendar: calendar), maxStreakDays)
    }

    func testRestoredReadingProgressStaysInsideTheBook() throws {
        let book = library().addBook(title: "T", author: "A", text: "One.\n\nTwo.")
        let saved = try XCTUnwrap(storage.files["books.json"])
        storage.files["books.json"] = saved.replacingOccurrences(
            of: #""progressParagraph"\s*:\s*0"#, with: #""progressParagraph":-7"#, options: .regularExpression
        )
        XCTAssertEqual(library().state.books.first { $0.id == book.id }?.progressParagraph, 0)
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
        // Added last first: the Library lists the newest first, so it shows them in the order given.
        XCTAssertEqual(library.state.books.reversed().map(\.title), ["The Red Boat", "A Day at the Market"])
        XCTAssertEqual(library.state.books.last?.level, "A1")
        XCTAssertEqual(library.state.books.last?.paragraphCount, 2)

        let reloaded = self.library()
        reloaded.seedIfNeeded { stories }
        XCTAssertEqual(reloaded.state.books.count, 2, "books persist and are not seeded twice")
    }

    func testBundledStoriesAreListedByLevelAndFoundInTheLibrary() {
        // A1 to C2, the first three (no senses) at the start of their own level.
        XCTAssertEqual(BundledStory.shelf.map(\.level), ["A1", "A1", "A1", "A1", "A2", "A2", "A2", "A2", "B1", "B1", "B1", "B1",
                                                          "B2", "B2", "B2", "C1", "C1", "C1", "C2", "C2", "C2"])
        XCTAssertEqual(BundledStory.shelf(level: "A2").map(\.title),
                       ["A Day at the Market", "A Part for Lila", "The Oven Next Door", "The Tree in the Second Row"])
        XCTAssertEqual(BundledStory.shelf(level: "C2").count, 3)
        XCTAssertEqual(BundledStory.shelf(level: nil).count, BundledStory.shelf.count)
        XCTAssertTrue(BundledStory.shelf(level: "C3").isEmpty)
        XCTAssertEqual(BundledStory.shelf.filter(\.hasSenses).count, 18)
        XCTAssertEqual(Set(BundledStory.shelf.map(\.resource)).count, BundledStory.shelf.count)
        XCTAssertEqual(Set(BundledStory.shelf.map(\.title)).count, BundledStory.shelf.count)

        let library = library()
        library.seedIfNeeded { stories }
        let copy = BundledStory.libraryCopy(of: "A Day at the Market", in: library.state.books)
        XCTAssertEqual(copy?.author, BundledStory.author)
        let imported = library.addBook(title: "The Lighthouse Keeper", author: "Someone", text: "Text.")
        let keeper = BundledStory.libraryCopy(of: "The Lighthouse Keeper", in: library.state.books)
        XCTAssertNil(keeper, "another author's book is not the story")
        XCTAssertNil(BundledStory.shelfStory(for: imported), "an import with a story's title is not the story")
        XCTAssertEqual(BundledStory.shelfStory(for: copy!)?.resource, "a-day-at-the-market")
        let downloaded = library.addBook(title: "The Red Boat", author: BundledStory.author, text: "Text.", gutenbergID: 1)
        XCTAssertNil(BundledStory.shelfStory(for: downloaded), "a Gutenberg book is not a story")
        library.deleteBook(imported.id)
        library.deleteBook(copy!.id)
        XCTAssertNil(BundledStory.libraryCopy(of: "A Day at the Market", in: library.state.books), "deleted: Discover offers it again")
    }

    private var shelfStories: [BundledStory] {
        BundledStory.shelf.map { BundledStory(title: $0.title, level: $0.level, text: "One.\n\nTwo.", hasSenses: $0.hasSenses) }
    }

    func testAFirstLaunchListsTheStoriesFromA1ToC2() {
        let library = library()
        library.seedIfNeeded { shelfStories }
        XCTAssertEqual(library.state.books.reversed().map(\.title), BundledStory.shelf.map(\.title), "the Library shows the newest first")
        XCTAssertEqual(library.state.books.reversed().first?.title, "The Red Boat")
        XCTAssertEqual(library.state.books.reversed().prefix(6).compactMap(\.level), ["A1", "A1", "A1", "A1", "A2", "A2"])
        XCTAssertNotNil(storage.files["seeded-stories-v2"], "a new install needs no later migration")
        library.addNewStoriesIfNeeded { shelfStories }
        XCTAssertEqual(library.state.books.count, 21)
    }

    /// An install seeded before the 18 stories: they come below the learner's books, once.
    private func oldInstall(deleting deleted: [String] = []) -> Library {
        let old = library()
        old.seedIfNeeded { Array(self.shelfStories.filter { !$0.hasSenses }) }
        storage.files["seeded-stories-v2"] = nil
        for title in deleted { old.deleteBook(BundledStory.libraryCopy(of: title, in: old.state.books)!.id) }
        return old
    }

    func testAnUpdateAddsOnlyTheNewStoriesBelowTheLearnersBooks() {
        let old = oldInstall()
        let mine = old.addBook(title: "My Book", author: "Me", text: "Hello there.")
        let before = old.state.books.reversed().map(\.title)
        let reloaded = library()
        reloaded.addNewStoriesIfNeeded { shelfStories }
        let shown = reloaded.state.books.reversed().map(\.title)
        XCTAssertEqual(Array(shown.prefix(before.count)), before, "the books the learner has keep their places")
        XCTAssertEqual(shown.first, "My Book")
        XCTAssertEqual(Array(shown.dropFirst(before.count)), BundledStory.shelf.filter(\.hasSenses).map(\.title), "A1 to C2")
        XCTAssertEqual(shown.count, 3 + 1 + 18)
        XCTAssertEqual(reloaded.state.books.filter { $0.title == "The Red Boat" }.count, 1, "the first three are not added again")
        XCTAssertNotNil(mine)
        reloaded.addNewStoriesIfNeeded { shelfStories }
        XCTAssertEqual(reloaded.state.books.count, 22, "once")
        let again = library()
        again.addNewStoriesIfNeeded { shelfStories }
        XCTAssertEqual(again.state.books.count, 22, "also after a restart")
    }

    func testAnUpdateDoesNotBringBackTheFirstThreeTheLearnerDeleted() {
        let old = oldInstall(deleting: ["The Red Boat", "A Day at the Market", "The Lighthouse Keeper"])
        XCTAssertTrue(old.state.books.isEmpty)
        old.addNewStoriesIfNeeded { shelfStories }
        XCTAssertEqual(old.state.books.count, 18, "an empty Library gets the 18, not the first three")
        XCTAssertNil(BundledStory.libraryCopy(of: "The Red Boat", in: old.state.books))
    }

    func testANewInstallIsNotMigratedWhenNothingWasSeeded() {
        let fresh = library()
        fresh.addNewStoriesIfNeeded { shelfStories }
        XCTAssertTrue(fresh.state.books.isEmpty, "seedIfNeeded does the first launch")
        XCTAssertNil(storage.files["seeded-stories-v2"])
    }

    func testTwoStorySensesOfOneWordAreTwoEntries() {
        let library = library()
        let sentence = "She got sad. He got the bags."
        library.saveWord("get", learned: false, translation: "ponerse (+ adjetivo)", translationLanguage: "es", context: sentence,
                         sense: Sense.story("get_become"), form: "got", formRange: WordRange(4, 7), story: "a-test-story")
        library.saveWord("get", learned: false, translation: "agarrar, tomar", translationLanguage: "es", context: sentence,
                         sense: Sense.story("get_fetch"), form: "got", formRange: WordRange(16, 19), story: "a-test-story")
        XCTAssertEqual(library.state.words.count, 2, "one entry per sense")
        let names = library.state.words.map { library.state.displayName($0) }.sorted()
        XCTAssertEqual(names, ["get (agarrar)", "get (ponerse)"], "told apart by their meanings")
        XCTAssertEqual(library.state.displayName(library.state.words[0], withMeaning: false), "get", "Review recalls first")
        XCTAssertTrue(library.state.promptShowsSentence(library.state.words[0]), "and shows the sentence")
        XCTAssertEqual(library.state.word("get", sense: Sense.story("get_fetch"))?.translation, "agarrar, tomar")
        // Saving the same sense again is the same entry.
        library.saveWord("get", learned: false, translation: "agarrar, tomar", context: sentence,
                         sense: Sense.story("get_fetch"), story: "a-test-story")
        XCTAssertEqual(library.state.words.count, 2)
        let reloaded = self.library()
        XCTAssertEqual(reloaded.state.words.count, 2, "both survive a restart")
        XCTAssertEqual(reloaded.state.words.first { $0.sense == Sense.story("get_fetch") }?.story, "a-test-story")
        // A single story sense shows the plain word.
        library.deleteWord("get", sense: Sense.story("get_become"))
        XCTAssertEqual(library.state.displayName(library.state.words[0]), "get")
    }

    func testAGroupSavedFromAStorySenseKeepsItsRange() {
        let library = library()
        let sentence = "Then his face went red."
        library.saveWord("go red", learned: false, translation: "ponerse colorado", translationLanguage: "es", context: sentence,
                         sense: Sense.story("go_red"), form: "went", formRange: WordRange(14, 18), story: "a-test-story",
                         groupRange: WordRange(5, 22))
        let word = library.state.words[0]
        XCTAssertEqual(word.word, "go red")
        XCTAssertEqual(word.groupRange, WordRange(5, 22))
        XCTAssertEqual(TextTools.substring(word.context, word.groupRange!), "his face went red")
        XCTAssertEqual(word.groupRange.map { [$0] } ?? [], [WordRange(5, 22)])
    }

    /// What a restored or edited file may hold in the story fields is brought inside.
    func testStoryFieldsAreBounded() {
        func word(sense: String?, story: String?, group: (Int, Int)?) -> VocabWord {
            var word = VocabWord(word: "go red", translation: "x", translationLanguage: nil, phonetic: "", context: "His face went red.",
                                 source: "", learned: false, box: 0, createdAt: now, nextReview: now)
            word.sense = sense
            word.story = story
            word.form = "went"
            word.formStart = 9
            word.formEnd = 13
            word.groupStart = group?.0
            word.groupEnd = group?.1
            return word.bounded()
        }
        let kept = word(sense: "s:go_red", story: "a-test-story", group: (0, 17))
        XCTAssertEqual(kept.story, "a-test-story")
        XCTAssertEqual(kept.groupRange, WordRange(0, 17))
        XCTAssertNil(word(sense: "s:Go Red", story: "a-test-story", group: (0, 17)).sense, "an unknown sense is dropped")
        XCTAssertNil(word(sense: Sense.verb, story: "a-test-story", group: (0, 17)).story, "only a story sense has a story")
        XCTAssertNil(word(sense: Sense.verb, story: nil, group: (0, 17)).groupRange)
        XCTAssertNil(word(sense: "s:go_red", story: "Bad Story!", group: (0, 17)).story)
        XCTAssertNil(word(sense: "s:go_red", story: "a-test-story", group: (0, 99)).groupRange, "past the sentence")
        XCTAssertNil(word(sense: "s:go_red", story: "a-test-story", group: (10, 17)).groupRange, "must hold the tapped word")
        XCTAssertNil(word(sense: "s:go_red", story: "a-test-story", group: (5, 5)).groupRange)
        XCTAssertNil(word(sense: "s:go_red", story: "a-test-story", group: (-1, 5)).groupRange)
    }

    func testTheMigrationMarkIsWrittenOnlyAfterTheBooksAreAdded() {
        let old = oldInstall()
        old.addNewStoriesIfNeeded { [] }
        XCTAssertNil(storage.files["seeded-stories-v2"], "nothing to add: try again at the next launch")
        old.addNewStoriesIfNeeded { shelfStories }
        XCTAssertNotNil(storage.files["seeded-stories-v2"])
        XCTAssertEqual(old.state.books.count, 21)
    }

    /// A story sense is translated from its own source, never from the bare spelling (SPEC S19).
    func testAStorySenseIsTranslatedFromItsSourceOrNotAtAll() {
        let library = library()
        library.saveWord("floor", learned: false, translation: nil, context: "The sixth floor.", sense: Sense.story("floor_storey"),
                         story: "a-test-story", translationSource: nil)
        library.saveWord("free", learned: false, context: "My oven is free.", sense: Sense.story("free_available"),
                         story: "a-test-story", translationSource: "not busy, available")
        library.saveWord("cat", learned: false, context: "A cat.")
        let needing = library.wordsNeedingTranslation("fr").map(\.word).sorted()
        XCTAssertEqual(needing, ["cat", "free"], "no source, no translation: the bare lemma of floor is not translated")
        let floor = library.state.word("floor", sense: Sense.story("floor_storey"))!
        let free = library.state.word("free", sense: Sense.story("free_available"))!
        XCTAssertNil(ReadingTranslation.source(for: floor))
        XCTAssertEqual(ReadingTranslation.source(for: free), "not busy, available", "the gloss, not the word")
        XCTAssertEqual(ReadingTranslation.source(for: library.state.word("cat")!), "cat")
        // A meaning saved in Spanish is cleared, not translated from the lemma, when the language changes.
        library.setTranslation("floor", "piso", language: "es", sense: Sense.story("floor_storey"))
        XCTAssertEqual(library.state.word("floor", sense: Sense.story("floor_storey"))?.translation, "piso")
        library.clearUntranslatableStoryMeanings("fr")
        XCTAssertEqual(library.state.word("floor", sense: Sense.story("floor_storey"))?.translation, "")
        XCTAssertTrue(library.wordsNeedingTranslation("fr").map(\.word).contains("free"), "free is translated from its gloss")
        library.clearUntranslatableStoryMeanings("fr")
        XCTAssertEqual(library.state.word("free", sense: Sense.story("free_available"))?.translationSource, "not busy, available")
    }

    func testANameOrAForeignWordIsNotSaved() {
        let library = library()
        XCTAssertNil(library.saveWord("long", learned: false, context: "Mr. Long.", sense: Sense.story("long_name"),
                                      story: "a-test-story", storyKind: .name))
        XCTAssertNil(library.saveWord("bunica", learned: false, context: "Bunica.", sense: Sense.story("bunica"),
                                      story: "a-test-story", storyKind: .foreign))
        XCTAssertTrue(library.state.words.isEmpty)
        library.saveWord("go red", learned: false, context: "Went red.", sense: Sense.story("go_red"), story: "a-test-story", storyKind: .chunk)
        XCTAssertEqual(library.state.words.count, 1)
    }

    func testAPlainWordSavedAsAStorySenseLosesItsOldMeaning() {
        let library = library()
        library.saveWord("free", learned: false, translation: "gratis", translationLanguage: "es", phonetic: "/fri/", context: "Free food.")
        library.saveWord("free", learned: false, context: "My oven is free.", sense: Sense.story("free_available"),
                         story: "a-test-story", translationSource: "not busy")
        XCTAssertEqual(library.state.words.count, 1)
        XCTAssertEqual(library.state.words[0].translation, "", "the false meaning does not stay")
        XCTAssertEqual(library.state.words[0].phonetic, "")
    }

    func testWordsSavedBeforeStorySensesStillLoad() {
        storage.files["words.json"] = """
        [{"word":"cat","translation":"gato","phonetic":"","context":"A cat.","source":"","learned":false,"box":0,
          "createdAt":"2026-10-01T00:00:00Z","nextReview":"2026-10-02T00:00:00Z"}]
        """
        let loaded = library()
        XCTAssertEqual(loaded.state.words.first?.word, "cat")
        XCTAssertNil(loaded.state.words.first?.story)
        XCTAssertNil(loaded.state.words.first?.translationSource)
    }

    func testAWordWithAHashDoesNotBecomeAnotherWordsSense() {
        var word = VocabWord(word: "a#verb", translation: "x", translationLanguage: nil, phonetic: "", context: "a",
                             source: "", learned: false, box: 0, createdAt: now, nextReview: now)
        word.sense = Sense.story("x")
        XCTAssertFalse(word.bounded().word.contains("#"))
        XCTAssertFalse(word.bounded().id.hasPrefix("a#verb"))
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
        XCTAssertTrue(learning(library, "animals", in: "All animals are equal."))
        XCTAssertFalse(learning(library, "equal", in: "All animals are equal."))
        XCTAssertTrue(library.dueWords().isEmpty, "a new word is first reviewed tomorrow")
        now = ISO8601DateFormatter().date(from: "2026-10-10T04:00:00Z")!
        XCTAssertEqual(library.dueWords().map(\.word), ["animal"], "due from 04:00 the next day")

        library.saveWord("animal", learned: true, translation: " ")
        XCTAssertFalse(learning(library, "animals", in: "All animals are equal."))
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

    func testLearningWordsAreMarkedOnlyWhereTheirSentenceMakesThemThatWord() {
        let library = library()
        library.saveWord("leaf", learned: false)
        XCTAssertTrue(learning(library, "leaves", in: "The dead leaves fell."))
        XCTAssertFalse(learning(library, "leaves", in: "She leaves at nine."), "\"leaves\" here is \"leave\", not \"leaf\"")
        library.saveWord("leave", learned: false)
        XCTAssertTrue(learning(library, "leaves", in: "She leaves at nine."))
        XCTAssertTrue(learning(library, "left", in: "She left the house early."))
        XCTAssertFalse(learning(library, "left", in: "Turn left at the church."), "the side, not the verb")
        library.saveWord("steal", learned: false)
        XCTAssertTrue(learning(library, "stole", in: "He stole the bread."))
        XCTAssertTrue(learning(library, "stolen", in: "It was stolen."))
    }

    func testLearningRangesMarkAWholeParagraphInOnePass() {
        let library = library()
        let paragraph = "Turn left, then she left. The dead leaves fell."
        let words = TextTools.wordRanges(paragraph)
        XCTAssertTrue(library.learningRanges(paragraph, words).isEmpty, "nothing being learned")
        library.saveWord("leave", learned: false)
        library.saveWord("leaf", learned: false)
        let marked = library.learningRanges(paragraph, words).sorted { $0.start < $1.start }.map { TextTools.substring(paragraph, $0) }
        XCTAssertEqual(marked, ["left", "leaves"], "the verb \"left\" and the noun \"leaves\", not the side")
        XCTAssertEqual(library.learningRanges(paragraph, words), Set(words.filter { library.isLearning(paragraph, $0) }))
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
        XCTAssertFalse(learning(library, "did", in: "He did it."), "a verb group doesn't underline the helper everywhere")
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
        for name in ["../secret", "a/b", ".hidden", "", "book-..txt", "books.json\n", String(repeating: "a", count: 200)] {
            XCTAssertFalse(StorageNames.isSafe(name), name)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let outside = dir.deletingLastPathComponent().appendingPathComponent("lingleaf-outside.txt")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertNil(FileStorage(directory: dir).read("../lingleaf-outside.txt"), "a restored book can't name a file outside")
    }

    func testAHugeContextIsNeverSaved() {
        let library = library()
        library.saveWord("sea", learned: false, context: String(repeating: "sea ", count: 5_000),
                         contextTranslation: String(repeating: "mar ", count: 5_000))
        let saved = library.state.word("sea")
        XCTAssertEqual(saved?.context.utf16.count, TextTools.maxSentence)
        XCTAssertLessThanOrEqual(saved?.contextTranslation?.utf16.count ?? 0, 2 * TextTools.maxSentence)
    }

    func testAHugeSavedContextIsCutWhenLoaded() {
        library().saveWord("sea", learned: false, context: String(repeating: "sea ", count: 5_000))
        XCTAssertEqual(library().state.word("sea")?.context.utf16.count, TextTools.maxSentence)
    }

    /// A restored or edited words file can't put megabytes in the fields the app shows.
    func testHugeSavedFieldsAreCutWhenLoaded() throws {
        library().saveWord("sea", learned: false, translation: "mar", translationLanguage: "es", context: "The sea.")
        let saved = Data(try XCTUnwrap(storage.files["words.json"]).utf8)
        var words = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [[String: Any]])
        let huge = String(repeating: "x", count: 50_000)
        for field in ["phonetic", "translation", "contextTranslation", "source"] { words[0][field] = huge }
        storage.files["words.json"] = String(decoding: try JSONSerialization.data(withJSONObject: words), as: UTF8.self)
        let loaded = try XCTUnwrap(library().state.word("sea"))
        XCTAssertEqual(loaded.phonetic.utf16.count, DictionaryEntry.maxShortField)
        XCTAssertEqual(loaded.translation.utf16.count, VocabWord.maxTranslation)
        XCTAssertEqual(loaded.contextTranslation?.utf16.count, VocabWord.maxTranslation)
        XCTAssertEqual(loaded.source.utf16.count, TextTools.maxLabel)
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
        files.write("empty.txt", "")
        XCTAssertEqual(files.read("empty.txt"), "", "an empty file reads as empty, not missing")
    }

    /// A file over the cap (a restored backup, a file put there by hand) is refused, not read whole.
    func testFileStorageRefusesFilesOverTheByteCap() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = FileStorage(directory: dir, maxBytes: 8)
        files.write("fits.txt", "12345678")
        XCTAssertEqual(files.read("fits.txt"), "12345678")
        files.write("big.txt", "123456789")
        XCTAssertNil(files.read("big.txt"))
        XCTAssertNil(files.read("missing.txt"))
        XCTAssertEqual(FileStorage(directory: dir).read("big.txt"), "123456789", "the default cap is Limits.maxBytes")
    }
}

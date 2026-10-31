import XCTest
@testable import LingleafCore

/// The words corrected after updating (SPEC S18): read again in their sentences, in runs, with
/// Undo; and how saved words are bounded on load.
final class CorrectionsTests: XCTestCase {
    private let storage = MemoryStorage()
    private var now = ISO8601DateFormatter().date(from: "2026-10-09T09:00:00Z")!

    private func library() -> Library {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let library = Library(storage: storage, now: { [unowned self] in self.now }, calendar: calendar)
        library.load()
        return library
    }

    func testWordsSavedWithTheOldListAreCorrectedOnceAndCanBeUndone() throws {
        storage.files["settings.json"] = #"{"targetLanguage": "es"}"#
        var library = library()
        library.saveWord("leave", learned: false, translation: "irse", context: "Turn left at the church.")
        library.saveWord("life", learned: false, translation: "vida", context: "Tom lives in a small house.")
        library.saveWord("feel", learned: true, translation: "sentir", context: "Left is the answer, she felt.")
        library.saveWord("find", learned: false, context: "They found it.", sense: Sense.verb)
        library.saveWord("rise", learned: false, translation: "subir", context: "Left is the answer.")
        library.saveWord("see", learned: false, translation: "ver", context: "First you saw it.")
        library.saveWord("cat", learned: false, translation: "gato", context: "The cat sat.")
        library.saveWord("did not go", learned: false, context: "He did not go.", kind: .helper, base: "do")
        let before = library.state.words
        let corrections = library.correctWordsIfNeeded()
        XCTAssertEqual(Set(corrections), [Correction(from: "leave", to: "left"), Correction(from: "life", to: "live")])
        let left = try XCTUnwrap(library.state.word("left", sense: Sense.noun))
        XCTAssertEqual(left.translation, "", "translated again")
        XCTAssertEqual(left.nextReview, now, "due now")
        XCTAssertEqual(left.box, 0, "it starts its review again")
        XCTAssertEqual(left.waitsForMeaning, true)
        XCTAssertFalse(library.dueWords().contains { $0.id == left.id }, "not due until it has a meaning")
        library.setTranslation("left", "izquierda", language: "es", sense: Sense.noun)
        XCTAssertTrue(library.dueWords().contains { $0.id == left.id }, "due once its meaning arrives")
        XCTAssertEqual(left.formRange, WordRange(5, 9))
        XCTAssertEqual(library.state.word("live", sense: Sense.verb)?.form, "lives", "Tom lives: now a certain verb")
        XCTAssertEqual(library.state.word("feel")?.translation, "sentir", "read the same in its sentence: unchanged")
        XCTAssertNotNil(library.state.word("rise"), "no homograph of the sentence was linked to it")
        XCTAssertEqual(library.state.corrections.count, 2)
        XCTAssertTrue(library.correctWordsIfNeeded().isEmpty, "only once")
        library = self.library()
        XCTAssertEqual(library.state.corrections.count, 2, "the card stays until closed")
        library.saveWord("new", learned: false)
        XCTAssertEqual(library.undoCorrections(), 0, "all put back")
        XCTAssertEqual(Set(library.state.words.map(\.id)), Set(before.map(\.id) + ["new"]), "all back; a word saved since stays")
        XCTAssertEqual(library.state.word("leave")?.box, before.first { $0.id == "leave" }?.box, "with its review box")
        XCTAssertTrue(library.state.corrections.isEmpty)
        library.closeCorrections()
        library.undoCorrections()
        XCTAssertTrue(self.library().state.corrections.isEmpty)
    }

    func testAnUnsureSentenceMakesTheWordItsTappedFormWithBothReadings() throws {
        storage.files["settings.json"] = #"{"targetLanguage": "es"}"#
        let library = library()
        library.saveWord("leave", learned: false, context: "Left is the answer.")
        library.saveWord("left", learned: false, sense: Sense.noun)
        library.saveWord("think", learned: false, context: "They found it, the old thought.")
        library.correctWordsIfNeeded()
        let left = try XCTUnwrap(library.state.word("left", sense: nil))
        XCTAssertEqual(left.meanings?.map(\.label), ["to leave", "the left"])
        XCTAssertEqual(left.meanings?.first?.text, "irse, salir", "the table's meaning in Spanish")
        XCTAssertEqual(left.meanings?.last?.text, "", "translated later")
        XCTAssertEqual(Set(library.state.corrections), [Correction(from: "leave", to: "left"), Correction(from: "think", to: "thought")])
        XCTAssertEqual(library.state.word("thought", sense: Sense.noun)?.form, "thought")
    }

    func testCorrectingIntoAWordAlreadySavedMergesIntoIt() throws {
        let library = library()
        library.saveWord("left", learned: false, translation: "izquierda", sense: Sense.noun)
        library.saveWord("leave", learned: false, translation: "irse", context: "Turn left now.")
        library.correctWordsIfNeeded()
        XCTAssertEqual(library.state.words.map(\.id), ["left#noun"])
        XCTAssertEqual(library.state.words.first?.translation, "izquierda", "the one saved stays")
    }

    func testUndoPutsBackOnlyWhatTheCorrectionChanged() throws {
        let library = library()
        library.saveWord("left", learned: false, translation: "izquierda", context: "She left early.")
        library.saveWord("leave", learned: false, translation: "irse", context: "Some left.")
        library.saveWord("cat", learned: false, translation: "gato", context: "The cat sat.")
        library.saveWord("see", learned: false, translation: "ver", context: "The old man saw it.")
        let before = library.state.words
        let corrections = library.correctWordsIfNeeded()
        XCTAssertEqual(Set(corrections), [Correction(from: "left", to: "leave"), Correction(from: "leave", to: "left")])
        XCTAssertNotNil(library.state.word("leave", sense: Sense.verb), "She left: the verb")
        XCTAssertEqual(library.state.word("left", sense: nil)?.isUnsure, true, "Some left: unsure, the tapped form")
        // Review after the correction: an uncorrected word keeps its progress through Undo.
        library.answerReview("cat", correct: true)
        let cat = try XCTUnwrap(library.state.word("cat"))
        library.undoCorrections()
        XCTAssertEqual(library.state.word("left", sense: nil), before.first { $0.id == "left" }, "both originals back, by id")
        XCTAssertEqual(library.state.word("leave", sense: nil), before.first { $0.id == "leave" })
        XCTAssertNil(library.state.word("leave", sense: Sense.verb))
        XCTAssertEqual(library.state.word("cat"), cat, "progress made since stays")
    }

    func testUndoLeavesAWordReviewedOrDeletedSinceAsItIsNow() throws {
        let library = library()
        library.saveWord("leave", learned: false, translation: "irse", context: "Turn left now.")
        library.saveWord("feel", learned: false, translation: "sentir", context: "She wore a felt hat.")
        library.correctWordsIfNeeded()
        library.setTranslation("left", "izquierda", language: "es", sense: Sense.noun)
        library.answerReview("left", sense: Sense.noun, correct: true)
        let reviewed = try XCTUnwrap(library.state.word("left", sense: Sense.noun))
        library.deleteWord("felt", sense: Sense.noun)
        XCTAssertEqual(library.undoCorrections(), 2, "two stay as they are now: the message says so")
        XCTAssertEqual(library.state.word("left", sense: Sense.noun), reviewed, "reviewed since: it stays")
        XCTAssertNil(library.state.word("leave"), "and the old one doesn't come back over it")
        XCTAssertNil(library.state.word("feel"), "deleted since: not brought back")
    }

    func testAWordChangedWhileCorrectionsRanIsLeftAlone() throws {
        let library = library()
        library.saveWord("leave", learned: false, context: "Turn left now.")
        let run = try XCTUnwrap(library.beginCorrections())
        let planned = Library.plannedCorrections(run, target: nil, now: now)
        XCTAssertEqual(planned.changes.count, 1)
        library.saveWord("leave", learned: true, context: "Turn left now.")
        XCTAssertTrue(library.applyCorrections(planned).isEmpty, "changed meanwhile: left as it is")
        XCTAssertEqual(library.state.word("leave")?.learned, true)
        XCTAssertEqual(storage.read(Library.correctionsDone), "done")
    }

    func testAWordThatHasItsMeaningWaitsForNothing() throws {
        let library = library()
        library.saveWord("leave", learned: false, context: "Turn left at the bank.")
        library.correctWordsIfNeeded()
        XCTAssertEqual(library.state.word("left", sense: Sense.noun)?.waitsForMeaning, true)
        XCTAssertTrue(library.dueWords().isEmpty)
        // Saved again from the card, with its translation.
        library.saveWord("left", learned: false, translation: "izquierda", translationLanguage: "es", sense: Sense.noun)
        XCTAssertNil(library.state.word("left", sense: Sense.noun)?.waitsForMeaning)
        XCTAssertEqual(library.dueWords().map(\.id), ["left#noun"])
        // A restored file can't keep a word with a meaning waiting.
        let restored = MemoryStorage()
        restored.files["corrections-v2"] = "done"
        restored.files["words.json"] = """
        [{"word": "cat", "translation": "gato", "translationLanguage": "es", "phonetic": "", "context": "", "source": "",
          "learned": false, "box": 0, "createdAt": "2026-01-01T00:00:00Z", "nextReview": "2026-01-01T00:00:00Z",
          "waitsForMeaning": true}]
        """
        let other = Library(storage: restored, now: { [unowned self] in self.now })
        other.load()
        XCTAssertNil(other.state.words.first?.waitsForMeaning)
        XCTAssertEqual(other.dueWords().count, 1)
    }

    private func vocab(_ word: String, _ context: String, _ created: Date, box: Int = 0) -> VocabWord {
        VocabWord(
            word: word, translation: "x", translationLanguage: nil, phonetic: "", context: context, source: "",
            learned: false, box: box, createdAt: created, nextReview: created
        )
    }

    /// `words` as the saved file, read by a new library.
    private func saved(_ words: [VocabWord]) -> Library {
        let writer = library()
        writer.state.words = words
        writer.save(words, "words.json")
        return library()
    }

    func testTiesAtARunsEndAreReadOnTheNextRun() {
        let same = now
        // "leave" comes after every "a…" of the same moment: past the first run's end.
        let library = saved((0..<Library.maxCorrectedWords).map { vocab("a\($0)", "A cat.", same) }
            + [vocab("leave", "Turn left at the bank.", same)])
        XCTAssertEqual(library.state.words.count, Library.maxCorrectedWords + 1)
        library.correctWordsIfNeeded()
        XCTAssertTrue(storage.read(Library.correctionsDone)?.hasPrefix("after:") == true)
        library.correctWordsIfNeeded()
        XCTAssertEqual(storage.read(Library.correctionsDone), "done")
        XCTAssertNotNil(library.state.word("left", sense: Sense.noun))
        XCTAssertNil(library.state.word("leave"))
    }

    func testAnUnsortedFileIsReadNewestFirstSoNothingIsSkipped() {
        let old = now - 86_400 * 365
        let library = saved((0..<Library.maxCorrectedWords).map { vocab("w\($0)", "A cat.", old) }
            + [vocab("leave", "Turn left at the bank.", now)])
        for _ in 0..<3 { library.correctWordsIfNeeded() }
        XCTAssertEqual(storage.read(Library.correctionsDone), "done")
        XCTAssertNotNil(library.state.word("left", sense: Sense.noun))
    }

    func testAHostileCorrectionsFlagStartsOver() {
        let date = now.timeIntervalSinceReferenceDate
        let flags = [
            "after:", "after:zzzz", "after:" + String(repeating: "9", count: 100_000), "after:\(date)\t", "garbage",
            "after:\(date)|left", "after:1e308\tx", "after:\(Date.distantPast.timeIntervalSinceReferenceDate)\tx",
            "after:\(date + 1)\t" + String(repeating: "a", count: Library.maxCursorID + 1),
        ]
        for flag in flags {
            storage.files.removeAll()
            storage.files["corrections-v2"] = flag
            let library = saved([vocab("leave", "Turn left at the bank.", now)])
            library.correctWordsIfNeeded()
            XCTAssertEqual(storage.read(Library.correctionsDone), "done", String(flag.prefix(12)))
            XCTAssertNotNil(library.state.word("left", sense: Sense.noun), String(flag.prefix(12)))
        }
        storage.files["corrections-v2"] = "1"
        XCTAssertNil(library().beginCorrections(), "done before runs")
    }

    func testEachRunCorrectsAtMostWhatUndoCanHold() throws {
        let records = (1..<Library.maxCorrections).map { #"{"from": "a\#($0)", "to": "b"}"# }.joined(separator: ",")
        storage.files["corrections.json"] = #"{"corrections": [\#(records)], "changes": []}"#
        var library = saved([vocab("leave", "Turn left at the bank.", now), vocab("feel", "The felt hat.", now - 86_400)])
        XCTAssertEqual(library.state.corrections.count, Library.maxCorrections - 1)
        library.correctWordsIfNeeded()
        XCTAssertEqual(library.state.corrections.count, Library.maxCorrections)
        XCTAssertNotNil(library.state.word("left", sense: Sense.noun))
        XCTAssertNotNil(library.state.word("feel"), "no room left to undo it: the next run")
        let cursor = try XCTUnwrap(storage.read(Library.correctionsDone))
        XCTAssertTrue(cursor.hasPrefix("after:"))
        library = self.library()
        XCTAssertTrue(library.correctWordsIfNeeded().isEmpty, "no room at all: nothing read")
        XCTAssertEqual(storage.read(Library.correctionsDone), cursor, "and the cursor is kept")
        library.closeCorrections()
        library.correctWordsIfNeeded()
        XCTAssertNotNil(library.state.word("felt", sense: Sense.noun))
        XCTAssertEqual(storage.read(Library.correctionsDone), "done")
    }

    func testCorrectionsOfTwoRunsAreOneCardAndUndoPutsBackBoth() throws {
        let library = saved([vocab("think", "They found it, the old thought.", now), vocab("leave", "Turn left now.", now - 60)])
        let before = library.state.words
        let run = try XCTUnwrap(library.beginCorrections())
        // As if Undo had room for one only.
        let first = Library.plannedCorrections(CorrectionsRun(words: run.words, eligible: run.eligible, room: 1), target: nil, now: now)
        library.applyCorrections(first)
        XCTAssertEqual(library.state.corrections, [Correction(from: "think", to: "thought")])
        let next = self.library()
        XCTAssertEqual(next.correctWordsIfNeeded(), [Correction(from: "leave", to: "left")], "the next launch: the rest")
        XCTAssertEqual(next.state.corrections.count, 2, "added to the card still open")
        next.undoCorrections()
        XCTAssertEqual(Set(next.state.words), Set(before), "Undo puts back both runs")
    }

    func testTwoWordsThatSwapAreBothKeptAndUndoGivesBothBack() throws {
        // The newer "leave" (from "Left.") becomes the unsure "left" while the older "left" becomes "leave".
        let words = [vocab("leave", "Left.", now), vocab("left", "She left early.", now - 86_400)]
        let library = saved(words)
        let before = library.state.words
        library.correctWordsIfNeeded()
        XCTAssertEqual(Set(library.state.words.map(\.id)), ["left", "leave#verb"])
        XCTAssertEqual(library.state.word("left")?.context, "Left.")
        XCTAssertEqual(library.state.word("leave", sense: Sense.verb)?.context, "She left early.")
        XCTAssertEqual(library.state.corrections.count, 2)
        XCTAssertTrue(try XCTUnwrap(library.loadCorrections()).changes.allSatisfy { $0.mergedInto == nil }, "none merged")
        library.undoCorrections()
        XCTAssertEqual(Set(library.state.words), Set(before), "both originals back, each as it was")
    }

    func testUndoPutsBackBothWordsWhateverTheOrder() {
        for context in ["Nothing left.", "Left.", "What is left?", "Is any left?", "Some left.", "Those left."] {
            storage.files.removeAll()
            let b = vocab("left", "She left early.", now)
            let a = vocab("leave", context, now - 86_400)
            let library = saved([b, a])
            let before = library.state.words
            library.correctWordsIfNeeded()
            library.undoCorrections()
            XCTAssertEqual(Set(library.state.words.map(\.id)), ["left", "leave"], context)
            XCTAssertEqual(Set(library.state.words), Set(before), "each as it was: \(context)")
        }
    }

    func testUndoNeverHoldsMoreThanItCanAndItsLimitCountsTheChanges() throws {
        func word(_ name: String) -> String {
            """
            {"word": "\(name)", "translation": "", "phonetic": "", "context": "", "source": "", "learned": false, "box": 0,
             "createdAt": "2026-10-01T00:00:00Z", "nextReview": "2026-10-01T00:00:00Z"}
            """
        }
        // A record whose changes outnumber its lines (a restored or edited file): Undo is full.
        let changes = (0..<Library.maxCorrections).map { #"{"before": \#(word("w\($0)")), "mergedInto": "x"}"# }
        storage.files["corrections.json"] = #"{"corrections": [], "changes": [\#(changes.joined(separator: ","))]}"#
        let library = saved([vocab("leave", "Turn left at the bank.", now)])
        XCTAssertEqual(try XCTUnwrap(library.beginCorrections()).room, 0)
        XCTAssertTrue(library.correctWordsIfNeeded().isEmpty, "no room: nothing read")
        XCTAssertNil(storage.read(Library.correctionsDone), "and the next run starts where this one would have")
        XCTAssertNotNil(library.state.word("leave"))
    }

    func testTheCorrectionsCursorReadsBackWhatItWrote() throws {
        // The longest word saved (a verb group without one is its sentence), newest.
        let long = vocab(String(repeating: "a", count: VocabWord.maxWord + 50), "A cat.", now)
        let library = saved([long, vocab("leave", "Turn left now.", now - 60)])
        let stored = try XCTUnwrap(library.state.words.first)
        XCTAssertEqual(stored.word.utf16.count, VocabWord.maxWord, "cut to size when saved and loaded")
        let run = try XCTUnwrap(library.beginCorrections())
        // A run that stops after the long word.
        let plan = Library.plannedCorrections(CorrectionsRun(words: [run.words[0]], eligible: run.eligible, room: 1), target: nil, now: now)
        library.applyCorrections(plan)
        XCTAssertTrue(storage.read(Library.correctionsDone)?.hasSuffix("\t" + stored.id) == true)
        XCTAssertEqual(library.beginCorrections()?.words.map(\.word), ["leave"], "the next run starts after it")
        library.saveWord(String(repeating: "b", count: 2000), learned: false)
        XCTAssertNotNil(library.state.words.first { $0.word.utf16.count == VocabWord.maxWord && $0.word.hasPrefix("b") })
    }

    func testALongSavedWordCantStallTheCorrectionsCursor() {
        // A full run ends on a word with a 250-character id: the next run must read past it.
        let filler = (0..<(Library.maxCorrectedWords - 1)).map { vocab("w\($0)", "A cat.", now) }
        let long = vocab(String(repeating: "z", count: 250), "A cat.", now - 86_400)
        let library = saved(filler + [long, vocab("leave", "Turn left at the bank.", now - 86_400 * 400)])
        library.correctWordsIfNeeded()
        XCTAssertTrue(storage.read(Library.correctionsDone)?.hasPrefix("after:") == true)
        library.correctWordsIfNeeded()
        XCTAssertNotNil(library.state.word("left", sense: Sense.noun), "the second run reads the rest")
        XCTAssertEqual(storage.read(Library.correctionsDone), "done")
        XCTAssertLessThanOrEqual(VocabWord.id(String(repeating: "a", count: VocabWord.maxWord), Sense.homonym).utf16.count,
                                 Library.maxCursorID, "every id fits the cursor")
    }

    func testSavedDatesOutsideTheirRangeAreBroughtInsideOnLoad() throws {
        storage.files["words.json"] = """
        [{"word": "old", "translation": "", "phonetic": "", "context": "", "source": "", "learned": false, "box": 0,
          "createdAt": "1990-01-01T00:00:00Z", "nextReview": "2300-01-01T00:00:00Z"}]
        """
        let word = try XCTUnwrap(library().state.words.first)
        XCTAssertEqual(word.createdAt, VocabWord.dateRange.lowerBound)
        XCTAssertEqual(word.nextReview, VocabWord.dateRange.upperBound)
    }

    func testUndoDoesntBringBackAWordMergedIntoOneDeletedSince() {
        var left = vocab("left", "", now)
        left.sense = Sense.noun
        let library = saved([vocab("leave", "Turn left.", now - 60), left])
        library.correctWordsIfNeeded()
        XCTAssertEqual(library.loadCorrections()?.changes.first?.mergedInto, "left#noun")
        library.deleteWord("left", sense: Sense.noun)
        library.undoCorrections()
        XCTAssertTrue(library.state.words.isEmpty)
    }

    func testACorrectedVerbGetsTheTablesMeaningAndIPAAndAnotherLinkKeepsAWord() throws {
        storage.files["settings.json"] = #"{"targetLanguage": "es"}"#
        let library = library()
        library.saveWord("wound", learned: true, context: "She wound the clock.")
        library.saveWord("leave", learned: false, context: "He left, and she was leaving too.")
        library.correctWordsIfNeeded()
        let wind = try XCTUnwrap(library.state.word("wind", sense: Sense.verb))
        XCTAssertEqual(wind.phonetic, "/waɪnd/")
        XCTAssertEqual(wind.translation, "enrollar, dar cuerda · serpentear")
        XCTAssertTrue(wind.learned, "a known word stays known")
        XCTAssertNotNil(library.state.word("leave"), "leaving still leads to it: left as it is")
    }

    func testRestoredCorrectionsAreBoundedOnLoad() throws {
        func word(_ name: String, _ date: String) -> String {
            """
            {"word": "\(name)", "translation": "", "phonetic": "", "context": "", "source": "", "learned": false, "box": 2,
             "createdAt": "\(date)", "nextReview": "\(date)"}
            """
        }
        storage.files["corrections.json"] = """
        {"corrections": [{"from": "\(String(repeating: "a", count: 99))", "to": "b\u{202E}"}],
         "changes": [{"before": \(word("ok", "2026-10-01T00:00:00Z")), "after": \(word("ok2", "2026-10-01T00:00:00Z"))},
                     {"before": \(word("old", "1990-01-01T00:00:00Z"))},
                     {"before": \(word("ok3", "2026-10-01T00:00:00Z")), "after": \(word("bad", "2200-01-01T00:00:00Z"))}]}
        """
        let library = library()
        let correction = try XCTUnwrap(library.state.corrections.first)
        XCTAssertEqual(correction.from.count, 40)
        XCTAssertEqual(correction.to, "b", "no invisible formatting")
        XCTAssertEqual(library.loadCorrections()?.changes.map(\.before.word), ["ok"], "out-of-range dates refused")
    }
}

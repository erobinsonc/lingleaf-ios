import XCTest
@testable import LingleafCore

/// Readings to choose, Listen, senses of saved words and how they are marked (SPEC S3, S4, S6, S7);
/// the corrected words are in `CorrectionsTests`.
final class SensesTests: XCTestCase {
    private let table = IrregularVerbs.shared
    private let storage = MemoryStorage()
    private var now = ISO8601DateFormatter().date(from: "2026-10-09T09:00:00Z")!

    private func library() -> Library {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let library = Library(storage: storage, now: { [unowned self] in self.now }, calendar: calendar)
        library.load()
        return library
    }

    private func range(_ word: String, in text: String) -> WordRange {
        let ranges = TextTools.wordRanges(text).filter { TextTools.substring(text, $0) == word }
        XCTAssertFalse(ranges.isEmpty, "\(word) not in \(text)")
        return ranges.first ?? WordRange(0, 0)
    }

    private func marked(_ library: Library, _ text: String) -> [String] {
        library.learningRanges(text, TextTools.wordRanges(text)).sorted { $0.start < $1.start }.map { TextTools.substring(text, $0) }
    }

    // MARK: Choices (S3)

    func testAnUnsureWordOffersItsTwoReadingsMostCommonFirst() {
        func labels(_ word: String, _ text: String) -> [String] { table.choices(in: text, at: range(word, in: text)).map(\.label) }
        XCTAssertEqual(labels("Left", "Left is the answer."), ["to leave", "the left"])
        XCTAssertEqual(labels("Wind", "Wind is strong here."), ["the wind", "to wind"], "wind is mostly a noun")
        XCTAssertEqual(labels("lay", "They lay bricks."), ["to lie", "to lay"], "after they: two verbs")
        XCTAssertEqual(labels("Found", "Found is a word."), ["to find", "to found"], "no noun: its two verbs")
        XCTAssertEqual(labels("Tears", "Tears fell."), ["to tear", "the tear"])
        XCTAssertTrue(labels("left", "He left early.").isEmpty, "the sentence tells")
        XCTAssertTrue(labels("cat", "The cat sat.").isEmpty)
        XCTAssertTrue(table.choices(in: "Left.", at: WordRange(1, 3)).isEmpty, "not a word of the text")
        let choice = table.choices(in: "Left is the answer.", at: WordRange(0, 4))[1]
        XCTAssertEqual(choice.sense, Sense.noun)
        XCTAssertEqual(choice.reading, Reading(kind: .noun, base: "left", step: .unsure))
        XCTAssertEqual(choice.id, "noun:left")
    }

    func testMeaningsIPAAndSensesFromTheTable() {
        XCTAssertEqual(table.spanishMeaning(of: "leave"), "irse, salir · dejar")
        XCTAssertEqual(table.spanishMeaning(of: "leave", all: false), "irse, salir")
        XCTAssertEqual(table.spanishMeaning(of: "lie", sense: Sense.homonym), "mentir")
        XCTAssertNil(table.spanishMeaning(of: "walk"))
        XCTAssertNil(table.ipa(of: "read", verb: "read"), "base and past disagree")
        XCTAssertEqual(table.baseIPA("read"), "/riːd/")
        XCTAssertNil(table.baseIPA("leave"))
        XCTAssertEqual(table.ipa(of: "wound", verb: "wind"), "/waʊnd/")
        XCTAssertNil(table.ipa(of: "dived", verb: "dive"), "past (dove's) and participle disagree")
        XCTAssertEqual(table.slots(of: "read", in: "read"), ["base", "past", "participle"])
        XCTAssertNil(table.ipa(of: "left", verb: "leave"), "no IPA in the table")
        XCTAssertNil(table.ipa(of: "x", verb: "walk"))
        XCTAssertEqual(table.ipa(of: "reading", verb: "read"), "/ˈriːdɪŋ/")
        XCTAssertEqual(table.ipa(of: "reads", verb: "read"), "/riːdz/")
        XCTAssertEqual(table.sense(of: Reading(kind: .verb, base: "leave", step: .subject)), Sense.verb)
        XCTAssertEqual(table.sense(of: Reading(kind: .noun, base: "left", step: .fixed)), Sense.noun)
        XCTAssertNil(table.sense(of: Reading(kind: .noun, base: "rose", step: .name)), "a name is no sense")
        XCTAssertNil(table.sense(of: Reading(kind: .unsure, base: "left", step: .unsure)))
        XCTAssertEqual(table.sense(of: Reading(kind: .homonym, base: "lie", step: .table)), Sense.homonym)
        XCTAssertNil(table.sense(of: Reading(kind: .word, base: "lights", step: .ordinary)), "an ordinary word has no sense")
    }

    // MARK: Listen (S6)

    func testListenSaysTheHeadwordThenTheFormEachInItsSlot() {
        func listen(_ headword: String, _ word: String, _ text: String, _ chosen: ReadingChoice? = nil) -> String {
            table.listenText(headword: headword, in: text, at: range(word, in: text), chosen: chosen)
        }
        XCTAssertEqual(listen("wind", "wound", "It wound around the tree."), "wined, wownd")
        XCTAssertEqual(listen("wound", "wound", "The wound healed."), "wound")
        XCTAssertEqual(listen("dive", "dove", "She dove into the lake."), "dive, dohv")
        XCTAssertEqual(listen("steal", "stolen", "It was stolen."), "steal, stolen")
        XCTAssertEqual(listen("read", "read", "She had read it."), "red")
        XCTAssertEqual(listen("animal", "animals", "All animals are equal."), "animal, animals")
        XCTAssertEqual(listen("Wound", "Wound", "Wound is a word."), "Wound, wownd", "unsure: each reading, rows' order")
        XCTAssertEqual(listen("Left", "Left", "Left is the answer."), "Left", "once when they sound the same")
        let verb = table.choices(in: "Wound is a word.", at: WordRange(0, 5))[1]
        XCTAssertEqual(listen("Wound", "Wound", "Wound is a word.", verb), "wownd", "only the chosen one")
        XCTAssertEqual(table.listenText(headword: "x", in: "cat", at: WordRange(0, 9), chosen: nil), "x")
    }

    // MARK: Senses (S4)

    func testASenseMarksOnlyFormsReadAsThatSense() {
        let library = library()
        library.saveWord("wind", learned: false, sense: Sense.noun)
        XCTAssertEqual(marked(library, "The wind was cold. She wound the clock. The winds blew."), ["wind", "winds"])
        library.saveWord("wind", learned: false, sense: Sense.verb)
        XCTAssertEqual(marked(library, "She wound the clock. A winding road. She is winding it."), ["wound", "winding"],
                       "an -s or -ing form only where its sentence proves the verb")
        library.deleteWord("wind", sense: Sense.noun)
        XCTAssertEqual(marked(library, "The wind was cold."), [], "only the verb is left")
        library.saveWord("leaf", learned: false, sense: Sense.noun)
        XCTAssertEqual(marked(library, "A leaf fell. The leaves fell. She leaves at nine."), ["leaf", "leaves"])
        library.saveWord("left", learned: false, sense: Sense.noun)
        XCTAssertEqual(marked(library, "Turn left. He left early. Left is the answer."), ["left"], "unsure marks no sense")
        library.saveWord("lie", learned: false, sense: Sense.homonym)
        XCTAssertEqual(marked(library, "He lied. She is lying. He is lying to me. She is lying down. They lay down."), ["lied", "lying"])
        library.saveWord("tear", learned: false, sense: Sense.noun)
        XCTAssertEqual(marked(library, "Tears fell. Her tears fell."), ["tears"], "unsure marks no sensed word, even with one base")
    }

    func testAWordSavedUnsureMarksItsSpellingEverywhere() {
        let library = library()
        let sentence = "Left is the answer."
        let meanings = table.choices(in: sentence, at: WordRange(0, 4)).map {
            SavedMeaning(label: $0.label, sense: $0.sense, base: $0.base, text: "", language: nil)
        }
        library.saveWord("Left", learned: false, context: sentence, form: "Left", formRange: WordRange(0, 4), meanings: meanings)
        let saved = library.state.word("left", sense: nil)
        XCTAssertEqual(saved?.isUnsure, true)
        XCTAssertEqual(saved?.formRange, WordRange(0, 4))
        XCTAssertEqual(marked(library, "Turn left. He left early."), ["left", "left"])
        XCTAssertEqual(TextTools.occurrences(of: saved!, in: "Turn left. He left."), [WordRange(5, 9), WordRange(14, 18)])
    }

    func testChoosingAReadingReplacesTheWordSavedUnsureKeepingItsProgress() throws {
        let library = library()
        let sentence = "Left is the answer."
        let meanings = table.choices(in: sentence, at: WordRange(0, 4)).map {
            SavedMeaning(label: $0.label, sense: $0.sense, base: $0.base, text: "x", language: "es")
        }
        library.saveWord("left", learned: false, context: sentence, form: "Left", formRange: WordRange(0, 4), meanings: meanings)
        library.answerReview("left", correct: true)
        let progress = try XCTUnwrap(library.state.word("left", sense: nil))
        let before = library.state.words
        library.saveWord("leave", learned: false, context: sentence, sense: Sense.verb, form: "Left", formRange: WordRange(0, 4))
        let chosen = try XCTUnwrap(library.state.word("leave", sense: Sense.verb))
        XCTAssertNil(library.state.word("left", sense: nil), "replaced")
        XCTAssertEqual(chosen.box, progress.box, "review progress kept")
        XCTAssertEqual(chosen.nextReview, progress.nextReview)
        XCTAssertNil(chosen.meanings)
        let after = library.state.words
        // Meanwhile another word is saved and translated: Undo leaves it.
        library.saveWord("cat", learned: false, context: "The cat sat.")
        library.setTranslation("cat", "gato", language: "es")
        let cat = try XCTUnwrap(library.state.word("cat"))
        library.undoChange(before: before, after: after)
        XCTAssertEqual(Set(library.state.words), Set(before + [cat]), "Undo puts back only what the save touched")
        XCTAssertNil(library.state.word("leave", sense: Sense.verb))
    }

    func testOneSpellingIsSavedOncePerSenseAndNamedByIt() {
        storage.files["settings.json"] = #"{"targetLanguage": "es"}"#
        let library = library()
        library.saveWord("wind", learned: false, sense: Sense.noun)
        XCTAssertEqual(library.state.displayName(library.state.words[0]), "the wind", "a homograph: always its sense")
        library.saveWord("wind", learned: false, sense: Sense.verb)
        library.saveWord("wind", learned: true, sense: Sense.verb)
        XCTAssertEqual(library.state.words.count, 2)
        let names = Set(library.state.words.map { library.state.displayName($0) })
        XCTAssertEqual(names, ["to wind", "the wind"])
        library.saveWord("lie", learned: false, sense: Sense.verb)
        XCTAssertEqual(library.state.displayName(library.state.word("lie", sense: Sense.verb)!), "to lie", "a verb with a twin")
        library.saveWord("lie", learned: false, sense: Sense.homonym)
        let lies = Set(library.state.words.filter { $0.word == "lie" }.map { library.state.displayName($0) })
        XCTAssertEqual(lies, ["to lie (estar acostado, tumbarse)", "to lie (mentir)"], "two verb senses: their first meaning")
        library.updateSettings { $0.targetLanguage = "pt" }
        library.setTranslation("lie", "mentir (pt)", language: "pt", sense: Sense.homonym)
        let translated = Set(library.state.words.filter { $0.word == "lie" }.map { library.state.displayName($0) })
        XCTAssertEqual(translated, ["to lie", "to lie (mentir (pt))"], "another language: the translated meaning, when there is one")
        library.saveWord("odd", learned: false, sense: "colour")
        XCTAssertNil(library.state.word("odd")?.sense, "an unknown sense is not kept")
    }

    func testTwoVerbSensesAreNamedByTheFirstGroupOfTheTranslatedMeaning() throws {
        storage.files["settings.json"] = #"{"targetLanguage": "es"}"#
        let library = library()
        library.saveWord("lie", learned: false, sense: Sense.verb)
        library.saveWord("lie", learned: false, sense: Sense.homonym)
        let twin = try XCTUnwrap(library.state.word("lie", sense: Sense.homonym))
        XCTAssertEqual(library.state.displayName(twin), "to lie (mentir)")
        XCTAssertEqual(library.state.displayName(twin, withMeaning: false), "to lie", "Review's prompt: no meaning before recall")
        library.updateSettings { $0.targetLanguage = "fr" }
        library.setTranslation("lie", "mentir · tromper", language: "fr", sense: Sense.homonym)
        let fr = library.state
        XCTAssertEqual(fr.displayName(try XCTUnwrap(fr.word("lie", sense: Sense.homonym))), "to lie (mentir)", "the first group")
        XCTAssertEqual(fr.displayName(try XCTUnwrap(fr.word("lie", sense: Sense.verb))), "to lie", "no meaning yet")
    }

    func testASpellingThatIsAlsoAnotherWordIsAlwaysNamedByItsSense() throws {
        let library = library()
        library.saveWord("left", learned: false, sense: Sense.noun)
        library.saveWord("lie", learned: false, sense: Sense.homonym)
        library.saveWord("light", learned: false, sense: Sense.verb)
        library.saveWord("leave", learned: false, sense: Sense.verb)
        library.saveWord("wind", learned: false)
        let state = library.state
        func name(_ word: String, _ sense: String?) throws -> String { state.displayName(try XCTUnwrap(state.word(word, sense: sense))) }
        XCTAssertEqual(try name("left", Sense.noun), "the left", "a homograph")
        XCTAssertEqual(try name("lie", Sense.homonym), "to lie", "a verb with a twin")
        XCTAssertEqual(try name("light", Sense.verb), "to light", "mostly a noun")
        XCTAssertEqual(try name("leave", Sense.verb), "leave", "only a verb: its spelling")
        XCTAssertEqual(try name("wind", nil), "wind", "saved without a sense: as before")
        XCTAssertTrue(table.namesItsSense("Wind"))
        XCTAssertFalse(table.namesItsSense("cat"))
    }

    func testReviewAndWordsSayAWordSavedUnsureInEachReading() {
        func unsure(_ word: String, _ meanings: [(String, String)], sense: String? = nil) -> VocabWord {
            var entry = VocabWord(
                word: word, translation: "", translationLanguage: nil, phonetic: "", context: "", source: "",
                learned: false, box: 0, createdAt: now, nextReview: now
            )
            entry.sense = sense
            entry.meanings = meanings.isEmpty ? nil : meanings.map {
                SavedMeaning(label: "", sense: $0.0, base: $0.1, text: "", language: nil)
            }
            return entry
        }
        XCTAssertEqual(table.spokenSaved(unsure("wound", [(Sense.noun, "wound"), (Sense.verb, "wind")])), "wound, wownd")
        XCTAssertEqual(table.spokenSaved(unsure("left", [(Sense.verb, "leave"), (Sense.noun, "left")])), "left", "once when the same")
        XCTAssertEqual(table.spokenSaved(unsure("lying", [(Sense.verb, "lie"), (Sense.homonym, "lie")])), "lying")
        XCTAssertEqual(table.spokenSaved(unsure("tear", [], sense: Sense.verb)), "tare")
        XCTAssertEqual(table.spokenSaved(unsure("tear", [])), "tear")
    }

    func testAWordSavedBeforeSensesBecomesTheSenseItIsSavedAs() {
        let library = library()
        library.saveWord("leave", learned: false, translation: "irse")
        XCTAssertEqual(library.state.saved("leave", sense: Sense.verb)?.sense, nil, "found as the same word")
        library.saveWord("leave", learned: true, sense: Sense.verb)
        XCTAssertEqual(library.state.words.map(\.id), ["leave#verb"])
        XCTAssertEqual(library.state.words.first?.translation, "irse")
    }

    func testSavedWordFieldsAreBoundedOnLoad() throws {
        let meaning = #"{"label": "to leave", "sense": "verb", "base": "leave", "text": "irse", "language": "es"}"#
        let bad = #"{"label": "x", "sense": "spell", "base": "leave", "text": "x"}"#
        let words = """
        [{"word": "left", "translation": "", "phonetic": "", "context": "Left is it.", "source": "", "learned": false, "box": 0,
          "createdAt": "2026-10-01T00:00:00Z", "nextReview": "2026-10-01T00:00:00Z",
          "form": "Left", "formStart": 0, "formEnd": 4, "meanings": [\(meaning), \(bad), \(meaning), \(meaning)]},
         {"word": "x", "translation": "", "phonetic": "", "context": "It is x.", "source": "", "learned": false, "box": 0,
          "createdAt": "2026-10-01T00:00:00Z", "nextReview": "2026-10-01T00:00:00Z",
          "sense": "everything", "form": "x y", "formStart": 6, "formEnd": 99, "meanings": [\(bad)]},
         {"word": "y", "translation": "", "phonetic": "", "context": "It is y.", "source": "", "learned": false, "box": 0,
          "createdAt": "2026-10-01T00:00:00Z", "nextReview": "2026-10-01T00:00:00Z", "form": "y", "formStart": 0, "formEnd": 1},
         {"word": "y", "translation": "", "phonetic": "", "context": "", "source": "", "learned": false, "box": 0,
          "createdAt": "2026-10-01T00:00:00Z", "nextReview": "2026-10-01T00:00:00Z"}]
        """
        storage.files["words.json"] = words
        let state = library().state
        let left = try XCTUnwrap(state.word("left"))
        XCTAssertEqual(left.formRange, WordRange(0, 4))
        XCTAssertEqual(left.meanings?.count, 1, "at most two kept, the unknown sense dropped")
        let x = try XCTUnwrap(state.word("x"))
        XCTAssertNil(x.sense)
        XCTAssertNil(x.form, "not one word")
        XCTAssertNil(x.formStart)
        XCTAssertNil(x.meanings)
        XCTAssertNil(state.word("y")?.formRange, "the range doesn't hold the form")
        XCTAssertEqual(state.words.filter { $0.word == "y" }.count, 1, "once per id")
        let long = SavedMeaning(
            label: String(repeating: "a", count: 99), sense: Sense.noun, base: "left",
            text: String(repeating: "b", count: 999), language: String(repeating: "c", count: 30)
        ).bounded()
        XCTAssertEqual(long?.label, "the left", "the label is made from the sense and base, never read from the file")
        XCTAssertEqual(long?.text.count, SavedMeaning.maxText)
        XCTAssertNil(long?.language)
        XCTAssertEqual(SavedMeaning(label: "x", sense: Sense.homonym, base: "lie", text: "", language: nil).bounded()?.label, "to lie")
        XCTAssertNil(SavedMeaning(label: "x", sense: Sense.noun, base: "Left", text: "", language: nil).bounded())
    }

    // MARK: Translations of readings

    func testReadingsAreTranslatedAsToOrTheAndCleanedAgain() {
        XCTAssertEqual(ReadingTranslation.source(word: "leave", sense: Sense.verb), "to leave")
        XCTAssertEqual(ReadingTranslation.source(word: "lie", sense: Sense.homonym), "to tell a lie", "the twin's own English query")
        XCTAssertEqual(ReadingTranslation.source(word: "left", sense: Sense.noun), "the left")
        XCTAssertEqual(ReadingTranslation.source(word: "cat", sense: nil), "cat")
        XCTAssertEqual(ReadingTranslation.cleaned("la izquierda", noun: true, language: "es"), "izquierda")
        XCTAssertEqual(ReadingTranslation.cleaned("la izquierda.", noun: false, language: "es"), "la izquierda", "a verb keeps it")
        XCTAssertEqual(ReadingTranslation.cleaned("l'arbre", noun: true, language: "fr"), "arbre")
        XCTAssertEqual(ReadingTranslation.cleaned("zu gehen", noun: false, language: "de"), "gehen")
        XCTAssertEqual(ReadingTranslation.cleaned("att gå", noun: false, language: "sv"), "gå")
        XCTAssertEqual(ReadingTranslation.cleaned("to leave", noun: false, language: "ja"), "leave", "an English marker left in")
        XCTAssertEqual(ReadingTranslation.cleaned("The left", noun: true, language: nil), "left")
        XCTAssertEqual(ReadingTranslation.cleaned(" la ", noun: true, language: "es"), "la", "nothing after it: kept")
        XCTAssertEqual(ReadingTranslation.cleaned("lado", noun: true, language: "es"), "lado", "not an article: \"la\" + \"do\"")
        XCTAssertEqual(ReadingTranslation.cleaned("salir", noun: false, language: "es-419"), "salir")
        XCTAssertTrue(ReadingTranslation.isSpanish("es-MX"))
        XCTAssertFalse(ReadingTranslation.isSpanish("pt"))
    }

    func testSavedReadingsGetTheirMeaningsFromTheTableOrTheTranslator() throws {
        let library = library()
        let meanings = [
            SavedMeaning(label: "to leave", sense: Sense.verb, base: "leave", text: "", language: nil),
            SavedMeaning(label: "the left", sense: Sense.noun, base: "left", text: "", language: nil),
        ]
        library.saveWord("left", learned: false, context: "Left is it.", meanings: meanings)
        library.saveWord("steal", learned: false, sense: Sense.verb)
        library.fillTableTranslations("pt")
        XCTAssertEqual(library.meaningsNeedingTranslation("pt").count, 2, "not Spanish: both to translate")
        library.fillTableTranslations("es")
        XCTAssertEqual(library.state.word("steal", sense: Sense.verb)?.translation, "robar")
        let pending = library.meaningsNeedingTranslation("es")
        XCTAssertEqual(pending, [MeaningRequest(id: "left", index: 1, label: "the left")])
        XCTAssertFalse(library.wordsNeedingTranslation("es").contains { $0.word == "left" }, "translated by its readings")
        library.setMeaning("left", index: 1, text: "la izquierda", language: "es")
        library.setMeaning("left", index: 7, text: "x", language: "es")
        library.setMeaning("missing", index: 0, text: "x", language: "es")
        library.setMeaning("left", index: 0, text: " ", language: "es")
        let left = try XCTUnwrap(library.state.word("left"))
        XCTAssertEqual(left.translation, "irse, salir · izquierda")
        XCTAssertTrue(library.meaningsNeedingTranslation("es").isEmpty)
    }

    func testASavedExpressionIsMarkedWhereverItIsThatExpression() {
        let library = library()
        library.saveWord("bound for", learned: false, context: "The ship was bound for Spain.")
        let other = "The train was bound for Rome. They bound the books."
        XCTAssertEqual(marked(library, other), ["bound"], "the expression in another book, not the verb")
    }

    func testListenInReviewSaysAVerbWithItsSpokenBase() {
        XCTAssertEqual(table.spokenHeadword("wind", sense: Sense.verb), "wined")
        XCTAssertEqual(table.spokenHeadword("wind", sense: Sense.noun), "wind")
        XCTAssertEqual(table.spokenHeadword("tear", sense: Sense.verb), "tare")
        XCTAssertEqual(table.spokenHeadword("tear", sense: nil), "tear")
        XCTAssertEqual(table.spokenHeadword("sow", sense: Sense.verb), "so")
        XCTAssertEqual(table.spokenHeadword("steal", sense: Sense.verb), "steal")
    }

    func testLayAfterAPluralSubjectOffersTwoVerbs() {
        let text = "Two men lay bricks."
        XCTAssertEqual(table.choices(in: text, at: range("lay", in: text)).map(\.label), ["to lie", "to lay"])
        let lying = "She is lying."
        let rows = table.choices(in: lying, at: range("lying", in: lying))
        XCTAssertEqual(rows.map(\.label), ["to lie", "to lie"], "the verb and its twin")
        XCTAssertEqual(rows.map(\.sense), [Sense.verb, Sense.homonym])
        XCTAssertEqual(table.spanishMeaning(of: "lie", sense: rows[1].sense, all: false), "mentir")
    }

    func testNoFormInTheBundledStoriesGetsATableMeaningAgainstItsSentence() throws {
        struct Case: Decodable {
            let source: String, sentence: String, word: String, expectedBase: String, expectedVerb: Bool
        }
        struct Corpus: Decodable { let cases: [Case] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "homograph-corpus", withExtension: "json"))
        let stories = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).cases.filter { $0.source == "stories" }
        XCTAssertFalse(stories.isEmpty)
        for story in stories where !story.expectedVerb {
            let range = range(story.word, in: story.sentence)
            let base = table.base(in: story.sentence, at: range)
            XCTAssertTrue(base == nil || table.homographs[TextTools.normalize(story.word)]?.noun == base,
                          "\(story.sentence) [\(story.word)]: a verb's meaning for a word that isn't one (\(base ?? ""))")
        }
    }
}

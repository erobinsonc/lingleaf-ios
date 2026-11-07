import XCTest
@testable import LingleafCore

/// What counts as a word (SPEC S3, Shared logic): letters of any script with their combining
/// marks and apostrophes between letters, so names and loanwords keep their accents ("Joaquín",
/// "café", "Kraków"); and what the English-only features do with such a word.
final class UnicodeWordsTests: XCTestCase {
    private func words(_ text: String) -> [String] {
        TextTools.wordRanges(text).map { TextTools.substring(text, $0) }
    }

    // MARK: Tokenizer

    func testNamesAndLoanwordsWithAccentsAreOneWord() {
        XCTAssertEqual(words("Joaquín Zieliński Kraków café naïve résumé São Paulo"),
                       ["Joaquín", "Zieliński", "Kraków", "café", "naïve", "résumé", "São", "Paulo"])
        XCTAssertEqual(words("Sofía, ¿cómo estás? ¡Qué bien! Ångström, Øresund, Łódź, Đà Nẵng, Straße"),
                       ["Sofía", "cómo", "estás", "Qué", "bien", "Ångström", "Øresund", "Łódź", "Đà", "Nẵng", "Straße"])
    }

    func testComposedAndDecomposedFormsAreEachOneWordAndKeyTheSame() {
        let composed = "Joaquín café Kraków"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(composed.utf16.count, decomposed.utf16.count)
        XCTAssertEqual(words(composed).count, 3)
        XCTAssertEqual(words(decomposed), ["Joaquín", "café", "Kraków"].map { $0.decomposedStringWithCanonicalMapping })
        XCTAssertEqual(words(decomposed).map(TextTools.normalize), words(composed).map(TextTools.normalize),
                       "the same key, whichever way it is typed")
        XCTAssertEqual(TextTools.normalize("CAFE\u{0301}"), "café")
        XCTAssertEqual(TextTools.normalize("Don’t"), "don't", "ASCII as before")
        // Lower case is the Unicode full mapping of each scalar: no locale, no final sigma.
        XCTAssertEqual(TextTools.normalize("ΟΔΟΣ"), "οδοσ", "no final-sigma rule")
        XCTAssertEqual(TextTools.normalize("İ"), "i\u{0307}", "i with its dot above, not composed")
        XCTAssertEqual(TextTools.normalize("ǅ"), "ǆ")
        XCTAssertEqual(TextTools.normalize("STRASSE"), "strasse")
        // Vietnamese stacks two marks on one letter.
        XCTAssertEqual(words("Việt Nam".decomposedStringWithCanonicalMapping).count, 2)
    }

    func testMarksAloneDigitsEmojiAndPunctuationAreNotWords() {
        XCTAssertEqual(words("\u{0301}\u{0301} \u{0301}"), [], "a word of only accents")
        XCTAssertEqual(words("5\u{0301} 12 ... — ¿?"), [])
        XCTAssertEqual(words("I ❤️ café 👍🏽 😀!"), ["I", "café"])
        XCTAssertEqual(words("naïve2 3dogs"), ["naïve", "dogs"], "digits end a word, as before")
        XCTAssertEqual(words("Jean-Luc well-known"), ["Jean", "Luc", "well", "known"], "hyphens split, as before")
    }

    func testApostrophesBetweenLettersKeepAWordWhole() {
        XCTAssertEqual(words("Don’t it's l’homme O'Brien d'Artagnan"), ["Don’t", "it's", "l’homme", "O'Brien", "d'Artagnan"])
        XCTAssertEqual(words("the dogs' bones 'quoted' ’tis"), ["the", "dogs", "bones", "quoted", "tis"],
                       "an apostrophe needs a letter after it")
    }

    /// ZWNJ (U+200C, a format character) is not a letter and not a mark: it splits a word.
    func testAJoinerSplitsAWord() {
        XCTAssertEqual(words("می\u{200C}خواهم"), ["می", "خواهم"])
        XCTAssertEqual(words("a\u{200C}b a\u{200D}b"), ["a", "b", "a", "b"])
    }

    func testOtherScriptsAreWordsToo() {
        XCTAssertEqual(words("привет мир"), ["привет", "мир"])
        XCTAssertEqual(words("Ελλάδα"), ["Ελλάδα"])
        XCTAssertEqual(words("مرحبا بالعالم"), ["مرحبا", "بالعالم"], "right-to-left letters")
        XCTAssertEqual(words("שָׁלוֹם עולם"), ["שָׁלוֹם", "עולם"], "Hebrew with its points")
        XCTAssertEqual(words("我爱你，你好。"), ["我爱你", "你好"], "a run of Han letters is one word: no spaces between Chinese words")
        XCTAssertEqual(words("Tokyo東京 hello"), ["Tokyo東京", "hello"])
        XCTAssertEqual(words("한국어 ひらがな カタカナ ภาษาไทย"), ["한국어", "ひらがな", "カタカナ", "ภาษาไทย"])
    }

    func testTooManyMarksOnALetterEndTheWordAndTheExtraAreSkipped() {
        let marks = String(repeating: "\u{0301}", count: 6)
        XCTAssertEqual(words("a\(marks)b"), ["a" + String(repeating: "\u{0301}", count: TextTools.maxCombiningMarks), "b"])
        XCTAssertEqual(words(marks + marks), [])
    }

    func testWordAtFindsAnAccentedWordAndItsTrailingEdge() {
        let text = "Hola, Joaquín."
        XCTAssertEqual(TextTools.wordAt(text, 7), WordRange(6, 13))
        XCTAssertEqual(TextTools.wordAt(text, 13), WordRange(6, 13), "right after the last letter")
        let decomposed = "Hola, Joaqui\u{0301}n."
        XCTAssertEqual(TextTools.wordAt(decomposed, 10), WordRange(6, 14))
    }

    // MARK: Sentences, paragraphs and caps

    func testSentencesEndAtFullWidthAndArabicMarksToo() {
        let chinese = "你好。再见！你是谁？好"
        XCTAssertEqual(TextTools.sentenceRanges(chinese).map { TextTools.substring(chinese, $0) }, ["你好。", "再见！", "你是谁？", "好"])
        // Closing brackets after the mark stay with its sentence: 」 (U+300D) and 』 (U+300F).
        let quoted = "他说「你好。」我说『再见！』好"
        XCTAssertEqual(TextTools.sentenceRanges(quoted).map { TextTools.substring(quoted, $0) }, ["他说「你好。」", "我说『再见！』", "好"])
        let arabic = "ما اسمك؟ اسمي علي"
        XCTAssertEqual(TextTools.sentenceRanges(arabic).count, 2)
        let spanish = "¿Cómo estás? ¡Muy bien! Joaquín llegó."
        XCTAssertEqual(TextTools.sentenceRanges(spanish).map { TextTools.substring(spanish, $0) },
                       ["¿Cómo estás?", "¡Muy bien!", "Joaquín llegó."])
        XCTAssertEqual(TextTools.sentenceAt("Hola, Joaquín. Adiós.", 8), "Hola, Joaquín.")
    }

    /// A cut at the paragraph cap never separates a letter from its accents.
    func testAParagraphCutAtTheCapKeepsEveryLetterWithItsAccents() {
        for prefix in ["x", "xx", "xxx"] {
            let text = prefix + String(repeating: "e\u{0301}", count: 1500)
            let pieces = TextTools.splitParagraphs(text)
            XCTAssertGreaterThan(pieces.count, 1)
            for piece in pieces {
                XCTAssertLessThanOrEqual(piece.utf16.count, TextTools.maxParagraph)
                XCTAssertFalse(piece.unicodeScalars.first.map { $0.properties.generalCategory == .nonspacingMark } ?? false,
                               "a piece never starts with an accent")
            }
            XCTAssertEqual(pieces.joined(), text, "nothing lost or repeated")
        }
        // Spaces still win when there are any.
        let spaced = String(repeating: "Joaquín ", count: 400)
        XCTAssertTrue(TextTools.splitParagraphs(spaced).allSatisfy { $0.hasSuffix("Joaquín") })
    }

    func testALongSentenceIsReadAloudInPiecesThatKeepEveryLetterWithItsAccents() {
        let text = "x" + String(repeating: "e\u{0301}", count: 700) + " tail."
        let pieces = ReadAloud.sentences(text)
        XCTAssertGreaterThan(pieces.count, 1)
        let ns = text as NSString
        for piece in pieces {
            XCTAssertLessThanOrEqual(piece.end - piece.start, TextTools.maxSentence)
            let first = ns.character(at: piece.start)
            XCTAssertNotEqual(first, 0x0301, "a piece never starts with an accent")
        }
        // A context cut to its cap, and the sentence around a word, keep letters whole too.
        let cut = TextTools.truncated("ae\u{0301}", 2)
        XCTAssertEqual(cut, "a")
        XCTAssertEqual(TextTools.truncated("abcdé", 5), "abcdé")
        XCTAssertEqual(TextTools.truncated("a😀", 2), "a", "a surrogate pair stays whole, as before")
        let around = TextTools.sentenceRangeAt(String(repeating: "e\u{0301}", count: 1000), 500)
        XCTAssertLessThanOrEqual(around.end - around.start, TextTools.maxSentence)
        let sentence = TextTools.substring(String(repeating: "e\u{0301}", count: 1000), around)
        XCTAssertFalse(sentence.unicodeScalars.first.map { $0.properties.generalCategory == .nonspacingMark } ?? true)
    }

    // MARK: Linear time

    private func seconds(_ text: String) -> Double {
        let start = Date()
        let ranges = TextTools.wordRanges(text)
        _ = TextTools.matchKeys(in: text, words: ranges)
        _ = TextTools.sentenceRanges(text)
        _ = TextTools.splitParagraphs(text)
        return Date().timeIntervalSince(start)
    }

    /// Reading is linear in the text, whatever it is made of: about 400,000 units of each hostile
    /// shape take far less than a generous absolute bound (a quadratic pass over such text would
    /// take minutes). One retry, so a busy machine doesn't fail it.
    func testHostileUnicodeTextIsReadInLinearTime() {
        let shapes: [String: String] = [
            "marks": "\u{0301}",
            "letter and marks": "a\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\u{0306}",
            "letters with accents": "Joaquín Zieliński ",
            "Han": "我爱你，你好。",
            "Arabic": "مرحبا بالعالم؟ ",
            "emoji": "👨‍👩‍👧 é ",
            "apostrophes": "a'a'a'a ' ' a’",
        ]
        _ = seconds("warm up the shared table Joaquín")
        for (name, unit) in shapes {
            let text = String(repeating: unit, count: 400_000 / unit.utf16.count + 1)
            var elapsed = seconds(text)
            if elapsed >= 10 { elapsed = min(elapsed, seconds(text)) }
            XCTAssertLessThan(elapsed, 10, "\(name): \(text.utf16.count) units took \(elapsed) s")
        }
    }

    // MARK: English-only features

    private let table = IrregularVerbs.shared

    private func resolve(_ word: String, in sentence: String) -> Reading? {
        let ranges = TextTools.wordRanges(sentence).filter { TextTools.substring(sentence, $0) == word }
        guard let range = ranges.first else { XCTFail("\(word) not in \(sentence)"); return nil }
        return table.resolve(sentence, range)
    }

    func testBaseFormsAndVerbRulesLeaveAWordWithAnAccentAlone() {
        XCTAssertEqual(TextTools.baseFormCandidates("cafés"), [], "no English suffix rules on a word with an accent")
        XCTAssertEqual(TextTools.baseFormCandidates("Joaquín"), [])
        XCTAssertEqual(TextTools.baseFormCandidates("walked"), ["walk", "walke"], "ASCII English as before")
        XCTAssertEqual(TextTools.matchKeys("Café"), ["café"])
        XCTAssertEqual(TextTools.matchKeys("CAFE\u{0301}"), ["café"], "composed and decomposed are one key")
        XCTAssertNil(table.resolve("Joaquín ate a café.", WordRange(0, 7)), "not a form of the table")
        XCTAssertNil(table.base(in: "São Paulo", at: WordRange(0, 3)))
    }

    func testAnAccentedNameOpeningASentenceIsASubjectLikeAnyName() {
        let tom = resolve("left", in: "Tom left early.")
        XCTAssertEqual(tom?.kind, .verb)
        for name in ["Joaquín", "Ángel", "Zieliński", "Sofía"] {
            XCTAssertEqual(resolve("left", in: "\(name) left early."), tom, "\(name) like Tom")
            XCTAssertEqual(resolve("left", in: "Then \(name) saw it. \(name) left."), tom, name)
        }
        XCTAssertTrue(table.isName("Then Ángel left.", WordRange(5, 10)), "capitalised in the middle of a sentence")
        XCTAssertFalse(table.isName("Then ángel left.", WordRange(5, 10)))
        XCTAssertEqual(resolve("left", in: "Turn left at Kraków.")?.kind, .noun, "the rule still reads its other words")
    }

    func testASavedWordWithAnAccentMarksItsFormsWhateverTheTyping() throws {
        let library = Library(storage: MemoryStorage())
        library.load()
        library.saveWord("Café", learned: false, context: "A café opened.")
        XCTAssertNotNil(library.state.word("café"), "saved under its composed lower-case key")
        let text = "The CAFÉ and the cafe\u{0301} and the cafe."
        let ranges = TextTools.wordRanges(text)
        let marked = library.learningRanges(text, ranges).sorted { $0.start < $1.start }.map { TextTools.substring(text, $0) }
        XCTAssertEqual(marked, ["CAFÉ", "cafe\u{0301}"], "both forms of the saved word, not the unaccented one")
        let group = "Un Café con leche"
        XCTAssertEqual(TextTools.occurrences(of: "café con", in: group).map { TextTools.substring(group, $0) }, ["Café con"])
        let decomposed = "Un Cafe\u{0301} con leche"
        XCTAssertEqual(TextTools.occurrences(of: "café con", in: decomposed).map { TextTools.substring(decomposed, $0) },
                       ["Cafe\u{0301} con"], "offsets stay in the sentence the learner sees")
    }

    // MARK: Dictionary

    private actor Requests {
        var words: [String] = []
        func add(_ url: String) { words.append(String(url.split(separator: "/").last ?? "")) }
    }

    private func client(_ requests: Requests, known: Set<String> = ["caf%C3%A9", "cat"]) -> DictionaryClient {
        DictionaryClient(http: ClosureFetcher { url in
            let word = String(url.split(separator: "/").last ?? "")
            await requests.add(url)
            guard known.contains(word) else { return HttpResponse(status: 404, text: "[]") }
            return HttpResponse(status: 200, text: """
            [{"word": "x", "phonetic": "/x/", "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "A place."}]}]}]
            """)
        })
    }

    /// Latin-script words go to the dictionary as typed: "café", "naïve" and "résumé" are English
    /// entries; a name simply has none. Nothing in another script, mixed or over-long is sent.
    func testOnlyLatinScriptWordsAreLookedUp() async {
        let requests = Requests()
        let dictionary = client(requests)
        let cafe = await dictionary.lookup("Café")
        XCTAssertEqual(cafe?.definition, "A place.")
        let decomposed = await dictionary.lookup("CAFE\u{0301}")
        XCTAssertEqual(decomposed?.definition, "A place.", "the same entry, cached under the composed key")
        let name = await dictionary.lookup("Joaquín")
        XCTAssertNil(name, "no entry for a name")
        _ = await dictionary.lookup("Joaquín")
        for never in ["привет", "Ελλάδα", "مرحبا", "你好", "Tokyo東京", "한국어", "ภาษาไทย", "x y", "", "12",
                      String(repeating: "a", count: DictionaryClient.maxLookupWord + 1)] {
            let found = await dictionary.lookup(never)
            XCTAssertNil(found, never)
        }
        let clock = await dictionary.lookup("o'clock")
        XCTAssertNil(clock)
        let sent = await requests.words
        XCTAssertEqual(sent, ["caf%C3%A9", "joaqu%C3%ADn", "o%27clock"], "café once, the name once, o'clock; nothing else")
    }

    /// A word in an address is percent-encoded as UTF-8: no letter outside ASCII is left as it is.
    func testAccentsAreEncodedInTheAddressOfADictionaryOrCatalogRequest() async throws {
        let requests = Requests()
        _ = await client(requests).lookup("Straße")
        let sent = await requests.words
        XCTAssertEqual(sent, ["stra%C3%9Fe"])
        let urls = UrlRecorder()
        let catalog = GutenbergClient(http: ClosureFetcher { url in
            await urls.add(url)
            return HttpResponse(status: 200, text: #"{"results": []}"#)
        })
        _ = try await catalog.search("Les Misérables 東京")
        let seen = await urls.list
        XCTAssertEqual(seen.count, 1)
        XCTAssertTrue(seen[0].hasSuffix("search=Les%20Mis%C3%A9rables%20%E6%9D%B1%E4%BA%AC"), seen[0])
        XCTAssertTrue(seen[0].allSatisfy(\.isASCII), "an ASCII address")
    }

    private actor UrlRecorder {
        var list: [String] = []
        func add(_ url: String) { list.append(url) }
    }

    /// The same key wherever an id is made from a word: a run of letters longer than the cap is cut
    /// once, so it can be saved, found, translated, undone and marked.
    func testAVeryLongWordHasOneKeyEverywhere() throws {
        let long = String(repeating: "东", count: VocabWord.maxWord + 100)
        let library = Library(storage: MemoryStorage())
        library.load()
        let previous = library.saveWord(long, learned: false, context: "他说 \(long).")
        XCTAssertNil(previous)
        let key = TextTools.key(long)
        XCTAssertEqual(key.utf16.count, VocabWord.maxWord)
        XCTAssertEqual(library.state.words.map(\.word), [key])
        XCTAssertNotNil(library.state.word(long), "shown as saved")
        XCTAssertNotNil(library.state.saved(long, sense: nil))
        library.setTranslation(long, "dice", language: "es")
        library.setContextTranslation(long, "él dice", language: "es")
        XCTAssertEqual(library.state.words.first?.translation, "dice")
        XCTAssertEqual(library.state.words.first?.contextTranslation, "él dice")
        let text = long
        let ranges = TextTools.wordRanges(text)
        XCTAssertEqual(library.learningRanges(text, ranges), Set(ranges), "marked where it is read")
        library.restoreWord(long, previous: nil)
        XCTAssertTrue(library.state.words.isEmpty, "Undo removes it")
    }

    /// What is stored and shown has no bidi override or zero-width character; joiners stay.
    func testInvisibleFormattingIsStrippedFromImportedTextAndSavedSentences() throws {
        let library = Library(storage: MemoryStorage())
        library.load()
        let text = "\u{FEFF}Hello \u{202E}evil\u{200B} w\u{00AD}orld\n\nمی\u{200C}خواهم a\u{200D}b"
        let book = library.addBook(title: "T", author: "A", text: text)
        XCTAssertEqual(library.openBook(book.id), ["Hello evil world", "می\u{200C}خواهم a\u{200D}b"])
        library.saveWord("hello", learned: false, context: "Hello \u{2066}evil\u{2069} world.")
        XCTAssertEqual(library.state.word("hello")?.context, "Hello evil world.")
        XCTAssertEqual(TextTools.stripFormat("plain é 東"), "plain é 東")
    }

    /// A search text is cut before it is sent, and an address stays ASCII.
    func testASearchTextIsCutToItsLimit() async throws {
        let urls = UrlRecorder()
        let catalog = GutenbergClient(http: ClosureFetcher { url in
            await urls.add(url)
            return HttpResponse(status: 200, text: #"{"results": []}"#)
        })
        _ = try await catalog.search(String(repeating: "東", count: 5000))
        let seen = await urls.list
        XCTAssertEqual(seen[0].hasSuffix("search=" + String(repeating: "%E6%9D%B1", count: GutenbergClient.maxQuery)), true)
    }

    /// A reading's base is a key: "Café" and "café" are one dictionary entry.
    func testAReadingsBaseIsNormalisedLikeTheWord() async {
        let requests = Requests()
        let dictionary = client(requests)
        let found = await dictionary.lookup("cafés", reading: Reading(kind: .noun, base: "CAFE\u{0301}", step: .noun))
        XCTAssertEqual(found?.definition, "A place.")
        let sent = await requests.words
        XCTAssertEqual(sent, ["caf%C3%A9"])
    }

    func testWhichTokensMayBeLookedUp() {
        for yes in ["cat", "café", "naïve", "résumé", "joaquín", "zieliński", "kraków", "straße", "o'clock", "l’homme", "đà"] {
            XCTAssertTrue(DictionaryClient.canLookUp(yes), yes)
        }
        for no in ["", "привет", "你好", "مرحبا", "Tokyo東京", "东京tokyo", "a b", "a-b", "3d", "\u{0301}", "😀", "cat\n", "cat\n\n", "\ncat",
                   String(repeating: "a", count: 51)] {
            XCTAssertFalse(DictionaryClient.canLookUp(no), no)
        }
    }
}

import XCTest
@testable import LingleafCore

/// v4 of the rule and the table (same cases as lingleaf-android's RoundFourTest): expressions, the
/// twin's noun, mostly-noun -s forms, the noun's pronunciation and per-sense English queries.
final class RoundFourTests: XCTestCase {
    private let table = IrregularVerbs.shared

    private func range(_ word: String, in sentence: String) -> WordRange {
        let ranges = TextTools.wordRanges(sentence).filter { TextTools.substring(sentence, $0) == word }
        XCTAssertFalse(ranges.isEmpty, "\(word) not in \(sentence)")
        return ranges.first ?? WordRange(0, 0)
    }

    private func read(_ sentence: String, _ word: String) -> Reading? {
        table.resolve(sentence, range(word, in: sentence))
    }

    private func choices(_ sentence: String, _ word: String) -> [ReadingChoice] {
        table.choices(in: sentence, at: range(word, in: sentence))
    }

    private func nounIPA(_ sentence: String, _ word: String) -> String? {
        table.nounIPA(in: sentence, at: range(word, in: sentence))
    }

    func testBoundForAndBoundToAreExpressions() {
        XCTAssertEqual(read("The ship was bound for Spain.", "bound"), Reading(kind: .expression, base: "bound for", step: .expression))
        XCTAssertEqual(read("It is bound to rain.", "bound"), Reading(kind: .expression, base: "bound to", step: .expression))
        XCTAssertEqual(read("Bound for London, they sailed.", "Bound"), Reading(kind: .expression, base: "bound for", step: .expression))
        XCTAssertEqual(read("They were bound to the mast.", "bound")?.kind, .verb, "to + no verb: the participle")
        let sentence = "It is bound to rain."
        let expression = read(sentence, "bound")
        XCTAssertEqual(TextTools.baseFormCandidates(in: sentence, at: range("bound", in: sentence)), [])
        XCTAssertNil(expression.flatMap(table.sense(of:)))
        XCTAssertFalse(expression?.isVerb ?? true)
        XCTAssertEqual(table.tableMeaning(.expression, base: "bound to"), "seguro que · obligado a")
        XCTAssertEqual(table.query(.expression, base: "bound to"), "certain to")
        XCTAssertEqual(table.gloss(.expression, base: "bound to"), "sure or obliged to")
        XCTAssertEqual(table.base(in: sentence, at: range("bound", in: sentence)), "bound to")
        XCTAssertEqual(table.listenText(headword: "bound to", in: sentence, at: range("bound", in: sentence), chosen: nil), "bound to",
                       "said as the unit")
        XCTAssertEqual(ReadingTranslation.source(word: "bound for", sense: nil), "heading for")
    }

    func testLiesAfterADeterminerIsTheTwinsNounUnprovenItIsUnsure() {
        XCTAssertEqual(read("His lies hurt.", "lies"), Reading(kind: .noun, base: "lie", step: .twinNoun))
        XCTAssertEqual(TextTools.baseFormCandidates(in: "His lies hurt.", at: range("lies", in: "His lies hurt.")), ["lie"])
        XCTAssertEqual(read("She tells lies.", "lies"), Reading(kind: .unsure, base: "lie", step: .unsureNoun))
        let rows = choices("She tells lies.", "lies")
        XCTAssertEqual(rows.map(\.kind), [.noun, .verb])
        XCTAssertEqual(rows.map(\.base), ["lie", "lie"])
        XCTAssertEqual(rows.map(\.label), ["the lie", "to lie"])
        XCTAssertEqual(rows.first.flatMap { table.tableMeaning($0.kind, base: $0.base, form: $0.form, first: true) }, "mentira")
        XCTAssertEqual(rows.last.flatMap { table.tableMeaning($0.kind, base: $0.base, form: $0.form, first: true) }, "estar, encontrarse",
                       "the -s form's meaning")
        XCTAssertEqual(table.twinNounEs("lie"), ["mentira"])
        XCTAssertNil(table.twinNounEs("cat"))
    }

    func testAMostlyNounSFormAfterANounSubjectWithNoObjectIsUnsure() {
        XCTAssertEqual(read("The bell rings.", "rings"), Reading(kind: .unsure, base: "ring", step: .unsureNounFirst))
        let rows = choices("The bell rings.", "rings")
        XCTAssertEqual(rows.map(\.kind), [.verb, .noun])
        XCTAssertEqual(rows.map(\.base), ["ring", "ring"], "v5: the noun's regular lemma")
        XCTAssertEqual(rows.map(\.label), ["to ring", "the ring"])
        XCTAssertEqual(rows.first.flatMap { table.tableMeaning($0.kind, base: $0.base, form: $0.form, first: true) }, "sonar")
        XCTAssertNil(rows.last.flatMap { table.tableMeaning($0.kind, base: $0.base, form: $0.form) }, "the noun is translated")
        XCTAssertEqual(read("The sun lights the room.", "lights")?.kind, .verb, "an object after it: the verb")
    }

    func testTheNounsPronunciationComesFromItsSentence() {
        XCTAssertEqual(nounIPA("Tears in her eyes.", "Tears"), "tɪr")
        XCTAssertEqual(nounIPA("There is a tear in my shirt.", "tear"), "tɛr")
        XCTAssertEqual(nounIPA("It was made of lead.", "lead"), "lɛd")
        XCTAssertEqual(nounIPA("He took the lead.", "lead"), "liːd")
        XCTAssertEqual(nounIPA("The wind blew.", "wind"), "wɪnd")
        XCTAssertNil(nounIPA("The tear was big.", "tear"), "nothing proves it")
        XCTAssertNil(nounIPA("A cat.", "cat"))
        XCTAssertNil(table.nounIPA(in: "A cat.", at: WordRange(9, 12)), "not a word of the text")
        XCTAssertNil(nounIPA("She left.", "left"), "no rules for left")
        XCTAssertTrue(table.hasNounIPA("Tears"))
        XCTAssertFalse(table.hasNounIPA("left"))
    }

    func testEachSenseHasItsOwnEnglishQueryAndAGlossWhenTwoRowsMatch() {
        XCTAssertEqual(table.query(.verb, base: "lie"), "to lie down")
        XCTAssertEqual(table.query(.homonym, base: "lie"), "to tell a lie")
        XCTAssertEqual(table.query(.verb, base: "leave"), "to leave")
        XCTAssertEqual(table.query(.noun, base: "left"), "the left")
        XCTAssertEqual(table.query(.verb, base: "hang"), "to hang up")
        XCTAssertEqual(table.query(.expression, base: "zz"), "zz")
        XCTAssertEqual(table.query(.homonym, base: "zzz"), "to zzz")
        XCTAssertEqual(ReadingTranslation.source(word: "lie", sense: Sense.homonym), "to tell a lie")
        let lie = ReadingChoice(kind: .verb, base: "lie", sense: Sense.verb)
        let twin = ReadingChoice(kind: .homonym, base: "lie", sense: Sense.homonym)
        XCTAssertEqual(table.distinguished([lie, twin], ["mentir", "Mentir"]), ["mentir (recline)", "Mentir (say what isn't true)"])
        XCTAssertEqual(table.distinguished([lie, twin], ["a", "b"]), ["a", "b"])
        XCTAssertEqual(table.distinguished([lie, twin], ["a", nil]), ["a", nil])
        XCTAssertEqual(table.distinguished([lie], ["a"]), ["a"])
        let noun = ReadingChoice(kind: .noun, base: "lie", sense: Sense.noun)
        XCTAssertEqual(table.distinguished([noun, lie], ["x", "x"]), ["x", "x (recline)"], "a noun has no gloss")
        XCTAssertNil(table.gloss(.noun, base: "lie"))
    }

    func testReadingsTranslatedLaterAskEachSensesQueryAndAreToldApart() throws {
        let library = Library(storage: MemoryStorage())
        library.load()
        let meanings = [
            SavedMeaning(label: "to lie", sense: Sense.verb, base: "lie", text: "", language: nil),
            SavedMeaning(label: "to lie", sense: Sense.homonym, base: "lie", text: "", language: nil),
        ]
        library.saveWord("lying", learned: false, context: "She is lying.", meanings: meanings)
        XCTAssertEqual(library.meaningsNeedingTranslation("fr").map(\.label), ["to lie down", "to tell a lie"])
        library.setMeaning("lying", index: 0, text: "mentir", language: "fr")
        XCTAssertEqual(library.state.word("lying")?.meanings?.first?.text, "mentir", "the other row isn't there yet")
        library.setMeaning("lying", index: 1, text: "Mentir", language: "fr")
        let word = try XCTUnwrap(library.state.word("lying"))
        XCTAssertEqual(word.meanings?.map(\.text), ["mentir (recline)", "Mentir (say what isn't true)"])
        XCTAssertEqual(word.translation, "mentir (recline) · Mentir (say what isn't true)")
        // Offline in Spanish: the table's first meaning group of each reading, the twin's noun too.
        let spanish = Library(storage: MemoryStorage())
        spanish.load()
        let rows = [
            SavedMeaning(label: "the lie", sense: Sense.noun, base: "lie", text: "", language: nil),
            SavedMeaning(label: "to lie", sense: Sense.verb, base: "lie", text: "", language: nil),
        ]
        spanish.saveWord("lies", learned: false, context: "She tells lies.", meanings: rows)
        spanish.saveWord("bound for", learned: false, context: "The ship was bound for Spain.")
        spanish.fillTableTranslations("es")
        XCTAssertEqual(spanish.state.word("lies")?.meanings?.map(\.text), ["mentira", "estar, encontrarse"],
                       "the -s form's own meaning, from the form saved")
        XCTAssertEqual(spanish.state.word("bound for")?.translation, "rumbo a, con destino a")
    }

    private static func fixture(_ name: String) -> HttpResponse? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "dictionary"),
              let data = try? Data(contentsOf: url) else { return nil }
        return HttpResponse(status: 200, body: data)
    }

    func testANounOfTearOrLeadIsTheEntryItsSentencesSoundProvesElseNone() async {
        let dictionary = DictionaryClient(http: ClosureFetcher { url in
            let word = String(url.split(separator: "/").last ?? "")
            guard ["tear", "lead", "lie"].contains(word) else { return HttpResponse(status: 404, text: "") }
            return Self.fixture(word) ?? HttpResponse(status: 404, text: "")
        })
        let drop = await dictionary.lookup("tears", reading: Reading(kind: .noun, base: "tear", step: .noun), nounIPA: "tɪr")
        XCTAssertTrue(drop?.definition?.hasPrefix("A drop") == true)
        let hole = await dictionary.lookup("tear", reading: Reading(kind: .noun, base: "tear", step: .noun), nounIPA: "tɛr")
        XCTAssertTrue(hole?.definition?.hasPrefix("A hole") == true)
        let unproven = await dictionary.lookup("tear", reading: Reading(kind: .noun, base: "tear", step: .noun))
        XCTAssertNil(unproven, "nothing proves it")
        let metal = await dictionary.lookup("lead", reading: Reading(kind: .noun, base: "lead", step: .noun), nounIPA: "lɛd")
        XCTAssertTrue(metal?.definition?.hasPrefix("A heavy") == true)
        let twinNoun = await dictionary.lookup("lies", reading: Reading(kind: .noun, base: "lie", step: .twinNoun))
        XCTAssertNil(twinNoun, "the twin's noun: none")
        let noAdjective = await dictionary.lookup("bound", reading: Reading(kind: .expression, base: "bound for", step: .expression))
        XCTAssertNil(noAdjective, "no adjective entry")
        let bound = DictionaryClient(http: ClosureFetcher { _ in
            HttpResponse(status: 200, text: """
            [{"word": "bound", "meanings": [{"partOfSpeech": "verb", "definitions": [{"definition": "To leap."}]},
              {"partOfSpeech": "adjective", "definitions": [{"definition": "Heading for a place."}]}]}]
            """)
        })
        let adjective = await bound.lookup("bound", reading: Reading(kind: .expression, base: "bound for", step: .expression))
        XCTAssertEqual(adjective?.definition, "Heading for a place.")
        XCTAssertEqual(table.baseIPA("lie"), "/laɪ/", "the twin shows the base's IPA")
        XCTAssertEqual(table.baseIPA("hang"), "/hæŋ/")
    }

    func testACorrectedExpressionBecomesTheUnit() throws {
        let storage = MemoryStorage()
        storage.files["settings.json"] = #"{"targetLanguage": "es"}"#
        let library = Library(storage: storage)
        library.load()
        library.saveWord("bound", learned: false, translation: "x", context: "The ship was bound for Spain.")
        library.correctWordsIfNeeded()
        let unit = try XCTUnwrap(library.state.word("bound for"))
        XCTAssertNil(unit.sense)
        XCTAssertEqual(unit.translation, "rumbo a, con destino a")
        XCTAssertEqual(library.state.corrections, [Correction(from: "bound", to: "bound for")])
    }

    func testACorrectedNounOfTearGetsItsSentencesSound() throws {
        let library = Library(storage: MemoryStorage())
        library.load()
        library.saveWord("tears", learned: false, context: "Her eyes filled with tears.")
        library.correctWordsIfNeeded()
        let tear = try XCTUnwrap(library.state.word("tear", sense: Sense.noun))
        XCTAssertEqual(tear.phonetic, "/tɪr/")
    }

    // MARK: v5

    func testANounIsSpokenAsWrittenUnlessItsSentenceProvesASoundTheVoiceWouldntMake() {
        func spoken(_ sentence: String, _ word: String) -> String { table.spokenForm(in: sentence, at: range(word, in: sentence)) }
        XCTAssertEqual(spoken("It was made of lead.", "lead"), "led")
        XCTAssertEqual(spoken("He took the lead.", "lead"), "lead", "liːd: the voice says it right")
        XCTAssertEqual(spoken("There is a tear in my shirt.", "tear"), "tare")
        XCTAssertEqual(spoken("A tear rolled down her cheek.", "tear"), "tear")
        XCTAssertEqual(spoken("The tear was small.", "tear"), "tear", "nothing proves it")
        let curtain = "The tears in the curtain let the light in."
        XCTAssertEqual(spoken(curtain, "tears"), "tears", "the respelling is of the singular")
        XCTAssertEqual(table.listenText(headword: "tear", in: curtain, at: range("tears", in: curtain), chosen: nil), "tare, tears")
        XCTAssertEqual(table.listenText(headword: "lead", in: "It was made of lead.", at: range("lead", in: "It was made of lead."),
                                        chosen: nil), "led")
        func saved(_ word: String, _ phonetic: String) -> VocabWord {
            var entry = VocabWord(
                word: word, translation: "", translationLanguage: nil, phonetic: phonetic, context: "", source: "",
                learned: false, box: 0, createdAt: Date(), nextReview: Date()
            )
            entry.sense = Sense.noun
            return entry
        }
        XCTAssertEqual(table.spokenSaved(saved("lead", "/lɛd/")), "led", "from the saved IPA")
        XCTAssertEqual(table.spokenSaved(saved("lead", "/liːd/")), "lead")
        XCTAssertEqual(table.spokenSaved(saved("tear", "/tɛr/")), "tare")
        XCTAssertEqual(table.spokenSaved(saved("tear", "")), "tear", "no sound proven")
        XCTAssertEqual(table.spokenSaved(saved("left", "/lɛft/")), "left")
    }

    func testReviewShowsTheSentenceWhenTheLabelAloneDoesntTellTheSense() throws {
        let library = Library(storage: MemoryStorage())
        library.load()
        library.saveWord("lie", learned: false, context: "She lay down to rest.", sense: Sense.verb)
        library.saveWord("hang", learned: false, context: "They hanged him.", sense: Sense.homonym)
        library.saveWord("leave", learned: false, context: "She left early.", sense: Sense.verb)
        library.saveWord("wind", learned: false, context: "The wind blew.", sense: Sense.noun)
        library.saveWord("light", learned: false, sense: Sense.verb)
        let state = library.state
        func shows(_ word: String, _ sense: String) throws -> Bool { state.promptShowsSentence(try XCTUnwrap(state.word(word, sense: sense))) }
        XCTAssertTrue(try shows("lie", Sense.verb), "a verb with a twin, one sense saved")
        XCTAssertTrue(try shows("hang", Sense.homonym), "the twin")
        XCTAssertFalse(try shows("leave", Sense.verb))
        XCTAssertFalse(try shows("wind", Sense.noun), "one sense: its label tells")
        XCTAssertFalse(try shows("light", Sense.verb), "no sentence saved")
        library.saveWord("wind", learned: false, context: "She wound the clock.", sense: Sense.verb)
        XCTAssertTrue(try shows("wind", Sense.noun), "two senses of the spelling")
    }

    func testTheBellRingsChosenAsTheNounSavesTheLemma() throws {
        let sentence = "The bell rings."
        let noun = try XCTUnwrap(choices(sentence, "rings").last)
        let library = Library(storage: MemoryStorage())
        library.load()
        library.saveWord(noun.base, learned: false, context: sentence, sense: noun.sense, form: "rings", formRange: range("rings", in: sentence))
        let ring = try XCTUnwrap(library.state.word("ring", sense: Sense.noun))
        XCTAssertEqual(library.state.displayName(ring), "the ring")
        XCTAssertEqual(ring.form, "rings", "the tapped form stays bold in Review")
    }

    // MARK: The v4 fields of the table

    private static let bundled: Data = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/LingleafCore/Resources/irregular-verbs.json").standardizedFileURL
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    private func bundledTable() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bundled) as? [String: Any])
    }

    private func refused(_ table: [String: Any], _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONSerialization.data(withJSONObject: table)
        XCTAssertThrowsError(try IrregularVerbs.load(data), message, file: file, line: line)
    }

    private func withVerb(_ base: String, _ change: (inout [String: Any]) -> Void) throws -> [String: Any] {
        var table = try bundledTable()
        var verbs = try XCTUnwrap(table["verbs"] as? [[String: Any]])
        let index = try XCTUnwrap(verbs.firstIndex { $0["base"] as? String == base })
        change(&verbs[index])
        table["verbs"] = verbs
        return table
    }

    private func withHomonym(_ change: @escaping (inout [String: Any]) -> Void) throws -> [String: Any] {
        try withVerb("lie") { verb in
            var homonym = verb["homonym"] as? [String: Any] ?? [:]
            change(&homonym)
            verb["homonym"] = homonym
        }
    }

    private func withHomograph(_ form: String, _ change: (inout [String: Any]) -> Void) throws -> [String: Any] {
        var table = try bundledTable()
        var homographs = try XCTUnwrap(table["homographs"] as? [[String: Any]])
        let index = try XCTUnwrap(homographs.firstIndex { $0["form"] as? String == form })
        change(&homographs[index])
        table["homographs"] = homographs
        return table
    }

    func testTheV4FieldsOfTheTableAreChecked() throws {
        XCTAssertNoThrow(try IrregularVerbs.load(Self.bundled))
        try refused(withVerb("lie") { $0["query"] = "To lie" }, "query not lower case")
        try refused(withVerb("lie") { $0["gloss"] = "x" }, "gloss too short")
        try refused(withVerb("lie") { $0["sEs"] = " estar" }, "sEs with a space around")
        try refused(withHomonym { $0["nounEs"] = nil }, "a noun without its meanings")
        try refused(withHomonym { $0["noun"] = "Lie" }, "noun not a–z")
        try refused(withHomonym { $0["nounEs"] = [String]() }, "no noun meanings")
        try refused(withHomonym { $0["query"] = "tell a lie!" }, "homonym query")
        try refused(withVerb("lie") { $0["ipa"] = ["base": "lcy"] }, "c and y are not IPA here")
        let plain: [String: Any] = ["ipa": "tɪr"]
        try refused(withHomograph("tear") { $0["nounIpa"] = [plain, plain] }, "a default before the last rule")
        try refused(withHomograph("tear") { $0["nounIpa"] = [["ipa": "tɪr", "near": ["Eye"]] as [String: Any]] }, "near not a–z")
        try refused(withHomograph("tear") { $0["nounIpa"] = [["ipa": "tɪr", "far": ["eye"]] as [String: Any]] }, "unknown rule key")
        let bound = try withHomograph("bound") { _ in }
        let homographs = try XCTUnwrap(bound["homographs"] as? [[String: Any]])
        let expressions = try XCTUnwrap(homographs.first { $0["form"] as? String == "bound" }?["expressions"] as? [[String: Any]])
        let expression = try XCTUnwrap(expressions.first)
        func changed(_ key: String, _ value: Any) -> [String: Any] {
            var copy = expression
            copy[key] = value
            return copy
        }
        try refused(withHomograph("bound") { $0["expressions"] = [changed("next", "For")] }, "next not a–z")
        try refused(withHomograph("bound") { $0["expressions"] = [changed("es", [String]())] }, "no meanings")
        try refused(withHomograph("bound") { $0["expressions"] = [changed("query", "Heading")] }, "query")
        try refused(withHomograph("bound") { $0["expressions"] = [changed("gloss", "")] }, "gloss")
        try refused(withHomograph("bound") { $0["expressions"] = [changed("extra", "x")] }, "unknown key")
        var old = try bundledTable()
        var context = try XCTUnwrap(old["context"] as? [String: Any])
        context["boundAdjective"] = ["for"]
        old["context"] = context
        try refused(old, "the list v4 removed")
        // v5: a rule's respelling is a–z, and a rule on the word before never comes before one on the word after.
        try refused(withHomograph("lead") { h in
            var rules = h["nounIpa"] as? [[String: Any]] ?? []
            rules[0]["spokenAs"] = "Led"
            h["nounIpa"] = rules
        }, "spokenAs not a–z")
        try refused(withHomograph("lead") { h in
            var rules = h["nounIpa"] as? [[String: Any]] ?? []
            if let after = rules.firstIndex(where: { $0["after"] != nil && $0["before"] == nil }) { rules.insert(rules.remove(at: after), at: 0) }
            h["nounIpa"] = rules
        }, "an after rule before a before rule")
        for bad in [" mentir", "", "a\u{2028}b"] {
            try refused(withHomonym { $0["es"] = [bad] }, "homonym es: \(bad.unicodeScalars.map(\.value))")
            try refused(withVerb("lie") { $0["sEs"] = bad }, "sEs: \(bad.unicodeScalars.map(\.value))")
            try refused(withHomonym { $0["nounEs"] = [bad] }, "nounEs: \(bad.unicodeScalars.map(\.value))")
            try refused(withHomograph("bound") { $0["expressions"] = [changed("es", [bad])] }, "es: \(bad.unicodeScalars.map(\.value))")
        }
        for bad in ["a\u{202E}b", "a\u{200B}b", "a\nb", "a\u{0}b", "a\u{2068}b\u{2069}"] {
            try refused(withHomonym { $0["es"] = [bad] }, "homonym es: \(bad.unicodeScalars.map(\.value))")
        }
        // The Spanish fields pass the same text check as the rest of the table.
        for bad in ["a\u{202E}b", "a\u{200B}b", "a\nb", "a\u{0}b", "a\u{2068}b\u{2069}"] {
            try refused(withVerb("lie") { $0["sEs"] = bad }, "sEs: \(bad.unicodeScalars.map(\.value))")
            try refused(withHomonym { $0["nounEs"] = [bad] }, "nounEs: \(bad.unicodeScalars.map(\.value))")
            try refused(withHomograph("bound") { $0["expressions"] = [changed("es", [bad])] }, "es: \(bad.unicodeScalars.map(\.value))")
        }
    }
}

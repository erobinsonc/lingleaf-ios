import XCTest
@testable import LingleafCore

/// The verb-or-noun rule on single sentences, the table's base form of a tapped word, and what
/// Listen says for it (the shared corpus measures the rule as a whole: `HomographCorpusTests`).
final class VerbOrNounTests: XCTestCase {
    private let table = IrregularVerbs.shared

    /// The first `word` of `sentence` (case-sensitive, whole word).
    private func range(_ word: String, in sentence: String) -> WordRange {
        let ranges = TextTools.wordRanges(sentence).filter { TextTools.substring(sentence, $0) == word }
        XCTAssertFalse(ranges.isEmpty, "\(word) not in \(sentence)")
        return ranges.first ?? WordRange(0, 0)
    }

    private func reading(_ word: String, _ sentence: String) -> Reading? {
        table.resolve(sentence, range(word, in: sentence))
    }

    private func assertReading(
        _ word: String, _ sentence: String, _ kind: Reading.Kind, _ base: String, _ step: Reading.Step, _ why: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(reading(word, sentence), Reading(kind: kind, base: base, step: step), "\(sentence) \(why)", file: file, line: line)
    }

    func testTheBundledStoriesLeaveNothingUnsureAndTheLightsAreLights() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../Lingleaf/Resources/Books").standardizedFileURL
        let books = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertEqual(books.count, 3, "the bundled stories")
        var unsure: [String] = []
        var lights = 0
        for book in books {
            for paragraph in TextTools.splitParagraphs(try String(contentsOf: book, encoding: .utf8)) {
                let words = Words(paragraph as NSString)
                for i in words.ranges.indices {
                    guard let reading = table.resolve(words, i) else { continue }
                    let surface = words.surface(i)
                    if reading.kind == .unsure { unsure.append("\(book.lastPathComponent): \(surface)") }
                    if surface == "lights" {
                        lights += 1
                        XCTAssertEqual(reading.kind, .word, "the lights that guide")
                    }
                }
            }
        }
        XCTAssertEqual(unsure, [])
        XCTAssertGreaterThan(lights, 0, "the stories have lights")
    }

    /// The best of a few runs of reading every word of `text`, in nanoseconds.
    private func bestNanos(_ text: String) -> UInt64 {
        (0..<5).map { _ in
            let start = DispatchTime.now().uptimeNanoseconds
            let words = Words(text as NSString)
            for i in words.ranges.indices { _ = table.resolve(words, i) }
            return DispatchTime.now().uptimeNanoseconds - start
        }.min() ?? 0
    }

    func testReadingEveryWordStaysLinearInTheParagraphsLength() {
        // Homographs, capitalised forms and names everywhere, and a long run without punctuation:
        // the worst cases for the rule (the finite-verb scan stops after 60 words).
        for unit in ["Left left Rose saw Drew leaves, the Lay wound; Tom Read read. She left. ", "Tom lives in a small house by the sea "] {
            let small = String(repeating: unit, count: TextTools.maxParagraph / unit.count)
            let large = String(repeating: unit, count: 10 * TextTools.maxParagraph / unit.count)
            _ = bestNanos(large)
            let tSmall = bestNanos(small)
            let tLarge = bestNanos(large)
            // 10× the text: about 10× the time when linear, 100× when quadratic.
            XCTAssertLessThanOrEqual(tLarge, 30 * tSmall + 50_000_000, "10× the text took \(tLarge / max(tSmall, 1))× the time")
            XCTAssertLessThan(tLarge, 10_000_000_000, "\(large.count) characters took \(tLarge / 1_000_000) ms")
        }
    }

    func testTheWordListVersionsAgreeWithTheRangeOnes() {
        let text = "Turn left. She left; Uncle Drew had read it, and the wound bled."
        let ns = text as NSString
        let words = Words(ns)
        for (i, range) in words.ranges.enumerated() {
            let surface = TextTools.substring(text, range)
            XCTAssertEqual(table.resolve(text, range), table.resolve(words, i), surface)
            XCTAssertEqual(table.isName(text, range), table.isName(words, i), surface)
            XCTAssertEqual(table.base(in: text, at: range), table.base(words, i), surface)
            XCTAssertEqual(table.spokenForm(in: text, at: range), table.spokenForm(words, i) ?? surface, surface)
            XCTAssertEqual(TextTools.matchKeys(in: text, at: range), TextTools.matchKeys(words, i), surface)
            XCTAssertEqual(TextTools.baseFormCandidates(in: text, at: range), TextTools.baseFormCandidates(words, i), surface)
        }
        XCTAssertEqual(TextTools.matchKeys(in: text, words: words.ranges), words.ranges.map { TextTools.matchKeys(in: text, at: $0) })
        let absent = WordRange(1, 3)
        XCTAssertNil(table.resolve(text, absent))
        XCTAssertNil(table.base(in: text, at: absent))
        XCTAssertEqual(table.spokenForm(in: "I read.", at: WordRange(3, 5)), "ea", "not a word of the text: as written")
        XCTAssertEqual(TextTools.matchKeys(in: text, at: absent), TextTools.matchKeys("ur"))
        XCTAssertEqual(TextTools.baseFormCandidates(in: text, at: absent), TextTools.baseFormCandidates("ur"))
        XCTAssertEqual(table.spokenForm(in: text, at: range("read", in: text)), "red")
        XCTAssertTrue(table.isName(text, range("Drew", in: text)))
    }

    func testEachStepDecides() {
        assertReading("Rose", "Aunt Rose came.", .noun, "rose", .name)
        assertReading("left", "He is left-handed.", .noun, "left", .name)
        assertReading("left", "Turn left at the church.", .noun, "left", .fixed)
        assertReading("left", "He held it in his left hand.", .noun, "left", .fixed)
        assertReading("left", "Nothing in the left one.", .noun, "left", .noun)
        assertReading("bit", "Wait a little bit.", .noun, "bit", .noun)
        assertReading("leaves", "The dead leaves fell.", .noun, "leaf", .noun)
        assertReading("Lay", "Lay the table, please.", .verb, "lay", .base)
        assertReading("tear", "Don't tear the page.", .verb, "tear", .base)
        assertReading("wound", "He tried to wound the bear.", .verb, "wound", .base)
        assertReading("left", "He had left.", .verb, "leave", .participle)
        assertReading("left", "She left the house early.", .verb, "leave", .subject)
        assertReading("leaves", "She leaves at nine.", .verb, "leave", .subject)
        assertReading("lay", "She lay down.", .verb, "lie", .subject)
        assertReading("rose", "The sun rose slowly.", .verb, "rise", .subjectNoun)
        assertReading("left", "She saw it and left.", .verb, "leave", .conjunction)
        assertReading("lay", "They lay bricks.", .unsure, "lay", .unsure)
        assertReading("Left", "Left is the answer.", .unsure, "left", .unsure)
    }

    func testTheStepsOfTheTablesV2Lists() {
        assertReading("found", "Check the lost and found first.", .noun, "found", .phrase)
        assertReading("found", "She lost and found her keys.", .verb, "find", .conjunction, "a subject before the phrase")
        assertReading("Left", "Left alone, she cried.", .verb, "leave", .participleOpen)
        assertReading("Found", "Found guilty, he went to jail.", .verb, "find", .participleOpen)
        assertReading("Felt", "Felt hats, they said, were warm.", .noun, "felt", .fixed)
        assertReading("lives", "Tom lives in a small house.", .verb, "live", .nameS)
        assertReading("lives", "Double lives in fiction are common.", .unsure, "lives", .unsure, "a finite verb later")
        assertReading("lives", "Wasted lives are sad.", .unsure, "lives", .unsure, "a verb form, not a name")
        assertReading("leaves", "Holly leaves at six.", .unsure, "leaves", .unsure, "a plant that is also a name")
        assertReading("lives", "The old man lives alone.", .verb, "live", .nounS)
        assertReading("leaves", "The bus leaves at six.", .verb, "leave", .nounS)
        assertReading("left", "Many people left early.", .verb, "leave", .quantifier)
        assertReading("left", "Some of the guests left.", .verb, "leave", .quantifier)
        assertReading("lay", "Two men lay down.", .verb, "lie", .quantifier)
        assertReading("bore", "Long speeches bore me.", .unsure, "bore", .unsure, "no quantifier step for bore")
        assertReading("bit", "The dog bit him.", .verb, "bite", .subjectNoun)
        assertReading("bit", "The funny bit was long.", .unsure, "bit", .unsure, "bit needs an object word after it")
    }

    func testOtherFormsOfTheTable() {
        assertReading("tore", "She tore it.", .verb, "tear", .table)
        assertReading("lied", "He lied.", .homonym, "lie", .table)
        assertReading("hanged", "They hanged him.", .homonym, "hang", .table)
        assertReading("Drew", "I met Uncle Drew today.", .noun, "drew", .name)
        assertReading("Drew", "Drew a line.", .verb, "draw", .table, "the first word: not a name")
        assertReading("lights", "The lights were on.", .word, "lights", .ordinary)
        assertReading("lights", "The sun lights the room.", .verb, "light", .sSubject)
        assertReading("runs", "Tom runs home.", .verb, "run", .sSubject)
        assertReading("says", "\"Look!\" says Tom.", .verb, "say", .quote)
        assertReading("winding", "She is winding the clock.", .verb, "wind", .ing)
        assertReading("winding", "A winding road.", .word, "winding", .ordinary)
        assertReading("meeting", "The meeting ended.", .word, "meeting", .ordinary)
        assertReading("lying", "He is lying to me.", .homonym, "lie", .sense)
        assertReading("lying", "She is lying down.", .verb, "lie", .sense)
        assertReading("hangs", "It hangs on the wall.", .verb, "hang", .sense)
        assertReading("lying", "She is lying.", .unsure, "lying", .unsure, "the next word doesn't tell")
        XCTAssertTrue(Reading(kind: .homonym, base: "lie", step: .table).isVerb)
        XCTAssertFalse(Reading(kind: .word, base: "lights", step: .ordinary).isVerb)
    }

    func testFixedPhrasesAndBound() {
        assertReading("left", "He looked right and left.", .noun, "left", .fixed)
        assertReading("left", "He looked left and right.", .noun, "left", .fixed)
        assertReading("bound", "The ship was bound for Spain.", .noun, "bound", .fixed)
        assertReading("Bound", "Bound for London, the ship left.", .noun, "bound", .fixed, "not an opening participle")
        assertReading("bound", "It is bound to rain.", .noun, "bound", .fixed)
        assertReading("felt", "She wore a felt hat.", .noun, "felt", .fixed)
    }

    func testSubjectsNamesAndClauses() {
        assertReading("saw", "No one saw it.", .verb, "see", .subject)
        assertReading("saw", "Tom saw the bird.", .verb, "see", .subject)
        assertReading("rose", "There rose a cry.", .verb, "rise", .subject)
        assertReading("lay", "There lay the sword.", .verb, "lie", .subject)
        assertReading("tears", "This tears easily.", .verb, "tear", .subject)
        assertReading("stole", "She wore a fur stole.", .unsure, "stole", .unsure)
        assertReading("rose", "When the old moon rose, we left.", .verb, "rise", .subjectNoun)
        assertReading("lay", "We lay down.", .verb, "lie", .subject)
        assertReading("lay", "We lay the cloth on the grass.", .verb, "lay", .subject)
        assertReading("left", "He quietly left.", .verb, "leave", .subject)
        assertReading("leaves", "Tom's leaves are green.", .noun, "leaf", .noun)
        assertReading("bit", "Tom's bit was small.", .noun, "bit", .noun)
        assertReading("wound", "The soldier's wound was deep.", .unsure, "wound", .unsure, "may be \"has wound\"")
        assertReading("bound", "With one bound he was free.", .unsure, "bound", .unsure)
    }

    func testOnlyHomographsHaveAReading() {
        XCTAssertEqual(reading("stolen", "It was stolen."), Reading(kind: .verb, base: "steal", step: .table), "a form of the table")
        XCTAssertNil(reading("walked", "She walked home."), "neither a homograph nor a form of the table")
        XCTAssertNil(table.resolve("She left.", WordRange(4, 20)), "out of range")
        XCTAssertNil(table.resolve("She left.", WordRange(4, 4)), "empty")
        XCTAssertEqual(table.resolve("She left.", WordRange(5, 8)), nil, "not a word of the text: \"eft\"")
        XCTAssertNil(table.resolve("She lefts.", WordRange(4, 8)), "part of a longer word")
    }

    func testTheTableBaseOfATappedWord() {
        func base(_ word: String, _ sentence: String) -> String? { table.base(in: sentence, at: range(word, in: sentence)) }
        XCTAssertEqual(base("stolen", "It was stolen."), "steal")
        XCTAssertEqual(base("stole", "He stole the bread."), "steal")
        XCTAssertEqual(base("leaves", "The dead leaves fell."), "leaf")
        XCTAssertNil(base("left", "Turn left here."), "the noun \"left\": no other base")
        XCTAssertNil(base("Left", "Left is the answer."), "unsure")
        XCTAssertEqual(base("Left", "Left alone, she cried."), "leave", "an opening participle")
        XCTAssertEqual(base("Drew", "Drew a line."), "draw", "the first word: not a name")
        XCTAssertNil(base("Drew", "I met Uncle Drew today."), "a name")
        XCTAssertNil(base("cat", "The cat sat."))
        XCTAssertNil(table.base(in: "cat", at: WordRange(0, 9)))
        XCTAssertNil(table.base(in: "Drews", at: WordRange(0, 4)), "not a word of the text")
    }

    func testListenRespellsOnlyTheSlotTheSentenceProves() {
        func spoken(_ word: String, _ sentence: String) -> String { table.spokenForm(in: sentence, at: range(word, in: sentence)) }
        XCTAssertEqual(spoken("read", "I like to read."), "read", "the base has no respelling")
        XCTAssertEqual(spoken("read", "She had read it."), "red", "the participle after have")
        XCTAssertEqual(spoken("read", "It was read aloud."), "red", "the participle after a passive be")
        XCTAssertEqual(spoken("read", "Yesterday I read it."), "read", "not a homograph: no slot proven, as written")
        XCTAssertEqual(spoken("read", "I'd read it."), "read", "'d may be \"would\": not proven")
        XCTAssertEqual(spoken("read", "It got read."), "read", "get does not prove a participle")
        XCTAssertEqual(spoken("Read", "Read the book."), "Read", "nothing before it: as written")
        XCTAssertEqual(spoken("read", "We read, then slept."), "read")
        XCTAssertEqual(spoken("Drew", "I met Uncle Drew."), "Drew")
        XCTAssertEqual(spoken("wound", "He tried to wound the bear."), "wound", "the verb wound, not wind")
        XCTAssertEqual(spoken("wound", "It wound around the tree."), "wownd", "the past of wind")
        XCTAssertEqual(spoken("wound", "The rope was wound tight."), "wownd", "the participle of wind")
        XCTAssertEqual(spoken("wound", "The wound healed."), "wound", "a noun")
        XCTAssertEqual(spoken("tear", "Don't tear the page."), "tare")
        XCTAssertEqual(spoken("tear", "A tear fell."), "tear")
        XCTAssertEqual(spoken("tears", "She tears the paper."), "tares", "the -s form of a verb reading")
        XCTAssertEqual(spoken("dove", "She dove into the lake."), "dohv")
        XCTAssertEqual(spoken("dived", "She dived into the lake."), "dived")
        XCTAssertEqual(spoken("winding", "A winding road."), "winding")
        XCTAssertEqual(spoken("stole", "He stole it."), "stole")
        XCTAssertEqual(spoken("cat", "The cat sat."), "cat")
        XCTAssertEqual(table.spokenForm(in: "cat", at: WordRange(0, 9)), "")
        XCTAssertEqual(table.spokenForm(in: "reads", at: WordRange(0, 4)), "read", "not a word of the text: as written")
    }
}

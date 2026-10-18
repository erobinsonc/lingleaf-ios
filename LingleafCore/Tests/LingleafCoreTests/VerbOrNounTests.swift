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
        _ word: String, _ sentence: String, _ kind: Reading.Kind, _ base: String, _ step: Reading.Step,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(reading(word, sentence), Reading(kind: kind, base: base, step: step), sentence, file: file, line: line)
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
        assertReading("Left", "Left alone, she cried.", .unsure, "left", .unsure)
    }

    func testFixedPhrasesAndBound() {
        assertReading("left", "He looked right and left.", .noun, "left", .fixed)
        assertReading("left", "He looked left and right.", .noun, "left", .fixed)
        assertReading("bound", "The ship was bound for Spain.", .noun, "bound", .fixed)
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
    }

    func testOnlyHomographsHaveAReading() {
        XCTAssertNil(reading("stolen", "It was stolen."))
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
        XCTAssertNil(base("Left", "Left alone, she cried."), "unsure")
        XCTAssertEqual(base("Drew", "Drew a line."), "draw", "the first word: not a name")
        XCTAssertNil(base("Drew", "I met Uncle Drew today."), "a name")
        XCTAssertNil(base("cat", "The cat sat."))
        XCTAssertNil(table.base(in: "cat", at: WordRange(0, 9)))
        XCTAssertEqual(table.base(in: "Drews", at: WordRange(0, 4)), "draw", "not a word of the text: no name")
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

import XCTest
@testable import LingleafCore

final class ReadAloudTests: XCTestCase {
    private func texts(_ paragraph: String) -> [String] {
        ReadAloud.sentences(paragraph).map { TextTools.substring(paragraph, $0) }
    }

    func testAParagraphIsReadSentenceBySentence() {
        XCTAssertEqual(texts("Tom has a boat. It is red!  Is it new?"), ["Tom has a boat.", "It is red!", "Is it new?"])
        XCTAssertEqual(texts("“Come here,” she said. He came."), ["“Come here,” she said.", "He came."])
        XCTAssertEqual(texts("  No end here  "), ["No end here"])
        XCTAssertEqual(texts("   "), [])
        XCTAssertEqual(texts(""), [])
    }

    func testAVeryLongSentenceComesInPiecesWithoutRepeatingOrLosingWords() {
        let long = (0..<400).map { "word\($0)" }.joined(separator: " ") + "."
        let pieces = ReadAloud.sentences(long)
        XCTAssertGreaterThan(pieces.count, 1)
        XCTAssertTrue(pieces.allSatisfy { $0.end - $0.start <= TextTools.maxSentence })
        XCTAssertEqual(pieces.flatMap { TextTools.substring(long, $0).split(separator: " ").map(String.init) }, long.split(separator: " ").map(String.init))
    }

    func testReadingStartsAtTheSentenceOfTheOffsetAndGoesOnToTheEnd() throws {
        let book = ["One. Two.", "", "Three."]
        let first = try XCTUnwrap(ReadAloud.start(book, 0))
        XCTAssertEqual(first, SentencePosition(0, WordRange(0, 4)))
        XCTAssertEqual(ReadAloud.start(book, 0, offset: 6), SentencePosition(0, WordRange(5, 9)), "the sentence that holds the offset")
        let second = try XCTUnwrap(ReadAloud.next(book, after: first))
        XCTAssertEqual(TextTools.substring(book[0], second.range), "Two.")
        let third = try XCTUnwrap(ReadAloud.next(book, after: second))
        XCTAssertEqual(third, SentencePosition(2, WordRange(0, 6)), "empty paragraphs are skipped")
        XCTAssertNil(ReadAloud.next(book, after: third), "the book's last sentence")
        XCTAssertNil(ReadAloud.start(book, 3))
        XCTAssertNil(ReadAloud.start(["", " "], 0))
        XCTAssertEqual(ReadAloud.start(book, -1), first, "a negative paragraph starts at the first")
    }

    func testPreviousGoesBackOneSentenceAcrossEmptyParagraphs() {
        let book = ["One. Two.", "", "Three."]
        let one = SentencePosition(0, WordRange(0, 4))
        let two = SentencePosition(0, WordRange(5, 9))
        let three = SentencePosition(2, WordRange(0, 6))
        XCTAssertEqual(ReadAloud.previous(book, before: three), two)
        XCTAssertEqual(ReadAloud.previous(book, before: two), one)
        XCTAssertNil(ReadAloud.previous(book, before: one), "the book's first sentence")
        XCTAssertEqual(ReadAloud.previous(book, before: SentencePosition(9, WordRange(0, 1))), three, "past the end: the last sentence")
    }

    func testARepeatedStretchCountsItsSentences() {
        let book = ["One. Two.", "", "Three."]
        let one = SentencePosition(0, WordRange(0, 4))
        let three = SentencePosition(2, WordRange(0, 6))
        XCTAssertEqual(ReadAloud.count(book, from: one, to: one), 1)
        XCTAssertEqual(ReadAloud.count(book, from: one, to: three), 3)
        XCTAssertEqual(ReadAloud.count(book, from: three, to: one), 0, "the end before the start")
        XCTAssertEqual(ReadAloud.count(book, from: one, to: SentencePosition(0, WordRange(1, 2))), 0, "an end that is no sentence")
    }

    func testSentencesMatchTheSentenceOfEachWordAndStayLinearOnHostileText() {
        let text = "Tom has a boat. It is red!  Is it new? “Yes,” he said. No end"
        for sentence in ReadAloud.sentences(text) {
            XCTAssertEqual(TextTools.sentenceRangeAt(text, sentence.start), sentence, "same rule as the sentence of a word")
        }
        let hostile = String(repeating: "a. ", count: 1000)
        let started = Date()
        XCTAssertEqual(ReadAloud.sentences(hostile).count, 1000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "one pass, not one per sentence")
    }

    func testALongRepeatedStretchIsCountedInOnePassPerParagraph() {
        let book = Array(repeating: String(repeating: "a. ", count: 600), count: 20)
        let first = ReadAloud.start(book, 0)!
        let last = ReadAloud.previous(book, before: SentencePosition(20, WordRange(0, 1)))!
        let started = Date()
        XCTAssertEqual(ReadAloud.count(book, from: first, to: last), 12_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "one split per paragraph, not one per sentence")
    }

    func testAHardCutKeepsAnEmojiWhole() {
        // 599 letters, then an emoji (2 UTF-16 units) across the 600-unit cut, with no space.
        let text = String(repeating: "a", count: 599) + "😀" + String(repeating: "b", count: 10)
        let pieces = ReadAloud.sentences(text)
        XCTAssertEqual(pieces.first, WordRange(0, 599), "the cut moves before the emoji")
        XCTAssertEqual(pieces.last?.end, (text as NSString).length, "nothing skipped")
    }
}

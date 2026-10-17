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
}

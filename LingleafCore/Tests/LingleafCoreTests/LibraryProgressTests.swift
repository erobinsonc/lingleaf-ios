import XCTest
@testable import LingleafCore

/// Reading progress (SPEC S2): where to resume, and how much has been read.
final class LibraryProgressTests: XCTestCase {
    private let storage = MemoryStorage()
    private var now = ISO8601DateFormatter().date(from: "2026-10-09T09:00:00Z")!
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

    func testRestoredReadingProgressStaysInsideTheBook() throws {
        let book = library().addBook(title: "T", author: "A", text: "One.\n\nTwo.")
        let saved = try XCTUnwrap(storage.files["books.json"])
        storage.files["books.json"] = saved.replacingOccurrences(
            of: #""progressParagraph"\s*:\s*0"#, with: #""progressParagraph":-7"#, options: .regularExpression
        )
        XCTAssertEqual(library().state.books.first { $0.id == book.id }?.progressParagraph, 0)
    }

    // MARK: Reading progress (SPEC S2)

    func testProgressFollowsTheFurthestParagraphSeenAndNeverGoesBack() {
        let library = library()
        let book = library.addBook(title: "T", author: "A", text: "1.\n\n2.\n\n3.\n\n4.\n\n5.")
        func progress() -> Double { library.state.books.first { $0.id == book.id }?.progress ?? -1 }
        XCTAssertEqual(progress(), 0)
        library.updateProgress(book.id, paragraph: 1)
        XCTAssertEqual(progress(), 0.25)
        // The last paragraph on screen while the top one is the second: the whole book has been seen.
        library.markSeen(book.id, paragraph: 4)
        XCTAssertEqual(progress(), 1)
        // Scrolling back up moves the place to resume, not how much has been read.
        library.updateProgress(book.id, paragraph: 0)
        XCTAssertEqual(library.state.books.first?.progressParagraph, 0)
        XCTAssertEqual(progress(), 1, "never goes back")
        library.markSeen(book.id, paragraph: 2)
        XCTAssertEqual(library.state.books.first?.furthestParagraph, 4, "a paragraph before the furthest changes nothing")
        library.markSeen(book.id, paragraph: 99)
        library.markSeen(book.id, paragraph: -3)
        library.markSeen("missing", paragraph: 1)
        XCTAssertEqual(library.state.books.first?.furthestParagraph, 4, "inside the book")
        library.flush()
        XCTAssertEqual(self.library().state.books.first?.progress, 1, "kept")
    }

    func testAOneParagraphBookIsReadOnceItHasBeenOnScreen() {
        let library = library()
        let book = library.addBook(title: "T", author: "A", text: "Only.")
        XCTAssertEqual(library.state.books.first?.progress, 0, "not opened yet")
        library.markSeen(book.id, paragraph: 0)
        XCTAssertEqual(library.state.books.first?.progress, 1, "its last paragraph is on screen")
    }

    func testAOneParagraphBookOpenedBeforeFurthestParagraphExistedCountsAsRead() throws {
        let book = library().addBook(title: "T", author: "A", text: "Only.")
        _ = library().openBook(book.id)
        // As an older version saved it: opened, with no furthest paragraph.
        let data = try XCTUnwrap(storage.files["books.json"]?.data(using: .utf8))
        var books = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        books[0]["furthestParagraph"] = nil
        storage.files["books.json"] = String(decoding: try JSONSerialization.data(withJSONObject: books), as: UTF8.self)
        let old = try XCTUnwrap(library().state.books.first)
        XCTAssertNil(old.furthestParagraph)
        XCTAssertNotNil(old.lastOpenedAt)
        XCTAssertEqual(old.progress, 1, "opened before: its only paragraph was on screen")
        books[0]["lastOpenedAt"] = nil
        storage.files["books.json"] = String(decoding: try JSONSerialization.data(withJSONObject: books), as: UTF8.self)
        XCTAssertEqual(library().state.books.first?.progress, 0, "never opened")
    }

    func testABookSavedBeforeFurthestParagraphLoadsWithItsPlaceAndAValueOutsideTheBookIsBroughtIn() throws {
        let book = library().addBook(title: "T", author: "A", text: "1.\n\n2.\n\n3.")
        func rewrite(_ change: (inout [String: Any]) -> Void) throws {
            let data = try XCTUnwrap(storage.files["books.json"]?.data(using: .utf8))
            var books = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            change(&books[0])
            storage.files["books.json"] = String(decoding: try JSONSerialization.data(withJSONObject: books), as: UTF8.self)
        }
        func loaded() -> Book? { library().state.books.first { $0.id == book.id } }
        try rewrite { $0["progressParagraph"] = 1; $0["furthestParagraph"] = nil }
        XCTAssertNil(loaded()?.furthestParagraph, "an old file has none")
        XCTAssertEqual(loaded()?.progress, 0.5, "the place stands in")
        try rewrite { $0["furthestParagraph"] = 99 }
        XCTAssertEqual(loaded()?.furthestParagraph, 2, "inside the book")
        XCTAssertEqual(loaded()?.progress, 1)
        try rewrite { $0["furthestParagraph"] = -5 }
        XCTAssertEqual(loaded()?.furthestParagraph, 0)
        XCTAssertEqual(loaded()?.progress, 0.5, "the place is still where it was")
    }

    func testOpeningABookWhoseTextLostInvisibleParagraphsMovesTheFurthestParagraphToo() {
        let library = library()
        let book = library.addBook(title: "T", author: "A", text: "One.\n\nTwo.\n\nThree.\n\nFour.")
        library.updateProgress(book.id, paragraph: 3)
        library.markSeen(book.id, paragraph: 3)
        // The text as an older version stored it: a paragraph made only of a zero-width space.
        storage.files[book.fileName] = "One.\n\n\u{200B}\n\nThree.\n\nFour."
        XCTAssertEqual(library.openBook(book.id).count, 3)
        let opened = library.state.books.first
        XCTAssertEqual(opened?.paragraphCount, 3)
        XCTAssertEqual(opened?.progressParagraph, 2)
        XCTAssertEqual(opened?.furthestParagraph, 2)
        XCTAssertEqual(opened?.progress, 1)
    }

    func testOpeningAnOldBookWithNoFurthestParagraphKeepsItAbsent() throws {
        let book = library().addBook(title: "T", author: "A", text: "One.\n\nTwo.\n\nThree.\n\nFour.")
        let data = try XCTUnwrap(storage.files["books.json"]?.data(using: .utf8))
        var books = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        books[0]["progressParagraph"] = 3
        books[0]["furthestParagraph"] = nil
        storage.files["books.json"] = String(decoding: try JSONSerialization.data(withJSONObject: books), as: UTF8.self)
        let library = self.library()
        storage.files[book.fileName] = "One.\n\n\u{200B}\n\nThree.\n\nFour."
        XCTAssertEqual(library.openBook(book.id).count, 3)
        let opened = library.state.books.first
        XCTAssertEqual(opened?.progressParagraph, 2)
        XCTAssertNil(opened?.furthestParagraph, "absent stays absent")
        XCTAssertEqual(opened?.progress, 1)
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
}

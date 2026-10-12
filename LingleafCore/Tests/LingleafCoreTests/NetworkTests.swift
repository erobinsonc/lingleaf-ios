import XCTest
@testable import LingleafCore

private func ok(_ body: String) -> HttpResponse { HttpResponse(status: 200, text: body) }
private let notFound = HttpResponse(status: 404, text: "[]")

/// Thread-safe list of requested URLs.
private actor Recorder {
    var urls: [String] = []
    func add(_ url: String) { urls.append(url) }
}

final class GutenbergTests: XCTestCase {
    private let alice = """
    {"id": 11, "title": "Alice", "authors": [{"name": "Carroll, Lewis", "birth_year": 1832}],
     "formats": {"text/plain; charset=us-ascii": "https://example.com/11.txt",
                 "text/plain; charset=utf-8": "https://example.com/11.utf8.txt",
                 "application/zip": "https://example.com/11.zip",
                 "image/jpeg": "https://example.com/11.jpg"},
     "download_count": 5}
    """

    func testStripsLicenseHeaderAndFooter() {
        let raw = "The Project Gutenberg eBook\r\nLicense\r\n*** START OF THE PROJECT GUTENBERG EBOOK X ***\r\n\r\n"
            + "Chapter 1\r\n\r\nOnce upon a time.\r\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\r\nMore license"
        XCTAssertEqual(GutenbergClient.stripBoilerplate(raw), "Chapter 1\n\nOnce upon a time.")
        XCTAssertEqual(GutenbergClient.stripBoilerplate("  Just a story.\n"), "Just a story.")
    }

    func testCatalogTitlesAndAuthorsAreShortenedForDisplay() {
        func book(_ title: String, _ author: String) -> GutenbergBook {
            GutenbergBook(id: 1, title: title, authors: [.init(name: author)])
        }
        XCTAssertEqual(book("Peter Pan : $b [Peter and Wendy]", "x").displayTitle, "Peter Pan")
        XCTAssertEqual(book("Moby-Dick; Or, The Whale", "x").displayTitle, "Moby-Dick")
        XCTAssertEqual(book("Frankenstein\r\nOr, The Modern Prometheus", "x").displayTitle, "Frankenstein")
        XCTAssertEqual(book("Treasure Island", "x").displayTitle, "Treasure Island")
        XCTAssertEqual(book("x", "Baum, L. Frank (Lyman Frank)").authorName, "L. Frank Baum")
        XCTAssertEqual(book("x", "Barrie, J. M. (James Matthew)").authorName, "J. M. Barrie")
        XCTAssertEqual(book("x", "Aesop").authorName, "Aesop")
    }

    func testRecommendedBooksShipWithTheAppWithDirectLinks() {
        let books = GutenbergClient.recommendedBooks
        XCTAssertEqual(books.map(\.id), GutenbergClient.recommended.map(\.id), "same books, same order as the levels")
        let alice = books.first { $0.id == 11 }
        XCTAssertEqual(alice?.displayTitle, "Alice's Adventures in Wonderland")
        XCTAssertEqual(alice?.authorName, "Lewis Carroll")
        XCTAssertEqual(alice?.textURL, "https://www.gutenberg.org/cache/epub/11/pg11.txt")
        XCTAssertEqual(alice?.coverURL?.absoluteString, "https://www.gutenberg.org/cache/epub/11/pg11.cover.medium.jpg")
        XCTAssertEqual(GutenbergClient.level(for: 11), "B2")
    }

    func testCatalogBooksDownloadFromTheFileCache() throws {
        let data = Data(#"{"results": [\#(alice)]}"#.utf8)
        struct Page: Decodable { let results: [GutenbergBook] }
        let book = try XCTUnwrap(JSONDecoder().decode(Page.self, from: data).results.first)
        XCTAssertEqual(book.textURL, "https://www.gutenberg.org/cache/epub/11/pg11.txt", "not the catalog's redirecting link")
        XCTAssertNil(GutenbergBook(id: 2, title: "No text", formats: ["application/zip": "https://example.com/2.zip"]).textURL)
    }

    func testFilterKeepsBooksAtTheChosenLevelInOrder() {
        let books = GutenbergClient.recommended.map { GutenbergBook(id: $0.id, title: "Book \($0.id)") }
        XCTAssertEqual(GutenbergClient.filter(books, level: nil), books)
        XCTAssertEqual(GutenbergClient.filter(books, level: "B1").map(\.id), [55, 16, 236])
        XCTAssertEqual(GutenbergClient.filter(books, level: "A1"), [])
        XCTAssertEqual(GutenbergClient.filter([GutenbergBook(id: 999_999, title: "Unlisted")], level: "B1"), [])
    }

    func testEveryRecommendedLevelIsAKnownLevel() {
        for book in GutenbergClient.recommended {
            XCTAssertTrue(GutenbergClient.levels.contains(book.level), "\(book.id) has unknown level \(book.level)")
        }
    }

    private func error(_ operation: () async throws -> Void) async -> Error? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }

    func testSearchEncodesTheQueryAndSaysWhyItFailed() async throws {
        let client = GutenbergClient(http: ClosureFetcher { url in
            if url.contains("search=tom%20sawyer") { return ok(#"{"results": []}"#) }
            if url.contains("search=offline") { throw NetworkError("No internet", kind: .offline) }
            if url.contains("search=slow") { throw NetworkError("Timed out", kind: .timedOut) }
            if url.contains("search=broken") { return ok("<html>") }
            return HttpResponse(status: 500, text: "")
        })
        let none = try await client.search("tom sawyer")
        XCTAssertTrue(none.isEmpty)
        let offline = await error { _ = try await client.search("offline") }
        XCTAssertEqual(offline as? GutenbergError, .offline)
        let slow = await error { _ = try await client.search("slow") }
        XCTAssertEqual(slow as? GutenbergError, .timedOut)
        let broken = await error { _ = try await client.search("broken") }
        XCTAssertEqual(broken as? GutenbergError, .failed)
        let server = await error { _ = try await client.search("other") }
        XCTAssertEqual(server as? GutenbergError, .failed)
        let cancelled = await error { _ = try await GutenbergClient(http: ClosureFetcher { _ in throw CancellationError() }).search("x") }
        XCTAssertTrue(cancelled is CancellationError, "cancelling is not a failure to show")
        let other = await error { _ = try await GutenbergClient(http: ClosureFetcher { _ in throw URLError(.badURL) }).search("x") }
        XCTAssertEqual(other as? GutenbergError, .failed)
    }

    func testDownloadStripsBoilerplateReportsProgressAndSaysWhyItFailed() async throws {
        let book = GutenbergBook(id: 1, title: "X", formats: ["text/plain": "https://example.com/1.txt"])
        let done = Recorder()
        let text = try await GutenbergClient(http: ClosureFetcher { url in
            XCTAssertEqual(url, "https://www.gutenberg.org/cache/epub/1/pg1.txt")
            return ok("h\n*** START OF IT ***\nCafé story.\n*** END OF IT ***")
        }).downloadText(book) { fraction in Task { await done.add(String(fraction)) } }
        XCTAssertEqual(text, "Café story.")
        try await Task.sleep(nanoseconds: 50_000_000)
        let progress = await done.urls
        XCTAssertEqual(progress, ["1.0"])
        let cases: [(GutenbergClient, GutenbergBook, GutenbergError)] = [
            (GutenbergClient(http: ClosureFetcher { _ in ok("*** START OF IT ***\n*** END OF IT ***") }), book, .unavailable),
            (GutenbergClient(http: ClosureFetcher { _ in notFound }), book, .unavailable),
            (GutenbergClient(http: ClosureFetcher { _ in HttpResponse(status: 403, text: "") }), book, .unavailable),
            (GutenbergClient(http: ClosureFetcher { _ in HttpResponse(status: 503, text: "") }), book, .failed),
            (GutenbergClient(http: ClosureFetcher { _ in ok("x") }), GutenbergBook(id: 2, title: "No text"), .unavailable),
        ]
        for (client, target, expected) in cases {
            let failure = await error { _ = try await client.downloadText(target) }
            XCTAssertEqual(failure as? GutenbergError, expected)
        }
    }

    func testURLErrorsMapToOfflineTimedOutAndCancelled() {
        XCTAssertEqual((URLSessionFetcher.networkError(URLError(.notConnectedToInternet)) as? NetworkError)?.kind, .offline)
        XCTAssertEqual((URLSessionFetcher.networkError(URLError(.timedOut)) as? NetworkError)?.kind, .timedOut)
        XCTAssertEqual((URLSessionFetcher.networkError(URLError(.cannotFindHost)) as? NetworkError)?.kind, .offline)
        XCTAssertEqual((URLSessionFetcher.networkError(URLError(.cannotConnectToHost)) as? NetworkError)?.kind, .offline)
        XCTAssertEqual((URLSessionFetcher.networkError(URLError(.badServerResponse)) as? NetworkError)?.kind, .other)
        XCTAssertTrue(URLSessionFetcher.networkError(URLError(.cancelled)) is CancellationError)
    }
}

final class DictionaryTests: XCTestCase {
    private static func entry(_ word: String, _ definition: String, phonetic: String? = nil) -> HttpResponse {
        let phoneticField = phonetic.map { #""phonetic": "\#($0)","# } ?? ""
        return ok(#"""
        [{"word": "\#(word)", \#(phoneticField)
          "phonetics": [{"audio": ""}, {"text": "/\#(word)/"}],
          "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "\#(definition)"}]}]}]
        """#)
    }

    func testFallsBackToBaseFormsWhenTheWordIsMissing() async {
        let recorder = Recorder()
        let client = DictionaryClient(http: ClosureFetcher { url in
            let word = String(url.split(separator: "/").last ?? "")
            await recorder.add(word)
            return word == "animal" ? Self.entry("animal", "A living creature.", phonetic: "/ˈænɪməl/") : notFound
        })
        let result = await client.lookup("Animals")
        XCTAssertEqual(result?.word, "animal")
        XCTAssertEqual(result?.phonetic, "/ˈænɪməl/")
        XCTAssertEqual(result?.partOfSpeech, "noun")
        let requested = await recorder.urls
        XCTAssertEqual(requested, ["animals", "animal"])
        _ = await client.lookup("animals")
        let afterCache = await recorder.urls
        XCTAssertEqual(afterCache.count, 2, "results and misses are cached")
    }

    func testFollowsPastTenseOfToTheBaseWord() async {
        let client = DictionaryClient(http: ClosureFetcher { url in
            switch url.split(separator: "/").last.map(String.init) ?? "" {
            case "walked": return Self.entry("walked", "simple past tense and past participle of walk")
            case "walk": return Self.entry("walk", "To move on the feet.")
            default: return notFound
            }
        })
        let result = await client.lookup("walked")
        XCTAssertEqual(result?.word, "walk")
        XCTAssertEqual(result?.phonetic, "/walk/")
    }

    func testReturnsNilWhenOfflineOnServerErrorsOrBadJSON() async {
        let offline = await DictionaryClient(http: ClosureFetcher { _ in throw NetworkError("offline") }).lookup("equal")
        XCTAssertNil(offline)
        let serverError = await DictionaryClient(http: ClosureFetcher { _ in HttpResponse(status: 500, text: "") }).lookup("equal")
        XCTAssertNil(serverError)
        let badJSON = await DictionaryClient(http: ClosureFetcher { _ in ok("not json") }).lookup("equal")
        XCTAssertNil(badJSON)
        let missing = await DictionaryClient(http: ClosureFetcher { _ in notFound }).lookup("zzzz")
        XCTAssertNil(missing)
    }
}

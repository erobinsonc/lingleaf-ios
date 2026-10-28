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

    func testCoversLoadOnlyFromTheGutenbergFileCache() {
        let elsewhere = GutenbergBook(id: 3, title: "x", formats: ["image/jpeg": "http://example.com/huge.jpg"])
        let cover = "https://www.gutenberg.org/cache/epub/3/pg3.cover.medium.jpg"
        XCTAssertEqual(elsewhere.coverURL?.absoluteString, cover, "not the catalog's link")
        XCTAssertNil(GutenbergBook(id: 4, title: "No cover").coverURL)
    }

    func testCoversDecodeDownsampledAndHugeImagesAreRefused() {
        XCTAssertEqual(GutenbergClient.coverSample(width: 350, height: 500), 1, "a medium cover stays sharp")
        XCTAssertEqual(GutenbergClient.coverSample(width: 1000, height: 1400), 4)
        XCTAssertNil(GutenbergClient.coverSample(width: 5000, height: 10), "a side over 4096 px")
        XCTAssertNil(GutenbergClient.coverSample(width: 4096, height: 4096), "over 4 megapixels")
        XCTAssertNil(GutenbergClient.coverSample(width: -1, height: -1), "not an image")
    }

    func testOnlyJPEGCoversReachTheImageDecoder() {
        XCTAssertTrue(GutenbergClient.isJPEG(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        XCTAssertFalse(GutenbergClient.isJPEG(Data("RIFF....WEBP".utf8)), "WebP")
        XCTAssertFalse(GutenbergClient.isJPEG(Data([0xFF, 0xD8])), "too short")
        XCTAssertFalse(GutenbergClient.isJPEG(Data()))
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

    func testDeeplyNestedJSONIsRefusedBeforeParsing() async throws {
        let deep = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        XCTAssertFalse(JSONGuard.isShallow(Data(deep.utf8)))
        XCTAssertTrue(JSONGuard.isShallow(Data(#"{"results": [{"id": 1, "title": "[[[[[[[[[[\"]]"}]}"#.utf8)), "brackets in strings")
        let search = await error { _ = try await GutenbergClient(http: ClosureFetcher { _ in ok(deep) }).search("x") }
        XCTAssertEqual(search as? GutenbergError, .failed)
        let word = await DictionaryClient(http: ClosureFetcher { _ in ok(deep) }).lookup("x")
        XCTAssertNil(word)
    }

    func testSearchShowsEachBookOnceAndRecommendedBooksAsShipped() async throws {
        let fake = #"{"id": 21, "title": "\u202eFake", "formats": {"text/plain": "x"}}"#
        let other = #"{"id": 99, "title": "Other", "formats": {"text/plain": "x"}}"#
        let many = (1000..<1100).map { #"{"id": \#($0), "title": "B"}"# }.joined(separator: ",")
        let client = GutenbergClient(http: ClosureFetcher { _ in ok(#"{"results": [\#(fake), \#(other), \#(fake), \#(many)]}"#) })
        let found = try await client.search("x")
        XCTAssertEqual(Array(found.prefix(2).map(\.id)), [21, 99], "the duplicate is dropped")
        XCTAssertEqual(found.first?.title, GutenbergClient.recommendedBooks.first { $0.id == 21 }?.title)
        XCTAssertEqual(found.count, GutenbergClient.maxResults)
    }

    func testOnlyHTTPSToTheAppsHostsIsAllowed() async {
        XCTAssertTrue(Hosts.isAllowed(URL(string: "https://www.gutenberg.org/cache/epub/11/pg11.txt")))
        XCTAssertTrue(Hosts.isAllowed(URL(string: "https://gutendex.com/books/?search=alice")))
        XCTAssertTrue(Hosts.isAllowed(URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/walk")))
        XCTAssertFalse(Hosts.isAllowed(URL(string: "http://www.gutenberg.org/x")), "plain HTTP")
        XCTAssertFalse(Hosts.isAllowed(URL(string: "https://evil.example/x")), "another host")
        XCTAssertFalse(Hosts.isAllowed(URL(string: "https://gutenberg.org.evil.example/x")), "a look-alike host")
        XCTAssertFalse(Hosts.isAllowed(URL(string: "https://www.gutenberg.org:8443/x")), "another port")
        XCTAssertFalse(Hosts.isAllowed(URL(string: "https://user@www.gutenberg.org/x")), "credentials in the URL")
        XCTAssertFalse(Hosts.isAllowed(nil))
        // Refused before any connection is made.
        do {
            _ = try await URLSessionFetcher().get("https://evil.example/x")
            XCTFail("another host must be refused")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
}

final class DictionaryTests: XCTestCase {
    private static func entry(
        _ word: String, _ definition: String, phonetic: String? = nil, partOfSpeech: String = "noun"
    ) -> HttpResponse {
        let phoneticField = phonetic.map { #""phonetic": "\#($0)","# } ?? ""
        return ok(#"""
        [{"word": "\#(word)", \#(phoneticField)
          "phonetics": [{"audio": ""}, {"text": "/\#(word)/"}],
          "meanings": [{"partOfSpeech": "\#(partOfSpeech)", "definitions": [{"definition": "\#(definition)"}]}]}]
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

    /// A client answering from `entries` (word → definition), recording what it asked for.
    private static func client(_ entries: [String: String], _ recorder: Recorder, verbs: Set<String> = []) -> DictionaryClient {
        DictionaryClient(http: ClosureFetcher { url in
            let word = String(url.split(separator: "/").last ?? "")
            await recorder.add(word)
            return entries[word].map { Self.entry(word, $0, partOfSpeech: verbs.contains(word) ? "verb" : "noun") } ?? notFound
        })
    }

    func testAVerbReadingLooksItsBaseUpFirst() async {
        let recorder = Recorder()
        let client = Self.client(["steal": "To take without permission.", "stole": "A long scarf."], recorder, verbs: ["steal"])
        let result = await client.lookup("stole", reading: Reading(kind: .verb, base: "steal", step: .subject))
        XCTAssertEqual(result?.word, "steal")
        let requested = await recorder.urls
        XCTAssertEqual(requested, ["steal"])
    }

    func testANounReadingDoesNotFollowPastTenseOf() async {
        let recorder = Recorder()
        let client = Self.client(["left": "simple past tense and past participle of leave", "leave": "To go away."], recorder)
        let result = await client.lookup("left", reading: Reading(kind: .noun, base: "left", step: .fixed))
        XCTAssertEqual(result?.word, "left")
        let requested = await recorder.urls
        XCTAssertEqual(requested, ["left"])
    }

    func testAReadingFallsBackToTheTappedWord() async {
        let recorder = Recorder()
        let client = Self.client(["leaves": "plural of leaf"], recorder)
        let result = await client.lookup("Leaves", reading: Reading(kind: .noun, base: "leaf", step: .noun))
        XCTAssertEqual(result?.word, "leaves", "no entry for the base: the word as tapped")
        let requested = await recorder.urls
        XCTAssertEqual(requested, ["leaf", "leaves"])
    }

    func testAnUnsureReadingLooksUpAsBefore() async {
        let recorder = Recorder()
        let client = Self.client(["left": "simple past tense and past participle of leave", "leave": "To go away."], recorder)
        let result = await client.lookup("left", reading: Reading(kind: .unsure, base: "left", step: .unsure))
        XCTAssertEqual(result?.word, "leave", "as without a reading: follows \"past tense of\"")
    }

    func testAReadingTakesTheMeaningOfItsPartOfSpeechWithItsEntrysIPA() async {
        let answer = ok(#"""
        [{"word": "wind", "phonetic": "/wɪnd/", "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "Moving air."}]}]},
         {"word": "wind", "phonetic": "/waɪnd/", "meanings": [{"partOfSpeech": "verb", "definitions": [{"definition": "To turn."}]}]}]
        """#)
        let client = DictionaryClient(http: ClosureFetcher { _ in answer })
        let verb = await client.lookup("wound", reading: Reading(kind: .verb, base: "wind", step: .subject))
        XCTAssertEqual(verb?.definition, "To turn.")
        XCTAssertEqual(verb?.phonetic, "/waɪnd/", "the IPA of the entry the meaning is in")
        let noun = await client.lookup("wind", reading: Reading(kind: .noun, base: "wind", step: .noun), nounIPA: "wɪnd")
        XCTAssertEqual(noun?.definition, "Moving air.")
        let plain = await client.lookup("wind")
        XCTAssertEqual(plain?.definition, "Moving air.", "without a reading: the first meaning")
        XCTAssertEqual(DictionaryEntry.parseAll([["word": "x"]]).first?.definition, nil, "an entry without meanings")
        XCTAssertTrue(DictionaryEntry.parseAll([["meanings": [[String: Any]]()]]).isEmpty, "no word: nothing")
        let many = [[String: Any]](repeating: ["word": "x", "meanings": [["partOfSpeech": "noun"], ["partOfSpeech": "verb"]]], count: 40)
        XCTAssertEqual(DictionaryEntry.parseAll(many).count, DictionaryEntry.maxEntries * 2, "10 entries of at most 10 meanings")
        let meanings = [[String: Any]](repeating: ["partOfSpeech": "noun"], count: 20)
        let wide: [[String: Any]] = [["word": "x", "meanings": meanings]]
        XCTAssertEqual(DictionaryEntry.parseAll(wide).count, DictionaryEntry.maxMeanings)
    }

    /// Real dictionaryapi.dev (Wiktionary) answers, identical to lingleaf-android's
    /// (core/src/test/resources/dictionary), and "tear" with its entries the other way round.
    private static func fixture(_ name: String) -> HttpResponse? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "dictionary"),
              let data = try? Data(contentsOf: url) else { return nil }
        return HttpResponse(status: 200, body: data)
    }

    private static func fixtureClient(tear: String = "tear") -> DictionaryClient {
        DictionaryClient(http: ClosureFetcher { url in
            let word = String(url.split(separator: "/").last ?? "")
            guard ["wind", "tear", "lead", "lie", "bear"].contains(word) else { return notFound }
            return Self.fixture(word == "tear" ? tear : word) ?? notFound
        })
    }

    func testAReadingTakesTheEntryPronouncedAsTheTableSaysAndNeverAnotherPartOfSpeech() async {
        XCTAssertNotNil(Self.fixture("tear-reversed"), "the fixtures ship with the tests")
        let client = Self.fixtureClient()
        func lookup(
            _ word: String, _ kind: Reading.Kind, _ base: String, _ step: Reading.Step = .subject, nounIPA: String? = nil
        ) async -> DictionaryEntry? {
            await client.lookup(word, reading: Reading(kind: kind, base: base, step: step), nounIPA: nounIPA)
        }
        let wind = await lookup("wound", .verb, "wind")
        XCTAssertTrue(wind?.definition?.hasPrefix("To turn coils") == true, "/waɪnd/, not /wɪnd/")
        XCTAssertEqual(wind?.phonetic, "/waɪnd/")
        let windNoun = await lookup("wind", .noun, "wind", .noun, nounIPA: "wɪnd")
        XCTAssertTrue(windNoun?.definition?.hasPrefix("Real or perceived") == true)
        let tear = await lookup("tore", .verb, "tear", .table)
        XCTAssertTrue(tear?.definition?.hasPrefix("To rend") == true, "/tɛɹ/ is the table's tɛr")
        let led = await lookup("led", .verb, "lead", .table)
        XCTAssertTrue(led?.definition?.hasPrefix("To guide") == true)
        let lay = await lookup("lay", .verb, "lie")
        XCTAssertTrue(lay?.definition?.hasPrefix("To rest") == true)
        let lied = await lookup("lied", .homonym, "lie", .table)
        XCTAssertNil(lied, "the twin: none")
        let bore = await lookup("bore", .verb, "bear")
        XCTAssertTrue(bore?.definition?.hasPrefix("To carry") == true)
        let bear = await lookup("bear", .noun, "bear", .noun)
        XCTAssertTrue(bear?.definition?.hasPrefix("A large mammal") == true)
        let ordinary = await lookup("bear", .word, "bear", .ordinary)
        XCTAssertEqual(ordinary?.word, "bear", "an ordinary word is looked up as tapped")
        let reversed = await Self.fixtureClient(tear: "tear-reversed")
            .lookup("tore", reading: Reading(kind: .verb, base: "tear", step: .table))
        XCTAssertEqual(reversed, tear, "the entry by its sound, not its place in the answer")
        let nothing = DictionaryClient(http: ClosureFetcher { _ in Self.entry("light", "Brightness.") })
        let noVerb = await nothing.lookup("lit", reading: Reading(kind: .verb, base: "light", step: .table))
        XCTAssertNil(noVerb, "no verb meaning: none, not the noun's")
    }

    func testTheTableIPAWithNoEntryPronouncedSoGivesNoDefinition() async {
        // Only the /wɪnd/ entry, and the past form's own entry ("wound": to injure).
        let client = DictionaryClient(http: ClosureFetcher { url in
            switch String(url.split(separator: "/").last ?? "") {
            case "wind": return Self.entry("wind", "To blow air through a wind instrument.", phonetic: "/wɪnd/", partOfSpeech: "verb")
            case "wound": return Self.entry("wound", "To hurt or injure.", phonetic: "/wuːnd/", partOfSpeech: "verb")
            default: return notFound
            }
        })
        let wound = await client.lookup("wound", reading: Reading(kind: .verb, base: "wind", step: .subject))
        XCTAssertNil(wound, "nothing pronounced /waɪnd/: no definition, never the first meaning")
        let none = DictionaryClient(http: ClosureFetcher { url in
            url.hasSuffix("/wound") ? Self.entry("wound", "To hurt or injure.", partOfSpeech: "verb") : notFound
        })
        let tapped = await none.lookup("wound", reading: Reading(kind: .verb, base: "wind", step: .subject))
        XCTAssertEqual(tapped?.word, "wound", "no verb entry of the base at all: the word as tapped (as lingleaf-android)")
    }

    func testPronunciationsMatchAcrossNotationsAndAMalformedEntryIsSkipped() {
        XCTAssertTrue(DictionaryEntry.sameIPA("/ˈwaɪnd/", "waɪnd"))
        XCTAssertTrue(DictionaryEntry.sameIPA("[tɛɹ]", "tɛr"))
        XCTAssertTrue(DictionaryEntry.sameIPA("/ɡɪv/", "gɪv"), "Wiktionary's ɡ is g")
        XCTAssertTrue(DictionaryEntry.sameIPA("/te\u{0301}/", "/t\u{00E9}/"), "compared in NFC")
        XCTAssertFalse(DictionaryEntry.sameIPA("/WAɪnd/", "waɪnd"), "no lowercasing: IPA letters are sounds")
        XCTAssertFalse(DictionaryEntry.sameIPA("", ""))
        XCTAssertFalse(DictionaryEntry.sameIPA("/ˈ/", "ˈ"), "only marks: nothing")
        let meaning: [String: Any] = ["partOfSpeech": "noun", "definitions": ["y", ["definition": "A drop."]] as [Any]]
        let entry: [String: Any] = [
            "word": "tear", "phonetic": "/tɪə/",
            "phonetics": [["text": "/tɪɹ/"], "x", ["audio": ""], ["text": "/tɪə/"]] as [Any],
            "meanings": [42, meaning] as [Any],
        ]
        let entries = DictionaryEntry.parseAll(["not an entry", entry])
        XCTAssertEqual(entries.count, 1, "a non-object element is skipped, not the whole answer")
        XCTAssertEqual(entries.first?.phonetics, ["/tɪə/", "/tɪɹ/"], "every pronunciation, once")
        XCTAssertEqual(entries.first?.definition, nil, "a first definition that is not an object is none")
    }

    func testHugeAnswersAreCutToSaneLengths() async {
        let huge = String(repeating: "plural ", count: 200_000)
        let client = DictionaryClient(http: ClosureFetcher { _ in Self.entry("big", huge, phonetic: String(repeating: "x", count: 5_000)) })
        let result = await client.lookup("big")
        XCTAssertEqual(result?.definition?.count, DictionaryEntry.maxDefinition)
        XCTAssertEqual(result?.phonetic?.count, DictionaryEntry.maxShortField)
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

import Foundation

/// A public-domain book from Project Gutenberg, as listed by the Gutendex API.
public struct GutenbergBook: Decodable, Identifiable, Hashable, Sendable {
    public struct Person: Decodable, Hashable, Sendable {
        public let name: String

        public init(name: String) { self.name = name }
    }

    public let id: Int
    public let title: String
    public let authors: [Person]
    public let formats: [String: String]

    public init(id: Int, title: String, authors: [Person] = [], formats: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.authors = authors
        self.formats = formats
    }

    enum CodingKeys: String, CodingKey { case id, title, authors, formats }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        authors = try c.decodeIfPresent([Person].self, forKey: .authors) ?? []
        formats = try c.decodeIfPresent([String: String].self, forKey: .formats) ?? [:]
    }

    /// "Carroll, Lewis" → "Lewis Carroll"
    public var authorName: String? {
        guard let raw = authors.first?.name else { return nil }
        // "Baum, L. Frank (Lyman Frank)" → "Baum, L. Frank": drop the catalog's full-name note.
        let name = raw.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let parts = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return TextTools.cleanLabel(parts.count == 2 ? "\(parts[1]) \(parts[0])" : name)
    }

    /// Short title for lists: catalog titles carry subtitles and MARC markers
    /// ("Peter Pan : $b [Peter and Wendy]", "Moby-Dick; Or, The Whale").
    public var displayTitle: String {
        // Split on newlines first: Swift treats "\r\n" as one Character, which a
        // plain "\n" search would not find.
        var short = title.components(separatedBy: .newlines).first ?? title
        for separator in [" : ", ";", "$b"] {
            if let range = short.range(of: separator) { short = String(short[..<range.lowerBound]) }
        }
        let trimmed = TextTools.cleanLabel(short)
        return trimmed.isEmpty ? TextTools.cleanLabel(title) : trimmed
    }

    /// The medium cover from Project Gutenberg's file cache, never a link taken from the
    /// catalog: covers load only from www.gutenberg.org. Nil when the catalog lists none.
    public var coverURL: URL? {
        guard formats["image/jpeg"] != nil else { return nil }
        return URL(string: GutenbergClient.coverURL(id))
    }

    /// The plain-text edition, straight from Project Gutenberg's file cache: the catalog's
    /// "ebooks/<id>.txt.utf-8" links redirect there, and every hop is another chance to fail.
    /// Nil when the catalog lists no plain-text edition.
    public var textURL: String? {
        guard formats.contains(where: { $0.key.hasPrefix("text/plain") && !$0.value.hasSuffix(".zip") }) else { return nil }
        return GutenbergClient.textURL(id)
    }
}

/// Why talking to Project Gutenberg failed, so the learner gets the right message and action.
public enum GutenbergError: Error, Equatable, Sendable {
    /// No internet connection.
    case offline
    /// The server didn't answer in time.
    case timedOut
    /// The book can't be had right now (403, 404, 410, no plain text, or empty).
    case unavailable
    /// Anything else (5xx, a broken answer).
    case failed

    init(_ error: Error) {
        if let error = error as? GutenbergError {
            self = error
        } else if let error = error as? NetworkError {
            switch error.kind {
            case .offline: self = .offline
            case .timedOut: self = .timedOut
            case .other: self = .failed
            }
        } else {
            self = .failed
        }
    }

    init(status: Int) {
        self = [403, 404, 410].contains(status) ? .unavailable : .failed
    }
}

private struct GutendexResponse: Decodable {
    let results: [GutenbergBook]
}

public struct GutenbergClient: Sendable {
    private let http: HttpFetcher
    private static let base = "https://gutendex.com/books"

    /// Hand-picked classics with a CEFR level hint, easiest first: public domain worldwide
    /// (every author died in 1925 or earlier) and without old spellings such as "to-day". Shipped with the app
    /// (title, author, level), so Discover shows them at once and without the catalog.
    public static let recommendedBooks: [GutenbergBook] = [
        (25519, "Little Wizard Stories of Oz", "Baum, L. Frank"),
        (55, "The Wonderful Wizard of Oz", "Baum, L. Frank"),
        (54, "The Marvelous Land of Oz", "Baum, L. Frank"),
        (486, "Ozma of Oz", "Baum, L. Frank"),
        (517, "The Emerald City of Oz", "Baum, L. Frank"),
        (1874, "The Railway Children", "Nesbit, E."),
        (3536, "The Enchanted Castle", "Nesbit, E."),
        (157, "Daddy-Long-Legs", "Webster, Jean"),
        (11, "Alice's Adventures in Wonderland", "Carroll, Lewis"),
        (14522, "The Canterville Ghost", "Wilde, Oscar"),
        (160, "The Awakening and Selected Short Stories", "Chopin, Kate"),
        (208, "Daisy Miller", "James, Henry"),
        (209, "The Turn of the Screw", "James, Henry"),
    ].map { id, title, author in
        GutenbergBook(
            id: id, title: title, authors: [.init(name: author)],
            formats: ["text/plain; charset=utf-8": GutenbergClient.textURL(id), "image/jpeg": GutenbergClient.coverURL(id)]
        )
    }

    /// Project Gutenberg's file cache: the plain-text edition and the medium cover.
    public static func textURL(_ id: Int) -> String { "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).txt" }
    public static func coverURL(_ id: Int) -> String { "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).cover.medium.jpg" }

    /// A real cover is under 1000 px a side; anything far larger is refused before decoding.
    public static let coverMaxSide = 4096
    public static let coverMaxPixels = 4_000_000
    /// Twice the 44×62 pt shown at the densest screens: sharp, yet a few hundred KB at most.
    public static let coverThumbnailWidth = 176
    public static let coverThumbnailHeight = 248

    /// Whether `data` starts like a JPEG file (FF D8 FF). Only JPEG covers reach the system's
    /// image decoder: formats with a history of decoder exploits (WebP, HEIC…) never do.
    public static func isJPEG(_ data: Data) -> Bool { data.starts(with: [0xFF, 0xD8, 0xFF]) }

    /// The power-of-two downsampling that keeps a cover of `width`×`height` px at least
    /// thumbnail-sized, or nil when the image is empty or too large to decode safely.
    public static func coverSample(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0, width <= coverMaxSide, height <= coverMaxSide, width * height <= coverMaxPixels else { return nil }
        var sample = 1
        while width / (sample * 2) >= coverThumbnailWidth, height / (sample * 2) >= coverThumbnailHeight { sample *= 2 }
        return sample
    }

    /// The level of each recommended book, easiest first.
    public static let recommended: [(id: Int, level: String)] = [
        (25519, "B1"), // Little Wizard Stories of Oz
        (55, "B1"), // The Wonderful Wizard of Oz
        (54, "B1"), // The Marvelous Land of Oz
        (486, "B1"), // Ozma of Oz
        (517, "B1"), // The Emerald City of Oz
        (1874, "B2"), // The Railway Children
        (3536, "B2"), // The Enchanted Castle
        (157, "B2"), // Daddy-Long-Legs
        (11, "B2"), // Alice's Adventures in Wonderland
        (14522, "B2"), // The Canterville Ghost
        (160, "C1"), // The Awakening and Selected Short Stories
        (208, "C1"), // Daisy Miller
        (209, "C2"), // The Turn of the Screw
    ]

    /// CEFR levels, easiest first.
    public static let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    /// Levels that have at least one recommended book, easiest first: the filter's chips.
    public static var filterLevels: [String] {
        levels.filter { level in recommended.contains { $0.level == level } }
    }

    public init(http: HttpFetcher) { self.http = http }

    public static func level(for id: Int) -> String? { recommended.first { $0.id == id }?.level }

    /// Books at `level`, in their original order; a nil level keeps every book.
    public static func filter(_ books: [GutenbergBook], level: String?) -> [GutenbergBook] {
        guard let level else { return books }
        return books.filter { Self.level(for: $0.id) == level }
    }

    /// Searches the catalog by title or author. Throws `GutenbergError`; cancelling the task cancels the request.
    public func search(_ query: String) async throws -> [GutenbergBook] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let response = try await call { try await http.get("\(Self.base)?languages=en&search=\(encoded)") }
        guard response.status == 200 else { throw GutenbergError(status: response.status) }
        guard JSONGuard.isShallow(response.body) else { throw GutenbergError.failed }
        do {
            return Self.cleanResults(try JSONDecoder().decode(GutendexResponse.self, from: response.body).results)
        } catch {
            throw GutenbergError.failed
        }
    }

    /// Most results shown for one search (one page of the catalog).
    public static let maxResults = 32

    /// One row per book, at most `maxResults`. A recommended book always shows as shipped
    /// with the app, so a catalog answer can't put another title under its level badge.
    static func cleanResults(_ books: [GutenbergBook]) -> [GutenbergBook] {
        var seen = Set<Int>()
        return books.filter { seen.insert($0.id).inserted }
            .prefix(maxResults)
            .map { book in recommendedBooks.first { $0.id == book.id } ?? book }
    }

    /// The book's text without the license header and footer, reporting progress (0…1)
    /// while it downloads. Throws `GutenbergError`; cancelling the task cancels the download.
    public func downloadText(_ book: GutenbergBook, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        guard let url = book.textURL else { throw GutenbergError.unavailable }
        let response = try await call { try await http.get(url, progress: progress) }
        guard response.status == 200 else { throw GutenbergError(status: response.status) }
        let text = Self.stripBoilerplate(response.text)
        guard !text.isEmpty else { throw GutenbergError.unavailable }
        return text
    }

    /// Runs a request, turning its errors into `GutenbergError` (cancellation passes through).
    private func call(_ request: () async throws -> HttpResponse) async throws -> HttpResponse {
        do {
            return try await request()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GutenbergError(error)
        }
    }

    /// Removes the Project Gutenberg license header and footer.
    public static func stripBoilerplate(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func isMarker(_ line: String, _ kind: String) -> Bool {
            line.hasPrefix("*** \(kind) OF") || line.hasPrefix("***\(kind) OF")
        }
        if let start = lines.firstIndex(where: { isMarker($0, "START") }) { lines.removeSubrange(...start) }
        if let end = lines.firstIndex(where: { isMarker($0, "END") }) { lines.removeSubrange(end...) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

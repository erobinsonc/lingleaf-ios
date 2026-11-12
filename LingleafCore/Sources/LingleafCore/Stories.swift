import Foundation

// The original stories shipped with the app (Resources/Books) and where the Library finds their copies.

public struct BundledStory: Sendable {
    public let title: String
    public let level: String
    public let text: String
    /// One of the 18 stories added with senses (SPEC S19), not one of the first three.
    public let hasSenses: Bool

    public init(title: String, level: String, text: String, hasSenses: Bool = false) {
        self.title = title
        self.level = level
        self.text = text
        self.hasSenses = hasSenses
    }
}

/// A story shipped with the app: its resource file name (without ".txt"), title and level.
public struct ShelfStory: Hashable, Sendable {
    public let resource: String
    public let title: String
    public let level: String
    /// Whether the story ships a senses file, `<resource>.senses.json` (SPEC S19).
    public let hasSenses: Bool

    public init(resource: String, title: String, level: String, hasSenses: Bool = true) {
        self.resource = resource
        self.title = title
        self.level = level
        self.hasSenses = hasSenses
    }
}

extension BundledStory {
    /// The original stories shipped with the app (resource file name, title, level), in the order the
    /// Library lists them on a first launch, top to bottom: A1 to C2, the first three at the start of
    /// their own level. Discover lists them under their level too, so no level of the filter is empty.
    public static let shelf: [ShelfStory] = [
        ShelfStory(resource: "the-red-boat", title: "The Red Boat", level: "A1", hasSenses: false),
        ShelfStory(resource: "a-shoe-in-the-fridge", title: "A Shoe in the Fridge", level: "A1"),
        ShelfStory(resource: "an-empty-apartment", title: "An Empty Apartment", level: "A1"),
        ShelfStory(resource: "nours-long-race", title: "Nour's Long Race", level: "A1"),
        ShelfStory(resource: "a-day-at-the-market", title: "A Day at the Market", level: "A2", hasSenses: false),
        ShelfStory(resource: "a-part-for-lila", title: "A Part for Lila", level: "A2"),
        ShelfStory(resource: "the-oven-next-door", title: "The Oven Next Door", level: "A2"),
        ShelfStory(resource: "the-tree-in-the-second-row", title: "The Tree in the Second Row", level: "A2"),
        ShelfStory(resource: "the-lighthouse-keeper", title: "The Lighthouse Keeper", level: "B1", hasSenses: false),
        ShelfStory(resource: "a-very-important-visitor", title: "A Very Important Visitor", level: "B1"),
        ShelfStory(resource: "the-beat-on-the-hill", title: "The Beat on the Hill", level: "B1"),
        ShelfStory(resource: "the-chess-table-by-the-lake", title: "The Chess Table by the Lake", level: "B1"),
        ShelfStory(resource: "notes-on-the-fridge", title: "Notes on the Fridge", level: "B2"),
        ShelfStory(resource: "the-presentation-in-kisumu", title: "The Presentation in Kisumu", level: "B2"),
        ShelfStory(resource: "three-in-the-morning", title: "Three in the Morning", level: "B2"),
        ShelfStory(resource: "a-number-in-osaka", title: "A Number in Osaka", level: "C1"),
        ShelfStory(resource: "an-apartment-full-of-notes", title: "An Apartment Full of Notes", level: "C1"),
        ShelfStory(resource: "lane-four", title: "Lane Four", level: "C1"),
        ShelfStory(resource: "five-minutes-maximum", title: "Five Minutes, Maximum", level: "C2"),
        ShelfStory(resource: "the-exit-interview", title: "The Exit Interview", level: "C2"),
        ShelfStory(resource: "the-second-violin", title: "The Second Violin", level: "C2"),
    ]

    /// The author the bundled stories are saved with: internal data that finds the library's copy of a shelf
    /// story, never shown (a row says "Our story"). The one place to change if the app is renamed.
    public static let author = "Lingleaf"

    /// Shelf stories at `level`, in order; a nil level keeps every story.
    public static func shelf(level: String?) -> [ShelfStory] {
        guard let level else { return shelf }
        return shelf.filter { $0.level == level }
    }

    /// The shelf story that `book` is the library's copy of: a book saved by the app from the shelf, never an
    /// import or a download that happens to have the same title.
    public static func shelfStory(for book: Book) -> ShelfStory? {
        guard book.author == author, book.gutenbergID == nil else { return nil }
        return shelf.first { $0.title == book.title }
    }

    /// The library's copy of the bundled story titled `title`, if the learner still has it.
    public static func libraryCopy(of title: String, in books: [Book]) -> Book? {
        books.first { $0.title == title && $0.author == author && $0.gutenbergID == nil }
    }
}

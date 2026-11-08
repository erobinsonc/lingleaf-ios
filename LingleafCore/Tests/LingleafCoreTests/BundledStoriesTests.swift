import XCTest
@testable import LingleafCore

/// The stories shipped with the app (Lingleaf/Resources/Books): every text and every senses file is
/// read as the app reads it, and every entry is checked against its story's own text (SPEC S19).
final class BundledStoriesTests: XCTestCase {
    /// Lingleaf/Resources/Books, found from this file (the tests run from a checkout).
    private static let books: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Lingleaf/Resources/Books", isDirectory: true)

    private func text(_ story: ShelfStory) throws -> String {
        try String(contentsOf: Self.books.appendingPathComponent("\(story.resource).txt"), encoding: .utf8)
    }

    private func senses(_ story: ShelfStory) throws -> StorySenses {
        let data = try Data(contentsOf: Self.books.appendingPathComponent("\(story.resource).senses.json"))
        return try StorySenses.load(data, story: story.resource, paragraphs: TextTools.splitParagraphs(try text(story)))
    }

    func testEveryShelfStoryHasItsTextAndTheTextIsSound() throws {
        for story in BundledStory.shelf {
            let paragraphs = TextTools.splitParagraphs(try text(story))
            XCTAssertGreaterThan(paragraphs.count, 5, story.title)
            // Nothing was cut: no paragraph reaches the limit, and no markdown or title line is left in the text.
            XCTAssertTrue(paragraphs.allSatisfy { $0.utf16.count < TextTools.maxParagraph }, story.title)
            XCTAssertFalse(paragraphs.contains { $0.contains("*") || $0.hasPrefix("#") }, story.title)
            XCTAssertNotEqual(paragraphs.first, story.title, "the title comes from the shelf, not from the text")
            XCTAssertEqual(TextTools.cleanText(paragraphs.joined(separator: " ")), paragraphs.joined(separator: " "), story.title)
        }
    }

    func testEveryBundledSensesFileLoadsAgainstItsStory() throws {
        for story in BundledStory.shelf where story.hasSenses {
            let loaded = try senses(story)
            XCTAssertEqual(loaded.story, story.resource)
            XCTAssertGreaterThan(loaded.count, 10, "\(story.title): entries")
            // Every sense is used, and every entry's text is the word at its offsets (the loader checked it).
            let used = Set(loaded.places.map(\.hit.id))
            XCTAssertEqual(used.count, loaded.senses.count, "\(story.title): a sense nothing uses")
        }
    }

    func testTheShelfHoldsThreeStoriesAtEveryLevelWithSensesAndNoStrayFiles() throws {
        for level in ["A1", "A2", "B1", "B2", "C1", "C2"] {
            XCTAssertEqual(BundledStory.shelf(level: level).filter(\.hasSenses).count, 3, level)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.books.path)
        var expected: Set<String> = ["LICENSE"]
        for story in BundledStory.shelf {
            expected.insert("\(story.resource).txt")
            if story.hasSenses { expected.insert("\(story.resource).senses.json") }
        }
        XCTAssertEqual(Set(names), expected, "every file in Books is a shelf story's text or senses, or the license")
    }

    func testTheLicenseNamesEveryStory() throws {
        let license = try String(contentsOf: Self.books.appendingPathComponent("LICENSE"), encoding: .utf8)
        for story in BundledStory.shelf {
            XCTAssertTrue(license.contains("\(story.resource).txt"), "the license names \(story.resource).txt")
        }
        XCTAssertTrue(license.contains("CC0 1.0 Universal"))
        XCTAssertTrue(license.contains("AI"), "the license says the stories were written with AI help")
    }

    /// The senses the story gives for the well-known traps: a sense is not the word's most common gloss.
    func testTheSensesCatchTheFalseFriends() throws {
        let oven = try XCTUnwrap(BundledStory.shelf.first { $0.resource == "the-oven-next-door" })
        let loaded = try senses(oven)
        let free = try XCTUnwrap(loaded.places.first { $0.hit.sense.lemma == "free" }?.hit)
        XCTAssertTrue(free.sense.spanish.hasPrefix("libre"), "free here is \"libre\", not \"gratis\"")
        let red = try XCTUnwrap(loaded.places.first { $0.hit.sense.lemma == "go red" }?.hit)
        XCTAssertEqual(red.sense.kind, .chunk)
        XCTAssertEqual(red.group?.spanish, "se puso colorado")
        XCTAssertEqual(red.group?.text, "his face went red")
        let name = try XCTUnwrap(loaded.places.first { $0.hit.sense.lemma == "The Blue Table" }?.hit)
        XCTAssertEqual(name.sense.kind, .name)
    }

    /// Entries are on words of the story's own text; none points at a name's accent or at markup.
    func testEveryEntryIsOnAWholeWordOfTheParagraph() throws {
        for story in BundledStory.shelf where story.hasSenses {
            let paragraphs = TextTools.splitParagraphs(try text(story))
            for place in try senses(story).places {
                let paragraph = paragraphs[place.paragraph]
                let location = "\(story.title) \(place.paragraph):\(place.range.start)"
                XCTAssertTrue(TextTools.wordRanges(paragraph).contains(place.range), location)
            }
        }
    }

    /// A bare word that has another sense in its story, or a false-friend warning, carries an English gloss, so
    /// a language other than Spanish never gets the machine translation of the bare word (SPEC S19).
    func testBareWordsThatCouldBeMistranslatedHaveAnEnglishGloss() throws {
        for story in BundledStory.shelf where story.hasSenses {
            for place in try senses(story).places where place.hit.sense.kind == .word && place.hit.group == nil {
                let hit = place.hit
                if hit.siblings || hit.sense.spanish.contains("no \"") {
                    XCTAssertNotNil(hit.sense.english, "\(story.title): \(hit.id) needs an English gloss")
                }
            }
        }
    }

    /// The Spanish is Latin American: no word that only Spain uses (reviewed by the learning-content validator).
    func testTheSpanishHasNoPeninsularWords() throws {
        let spain: Set<String> = ["coger", "cogió", "cogí", "coged", "cojo", "móvil", "móviles", "ordenador", "coche", "zumo",
                                  "vosotros", "vale", "guay", "enfadado", "enfadada", "escayola", "neumático", "bañador",
                                  "rotulador", "moqueta", "cotilla", "nevera", "grifo", "aparcamiento", "gafas", "portátil",
                                  "empanadilla", "socorrista", "dimisión", "venid", "tío"]
        for story in BundledStory.shelf where story.hasSenses {
            for place in try senses(story).places {
                let texts = [place.hit.sense.spanish, place.hit.sense.note, place.hit.group?.spanish].compactMap { $0?.lowercased() }
                for text in texts {
                    let words = Set(text.split { !$0.isLetter }.map(String.init))
                    XCTAssertTrue(words.isDisjoint(with: spain), "\(story.title): \(text)")
                }
            }
        }
    }
}

import XCTest
@testable import LingleafCore

/// The senses file of a bundled story (SPEC S19): a valid one loads, and one that breaks any rule is
/// refused whole, at the first problem.
final class StorySensesTests: XCTestCase {
    private let story = "a-test-story"
    // "His face went red." is 0–18 ("went" 9–13), "Free" 19–23; "Mr. Long likes the cafe." has "Long" at 4–8.
    private let paragraphs = ["His face went red. Free food.", "Mr. Long likes the cafe."]

    /// A small valid file, edited by `edit` before it is encoded.
    private func file(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var json: [String: Any] = [
            "schemaVersion": 1,
            "story": story,
            "senses": [
                "go_red": ["lemma": "go red", "pos": "phrase", "ipa": "ɡoʊ rɛd", "es": "ponerse colorado", "kind": "chunk"],
                "free_available": [
                    "lemma": "free", "pos": "adjective", "ipa": "fri", "es": "libre, disponible", "kind": "word", "variety": "AmE",
                    "note": "Una nota.",
                ],
                "long_name": ["lemma": "Long", "pos": "proper noun", "ipa": NSNull(), "es": "nombre", "kind": "name"],
            ],
            "entries": [
                ["p": 0, "start": 9, "end": 13, "text": "went", "sense": "go_red",
                 "chunk": ["start": 0, "end": 17, "text": "His face went red", "es": "se puso colorado"]],
                ["p": 0, "start": 19, "end": 23, "text": "Free", "sense": "free_available"],
                ["p": 1, "start": 4, "end": 8, "text": "Long", "sense": "long_name"],
            ],
        ]
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func load(_ data: Data) throws -> StorySenses {
        try StorySenses.load(data, story: story, paragraphs: paragraphs)
    }

    /// Changes one sense's field.
    private func sense(_ key: String, _ field: String, _ value: Any?) throws -> Data {
        try file { json in
            var senses = json["senses"] as! [String: [String: Any]]
            senses[key]![field] = value
            json["senses"] = senses
        }
    }

    /// Changes the first matching entry's field (or the group's, with `inChunk`).
    private func entry(_ index: Int, _ field: String, _ value: Any?, inChunk: Bool = false) throws -> Data {
        try file { json in
            var entries = json["entries"] as! [[String: Any]]
            if inChunk {
                var chunk = entries[index]["chunk"] as! [String: Any]
                chunk[field] = value
                entries[index]["chunk"] = chunk
            } else {
                entries[index][field] = value
            }
            json["entries"] = entries
        }
    }

    private func assertRefused(_ data: Data, _ message: String, line: UInt = #line) {
        XCTAssertThrowsError(try load(data), message, line: line)
    }

    func testAValidFileLoads() throws {
        let senses = try load(try file())
        XCTAssertEqual(senses.story, story)
        XCTAssertEqual(senses.count, 3)
        XCTAssertEqual(senses.senses.count, 3)
        let went = try XCTUnwrap(senses.hit(paragraph: 0, range: WordRange(9, 13)))
        XCTAssertEqual(went.id, "go_red")
        XCTAssertEqual(went.sense.lemma, "go red")
        XCTAssertEqual(went.sense.spanish, "ponerse colorado")
        XCTAssertEqual(went.sense.kind, .chunk)
        XCTAssertEqual(went.group, StoryGroup(range: WordRange(0, 17), text: "His face went red", spanish: "se puso colorado"))
        let free = try XCTUnwrap(senses.hit(paragraph: 0, range: WordRange(19, 23)))
        XCTAssertEqual(free.sense.variety, .american)
        XCTAssertEqual(free.sense.note, "Una nota.")
        XCTAssertNil(free.group)
        XCTAssertEqual(free.sense.displayIPA, "/fri/")
        let name = try XCTUnwrap(senses.hit(paragraph: 1, range: WordRange(4, 8)))
        XCTAssertEqual(name.sense.kind, .name)
        XCTAssertNil(name.sense.ipa, "a null IPA is allowed")
        XCTAssertNil(name.sense.displayIPA)
        XCTAssertNil(senses.hit(paragraph: 0, range: WordRange(4, 8)), "a word with no entry")
        XCTAssertNil(senses.hit(paragraph: 0, range: WordRange(9, 12)), "only the entry's own range")
        XCTAssertNil(senses.hit(paragraph: 5, range: WordRange(9, 13)))
        XCTAssertEqual(senses.places.map(\.range.start), [9, 19, 4])
        XCTAssertEqual(senses.places.map(\.paragraph), [0, 0, 1])
    }

    func testWhatTheCardAsksOfASense() throws {
        let senses = try load(try file())
        let chunk = try XCTUnwrap(senses.senses["go_red"])
        let word = try XCTUnwrap(senses.senses["free_available"])
        let name = try XCTUnwrap(senses.senses["long_name"])
        XCTAssertEqual(word.definitionPartOfSpeech, "adjective")
        XCTAssertNil(chunk.definitionPartOfSpeech, "a group of words has no definition")
        XCTAssertNil(name.definitionPartOfSpeech, "a name has none")
        XCTAssertTrue(word.speaksIPA)
        XCTAssertFalse(chunk.speaksIPA, "a group is said as text")
        XCTAssertFalse(name.speaksIPA, "no IPA, no respelling")
        for (pos, expected) in [("noun", "noun"), ("modal", "verb"), ("phrasal verb", nil), ("proper noun", nil), ("suffix", nil)] {
            let made = StorySense(lemma: "x", partOfSpeech: pos, ipa: nil, spanish: "x", kind: .word, variety: nil, note: nil)
            XCTAssertEqual(made.definitionPartOfSpeech, expected, pos)
        }
        let foreign = StorySense(lemma: "san", partOfSpeech: "noun", ipa: "sɑn", spanish: "x", kind: .foreign, variety: .local, note: nil)
        XCTAssertNil(foreign.definitionPartOfSpeech, "a word from another language has none")
    }

    func testTheLabelAndWhatTheCardTranslates() throws {
        let senses = try load(try file())
        let went = try XCTUnwrap(senses.hit(paragraph: 0, range: WordRange(9, 13)))
        let free = try XCTUnwrap(senses.hit(paragraph: 0, range: WordRange(19, 23)))
        let name = try XCTUnwrap(senses.hit(paragraph: 1, range: WordRange(4, 8)))
        XCTAssertNil(went.label, "no variety, no label")
        XCTAssertEqual(free.label, .american)
        XCTAssertEqual(name.label, .name)
        XCTAssertEqual(went.translationSource, "His face went red", "the group, else the base form")
        XCTAssertEqual(free.translationSource, "free")
        XCTAssertNil(name.translationSource, "a name is not translated")
        let foreign = try XCTUnwrap(load(try sense("long_name", "kind", "foreign")).hit(paragraph: 1, range: WordRange(4, 8)))
        XCTAssertEqual(foreign.label, .foreign)
        XCTAssertNil(foreign.translationSource)
        let british = try XCTUnwrap(load(try sense("free_available", "variety", "BrE")).hit(paragraph: 0, range: WordRange(19, 23)))
        XCTAssertEqual(british.label, .british)
        let local = try XCTUnwrap(load(try sense("free_available", "variety", "local")).hit(paragraph: 0, range: WordRange(19, 23)))
        XCTAssertEqual(local.label, .local)
    }

    func testAFileOverTheLimitsIsRefused() {
        XCTAssertThrowsError(try load(Data(count: StorySenses.maxBytes + 1))) { XCTAssertEqual($0 as? StorySensesError, .tooLarge) }
        let deep = Data((String(repeating: "[", count: 9) + String(repeating: "]", count: 9)).utf8)
        XCTAssertThrowsError(try load(deep)) { XCTAssertEqual($0 as? StorySensesError, .tooDeep) }
        XCTAssertThrowsError(try load(Data("not json".utf8)))
        XCTAssertThrowsError(try load(Data("[]".utf8)))
    }

    func testTheFileIsStrictAboutKeysAndVersion() throws {
        assertRefused(try file { $0["schemaVersion"] = 2 }, "another schema version")
        assertRefused(try file { $0["schemaVersion"] = "1" }, "a version that is not a number")
        assertRefused(try file { $0["extra"] = 1 }, "an unknown key")
        assertRefused(try file { $0["entries"] = nil }, "a missing key")
        assertRefused(try sense("go_red", "extra", "x"), "an unknown sense key")
        assertRefused(try sense("go_red", "es", nil), "a missing sense key")
        assertRefused(try sense("go_red", "ipa", nil), "ipa is required, even if null")
        assertRefused(try entry(0, "extra", 1), "an unknown entry key")
        assertRefused(try entry(0, "extra", 1, inChunk: true), "an unknown group key")
        assertRefused(try entry(0, "text", nil), "a missing entry key")
        assertRefused(try entry(0, "p", "0"), "a paragraph that is not a number")
        let other = try StorySenses.load(try file(), story: story, paragraphs: paragraphs)
        XCTAssertEqual(other.story, story)
        XCTAssertThrowsError(try StorySenses.load(try file(), story: "another-story", paragraphs: paragraphs), "a file of another story")
    }

    func testTheStoryAndSenseKeysAreIdentifiers() throws {
        for id in ["Bad-Story", "two--dashes", "-lead", "trail-", "under_score", "", "é"] {
            XCTAssertThrowsError(try StorySenses.load(try file { $0["story"] = id }, story: id, paragraphs: paragraphs), id)
        }
        let renamed = try file { json in
            var senses = json["senses"] as! [String: Any]
            senses["Bad Key"] = senses.removeValue(forKey: "go_red")
            json["senses"] = senses
        }
        assertRefused(renamed, "a sense key outside a–z, 0–9 and _")
        let long = String(repeating: "a", count: 41)
        assertRefused(try file { json in
            var senses = json["senses"] as! [String: Any]
            senses[long] = senses.removeValue(forKey: "go_red")
            json["senses"] = senses
        }, "a sense key over 40 characters")
    }

    func testASenseWithATextOutsideItsRulesIsRefused() throws {
        assertRefused(try sense("go_red", "lemma", ""), "empty lemma")
        assertRefused(try sense("go_red", "lemma", "é"), "a lemma with an accent")
        assertRefused(try sense("go_red", "lemma", " go"), "a lemma that starts with a space")
        assertRefused(try sense("go_red", "lemma", "go.red"), "a lemma with a full stop")
        assertRefused(try sense("go_red", "lemma", String(repeating: "a", count: 61)), "a lemma over 60 characters")
        assertRefused(try sense("go_red", "pos", "article"), "an unknown part of speech")
        assertRefused(try sense("go_red", "ipa", "ɡoʊ/rɛd"), "a slash in the IPA")
        assertRefused(try sense("go_red", "ipa", "x!"), "a character outside the IPA letters")
        assertRefused(try sense("go_red", "ipa", String(repeating: "a", count: 81)), "an IPA over 80 characters")
        assertRefused(try sense("go_red", "ipa", "e\u{0301}"), "a combining accent in the IPA")
        assertRefused(try sense("go_red", "es", ""), "empty meaning")
        assertRefused(try sense("go_red", "es", " ponerse"), "a meaning with a space around it")
        assertRefused(try sense("go_red", "es", "poner\u{202E}se"), "a bidi override in the meaning")
        assertRefused(try sense("go_red", "es", "poner\nse"), "a line break in the meaning")
        assertRefused(try sense("go_red", "es", String(repeating: "a", count: 141)), "a meaning over 140 characters")
        assertRefused(try sense("go_red", "kind", "idiom"), "an unknown kind")
        assertRefused(try sense("go_red", "variety", "AusE"), "an unknown variety")
        assertRefused(try sense("go_red", "note", ""), "an empty note")
        assertRefused(try sense("go_red", "note", "x\u{200B}"), "a zero-width character in the note")
        assertRefused(try sense("go_red", "note", String(repeating: "a", count: 201)), "a note over 200 characters")
        assertRefused(try sense("go_red", "note", "x "), "a note with a space around it")
        assertRefused(try sense("go_red", "lemma", 3), "a lemma that is not text")
    }

    func testAnEntryThatIsNotTheWordAtItsOffsetsIsRefused() throws {
        assertRefused(try entry(0, "p", 2), "a paragraph the story doesn't have")
        assertRefused(try entry(0, "p", 1000), "a paragraph number over 999")
        assertRefused(try entry(0, "p", -1), "a negative paragraph")
        assertRefused(try entry(0, "start", 10), "the middle of a word")
        assertRefused(try entry(0, "end", 12), "an end inside a word")
        assertRefused(try entry(0, "start", 13), "an empty range")
        assertRefused(try entry(0, "end", 2001), "a range past the limit")
        assertRefused(try entry(0, "start", -1), "a negative start")
        assertRefused(try entry(0, "text", "wend"), "a text that is not the word")
        assertRefused(try entry(0, "text", String(repeating: "w", count: 41)), "a text over 40 characters")
        assertRefused(try entry(0, "sense", "missing"), "an unknown sense")
        assertRefused(try file { json in
            var entries = json["entries"] as! [[String: Any]]
            entries.append(entries[0])
            json["entries"] = entries
        }, "two entries for one word")
    }

    func testAGroupMustBeWholeWordsHoldingTheEntrysWord() throws {
        assertRefused(try entry(0, "start", 1, inChunk: true), "a group that starts inside a word")
        assertRefused(try entry(0, "end", 16, inChunk: true), "a group that ends inside a word")
        assertRefused(try entry(0, "start", 14, inChunk: true), "a group that starts after the word")
        assertRefused(try entry(0, "end", 8, inChunk: true), "a group that ends before the word")
        assertRefused(try entry(0, "end", 2001, inChunk: true), "a group past the limit")
        assertRefused(try entry(0, "start", 17, inChunk: true), "an empty group")
        assertRefused(try entry(0, "text", "His face went blue", inChunk: true), "a group text that is not the text")
        assertRefused(try entry(0, "es", " se puso", inChunk: true), "a group meaning with a space around it")
        assertRefused(try entry(0, "es", "", inChunk: true), "an empty group meaning")
        let tooLong = String(repeating: "word ", count: 30) + "end"
        let longParagraph = tooLong + " went."
        XCTAssertThrowsError(try StorySenses.load(try file { json in
            json["entries"] = [
                ["p": 0, "start": 0, "end": 4, "text": "word", "sense": "go_red",
                 "chunk": ["start": 0, "end": tooLong.count, "text": tooLong, "es": "x"]],
            ]
        }, story: story, paragraphs: [longParagraph]), "a group over 120 characters")
    }

    func testTooManySensesOrEntriesAreRefused() throws {
        assertRefused(try file { json in
            var senses = json["senses"] as! [String: Any]
            for n in 0..<StorySenses.maxSenses { senses["s\(n)"] = senses["go_red"] }
            json["senses"] = senses
        }, "over 2000 senses")
        assertRefused(try file { json in
            let entries = json["entries"] as! [[String: Any]]
            json["entries"] = (0...StorySenses.maxEntries).map { _ in entries[1] }
        }, "over 5000 entries")
        XCTAssertThrowsError(try StorySenses.load(try file(), story: story, paragraphs: Array(repeating: "A.", count: 1001)),
                             "over 1000 paragraphs")
    }
}

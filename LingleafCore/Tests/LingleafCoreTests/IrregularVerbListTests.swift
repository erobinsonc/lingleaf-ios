import XCTest
@testable import LingleafCore

/// The irregular-verb list (SPEC.md S24, Grammar rules data, "Verb search" and "Speech"): the order, the search
/// and the text the voice says.
final class IrregularVerbListTests: XCTestCase {
    private let table = IrregularVerbs.shared

    private func verb(_ base: String) throws -> IrregularVerb { try XCTUnwrap(table.verb(base: base), base) }
    private func search(_ query: String) -> [String] { IrregularVerbSearch.search(query, in: table).map(\.base) }

    // MARK: Order

    func testTheListIsTheGroupsInOrderMostUsedFirstThenByBase() {
        let sections = IrregularVerbOrder.sections(table)
        XCTAssertEqual(sections.map(\.group.id), table.groups.map(\.id).filter { id in table.verbs.contains { $0.group == id } })
        XCTAssertEqual(IrregularVerbOrder.ordered(table).count, table.verbs.count, "every verb once")
        XCTAssertEqual(Set(IrregularVerbOrder.ordered(table).map(\.base)), Set(table.verbs.map(\.base)))
        for section in sections {
            XCTAssertTrue(section.verbs.allSatisfy { $0.group == section.group.id })
            for (lhs, rhs) in zip(section.verbs, section.verbs.dropFirst()) {
                XCTAssertGreaterThanOrEqual(lhs.freq ?? 0, rhs.freq ?? 0, "\(lhs.base) before \(rhs.base)")
                if (lhs.freq ?? 0) == (rhs.freq ?? 0) { XCTAssertLessThan(lhs.base, rhs.base) }
            }
        }
    }

    func testAVerbWithoutFrequencyCountsAsZeroAndTiesGoByCodePoint() throws {
        XCTAssertTrue(table.verbs.contains { $0.freq == nil }, "the table has verbs without freq (sow, dive)")
        let sow = try verb("sow")
        let frequent = try verb("take")
        XCTAssertTrue(IrregularVerbOrder.before(frequent, sow))
        XCTAssertFalse(IrregularVerbOrder.before(sow, frequent))
        let group = IrregularVerbOrder.sections(table).first { $0.group.id == sow.group }
        let ordered = try XCTUnwrap(group).verbs.map(\.base)
        let noFreq = ordered.filter { table.verb(base: $0)?.freq == nil }
        XCTAssertEqual(noFreq, noFreq.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) })
        XCTAssertEqual(ordered.suffix(noFreq.count).map { $0 }, noFreq, "they come last in their group")
    }

    // MARK: Search vectors

    func testTheSearchVectorsOfTheSpecOnTheBundledTable() {
        XCTAssertEqual(search("took"), ["take"])
        XCTAssertEqual(search("TAKEN"), ["take"])
        XCTAssertEqual(search("learnt"), ["learn"])
        XCTAssertEqual(search("got"), ["get"])
        XCTAssertEqual(search("tomar"), ["take", "drink", "catch"])
        XCTAssertEqual(search("tom"), ["catch", "take", "drink"])
        XCTAssertEqual(search("go"), ["go", "get", "hit", "strike", "beat", "smite"])
        XCTAssertEqual(search("ir"), ["go", "burst", "leave", "speed"])
        XCTAssertEqual(search("acost"), ["lie"])
        XCTAssertEqual(search("mentir"), ["lie"])
        XCTAssertEqual(search("lied"), ["lie"])
        XCTAssertEqual(search("ahorcar"), ["hang"])
        XCTAssertEqual(search("encontrarse"), ["meet", "lie"])
        XCTAssertEqual(search("encontrarse (un lugar)"), ["lie"])
        XCTAssertEqual(search("un lugar"), ["lie"])
        XCTAssertEqual(search(""), [])
        XCTAssertEqual(search("zzz"), [])
    }

    func testTheSearchIgnoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(search("  Took  "), ["take"])
        XCTAssertEqual(search("TOMÁR"), search("tomar"))
        XCTAssertEqual(search("took!"), ["take"])
        XCTAssertEqual(search("took2"), ["take"], "digits split")
        XCTAssertEqual(search("!!!"), [])
        XCTAssertEqual(search("   "), [])
        XCTAssertTrue(search("took tomar").contains("take"), "every word must match: form and meaning")
        XCTAssertEqual(search("took zzz"), [], "a word that matches nothing excludes the verb")
    }

    func testARankIsTheWorstOfTheWordsAndTheWholeMeaningRuleOnlyImproves3() throws {
        let take = try verb("take"), lie = try verb("lie"), go = try verb("go")
        XCTAssertEqual(IrregularVerbSearch.rank(take, words: ["took"]), 0)
        XCTAssertEqual(IrregularVerbSearch.rank(take, words: ["tak"]), 1)
        XCTAssertEqual(IrregularVerbSearch.rank(take, words: ["tom"]), 3, "a prefix of a meaning word")
        XCTAssertEqual(IrregularVerbSearch.rank(take, words: ["tomar"]), 2, "the whole query is a whole meaning entry")
        XCTAssertEqual(IrregularVerbSearch.rank(take, words: ["took", "tom"]), 3, "the worst of its words")
        XCTAssertEqual(IrregularVerbSearch.rank(take, words: ["tak", "took"]), 1)
        XCTAssertEqual(IrregularVerbSearch.rank(go, words: ["ir"]), 2)
        XCTAssertEqual(IrregularVerbSearch.rank(lie, words: ["encontrarse", "un", "lugar"]), 2)
        XCTAssertNil(IrregularVerbSearch.rank(take, words: ["zzz"]))
        // The whole-query rule never worsens a rank 0 or 1: "go" is a form word of go and a prefix of "got".
        XCTAssertEqual(IrregularVerbSearch.rank(go, words: ["go"]), 0)
    }

    func testTheNounOfAHomonymDoesNotCount() {
        XCTAssertEqual(search("mentira"), [], "`nounEs` of lie: a noun, not a meaning of the verb")
        XCTAssertFalse(search("estar").isEmpty)
    }

    func testOnlyTheFirstHundredCodePointsOfAQueryAreUsed() {
        let beyond = "\u{1D400}"
        XCTAssertEqual(search("in" + String(repeating: " ", count: 97) + beyond), [], "the 100th code point is a letter and is used")
        XCTAssertEqual(search("in" + String(repeating: " ", count: 98) + beyond), search("in"), "the 101st is cut")
        XCTAssertFalse(search("in").isEmpty)
        XCTAssertEqual(search(String(repeating: "x", count: 1_000_000)), [], "a huge query is bounded")
    }

    func testTheFormsAndMeaningsAWordIsFoundBy() throws {
        let lie = try verb("lie")
        let forms = IrregularVerbSearch.formWords(lie)
        XCTAssertTrue(forms.isSuperset(of: ["lie", "lay", "lain", "lying", "lies", "lied"]), "the homonym's forms too")
        let entries = IrregularVerbSearch.meaningEntries(lie)
        XCTAssertTrue(entries.contains(["encontrarse", "un", "lugar"]), "punctuation and parentheses dropped")
        XCTAssertTrue(entries.contains(["mentir"]))
        XCTAssertTrue(entries.contains(["estar", "acostado"]))
        let hang = try verb("hang")
        XCTAssertTrue(IrregularVerbSearch.formWords(hang).contains("hanged"))
    }

    // MARK: Speech

    private func said(_ base: String, _ slot: VerbSlot, _ index: Int = 0) throws -> String? {
        GrammarSpeech.verbForm(try verb(base), slot: slot, index: index)?.text
    }

    func testTheFormsAVoiceSaysFollowTheTablesRespelling() throws {
        XCTAssertEqual(try said("read", .past), "red")
        XCTAssertEqual(try said("read", .base), "read")
        XCTAssertEqual(try said("tear", .base), "tare")
        XCTAssertEqual(try said("wind", .base), "wined")
        XCTAssertEqual(try said("wind", .past), "wownd")
        XCTAssertEqual(try said("sow", .base), "so")
        XCTAssertEqual(try said("dive", .past, 0), "dohv")
        XCTAssertEqual(try said("dive", .past, 1), "dived")
        XCTAssertNil(try said("dive", .past, 2))
        XCTAssertNil(try said("take", .base, 1))
        XCTAssertNil(try said("take", .base, -1))
    }

    func testTheThreeFormsAreSaidWithAPauseBetweenThem() throws {
        XCTAssertEqual(GrammarSpeech.verbForms(try verb("take")).text, "take. took. taken.")
        XCTAssertEqual(GrammarSpeech.verbForms(try verb("read")).text, "read. red. red.")
        XCTAssertEqual(GrammarSpeech.verbForms(try verb("learn")).text, "learn. learned. learned.", "index 0 of a slot with two forms")
    }

    func testSpeechIsAlwaysEnglish() throws {
        XCTAssertEqual(GrammarSpeech.verbForms(try verb("take")).language, "en")
        XCTAssertEqual(GrammarSpeech.verbForm(try verb("take"), slot: .ing)?.language, "en")
        XCTAssertEqual(GrammarSpeech.example("I take the bus."), SpokenText(text: "I take the bus.", language: "en"))
        for slot in VerbSlot.allCases { XCTAssertFalse(GrammarSpeech.forms(of: try verb("take"), slot: slot).isEmpty) }
        XCTAssertEqual(GrammarSpeech.forms(of: try verb("learn"), slot: .past), ["learned", "learnt"])
        XCTAssertEqual(try said("take", .s), "takes")
        XCTAssertEqual(try said("take", .ing), "taking")
        XCTAssertEqual(try said("tear", .s), "tares", "the table's respelling for the -s form")
    }
}

/// The lines of a verb row.
final class IrregularVerbLineTests: XCTestCase {
    private func verb(_ base: String) throws -> IrregularVerb { try XCTUnwrap(IrregularVerbs.shared.verb(base: base), base) }

    func testARowShowsEveryFormOfEachSlot() throws {
        XCTAssertEqual(IrregularVerbLine.forms(try verb("take")), "take · took · taken")
        XCTAssertEqual(IrregularVerbLine.forms(try verb("learn")), "learn · learned / learnt · learned / learnt")
        XCTAssertEqual(IrregularVerbLine.forms(try verb("dive")), "dive · dove / dived · dived")
        XCTAssertEqual(IrregularVerbLine.forms(try verb("read")), "read · read · read")
    }

    func testTheMeaningsAreTheTablesAndTheHintIsHavePlusTheParticiple() throws {
        XCTAssertEqual(IrregularVerbLine.meanings(try verb("take")), "tomar, llevar; tardar")
        XCTAssertEqual(IrregularVerbLine.meanings(try verb("go")), "ir; irse")
        XCTAssertEqual(IrregularVerbLine.participleHint(try verb("take")), "have taken")
        XCTAssertEqual(IrregularVerbLine.participleHint(try verb("sow")), "have sown")
        for verb in IrregularVerbs.shared.verbs {
            XCTAssertFalse(IrregularVerbLine.forms(verb).isEmpty)
            XCTAssertFalse(IrregularVerbLine.meanings(verb).isEmpty, verb.base)
        }
    }
}

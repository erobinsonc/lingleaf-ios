import XCTest
@testable import LingleafCore

/// The cue rule of lie and hang (SPEC.md, Verb sentences data): a cue of its own sense where the form is the same in both
/// senses (positions 1, 2, 3, 6, 10), never a cue of the other sense anywhere.
final class VerbSentencesCueTests: VerbSentencesLintCase {
    func testTheSpecsExamplesPassTheNoContradictionCheckAndTheCueRule() {
        clean("lie", [f.sentence("didnt", "lie", "She didn't lie to me.", sense: 1, context: true)])
        clean("lie", [f.sentence("advice", "lie", "You should never lie to her.", sense: 1, context: true)])
        clean("lie", [f.sentence("advice", "lie", "You should lie down for an hour.", context: true)])
        clean("hang", [f.sentence("didnt", "hang", "They didn't hang the thief.", sense: 1, context: true)])
        clean("hang", [f.sentence("habit", "hang", "I hang my coat here every day.", context: true)])
    }

    // MARK: Where a cue is required

    func testOnlyTheFormsThatAreTheSameInBothSensesNeedACue() {
        // Positions 4, 5, 7, 8, 9: the form proves the sense (lied, hanged; lay, lain, hung).
        clean("hang", [f.sentence("past", "hanged", "Yesterday they hanged him.", sense: 1)])
        clean("hang", [f.sentence("past", "hanged", "Yesterday they hanged her.", sense: 1)])
        clean("hang", [f.sentence("past", "hung", "Yesterday I hung it there.")])
        clean("lie", [f.sentence("past", "lay", "Yesterday I lay awake.")])
        clean("lie", [f.sentence("past", "lied", "Yesterday he lied.", sense: 1)])
        clean("lie", [f.sentence("perfect", "lain", "The dog has lain here since noon.")])
        // Positions 1, 2, 3, 6, 10: the form is the same, so a cue is required.
        refused("hang", [f.sentence("habit", "hang", "I hang it here every day.", context: true)], "cue-sense")
        refused("lie", [f.sentence("third", "lies", "She lies a lot at six.")], "cue-sense")
        refused("hang", [f.sentence("advice", "hang", "You should hang it.")], "cue-sense")
        refused("lie", [f.sentence("didnt", "lie", "We didn't lie.", sense: 1)], "cue-sense")
    }

    func testTheOtherSensesCueIsRefusedEvenWhereTheFormProvesTheSense() {
        refused("hang", [f.sentence("past", "hung", "Yesterday she hung the thief.")], "cue-sense")
        refused("hang", [f.sentence("past", "hanged", "Yesterday they hanged the coat.", sense: 1)], "cue-sense")
        refused("lie", [f.sentence("past", "lay", "Yesterday I lay to him down.")], "cue-sense")
        refused("lie", [f.sentence("past", "lied", "Yesterday he lied down.", sense: 1)], "cue-sense")
    }

    // MARK: lie, sense 1: a person deceived

    func testLieToOrAboutAnyoneIsSenseOne() {
        let yes: [[String]] = [
            ["past", "lied", "Yesterday she lied about it."], ["past", "lied", "Yesterday she lied about her age."],
            ["past", "lied", "Yesterday he lied to the police."], ["advice", "lie", "You should not lie to your doctor."],
            ["perfectq", "lied", "Have you ever lied to a friend?"], ["past", "lied", "Yesterday he lied to me on Monday."],
            ["past", "lied", "Yesterday he lied to me in May."], ["habit", "lie", "Why do you still lie to me?"],
            ["past", "lied", "Yesterday he lied to me in school."], ["past", "lied", "Yesterday she lied to anyone."],
            ["past", "lied", "Yesterday she lied to someone."], ["past", "lied", "Yesterday he lied to people."],
            ["past", "lied", "Yesterday he lied to the kids."], ["past", "lied", "Yesterday he lied to her mum."],
            ["past", "lied", "Yesterday he lied to each other."], ["past", "lied", "Yesterday he lied to Tom."],
            ["past", "lied", "Yesterday he lied to a man."], ["past", "lied", "Yesterday he lied through his teeth."],
        ]
        for item in yes {
            let context = item[0] == "habit" || item[0] == "advice"
            clean("lie", [f.sentence(item[0], item[1], item[2], sense: 1, context: context)])
        }
    }

    func testLieToADirectionOrLyingAboutIsNotSenseOne() {
        refused("lie", [f.sentence("advice", "lie", "You should lie to the north.", sense: 1, context: true)], "cue-sense")
        for direction in ["north", "south", "east", "west", "left", "right", "end", "top"] {
            let view = SentenceView("The road lies to the \(direction) of town.")
            XCTAssertFalse(VerbSentencesLint.cues(view, base: "lie")!.sense1, direction)
        }
        // "lying about" can be things lying about: a cue of neither sense.
        let lying = VerbSentencesLint.cues(SentenceView("He is lying about the room."), base: "lie")!
        XCTAssertFalse(lying.sense1)
        XCTAssertFalse(lying.sense0)
        XCTAssertTrue(VerbSentencesLint.cues(SentenceView("She lies about her age."), base: "lie")!.sense1)
        XCTAssertFalse(VerbSentencesLint.cues(SentenceView("She lied to"), base: "lie")!.sense1, "nothing after to")
        XCTAssertFalse(VerbSentencesLint.cues(SentenceView("She lied."), base: "lie")!.sense1)
    }

    // MARK: lie, sense 0: a place right after the verb

    func testAPlaceCueCountsOnlyRightAfterTheVerb() {
        clean("lie", [f.sentence("habit", "lie", "I lie quietly on the bed every day.", context: true)])
        clean("lie", [f.sentence("habit", "lie", "I lie awake every night.", context: true)])
        clean("lie", [f.sentence("advice", "lie", "You should lie down for an hour.", context: true)])
        // Two words after the verb at most; a farther or earlier place word is no cue.
        let far = VerbSentencesLint.cues(SentenceView("I lie all day on the bed."), base: "lie")!
        XCTAssertFalse(far.sense0)
        XCTAssertFalse(VerbSentencesLint.cues(SentenceView("Down there I lie."), base: "lie")!.sense0)
        XCTAssertFalse(VerbSentencesLint.cues(SentenceView("I still lie."), base: "lie")!.sense0, "still before the verb is not a cue")
        XCTAssertTrue(VerbSentencesLint.cues(SentenceView("I lie still."), base: "lie")!.sense0)
        refused("lie", [f.sentence("habit", "lie", "I lie a lot every day.", context: true)], "cue-sense")
        // Both cues: the explicit one is not cancelled by a distant place, an adjacent place is a conflict.
        refused("lie", [f.sentence("advice", "lie", "You should lie down to him.", sense: 1, context: true)], "cue-sense")
    }

    // MARK: hang

    func testHangThingsAndParticlesAreSenseZeroAndExecutedPeopleSenseOne() {
        for thing in VerbSentencesLint.hangThingWords {
            clean("hang", [f.sentence("habit", "hang", "I hang the \(thing) every day.", context: true)])
        }
        for person in VerbSentencesLint.hangExecutedWords {
            clean("hang", [f.sentence("didnt", "hang", "They didn't hang the \(person).", sense: 1, context: true)])
        }
        for particle in ["up", "out", "on", "around", "upside", "from", "over"] {
            XCTAssertTrue(VerbSentencesLint.cues(SentenceView("I hang \(particle) it."), base: "hang")!.sense0, particle)
        }
        let late = VerbSentencesLint.cues(SentenceView("I hang it up."), base: "hang")!
        XCTAssertFalse(late.sense0, "a particle counts right after the verb")
        // hanged him, her, them.
        for object in ["him", "her", "them"] {
            XCTAssertTrue(VerbSentencesLint.cues(SentenceView("They hanged \(object)."), base: "hang")!.sense1, object)
        }
        XCTAssertFalse(VerbSentencesLint.cues(SentenceView("They hung him."), base: "hang")!.sense1, "only after hanged")
    }

    /// "thief's" is one word: the apostrophe stays in it, so it is not the executed person "thief".
    func testAnApostropheNameTokenIsNotTheExecutedPerson() {
        clean("hang", [f.sentence("past", "hung", "Yesterday she hung the thief's coat.")])
        XCTAssertEqual(SentenceView("She hung the thief's coat.").tokens, ["she", "hung", "the", "thief's", "coat"])
    }

    func testNoReflexiveAfterHang() {
        for reflexive in ["himself", "herself", "themselves", "myself", "yourself"] {
            let found = codes("hang", [f.sentence("past", "hanged", "Yesterday she hanged \(reflexive).", sense: 1)])
            XCTAssertTrue(found.contains("hang-reflexive"), reflexive)
        }
        XCTAssertFalse(codes("hang", [f.sentence("past", "hanged", "Yesterday they hanged him.", sense: 1)]).contains("hang-reflexive"))
    }

    // MARK: One source of truth

    func testTheCueListsCoherWithTheTableAndTheSpec() throws {
        let table = IrregularVerbs.shared
        let lie = try XCTUnwrap(table.verb(base: "lie")?.homonym)
        let hang = try XCTUnwrap(table.verb(base: "hang")?.homonym)
        XCTAssertEqual(VerbSentencesLint.liePlaces, lie.verbBefore)
        XCTAssertEqual(VerbSentencesLint.lieDeceivesBefore, lie.homonymBefore)
        XCTAssertEqual(VerbSentencesLint.hangParticles, hang.verbBefore)
        XCTAssertEqual(VerbSentencesLint.hangReflexives, hang.homonymBefore)
        XCTAssertEqual(lie.homonymBefore, ["to", "about", "through"], "the sense-1 particles the SPEC names")
        XCTAssertTrue(["down", "on", "in", "awake", "flat", "here", "there", "still"].allSatisfy(lie.verbBefore.contains))
        XCTAssertTrue(["up", "out", "on", "around", "upside", "from", "over"].allSatisfy(hang.verbBefore.contains))
        // The senses do not share a cue.
        XCTAssertTrue(VerbSentencesLint.liePlaces.isDisjoint(with: VerbSentencesLint.lieDeceivesBefore))
        XCTAssertTrue(VerbSentencesLint.hangThings.isDisjoint(with: VerbSentencesLint.hangExecuted))
        XCTAssertTrue(VerbSentencesLint.hangExecuted.isDisjoint(with: ["man", "men"]), "man can read as a painting or a figure")
        // Every closed-list word is in the SPEC, which is the contract.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../SPEC.md")
        let spec = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(spec.range(of: "Cue rule for a verb with a homonym"))
        let end = try XCTUnwrap(spec.range(of: "- Bold-form rule", range: start.upperBound..<spec.endIndex))
        let text = String(spec[start.lowerBound..<end.lowerBound])
        let words = VerbSentencesLint.hangThingWords + VerbSentencesLint.hangExecutedWords + Array(VerbSentencesLint.lieDirections)
        for word in words + Array(VerbSentencesLint.hangedObjects) { XCTAssertTrue(text.contains(word), word) }
    }

    func testThePluralOfACueWord() {
        XCTAssertEqual(VerbSentencesLint.plural("thief"), "thieves")
        XCTAssertEqual(VerbSentencesLint.plural("spy"), "spies")
        XCTAssertEqual(VerbSentencesLint.plural("witch"), "witches")
        XCTAssertEqual(VerbSentencesLint.plural("dress"), "dresses")
        XCTAssertEqual(VerbSentencesLint.plural("bag"), "bags")
        XCTAssertEqual(VerbSentencesLint.plural("key"), "keys", "a vowel before y")
        XCTAssertTrue(VerbSentencesLint.hangExecuted.isSuperset(of: ["thieves", "spies", "witches", "pirates", "slaves"]))
    }

    func testTheCueListsOfOtherVerbsAreEmpty() {
        XCTAssertNil(VerbSentencesLint.cues(SentenceView("I take it."), base: "take"))
        clean("take", [f.sentence("habit", "take", "I take the bus every day.", context: true)])
        let none = try? XCTUnwrap(VerbSentencesLint.cues(SentenceView("A sentence with no form."), base: "hang"))
        XCTAssertEqual(none?.sense0, false)
        XCTAssertEqual(none?.sense1, false)
    }
}

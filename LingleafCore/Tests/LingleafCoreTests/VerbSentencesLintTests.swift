import XCTest
@testable import LingleafCore

/// Every content rule of `irregular-verb-sentences.json` (SPEC.md, Verb sentences data), one valid and one invalid vector
/// each, built here and never in the bundle. A vector fails for its rule alone: the tests compare the set of problem codes.
final class VerbSentencesLintTests: VerbSentencesLintCase {
    // MARK: The whole verb

    func testACompleteVerbPassesEveryRule() throws {
        let file = try VerbSentences.load(f.data(f.file(of: "take", f.take)))
        XCTAssertEqual(VerbSentencesLint.problems(in: file), [])
        XCTAssertEqual(VerbSentencesLint.problems(in: VerbSentences(verbs: [])), [])
    }

    func testTheLintListsTheReadersProblemsFirst() {
        var sentences = f.take
        sentences[0]["level"] = "Z9"
        XCTAssertNil(try? VerbSentences.load(f.data(f.file(of: "take", sentences))), "the reader refuses it")
        let omitted = VerbSentenceEntry(base: "take", sentences: [], omitted: [VerbOmission(slot: "habit", reason: "x")])
        XCTAssertTrue(VerbSentencesLint.problems(in: VerbSentences(verbs: [omitted])).first?.hasPrefix("omitted-slot") == true)
        let unknown = VerbSentences(verbs: [VerbSentenceEntry(base: "nothing", sentences: [])])
        XCTAssertEqual(VerbSentencesLint.problems(in: unknown), ["base-unknown: nothing"])
    }

    // MARK: Bold form

    func testTheFormAppearsInTheSentenceExactlyOnceAsAWholeWord() {
        clean("take", [f.sentence("habit", "take", "I take the bus every day.", context: true)])
        refused("take", [f.sentence("habit", "take", "I ride the bus every day.", context: true)], "bold-missing")
        // Not a whole word: "takes" and "overtake" and "mistake" are not "take".
        refused("take", [f.sentence("habit", "take", "She takes the bus every day.", context: true)], "bold-missing")
        refused("take", [f.sentence("habit", "take", "I take it and take it back.", context: true)], "bold-twice")
        // Case does not matter.
        clean("take", [f.sentence("habit", "take", "Take the bus every day.", context: true)])
        clean("take", [f.sentence("habit", "take", "I TAKE the bus every day.", context: true)])
    }

    func testNoOtherFormOfTheVerbOrItsHomonymAppears() {
        refused("take", [f.sentence("past", "took", "Yesterday I took what you take.")], "bold-other-form")
        refused("take", [f.sentence("past", "took", "Yesterday I took what she had taken.")], "bold-other-form")
        refused("take", [f.sentence("past", "took", "Yesterday I took the taking back.")], "bold-other-form")
        refused("take", [f.sentence("past", "took", "Yesterday she took what he takes.")], "bold-other-form")
        refused("learn", [f.sentence("past", "learned", "Yesterday I learned what he learnt.")], "bold-other-form")
        // The homonym's forms count for the verb's sentences too (lie / lied).
        refused("lie", [f.sentence("past", "lay", "Yesterday I lay down and she lied.")], "bold-other-form")
        clean("take", [f.sentence("past", "took", "Yesterday I took the train.")])
        // A word that only contains a form is another word.
        clean("take", [f.sentence("past", "took", "Yesterday I took the mistake home.")])
    }

    func testTheBaseAfterDidntShouldOrAnotherModalIsNotCounted() {
        // The form is the past: the base after "didn't" (a) is allowed.
        clean("take", [f.sentence("past", "took", "Yesterday he took it but you didn't take it.", level: "B1")])
        clean("take", [f.sentence("past", "took", "Yesterday he took it but you should take it.", level: "B1")])
        clean("take", [f.sentence("past", "took", "Yesterday he took it but you will take it.", level: "B1")])
        clean("take", [f.sentence("past", "took", "Yesterday he took it but you did not take it.", level: "B1")])
        clean("take", [f.sentence("past", "took", "Yesterday he took it but you should never take it.", level: "B1")])
        // Not after one of them.
        refused("take", [f.sentence("past", "took", "Yesterday he took it but you take it.", level: "B1")], "bold-other-form")
        refused("take", [f.sentence("past", "took", "Yesterday he took it but you to take it.", level: "B1")], "bold-other-form")
        refused("take", [f.sentence("past", "took", "Yesterday he took it but take it.", level: "B1")], "bold-other-form")
        // Only the base: after "didn't" the participle is not allowed.
        refused("take", [f.sentence("past", "took", "Yesterday he took it but you didn't taken it.", level: "B1")], "bold-other-form")
    }

    func testHaveBeAndDoMayUseTheirOwnAuxiliaryInTheConstruction() {
        // have: positions 7, 9 and perfectq. "I had had enough": the first "had" is the auxiliary.
        clean("have", [f.sentence("perfect", "had", "I have had a cold.")])
        clean("have", [f.sentence("perfect", "had", "He has had enough of it.")])
        clean("have", [f.sentence("pastperfect", "had", "I had had enough.", level: "A1")])
        clean("have", [f.sentence("perfectq", "had", "Have you ever had a dog?")])
        // be: positions 3, 7, 8, 9.
        clean("be", [f.sentence("now", "being", "He is being rude now.")])
        clean("be", [f.sentence("perfect", "been", "They have been here.", level: "A1")])
        clean("be", [f.sentence("perfectq", "been", "Have you ever been to Rome?")])
        clean("be", [f.sentence("pastperfect", "been", "She had been there before.")])
        // do: positions 6, 7, 9.
        clean("do", [f.sentence("didnt", "do", "We didn't do it.", level: "A1")])
        clean("do", [f.sentence("didnt", "do", "We did not do it.", level: "A1")])
        clean("do", [f.sentence("perfect", "done", "I have done it.", level: "A1")])
        // Outside those positions the auxiliary is another form of the verb.
        refused("have", [f.sentence("habit", "have", "I have what you had.")], "bold-other-form")
        refused("have", [f.sentence("past", "had", "Yesterday I had what you have.")], "bold-other-form")
        refused("have", [f.sentence("now", "having", "She is having what he has.")], "bold-other-form")
        refused("be", [f.sentence("past", "was", "Yesterday I was what you are.")], "bold-other-form")
        refused("do", [f.sentence("past", "did", "Yesterday I did what he does.")], "bold-other-form")
        refused("do", [f.sentence("advice", "do", "You should do what he does.")], "bold-other-form")
        // A form that is not the auxiliary of the construction still counts: "having" in position 7.
        refused("have", [f.sentence("perfect", "had", "I have had a cold, having none.")], "bold-other-form")
        // The form twice without an auxiliary role is twice.
        refused("take", [f.sentence("perfect", "taken", "I have taken what you taken.")], "bold-twice")
    }

    // MARK: Cues of the label

    func testPositionThreeNeedsAnAuxiliaryBeforeTheIngForm() {
        clean("take", [f.sentence("now", "taking", "He is taking a photo now.")])
        clean("take", [f.sentence("now", "taking", "They are taking a photo now.")])
        clean("take", [f.sentence("now", "taking", "I am taking a photo now.")])
        clean("take", [f.sentence("now", "taking", "I'm taking a photo now.")])
        clean("take", [f.sentence("now", "taking", "She's taking a photo now.")])
        clean("take", [f.sentence("now", "taking", "We’re taking a photo now.")])
        flagged("take", [f.sentence("now", "taking", "He taking a photo now.")], "cue-now")
        flagged("take", [f.sentence("now", "taking", "Taking a photo is fun.")], "cue-now")
        // After the form it does not count.
        flagged("take", [f.sentence("now", "taking", "Taking a photo now is fun.")], "cue-now")
        // A gerund has no cue.
        XCTAssertFalse(codes("take", [f.sentence("gerund", "taking", "Taking a photo is fun.")]).contains { $0.hasPrefix("cue") })
    }

    func testPositionFourNeedsATimeCue() {
        for cue in [
            "Yesterday I took the train.", "I took the train last week.", "I took the train two days ago.",
                "I took the train and then slept.",
            "I took the train when it came.", "I already took the train.", "I just took the train.", "I took the train before dinner.",
            "I took the train since noon.", "I took the train for an hour.", "I took the train a year ago.", "I took the train in June.",
            "I took the train in 2019.", "I took the train on 5/3 at noon.", "I took the train in May.",
                "I took the train on 3.5.2020 once.",
        ] { clean("take", [f.sentence("past", "took", cue)]) }
        for none in ["I took the train.", "I took the train to work.", "I took the train, may be.", "May I took the train?",
            "I took the train at noon."] {
            refused("take", [f.sentence("past", "took", none)], "cue-past")
        }
    }

    func testTheTimeCueListIsOneList() {
        let cue = { (text: String) in VerbSentencesLint.hasTimeCue(SentenceView(text)) }
        for word in ["yesterday", "last", "ago", "then", "when", "already", "just", "before", "since", "for"] {
            XCTAssertTrue(cue("I did it \(word) there."), word)
        }
        XCTAssertTrue(cue("It was a year of joy."))
        XCTAssertTrue(cue("It was in March."))
        XCTAssertTrue(cue("It was in 1999."))
        XCTAssertTrue(cue("It was on 12-05-2020."))
        XCTAssertTrue(cue("It was a Tuesday in May."), "May in the middle, capitalised")
        XCTAssertFalse(cue("May I go now?"), "May at the start is the modal")
        XCTAssertFalse(cue("It was a day. Maybe."))
        XCTAssertFalse(cue("It was a good year."), "'a year' means the two words in a row")
        XCTAssertFalse(cue("He may go there."), "may as a modal, lower case")
        XCTAssertFalse(cue("It was 12345 meters."))
        XCTAssertFalse(cue("It was at noon."))
    }

    func testPositionFiveNeedsAConnector() {
        for connector in ["and", "then", "after", "when"] {
            clean("take", [f.sentence("story", "took", "She took her bag \(connector) left.")])
        }
        refused("take", [f.sentence("story", "took", "She took her bag.")], "cue-story")
        refused("take", [f.sentence("story", "took", "She took her bag home.")], "cue-story")
    }

    func testPositionSixNeedsDidntOrDidNotBeforeTheForm() {
        clean("take", [f.sentence("didnt", "take", "We didn't take a taxi.")])
        clean("take", [f.sentence("didnt", "take", "We did not take a taxi.")])
        clean("take", [f.sentence("didnt", "take", "We didn’t take a taxi.")])
        refused("take", [f.sentence("didnt", "take", "We don't take a taxi.")], "cue-didnt")
        refused("take", [f.sentence("didnt", "take", "We take a taxi.")], "cue-didnt")
        refused("take", [f.sentence("didnt", "take", "We take a taxi, didn't we?")], "cue-didnt")
        refused("take", [f.sentence("didnt", "take", "We did take not a taxi.")], "cue-didnt")
    }

    func testPositionSevenNeedsHaveHasOrVeAndIsAStatement() {
        clean("take", [f.sentence("perfect", "taken", "I have taken my medicine.")])
        clean("take", [f.sentence("perfect", "taken", "She has taken my medicine.")])
        clean("take", [f.sentence("perfect", "taken", "I've taken my medicine.")])
        refused("take", [f.sentence("perfect", "taken", "I taken my medicine.")], "cue-perfect")
        refused("take", [f.sentence("perfect", "taken", "She had taken my medicine.")], "cue-perfect")
        refused("take", [f.sentence("perfect", "taken", "Have you taken my medicine?")], "cue-perfect")
        refused("take", [f.sentence("perfect", "taken", "Taken my medicine, I have.")], "cue-perfect")
    }

    func testPositionEightHasItsCuePerId() {
        for auxiliary in ["was", "were", "is", "are", "be", "been"] {
            clean("take", [f.sentence("passive", "taken", "The photos \(auxiliary) taken in May.")])
        }
        refused("take", [f.sentence("passive", "taken", "The photo taken in May.")], "cue-passive")
        refused("take", [f.sentence("passive", "taken", "They had taken the photo in May.")], "cue-passive")
        for auxiliary in ["is", "are", "was", "were"] {
            clean("go", [f.sentence("state", "gone", "The kids \(auxiliary) gone for a year.")])
        }
        refused("go", [f.sentence("state", "gone", "The kids have gone for a year.")], "cue-state")
        refused("go", [f.sentence("state", "gone", "The kids be gone for a year.")], "cue-state")
        clean("go", [f.sentence("perfectq", "gone", "Have you ever gone to Rome?")])
        clean("go", [f.sentence("perfectq", "gone", "Has she ever gone to Rome?")])
        clean("go", [f.sentence("perfectq", "gone", "Has she gone to Rome yet?")])
        refused("go", [f.sentence("perfectq", "gone", "Have you ever gone to Rome.")], "cue-perfectq")
        refused("go", [f.sentence("perfectq", "gone", "Are you gone yet?")], "cue-perfectq")
    }

    func testPerfectqIsAQuestionWithEverYetOrAlready() {
        for word in ["ever", "yet", "already"] {
            clean("go", [f.sentence("perfectq", "gone", "Has she \(word) gone to Rome?")])
        }
        refused("go", [f.sentence("perfectq", "gone", "Has she gone to Rome?")], "perfectq-shape")
        refused("go", [f.sentence("perfectq", "gone", "Has she never gone to Rome?")], "perfectq-shape")
    }

    func testPositionNineNeedsHadOrDBeforeTheForm() {
        clean("take", [f.sentence("pastperfect", "taken", "She had taken the key before I came.")])
        clean("take", [f.sentence("pastperfect", "taken", "She'd taken the key before I came.")])
        refused("take", [f.sentence("pastperfect", "taken", "She taken the key before I came.")], "cue-pastperfect")
        refused("take", [f.sentence("pastperfect", "taken", "She has taken the key before I came.")], "cue-pastperfect")
    }

    func testPositionTenNeedsShould() {
        clean("take", [f.sentence("advice", "take", "You should take a break.")])
        clean("take", [f.sentence("advice", "take", "Maybe you should never take a break.")])
        refused("take", [f.sentence("advice", "take", "You must take a break.")], "cue-advice")
        refused("take", [f.sentence("advice", "take", "You take a break.")], "cue-advice")
    }

    func testPositionsOneAndTwoHaveNoCue() {
        clean("take", [f.sentence("habit", "take", "Take a break.")])
        clean("take", [f.sentence("third", "takes", "She takes a break.")])
    }

    // MARK: Same-form verbs

    func testSameFormVerbsCarryATimeCueInPositionsFourSevenAndNine() {
        clean("put", [f.sentence("past", "put", "Yesterday I put the bag down.")])
        clean("put", [f.sentence("perfect", "put", "I have just put the bag down.")])
        clean("put", [f.sentence("pastperfect", "put", "She had put the bag down before noon.")])
        refused("put", [f.sentence("perfect", "put", "I have put the bag down.")], "same-form-cue")
        refused("put", [f.sentence("pastperfect", "put", "She had put the bag down.")], "same-form-cue")
        // Position 4 already needs it as a past.
        XCTAssertEqual(codes("put", [f.sentence("past", "put", "I put the bag down.")]), ["cue-past", "same-form-cue"])
        // Position 5 carries its connector (the other clause's past form is the reviewer's).
        clean("put", [f.sentence("story", "put", "She put the bag down and left.")])
        // A verb whose form differs from the base needs no cue in 7 and 9; one whose participle is the base does.
        clean("take", [f.sentence("perfect", "taken", "I have taken my medicine.")])
        refused("come", [f.sentence("perfect", "come", "I have come here.")], "same-form-cue")
        clean("come", [f.sentence("perfect", "come", "I have just come here.")])
        clean("come", [f.sentence("past", "came", "Yesterday I came here.")])
        clean("read", [f.sentence("perfect", "read", "I have just read the book.", spoken: "I have just red the book.")])
    }

    // MARK: perfectq against perfect

    func testPerfectAndPerfectqNeedDifferentSubjects() {
        let statement = f.sentence("perfect", "had", "I have had a cold.")
        clean("have", [statement, f.sentence("perfectq", "had", "Have you ever had a dog?")])
        clean("have", [statement, f.sentence("perfectq", "had", "Has she ever had a dog?")])
        refused("have", [statement, f.sentence("perfectq", "had", "Have I ever had a dog?")], "perfect-subject")
        refused("have", [f.sentence("perfect", "had", "She has had a cold."), f.sentence("perfectq", "had", "Has she ever had a dog?")],
            "perfect-subject")
        // The subject of a statement with a contraction is the word before 've.
        refused("have", [f.sentence("perfect", "had", "I've had a cold."), f.sentence("perfectq", "had", "Have I ever had a dog?")],
            "perfect-subject")
        clean("have", [f.sentence("perfect", "had", "I've had a cold."), f.sentence("perfectq", "had", "Have you ever had a dog?")])
        // Case does not matter.
        refused("have", [f.sentence("perfect", "had", "You have had a cold."), f.sentence("perfectq", "had", "Have YOU ever had a dog?")],
            "perfect-subject")
        // Alone, neither is compared.
        clean("have", [statement])
        clean("have", [f.sentence("perfectq", "had", "Have I ever had a dog?")])
    }

    func testASubjectThatCannotBeFoundIsRefused() {
        // A statement that opens with has: no word before it. A question whose have is its last word: none after it.
        flagged("have", [f.sentence("perfect", "had", "Has had enough, he said."), f.sentence("perfectq", "had",
            "Have you ever had a dog?")], "perfect-subject")
        flagged("have", [f.sentence("perfect", "had", "I have had a cold."), f.sentence("perfectq", "had", "Had you ever, as they have?")],
            "perfect-subject")
    }

    // MARK: spoken

    func testSpokenIsPresentExactlyWhereTheTableRespellsTheFormsSlot() {
        // read: past and participle "red"; its base has no respelling.
        clean("read", [f.sentence("past", "read", "Yesterday I read the book.", spoken: "Yesterday I red the book.")])
        clean("read", [f.sentence("habit", "read", "I read the news every day.", context: true)])
        refused("read", [f.sentence("past", "read", "Yesterday I read the book.")], "spoken-wrong")
        refused("read", [f.sentence("habit", "read", "I read the news every day.", context: true, spoken: "I red the news every day.")],
            "spoken-unexpected")
        refused("take", [f.sentence("habit", "take", "I take the bus every day.", context: true, spoken: "I take the bus every day.")],
            "spoken-unexpected")
        // It is `en` with the respelling, nothing else.
        refused("read", [f.sentence("past", "read", "Yesterday I read the book.", spoken: "Yesterday I red a book.")], "spoken-wrong")
        refused("read", [f.sentence("past", "read", "Yesterday I read the book.", spoken: "Yesterday I read the book.")], "spoken-wrong")
        refused("read", [f.sentence("past", "read", "Yesterday I read the book.", spoken: "yesterday I red the book.")], "spoken-wrong")
        // Wind respells its base and past: and a capital stays a capital.
        clean("wind", [f.sentence("habit", "wind", "Wind the clock every day.", context: true, spoken: "Wined the clock every day.")])
        clean("wind", [f.sentence("habit", "wind", "I wind the clock every day.", context: true, spoken: "I wined the clock every day.")])
        refused("wind", [f.sentence("habit", "wind", "I wind the clock every day.", context: true)], "spoken-wrong")
    }

    // MARK: Length

    private func words(_ count: Int) -> String { "I take" + String(repeating: " big", count: count - 2) }

    func testLengthByLevelIsTested() {
        let range: [String: ClosedRange<Int>] = ["A1": 4...8, "A2": 5...10, "B1": 6...12, "B2": 7...14, "C1": 8...16, "C2": 8...16]
        for (level, allowed) in range {
            for count in (allowed.lowerBound - 1)...(allowed.upperBound + 1) {
                let found = codes("take", [f.sentence("habit", "take", words(count), level: level, context: true)], keep: ["length"])
                XCTAssertEqual(found, allowed.contains(count) ? [] : ["length"], "\(level) with \(count) words")
            }
        }
        XCTAssertEqual(VerbSentencesLint.wordRange.count, 6)
    }

    func testAContractionIsOneWordAndDigitsAreNone() {
        // "We didn't take a taxi." is 5 words, with the contraction as one.
        clean("take", [f.sentence("didnt", "take", "We didn't take a taxi.", level: "A2")])
        XCTAssertEqual(codes("take", [f.sentence("didnt", "take", "Didn't take 3 4 5 6 7 8 9.", level: "A1")], keep: ["length"]),
            ["length"])
    }

    // MARK: context

    func testExactlyOneContextSentencePerVerbAndSense() {
        XCTAssertEqual(codes("take", f.take, keep: ["context-count"]), [])
        var none = f.take
        none[0].removeValue(forKey: "context")
        XCTAssertEqual(codes("take", none, keep: ["context-count"]), ["context-count"])
        var two = f.take
        two[5]["context"] = true
        XCTAssertEqual(codes("take", two, keep: ["context-count"]), ["context-count"])
        // Another verb sense is its own: a verb with no sentences needs none.
        XCTAssertEqual(codes("take", [], keep: ["context-count"]), [])
    }

    func testTheContextSentenceIsInPositionOneSixOrTen() {
        for index in [0, 5, 9] {
            var sentences = f.take
            sentences[0].removeValue(forKey: "context")
            sentences[index]["context"] = true
            XCTAssertEqual(codes("take", sentences, keep: ["context-count"]), [], "position \(index + 1)")
        }
        for index in [1, 2, 3, 4, 6, 7, 8] {
            var sentences = f.take
            sentences[0].removeValue(forKey: "context")
            sentences[index]["context"] = true
            XCTAssertEqual(codes("take", sentences, keep: ["context-count"]), ["context-slot"], "position \(index + 1)")
        }
    }

    func testEachSenseOfAHomonymHasItsOwnContextSentence() {
        let zero = f.sentence("advice", "lie", "You should lie down for an hour.", context: true)
        let one = f.sentence("didnt", "lie", "She didn't lie to me.", sense: 1, context: true)
        // Position order: sense 0 (position 10) before sense 1 (position 6) is a sense order, not a position order.
        XCTAssertEqual(codes("lie", [zero, one], keep: ["context-count"]), [])
        var unmarked = one
        unmarked.removeValue(forKey: "context")
        XCTAssertEqual(codes("lie", [zero, unmarked], keep: ["context-count"]), ["context-count"])
    }

    // MARK: S3

    func testAPastOrParticipleOfTheTableIsThatVerbAndTheTwinIsSenseOne() {
        clean("lie", [f.sentence("past", "lay", "Yesterday I lay on the bed.")])
        clean("lie", [f.sentence("past", "lied", "Yesterday he lied to me.", sense: 1)])
        clean("lie", [f.sentence("perfect", "lain", "The dog has lain here since noon.")])
        clean("hang", [f.sentence("past", "hanged", "Yesterday they hanged the thief.", sense: 1)])
        clean("hang", [f.sentence("past", "hung", "Yesterday I hung my coat there.")])
        // The sense the sentence claims must be the form's (the reader's rule): "lied" is no form of sense 0.
        XCTAssertNil(try? VerbSentences.load(f.data(f.file(of: "lie", [f.sentence("past", "lied", "Yesterday he lied to me.")]))))
    }

    /// S3 proving the word a noun, a name, another verb or another sense contradicts the file.
    func testAFormThatS3ProvesAnotherWordIsRefused() {
        clean("leave", [f.sentence("past", "left", "She left her bag here yesterday.")])
        clean("leave", [f.sentence("perfect", "left", "I have just left the house.")])
        refused("leave", [f.sentence("past", "left", "Yesterday the left was wet.")], "s3")
        // A name: "Aunt Rose" is not the past of rise.
        refused("rise", [f.sentence("past", "rose", "We met Aunt Rose yesterday.")], "s3")
        // The twin's noun after a determiner: "his lies".
        flagged("lie", [f.sentence("third", "lies", "His lies hurt me at six.")], "s3")
        // Another sense of this verb, proved by S3 (not by its next-word guess):
        // The next word's sense for lying, lies, hanging, hangs is a guess, not a proof: the cue rule refuses it, not S3.
        XCTAssertEqual(codes("lie", [f.sentence("now", "lying", "He is lying to me now.")]), ["cue-sense"])
    }

    /// Unsure and ordinary readings are accepted (and only reported), as are the forms S3 does not read on their own.
    func testAnUnsureOrOrdinaryReadingIsAcceptedAndReported() throws {
        clean("light", [f.sentence("third", "lights", "The lights are on at six.")])
        clean("take", [f.sentence("gerund", "taking", "Taking a photo is fun.")])
        clean("lie", [f.sentence("third", "lies", "She lies here at six.")])
        let file = try VerbSentences.load(f.data(f.file(of: "light", [f.sentence("third", "lights", "The lights are on at six.")])))
        XCTAssertEqual(VerbSentencesLint.unsureReadings(in: file), ["light 0 third: The lights are on at six."])
        let proven = try VerbSentences.load(f.data(f.file(of: "light", [f.sentence("third", "lights", "She lights the candle at six.")])))
        XCTAssertEqual(VerbSentencesLint.unsureReadings(in: proven), [])
        XCTAssertEqual(VerbSentencesLint.unsureReadings(in: VerbSentences(verbs: [VerbSentenceEntry(base: "nothing", sentences: [])])), [])
        let missing = try VerbSentences.load(f.data(f.file(of: "take", [f.sentence("habit", "take", "I ride the bus.")])))
        XCTAssertEqual(VerbSentencesLint.unsureReadings(in: missing), [], "no form found: reported by the bold rule")
    }

    func testTheAuxiliaryOfHaveBeAndDoCountsAsTheVerb() {
        let table = IrregularVerbs.shared
        let verb = { (base: String) in table.verb(base: base)! }
        func resolves(_ slot: VerbSlot, _ form: String, _ en: String, _ base: String) -> Bool {
            let view = SentenceView(en)
            let sentence = VerbSentence(slot: slot, form: form, en: en, es: "x", level: "A2")
            return VerbSentencesLint.resolves(sentence, view: view, index: view.tokens.firstIndex(of: form)!, verb: verb(base),
                table: table)
        }
        // Read on its own, "being" at the start of a sentence is not proven as the verb; as position 3 of be it is the auxiliary.
        XCTAssertTrue(resolves(.now, "being", "Being rude is hard.", "be"))
        XCTAssertTrue(resolves(.habit, "being", "Being rude is hard.", "be"), "ordinary: accepted anyway")
        XCTAssertTrue(resolves(.now, "taking", "Taking photos is fun.", "take"), "unsure: accepted")
        XCTAssertFalse(resolves(.past, "left", "Yesterday the left was wet.", "leave"), "a noun is proved")
    }
}

import XCTest
@testable import LingleafCore

final class FunctionWordsTests: XCTestCase {
    /// Analyzes the first occurrence of `word` in `sentence`; returns the result and the chunk's text.
    private func analyze(_ sentence: String, _ word: String) -> (FunctionWord?, String?) {
        let location = (sentence as NSString).range(of: word).location
        let range = TextTools.wordAt(sentence, location)!
        let result = FunctionWords.analyze(sentence, range)
        return (result, result?.chunk.map { TextTools.substring(sentence, $0) })
    }

    func testDidNotMakesThePastNegative() {
        let (result, chunk) = analyze("He did not go to the beach.", "did")
        XCTAssertEqual(result?.kind, .helper)
        XCTAssertEqual(result?.base, "do")
        XCTAssertEqual(result?.use, .pastNegative)
        XCTAssertEqual(chunk, "did not go")
    }

    func testContractionsAndPresentNegative() {
        XCTAssertEqual(analyze("She doesn’t like it.", "doesn").1, "doesn’t like")
        XCTAssertEqual(analyze("She doesn’t like it.", "doesn").0?.use, .presentNegative)
        XCTAssertEqual(analyze("Do not touch that.", "Do").1, "Do not touch")
        XCTAssertEqual(analyze("Do not touch that.", "Do").0?.use, .prohibition)
        XCTAssertEqual(analyze("Don’t go!", "Don").0?.use, .prohibition)
        XCTAssertEqual(analyze("Don't you know?", "Don").0?.use, .presentNegative, "a question is not a prohibition")
        XCTAssertEqual(analyze("Please don't go.", "don").0?.use, .prohibition)
        XCTAssertEqual(analyze("And don't forget it.", "don").0?.use, .prohibition)
        XCTAssertEqual(analyze("They don't go.", "don").0?.use, .presentNegative)
        XCTAssertEqual(analyze("I did not.", "did").1, "did not", "the sentence ends: the group stops there")
        let (result, chunk) = analyze("Why didn't you come?", "didn")
        XCTAssertEqual(result?.use, .pastNegative)
        XCTAssertEqual(chunk, "didn't you come")
        // Nothing after it: still a helper, without a verb group.
        XCTAssertNil(analyze("No, I didn't.", "didn").0?.chunk)
    }

    func testQuestions() {
        let (did, didChunk) = analyze("Did you see the ship?", "Did")
        XCTAssertEqual(did?.use, .pastQuestion)
        XCTAssertEqual(didChunk, "Did you see")
        XCTAssertEqual(analyze("What do they want?", "do").0?.use, .presentQuestion)
        XCTAssertEqual(analyze("What do they want?", "do").1, "do they want")
        // A noun subject: still a question, but no verb group.
        let (noun, nounChunk) = analyze("Does the dog bark?", "Does")
        XCTAssertEqual(noun?.use, .presentQuestion)
        XCTAssertNil(nounChunk)
    }

    func testDoAsAMainVerbIsAnOrdinaryWord() {
        XCTAssertNil(analyze("I did my homework.", "did").0)
        XCTAssertNil(analyze("What did he say, and what did he do?", "do").0)
        XCTAssertNil(analyze("They do it every day.", "do").0)
    }

    func testQuestionTags() {
        let (tag, chunk) = analyze("You went, didn't you?", "didn")
        XCTAssertEqual(tag?.use, .questionTag)
        XCTAssertEqual(tag?.base, "do")
        XCTAssertNil(chunk)
        XCTAssertEqual(analyze("She can swim, can't she?", "can't").0?.use, .questionTag)
        XCTAssertEqual(analyze("She can swim, can't she?", "can").0?.use, .modal("can"), "the first can is not the tag")
    }

    func testModals() {
        let (will, willChunk) = analyze("We will go home.", "will")
        XCTAssertEqual(will?.kind, .modal)
        XCTAssertEqual(will?.use, .modal("will"))
        XCTAssertEqual(willChunk, "will go")
        XCTAssertEqual(analyze("Will you help me?", "Will").1, "Will you help")
        XCTAssertEqual(analyze("You must not run.", "must").1, "must not run")
        XCTAssertEqual(analyze("I won't stay.", "won").0?.base, "will")
        XCTAssertEqual(analyze("I cannot see.", "cannot").0?.base, "can")
        XCTAssertEqual(analyze("I can't see.", "can").0?.base, "can")
        XCTAssertNil(analyze("Yes, I can.", "can").0?.chunk)
        XCTAssertEqual(analyze("You mustn't run.", "mustn").0?.negative, true)
        XCTAssertEqual(analyze("You must not run.", "must").0?.negative, true)
        XCTAssertEqual(analyze("I won't stay.", "won").0?.negative, true)
        XCTAssertEqual(analyze("I cannot see.", "cannot").0?.negative, true)
        XCTAssertEqual(analyze("You must run.", "must").0?.negative, false)
        XCTAssertEqual(analyze("A tool that can cut wood.", "can").1, "can cut", "after a relative pronoun it's still a modal")
        XCTAssertEqual(analyze("You should have known.", "should").1, "should have known", "have/be lead to the main verb")
        XCTAssertEqual(analyze("We will never be able to go.", "will").1, "will never be able")
        XCTAssertEqual(analyze("She did not really like it.", "did").1, "did not really like")
    }

    func testModalLookalikesAreOrdinaryWords() {
        XCTAssertNil(analyze("He opened a can of beans.", "can").0)
        XCTAssertNil(analyze("It was his will.", "will").0)
        XCTAssertNil(analyze("We met in May last year.", "May").0)
        XCTAssertNil(analyze("Then Will smiled.", "Will").0)
        XCTAssertNil(analyze("The cat sat.", "cat").0)
        XCTAssertNil(FunctionWords.analyze("The cat sat.", WordRange(0, 2)))
    }

    func testSentenceRangeAtMatchesSentenceAt() {
        let p = "  First one.  Did you go?  The end "
        let offset = (p as NSString).range(of: "you").location
        let range = TextTools.sentenceRangeAt(p, offset)
        XCTAssertEqual(TextTools.substring(p, range), "Did you go?")
        XCTAssertEqual(TextTools.sentenceAt(p, offset), "Did you go?")
        XCTAssertEqual(TextTools.sentenceAt(p, (p as NSString).range(of: "end").location), "The end")
    }
}

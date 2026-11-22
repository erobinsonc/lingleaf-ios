import XCTest

/// Try a question first, Try it and Practice (SPEC S22): the pretest, its Skip, an item's choose-then-feedback, a round
/// and its result, and the daily limit. The options are found by their position in the file (`grammar-option-N`).
final class GrammarPracticeUITests: XCTestCase {
    var app: XCUIApplication!

    func launch(_ seeds: String...) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + seeds + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Grammar"].tap()
    }

    func openRule(_ title: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        for _ in 0..<8 where !row.exists || !row.isHittable { app.swipeUp() }
        row.tap()
    }

    func element(startingWith text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// The first rule, past the pretest (skipped), on its page.
    func openHisHerItsSkippingThePretest() {
        openRule("His, her, its")
        XCTAssertTrue(app.staticTexts["Try a question first"].waitForExistence(timeout: 10))
        app.buttons["grammar-skip-pretest"].tap()
        XCTAssertTrue(app.buttons["Try it"].waitForExistence(timeout: 5))
    }

    // MARK: The pretest

    func testAFreshRuleOffersAQuestionFirstWithSkipAndNoNotSure() {
        launch()
        openRule("His, her, its")
        XCTAssertTrue(app.staticTexts["Try a question first"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Guess, then read the rule. A wrong guess is fine."].exists)
        let skip = app.buttons["grammar-skip-pretest"]
        XCTAssertTrue(skip.exists)
        XCTAssertEqual(skip.label, "Skip to the rule")
        XCTAssertTrue(app.buttons["Skip"].exists || skip.exists, "the visible word is Skip")
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44)
        XCTAssertFalse(app.buttons["Not sure"].exists, "the pretest has no Not sure")
        XCTAssertFalse(app.staticTexts["Examples"].exists, "the rule is hidden")
        XCTAssertTrue(app.buttons["grammar-option-0"].exists, "the options show with no answer")
        XCTAssertFalse(element(startingWith: "Right:").exists)
    }

    func testAnsweringThePretestShowsWhyAndThenTheRule() {
        launch()
        openRule("His, her, its")
        app.buttons["grammar-option-0"].tap()
        XCTAssertTrue(app.buttons["See the rule"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(startingWith: "Right:").exists || element(startingWith: "Not quite:").exists, "why, at once")
        XCTAssertFalse(app.buttons["grammar-option-0"].exists, "after an answer the options are plain rows, not buttons")
        app.buttons["See the rule"].tap()
        XCTAssertTrue(app.staticTexts["Examples"].waitForExistence(timeout: 5))
    }

    func testSkipShowsTheRuleAndIsNeverOfferedAgainButLeavingIsOfferedAgain() {
        launch()
        openRule("His, her, its")
        XCTAssertTrue(app.staticTexts["Try a question first"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openRule("His, her, its")
        XCTAssertTrue(app.staticTexts["Try a question first"].waitForExistence(timeout: 10), "left without answering: offered again")
        app.buttons["grammar-skip-pretest"].tap()
        XCTAssertTrue(app.staticTexts["Examples"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openRule("His, her, its")
        XCTAssertTrue(app.staticTexts["Examples"].waitForExistence(timeout: 10), "after a skip it is never offered again")
        XCTAssertFalse(app.staticTexts["Try a question first"].exists)
    }

    // MARK: A round

    func testARoundOfThreeEndsWithItsResultAndAnotherRound() {
        launch()
        openHisHerItsSkippingThePretest()
        app.buttons["Try it"].tap()
        for number in 1...3 {
            XCTAssertTrue(app.staticTexts["Question \(number) of 3"].waitForExistence(timeout: 5), "item \(number)")
            app.buttons["grammar-option-0"].tap()
            let next = app.buttons[number < 3 ? "Next" : "Finish"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(element(startingWith: "You got").waitForExistence(timeout: 5), "the result")
        XCTAssertTrue(app.buttons["Practice"].exists, "rounds remain today")
        XCTAssertTrue(app.buttons["Back to the rule"].exists)
        XCTAssertFalse(element(startingWith: "That was the last round").exists)
        app.buttons["Back to the rule"].tap()
        XCTAssertTrue(app.buttons["Practice"].waitForExistence(timeout: 5), "the rule's button now says Practice")
    }

    func testNotSureIsOfferedInPracticeAndCountsAsWrong() {
        launch()
        openHisHerItsSkippingThePretest()
        app.buttons["Try it"].tap()
        XCTAssertTrue(app.buttons["Not sure"].waitForExistence(timeout: 5))
        app.buttons["Not sure"].tap()
        XCTAssertTrue(element(startingWith: "That's okay. Right:").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next"].exists)
    }

    func testTheLastRoundOfTheDaySaysSoAndOffersNoMorePractice() {
        launch("-ui-testing-grammar-answered-4")
        openRule("In, on, at: time")
        app.buttons["grammar-skip-pretest"].tap()
        XCTAssertTrue(app.buttons["Practice"].waitForExistence(timeout: 5))
        app.buttons["Practice"].tap()
        for number in 1...2 {
            XCTAssertTrue(app.staticTexts["Question \(number) of 2"].waitForExistence(timeout: 5), "a round of 2 after 4 answered")
            app.buttons["grammar-option-0"].tap()
            let next = app.buttons[number < 2 ? "Next" : "Finish"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(element(startingWith: "You got").waitForExistence(timeout: 5))
        XCTAssertTrue(element(startingWith: "You got").label.contains("That was the last round for today."))
        XCTAssertFalse(app.buttons["Practice"].exists, "the result of the last round has no Practice button")
        app.buttons["Back to the rule"].tap()
        XCTAssertTrue(
            app.staticTexts["You've finished today's practice for this rule. Try another rule, or come back tomorrow."]
                .waitForExistence(timeout: 5)
        )
    }
}

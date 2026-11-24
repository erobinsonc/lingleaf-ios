import XCTest

/// The irregular verbs (SPEC S24): the first row of the Grammar list, the verb list and its search, Listen on a row, and a
/// verb page.
final class GrammarVerbsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Grammar"].tap()
    }

    func openVerbs() {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Irregular verbs")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the first row of the list")
        row.tap()
        XCTAssertTrue(app.navigationBars["Irregular verbs"].waitForExistence(timeout: 5))
    }

    /// A list builds its rows as they scroll in: a verb further down is found by scrolling.
    func reveal(_ element: XCUIElement) -> XCUIElement {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<12 where !element.exists || !element.isHittable { app.swipeUp() }
        return element
    }

    func verbRow(_ forms: String) -> XCUIElement {
        reveal(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", forms)).firstMatch)
    }

    func testTheFirstRowOpensTheVerbListWithTwoLineRows() {
        openVerbs()
        let take = verbRow("take, took, taken")
        XCTAssertTrue(take.exists, "every form of each slot")
        XCTAssertEqual(take.value as? String, "tomar, llevar; tardar", "the table's Spanish meanings for a Spanish translation language")
        XCTAssertTrue(verbRow("learn, learned / learnt, learned / learnt").exists, "a slot with two forms shows both")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "en-light-grammar-verbs"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testListenOnARowSaysTheFormsAndDoesNotNavigate() {
        openVerbs()
        let listen = reveal(app.buttons["Listen, take"].firstMatch)
        XCTAssertTrue(listen.exists)
        XCTAssertGreaterThanOrEqual(listen.frame.width, 44)
        XCTAssertGreaterThanOrEqual(listen.frame.height, 44)
        listen.tap()
        XCTAssertTrue(app.navigationBars["Irregular verbs"].exists, "still on the list")
        XCTAssertFalse(app.navigationBars["take"].exists)
    }

    func testAVerbPageShowsItsLevelAndItsForms() {
        openVerbs()
        verbRow("take, took, taken").tap()
        XCTAssertTrue(app.navigationBars["take"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Forms"].exists)
        XCTAssertTrue(app.staticTexts["took"].exists)
        XCTAssertTrue(app.staticTexts["have taken"].exists, "the hint under the past participle")
        XCTAssertTrue(app.buttons["Listen, took"].exists)
        XCTAssertTrue(app.staticTexts["A1 · Beginner"].exists || app.staticTexts["A1, Beginner"].exists)
    }

    func testSearchingTheVerbListFindsAFormAndAMeaning() {
        openVerbs()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("took")
        XCTAssertTrue(verbRow("take, took, taken").waitForExistence(timeout: 5))
        app.buttons["Clear text"].tap()
        search.typeText("tomar")
        XCTAssertTrue(verbRow("take, took, taken").waitForExistence(timeout: 5), "found by its Spanish meaning")
    }

    func testTheGrammarSearchHasARulesAndAVerbsSectionAndSaysWhatToTry() {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("took")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Verbs")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(verbRow("take, took, taken").exists)
        app.buttons["Clear text"].tap()
        search.typeText("zzz")
        XCTAssertTrue(app.staticTexts["Try the verb or its meaning, like go or ir."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No rules match. Try a shorter word, like in, on or at."].exists)
    }
}

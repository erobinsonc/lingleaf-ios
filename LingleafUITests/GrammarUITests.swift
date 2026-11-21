import XCTest

/// The Grammar tab (SPEC S20): the list, "Recent" and search. Rules and practice are bundled, so
/// nothing here depends on the network; progress comes from launch arguments (`GrammarSeeds`) in a fresh folder.
/// The default test setup has a Spanish translation language and an English interface, so the rule text starts in
/// Spanish ("Español" selected), as the SPEC's vector says.
final class GrammarUITests: XCTestCase {
    var app: XCUIApplication!

    /// Launches with the seeds, opens the Grammar tab.
    func launch(_ seeds: String..., language: String = "en") {
        continueAfterFailure = false
        app = XCUIApplication()
        let locale = language == "es" ? "es_CO" : "en_US"
        app.launchArguments = ["-ui-testing"] + seeds + ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        app.tabBars.buttons[language == "es" ? "Gramática" : "Grammar"].tap()
        XCTAssertTrue(app.navigationBars[language == "es" ? "Gramática" : "Grammar"].waitForExistence(timeout: 10))
    }

    /// A row of the list: its label is "<title>, <level>", its value the state.
    func row(_ title: String) -> XCUIElement {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        _ = row.waitForExistence(timeout: 10)
        return row
    }

    func header(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    // MARK: The list

    func testTheListShowsTheCategoriesWithTheirRulesLevelsAndStates() {
        launch("-ui-testing-grammar-states")
        XCTAssertTrue(header("Sentence building").exists)
        XCTAssertTrue(header("Verbs and tenses").exists)
        let new = row("His, her, its")
        XCTAssertEqual(new.label, "His, her, its, A1, Beginner", "commas, no dot, in what a screen reader says")
        XCTAssertEqual(new.value as? String, "New", "a New rule draws no state, VoiceOver says New")
        XCTAssertEqual(row("Irregular past").value as? String, "Practiced")
        XCTAssertEqual(row("Irregular past").label, "Irregular past, A2, Elementary")
        XCTAssertEqual(row("The -s in the present").value as? String, "In Review")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "en-light-grammar-list"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRecentListsTheLastOpenedFirst() {
        launch("-ui-testing-grammar-recent")
        XCTAssertTrue(header("Recent").exists)
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
                                                    "His, her, its", "Irregular past", "Questions and negatives"))
        // The seed opened his-her-its, irregular-past, do-does-did (oldest first): Recent shows the newest first.
        XCTAssertTrue(rows.element(boundBy: 0).label.hasPrefix("Questions and negatives"), "newest first")
    }

    // MARK: Search

    func testSearchFindsRulesInBothLanguagesAndSaysWhenNothingMatches() {
        launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("pasado")
        XCTAssertTrue(header("Rules").waitForExistence(timeout: 5), "the section header is always there")
        XCTAssertTrue(row("Irregular past").waitForExistence(timeout: 5), "found by its Spanish word")
        XCTAssertFalse(header("Sentence building").exists, "the categories give way to the results")
        app.buttons["Clear text"].tap()
        search.typeText("zzz")
        XCTAssertTrue(app.staticTexts["No rules match. Try a shorter word, like in, on or at."].waitForExistence(timeout: 5))
        XCTAssertTrue(header("Rules").exists)
    }

    // MARK: Spanish

    func testTheTabAndTheListAreInSpanish() {
        launch("-ui-testing-grammar-states", "-ui-testing-grammar-recent", language: "es")
        XCTAssertTrue(header("Recientes").exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "Practicada")).firstMatch.exists, "the state word in Spanish")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "Nueva")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "En el Repaso")).firstMatch.exists)
    }
}

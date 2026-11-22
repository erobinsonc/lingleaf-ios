import XCTest

/// The Grammar tab (SPEC S20, S21): the list, "Recent", search, and the rule page. Rules and practice are bundled, so
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
        _ = reveal(row)
        return row
    }

    /// A list builds its rows as they scroll into view, so a row further down is not there until the list is scrolled.
    @discardableResult
    func reveal(_ element: XCUIElement) -> Bool {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<8 where !element.exists || !element.isHittable { app.swipeUp() }
        return element.exists
    }

    func header(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    // MARK: The list

    func testTheListShowsTheCategoriesWithTheirRulesLevelsAndStates() {
        launch("-ui-testing-grammar-states")
        XCTAssertTrue(header("Sentence building").exists)
        let new = row("His, her, its")
        XCTAssertEqual(new.label, "His, her, its, A1, Beginner", "commas, no dot, in what a screen reader says")
        XCTAssertEqual(new.value as? String, "New", "a New rule draws no state, VoiceOver says New")
        XCTAssertEqual(row("Irregular past").value as? String, "Practiced")
        XCTAssertEqual(row("Irregular past").label, "Irregular past, A2, Elementary")
        XCTAssertEqual(row("The -s in the present").value as? String, "In Review")
        XCTAssertTrue(reveal(header("Verbs and tenses")), "the second category has its header")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "en-light-grammar-list"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRecentShowsOnlyOnceThreeRulesHaveBeenOpened() {
        launch()
        XCTAssertFalse(header("Recent").exists, "no rule opened yet")
        for title in ["His, her, its", "Irregular past", "Questions and negatives"] {
            row(title).tap()
            XCTAssertTrue(app.buttons["Try it"].waitForExistence(timeout: 5), "\(title) opened")
            back()
            XCTAssertTrue(row(title).waitForExistence(timeout: 5))
            if title != "Questions and negatives" { XCTAssertFalse(header("Recent").exists, "after fewer than 3 openings") }
        }
        XCTAssertTrue(header("Recent").waitForExistence(timeout: 5), "3 rules opened")
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

    // MARK: The rule page

    func testARulePageShowsTheRuleItsExamplesAndTheButton() {
        launch()
        row("His, her, its").tap()
        XCTAssertTrue(app.buttons["Try it"].waitForExistence(timeout: 5), "a rule whose items were never shown starts with Try it")
        XCTAssertTrue(header("Examples").exists)
        XCTAssertTrue(header("Don't mix up").exists)
        XCTAssertTrue(header("If you speak Spanish").exists)
        XCTAssertTrue(app.staticTexts["Practiced: right answers on 2 different days."].exists)
        let inReview = "In Review: this rule's questions will come back when you review."
        XCTAssertFalse(app.staticTexts[inReview].exists, "only for a rule In Review")
        XCTAssertTrue(app.staticTexts["The prince lost his shoe."].exists, "the example in English")
        XCTAssertTrue(app.staticTexts["El príncipe perdió su zapato."].exists, "its bundled translation (translation language Spanish)")
        let listen = app.buttons.matching(identifier: "Listen")
        XCTAssertGreaterThanOrEqual(listen.count, 3, "each example has Listen")
        XCTAssertGreaterThanOrEqual(listen.firstMatch.frame.width, 44)
        XCTAssertGreaterThanOrEqual(listen.firstMatch.frame.height, 44)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "en-light-grammar-rule"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheRuleLanguageStartsInSpanishForASpanishTranslationAndTheChoiceSwitchesIt() {
        launch()
        row("His, her, its").tap()
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.label, "Rule language")
        XCTAssertTrue(picker.buttons["Español"].isSelected, "translation Spanish, interface English: the rule is in Spanish")
        XCTAssertTrue(app.staticTexts["His, her, its (posesivos)"].exists, "the title in Spanish")
        picker.buttons["English"].tap()
        XCTAssertTrue(app.staticTexts["His, her, its"].waitForExistence(timeout: 5), "the rule switched to English at once")
        XCTAssertFalse(app.staticTexts["His, her, its (posesivos)"].exists)
        XCTAssertTrue(picker.buttons["English"].isSelected)
        // The choice is kept for every rule: the next rule opens in English too.
        back()
        row("Irregular past").tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["English"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["English"].isSelected, "a choice, once made, is never absent again")
        app.segmentedControls.firstMatch.buttons["Español"].tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["Español"].isSelected)
    }

    func testARuleInReviewExplainsWhatThatMeans() {
        launch("-ui-testing-grammar-states")
        row("The -s in the present").tap()
        XCTAssertTrue(app.staticTexts["In Review: this rule's questions will come back when you review."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Practiced: right answers on 2 different days."].exists)
    }

    func testTheButtonSaysPracticeOnceAnItemAfterTheFirstWasShown() {
        launch("-ui-testing-grammar-seen")
        row("His, her, its").tap()
        XCTAssertTrue(app.buttons["Practice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Try it"].exists)
    }

    func testAtSixItemsAnsweredTodayTheButtonGivesWayToTheLimitText() {
        launch("-ui-testing-grammar-limit")
        row("In, on, at: time").tap()
        XCTAssertTrue(
            app.staticTexts["You've finished today's practice for this rule. Try another rule, or come back tomorrow."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["Try it"].exists)
        XCTAssertFalse(app.buttons["Practice"].exists)
        app.buttons["See other rules"].tap()
        XCTAssertTrue(app.navigationBars["Grammar"].waitForExistence(timeout: 5), "back to the list")
    }

    func testWithFourAnsweredTodayThereIsStillARoundOfTwo() {
        launch("-ui-testing-grammar-answered-4")
        row("In, on, at: time").tap()
        XCTAssertTrue(app.buttons["Practice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["You've finished today's practice for this rule. Try another rule, or come back tomorrow."].exists)
    }

    // MARK: Spanish

    func testTheTabTheListAndTheRulePageAreInSpanish() {
        launch("-ui-testing-grammar-states", "-ui-testing-grammar-recent", language: "es")
        XCTAssertTrue(header("Recientes").exists)
        let practiced = app.buttons.matching(NSPredicate(format: "value == %@", "Practicada")).firstMatch
        XCTAssertTrue(reveal(practiced), "the state word in Spanish")
        XCTAssertTrue(reveal(app.buttons.matching(NSPredicate(format: "value == %@", "Nueva")).firstMatch))
        XCTAssertTrue(reveal(app.buttons.matching(NSPredicate(format: "value == %@", "En el Repaso")).firstMatch))
        practiced.tap()
        XCTAssertTrue(app.buttons["Pruébalo"].waitForExistence(timeout: 5) || app.buttons["Practicar"].exists)
        XCTAssertEqual(app.segmentedControls.firstMatch.label, "Idioma de la regla")
        XCTAssertTrue(app.staticTexts["Practicada: respuestas correctas en 2 días distintos."].exists)
        XCTAssertTrue(header("Ejemplos").exists)
    }
}

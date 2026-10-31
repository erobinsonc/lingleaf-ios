import XCTest

/// Walks every main screen and attaches a screenshot of each one, in light
/// and dark mode and in English and Spanish. CI exports the attachments and
/// publishes them to the `screenshots` branch, so the app can be looked at
/// without running it. The tour asserts little on purpose: its job is to
/// capture what is on screen, the other UI tests check behaviour.
final class ScreenTour: XCTestCase {
    private struct Labels {
        let language: String
        let saveWord: String
        let undo: String
        let reviewNow: String
        let showMeaning: String
        let remembered: String
        let knowIt: String
        let privacyPolicy: String
        let get: String
        let read: String
    }

    private static let english = Labels(
        language: "en", saveWord: "Save word", undo: "Undo", reviewNow: "Review now", showMeaning: "Show meaning",
        remembered: "I remembered", knowIt: "I know it", privacyPolicy: "Privacy policy",
        get: "Get", read: "Read"
    )
    private static let spanish = Labels(
        language: "es", saveWord: "Guardar palabra", undo: "Deshacer", reviewNow: "Repasar ahora", showMeaning: "Mostrar significado",
        remembered: "Lo recordé", knowIt: "Ya la sé", privacyPolicy: "Política de privacidad",
        get: "Obtener", read: "Leer"
    )

    private var app: XCUIApplication!
    private var prefix = ""

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
    }

    func testTourEnglishLight() { tour(Self.english, dark: false) }
    func testTourEnglishDark() { tour(Self.english, dark: true) }
    func testTourSpanishLight() { tour(Self.spanish, dark: false) }

    private func tour(_ labels: Labels, dark: Bool) {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        prefix = "\(labels.language)-\(dark ? "dark" : "light")"
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-due", "-AppleLanguages", "(\(labels.language))", "-AppleLocale", labels.language]
            + (dark ? ["-dark-mode"] : [])
        app.launch()

        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "The Red Boat")).firstMatch
        _ = book.waitForExistence(timeout: 10)
        snap("01-library")

        book.tap()
        let word = app.links["beach"].firstMatch
        _ = word.waitForExistence(timeout: 10)
        snap("02-reader")

        word.tap()
        _ = app.buttons[labels.saveWord].waitForExistence(timeout: 10)
        snap("03-word-card")
        app.buttons[labels.saveWord].tap()
        // The reader confirms the save with an Undo message for a few seconds.
        let undo = app.buttons[labels.undo]
        if undo.waitForExistence(timeout: 5) {
            snap("04-undo-message")
            _ = undo.waitForNonExistence(timeout: 15)
        }
        _ = word.waitForExistence(timeout: 5)
        snap("05-reader-with-marked-word")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab(2)
        snap("06-words")
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", labels.reviewNow)).firstMatch
        if review.waitForExistence(timeout: 5) {
            review.tap()
            snap("07-review")
            app.buttons[labels.showMeaning].tap()
            snap("08-review-meaning")
            app.buttons[labels.remembered].tap()
            snap("09-review-done")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        tab(1)
        _ = app.buttons["level-filter-all"].waitForExistence(timeout: 10)
        snap("10-discover")
        // A downloaded book: Get turns into the Read pill (the fake catalog answers at once).
        let get = app.buttons["\(labels.get) Little Wizard Stories of Oz"]
        if get.waitForExistence(timeout: 5) {
            get.tap()
            _ = app.buttons["\(labels.read) Little Wizard Stories of Oz"].waitForExistence(timeout: 10)
            snap("10b-discover-downloaded-book")
        }
        app.buttons["level-filter-A2"].tap()
        snap("11-discover-level-filter")
        app.buttons["level-filter-all"].tap()
        // A search (the fake catalog answers any query): results end with the public-domain notice.
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("oz\n")
            _ = app.staticTexts["The Marvelous Land of Oz"].waitForExistence(timeout: 10)
            snap("11b-discover-search-results")
        }
        tab(3)
        snap("12-settings")
        let privacy = app.buttons[labels.privacyPolicy].exists ? app.buttons[labels.privacyPolicy] : app.links[labels.privacyPolicy]
        for _ in 0..<6 where !privacy.isHittable { app.swipeUp() }
        snap("13-settings-about")
        longDefinitions(labels)
        app.terminate()
    }

    /// The fake dictionary gives "sand" a definition of several lines and "waves" one over
    /// 500 characters, which the card cuts and marks as shortened.
    private func longDefinitions(_ labels: Labels) {
        tab(0)
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "The Red Boat")).firstMatch
        guard book.waitForExistence(timeout: 10) else { return }
        book.tap()
        for (word, name) in [("sand", "03b-word-card-long-definition"), ("waves", "03c-word-card-shortened-definition")] {
            let link = app.links[word].firstMatch
            guard link.waitForExistence(timeout: 10) else { continue }
            link.tap()
            _ = app.buttons[labels.knowIt].waitForExistence(timeout: 10)
            snap(name)
            app.buttons[labels.knowIt].tap()
            _ = app.buttons[labels.knowIt].waitForNonExistence(timeout: 10)
        }
    }

    /// Taps a tab. After going back from the reader (which hides the tab bar) the bar slides
    /// back in: wait for it, and keep evidence if it never comes back.
    private func tab(_ index: Int) {
        let bar = app.tabBars.firstMatch
        if !bar.waitForExistence(timeout: 10) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "evidence-no-tab-bar"
            shot.lifetime = .keepAlways
            add(shot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "evidence-no-tab-bar-hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
        bar.buttons.element(boundBy: index).tap()
    }

    private func snap(_ name: String) {
        // Lets the screen settle (sheets, translations) before capturing.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(prefix)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import XCTest

/// Throwaway diagnostic: does the app go idle after a swipe in the plain reader?
final class ReaderSwipeDiagnostic: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func openMarket() {
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "A Day at the Market")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }

    private func timed(_ name: String, _ work: () -> Void) {
        let start = Date()
        work()
        let seconds = Date().timeIntervalSince(start)
        let note = XCTAttachment(string: "\(name): \(seconds) s")
        note.name = "timing-\(name)"
        note.lifetime = .keepAlways
        add(note)
        print("DIAG \(name): \(seconds) s")
        XCTAssertLessThan(seconds, 20, "\(name) took \(seconds) s: the app was not idle")
    }

    /// Control: a list scroll in the Library.
    func testControlSwipeInTheLibrary() {
        timed("library-swipe") { app.swipeUp() }
        timed("library-query") { _ = app.tabBars.firstMatch.buttons.count }
    }

    func testSwipeOnceInTheReaderThenBack() {
        openMarket()
        timed("reader-swipe") { app.swipeUp() }
        timed("reader-back") { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    func testSlowDragInTheReaderThenBack() {
        openMarket()
        timed("reader-drag") {
            let from = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        timed("reader-back") { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }
}

import XCTest

/// Apple's automated accessibility audit on every main screen, and what it needs. Kept apart from the
/// behaviour tests in `LingleafUITests.swift` (a class body may not grow past SwiftLint's limit).
extension LingleafUITests {
    /// Apple's automated accessibility audit (contrast, Dynamic Type, labels,
    /// hit areas…) on every main screen, empty and with a word being learned
    /// (marked word in the reader, a Words row, Review before and after the
    /// meaning). Collects every issue before failing, so one CI run shows the whole list.
    func testAccessibilityAudit() throws {
        var issues: [String] = []
        func audit(_ screen: String) throws {
            // The audit measures the pixels of one screenshot against the accessibility tree. A tab
            // switch cross-fades and a sheet slides, and on a loaded CI runner that takes much longer
            // than any fixed wait: audited mid-transition, black text on white failed contrast and
            // "inaccessible text" was found, run 41573071692 (it passed on the re-run of the same
            // tree). So wait until the screen itself has stopped changing, not for a fixed time.
            if !waitUntilSettled() {
                attachEvidence("audit-\(screen)-never-settled")
                // Auditing a screen that is still changing proves nothing: say so instead of going on.
                XCTFail("\(screen) never stopped changing within 30 s, so it was not audited")
            }
            // The reader hides the tab bar; then nothing can sit under it.
            let tabBar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
            let before = issues.count
            // A row half under the glass tab bar is measured against the bar's blur too, but
            // XCTest can't always resolve its elements, and then the exemption below can't
            // see where they are. Such unresolved contrast findings are accepted only up to the
            // number of elements under the bar right now; any more still fail, with a screenshot.
            let underBar = Self.elementsUnder(tabBar, in: app)
            var unresolved: [String] = []
            // The audit itself can time out (the first one after a cold simulator boot): that is
            // no result, so it runs again; the findings of an audit that completes always count.
            for attempt in 1...3 {
                issues.removeSubrange(before...)
                unresolved = []
                do {
                    try app.performAccessibilityAudit { issue in
                        // Rows scrolled under the translucent tab bar are measured against
                        // the bar's blur; scrolled into view they read normally. The tab
                        // bar's own buttons are not exempt: their contrast is still checked.
                        if issue.auditType == .contrast, let flagged = issue.element, flagged.frame.intersects(tabBar),
                           !Self.isTabBarButton(flagged, in: tabBar) { return true }
                        // The search field is UIKit's own (from `.searchable`); its clipping
                        // at large text sizes is iOS's to handle, not something the app can change.
                        if issue.auditType == .textClipped, issue.element?.elementType == .searchField { return true }
                        if Self.knownFalsePositive(issue, on: screen) { return true }
                        if issue.auditType == .contrast, issue.element == nil {
                            unresolved.append(
                                "[\(screen)] \(issue.compactDescription) — unresolved element — \(issue.detailedDescription)")
                            return true
                        }
                        let element = issue.element.map {
                            "type \($0.elementType.rawValue) '\($0.label)' id '\($0.identifier)' frame \($0.frame)"
                        } ?? "screen"
                        issues.append("[\(screen)] \(issue.compactDescription) — \(element) — \(issue.detailedDescription)")
                        return true
                    }
                    break
                } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit"
                    && error.code == -56 && attempt < 3 {
                    RunLoop.current.run(until: Date().addingTimeInterval(2))
                }
            }
            if unresolved.count > underBar {
                issues.append("[\(screen)] \(unresolved.count) unresolved contrast findings, \(underBar) elements under the tab bar")
                issues += unresolved
            }
            // Evidence for any finding: the screen as audited, kept with the test results, so a
            // finding without a resolvable element (a view that changed mid-audit) can be traced.
            if issues.count > before {
                let shot = XCTAttachment(screenshot: app.screenshot())
                // Named like the tour's shots, so CI exports and publishes it with them.
                let slug = screen.lowercased().split { !$0.isLetter }.joined(separator: "-")
                shot.name = "en-light-99-audit-\(slug)"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
        for tab in ["Library", "Discover", "Words", "Settings"] {
            app.tabBars.buttons[tab].tap()
            // The tab's own screen is there (its title), then still.
            _ = app.navigationBars[tab].waitForExistence(timeout: 10)
            try audit(tab)
        }
        app.tabBars.buttons["Library"].tap()
        button(startingWith: "The Red Boat").tap()
        XCTAssertTrue(app.links["beach"].firstMatch.waitForExistence(timeout: 10))
        try audit("Reader")
        app.links["beach"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Save word"].waitForExistence(timeout: 10))
        // The card as learners first see it: half height, on iOS 26 a glass sheet over the book.
        try audit("Word card (half height)")
        // Then at full height, where text clipping is checked too.
        // A slow drag, not a swipe: the card's ScrollView takes a swipe as a scroll and bounces back.
        let phonetic = app.staticTexts["/test/"]
        phonetic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThan(phonetic.frame.minY, 300, "The word card should be at full height before the audit")
        // Evidence for the audit result: the full-height card exactly as audited (exported with the tour).
        let fullHeight = XCTAttachment(screenshot: app.screenshot())
        fullHeight.name = "en-light-81-word-card-full-height"
        fullHeight.lifetime = .keepAlways
        add(fullHeight)
        try audit("Word card")

        // Populated states: save the word, then audit every screen that shows it.
        app.buttons["Save word"].tap()
        XCTAssertTrue(app.buttons["Save word"].waitForNonExistence(timeout: 10), "the card closes after Save word")
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        try audit("Reader with a learning word and the Undo message")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(element(labelled: "beach").waitForExistence(timeout: 5))
        try audit("Words with a word")
        // New words are first due tomorrow: a word due now comes from the test launch argument.
        relaunch("-ui-testing", "-ui-testing-due")
        app.tabBars.buttons["Words"].tap()
        button(startingWith: "Review now").tap()
        XCTAssertTrue(app.buttons["Show meaning"].waitForExistence(timeout: 5))
        try audit("Review")
        app.buttons["Show meaning"].tap()
        XCTAssertTrue(app.staticTexts["ES: sea"].waitForExistence(timeout: 5))
        try audit("Review with the meaning")
        XCTAssertTrue(issues.isEmpty, "Accessibility issues:\n" + issues.joined(separator: "\n"))
    }

    /// Waits until the screen stops changing: three screenshots in a row, 0.3 s apart, without its status
    /// bar (the clock changes by itself), are the same. False when it never does within `timeout`.
    @discardableResult
    private func waitUntilSettled(timeout: TimeInterval = 30) -> Bool {
        func frame() -> Data? {
            guard let image = app.screenshot().image.cgImage else { return nil }
            let top = image.height / 12
            let area = CGRect(x: 0, y: top, width: image.width, height: image.height - top)
            guard let body = image.cropping(to: area), let pixels = body.dataProvider?.data else { return nil }
            return pixels as Data
        }
        var previous: Data?
        var same = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = frame()
            if let current, current == previous { same += 1 } else { same = 0 }
            if same >= 2 { return true }
            previous = current
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    /// Audit findings checked by hand and found not to be real problems. Each
    /// one names the screen and the reason; anything else still fails the test.
    private static func knownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, on screen: String) -> Bool {
        // The DEBUG-only element that exposes the last spoken text to UI tests
        // (1×1 pt, nearly transparent); users never see it and live builds don't have it.
        if [lastSpokenID, spokenLogID].contains(issue.element?.identifier ?? "") { return true }
        switch (screen, issue.auditType) {
        case ("Word card (half height)", .textClipped):
            // At half height the card's text continues in its ScrollView; iOS 26 draws the
            // medium sheet slightly scaled and reports all of it as clipped. The test drags
            // the card to full height and audits it again, where clipping still fails.
            return true
        case ("Settings", .contrast) where issue.element?.label.uppercased() == "VOICE":
            // The four section headers share one style and colour. Measured on the
            // screenshot tour all four are 7.58:1 (#4D4D4D on #F2F2F7), yet only
            // "Voice" is reported, run after run; the others pass. Only this header
            // is exempt, so a real regression in the shared style still fails.
            return true
        case ("Settings", .contrast):
            // On iOS 26 the audit reports contrast failures inside Form controls
            // without naming any element. Measured on the screenshot tour, every
            // text and icon there is ≥ 6:1 (headers 6.0, slider icons 6.7,
            // accent 6.2, stepper 18.1), above WCAG AA's 4.5:1. A failure that
            // names an element is still reported.
            return issue.element == nil
        case (_, .hitRegion):
            // Progress bars (reader, review) are read-only indicators, not touch
            // targets, so the minimum hit area does not apply (WCAG 2.5.8 covers targets).
            return issue.element?.elementType == .progressIndicator
        case ("Word card", .contrast) where issue.element?.label == Self.beachDefinitionLabel:
            // Measured on the screenshot taken right before this audit (en-light-81-word-card-full-height):
            // #4D4D4D on the card's opaque #F1F1F6 panel, 7.5:1. The same line in the same colours
            // passes at half height; only this line is exempt, so a real regression in the card still fails.
            return true
        case ("Word card", .elementDetection), ("Word card (half height)", .elementDetection):
            // The card is a sheet over the reader: the book's text shows behind
            // it, dimmed and correctly hidden from VoiceOver while the card is open.
            return issue.element == nil
        default:
            return false
        }
    }

    /// A tab bar button sits entirely inside the bar; rows scrolled under the bar only overlap it.
    /// Labelled elements of the screen (not the tab bar's own) that reach under the tab bar.
    private static func elementsUnder(_ tabBar: CGRect, in app: XCUIApplication) -> Int {
        guard !tabBar.isNull, let root = try? app.snapshot() else { return 0 }
        func count(_ node: XCUIElementSnapshot) -> Int {
            if node.elementType == .tabBar { return 0 }
            if node.children.isEmpty { return !node.label.isEmpty && node.frame.intersects(tabBar) ? 1 : 0 }
            return node.children.reduce(0) { $0 + count($1) }
        }
        return count(root)
    }

    private static func isTabBarButton(_ element: XCUIElement, in tabBar: CGRect) -> Bool {
        element.elementType == .button && tabBar.contains(element.frame)
    }
}

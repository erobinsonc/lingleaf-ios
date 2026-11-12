import XCTest

/// Runs the real app in `-ui-testing` mode: fresh storage, canned dictionary
/// answers and fake translations, so results don't depend on the network.
final class LingleafUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testTapAWordSeeItsCardAndSaveIt() {
        button(startingWith: "The Red Boat").tap()

        let word = app.links["beach"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10), "words in the reader are tappable links")
        word.tap()

        XCTAssertTrue(app.staticTexts["ES: beach"].waitForExistence(timeout: 10), "the card shows the translation")
        XCTAssertTrue(app.staticTexts["/test/"].exists, "the card shows the IPA")
        XCTAssertTrue(app.buttons["Translation language: Español"].exists, "the language button sits under the translation")
        // One static text with its source (Wiktionary's CC BY-SA), and no doubled full stop.
        XCTAssertTrue(app.staticTexts[Self.beachDefinitionLabel].waitForExistence(timeout: 10), "the definition says where it comes from")
        app.buttons["Save word"].tap()
        XCTAssertTrue(app.staticTexts["“beach” saved to Words"].waitForExistence(timeout: 5), "the reader confirms the save")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(element(labelled: "beach").waitForExistence(timeout: 5), "the word was saved")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "ES: beach")).firstMatch.exists)
    }

    func testAModalVerbShowsItsVerbGroupAndWhatItDoes() {
        button(startingWith: "The Red Boat").tap()
        let word = app.links["Can"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()

        XCTAssertTrue(app.staticTexts["Modal verb"].waitForExistence(timeout: 10), "the card says what kind of word it is")
        XCTAssertTrue(app.staticTexts["can"].exists, "the base form")
        XCTAssertTrue(app.staticTexts["Can we fix"].exists, "the verb group it belongs to")
        XCTAssertTrue(app.staticTexts["ES: Can we fix"].exists, "the verb group is translated, not the word alone")
        XCTAssertTrue(app.staticTexts["“can” + verb: be able to, or be allowed to."].exists)
        let card = XCTAttachment(screenshot: app.screenshot())
        card.name = "en-light-82-modal-verb-card"
        card.lifetime = .keepAlways
        add(card)

        app.buttons["Save word"].tap()
        XCTAssertTrue(app.staticTexts["“Can we fix” saved to Words"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(element(labelled: "can we fix").waitForExistence(timeout: 5), "Words shows the verb group")
    }

    /// S16: a perfect's helper says what it does; a pronoun contraction, what it stands for.
    func testAPerfectSaysWhatItDoes() {
        button(startingWith: "The Lighthouse Keeper").tap()
        let had = app.links["had"].firstMatch
        XCTAssertTrue(had.waitForExistence(timeout: 10))
        had.tap()
        XCTAssertTrue(app.staticTexts["Helper verb"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["have"].exists, "the base form")
        XCTAssertTrue(app.staticTexts["had kept"].exists, "the verb group up to the participle")
        XCTAssertTrue(app.staticTexts["“had” + past participle: it happened before another past moment: “had left”."].exists)
        attachScreenshot("en-light-83-perfect-card")
    }

    func testAContractionSaysWhatItStandsFor() {
        button(startingWith: "A Day at the Market").tap()
        let that = app.links["That's"].firstMatch
        XCTAssertTrue(that.waitForExistence(timeout: 10))
        for _ in 0..<6 where !that.isHittable { app.swipeUp() }
        that.tap()
        XCTAssertTrue(app.staticTexts["that is"].waitForExistence(timeout: 10), "the contraction's expansion is its base form")
        XCTAssertTrue(app.staticTexts["“that's” = “that is”."].exists)
        XCTAssertFalse(app.staticTexts["Helper verb"].exists, "a plain contraction has no label")
        attachScreenshot("en-light-84-contraction-card")
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// S7: recall first; the meaning brings the sentence, its translation and the answers.
    func testReviewAWord() {
        relaunch("-ui-testing", "-ui-testing-due")
        app.tabBars.buttons["Words"].tap()
        button(startingWith: "Review now").tap()
        XCTAssertTrue(app.buttons["Show meaning"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["I remembered"].exists, "recall first: no answers before the meaning")
        XCTAssertFalse(app.staticTexts["ES: sea"].exists)
        app.buttons["Show meaning"].tap()
        XCTAssertTrue(app.staticTexts["ES: sea"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ES: Tom lives in a small house by the sea."].exists, "the sentence's translation")
        // "Again" repeats the word in the session, recall first again.
        app.buttons["Again"].tap()
        XCTAssertTrue(app.buttons["Show meaning"].waitForExistence(timeout: 5))
        app.buttons["Show meaning"].tap()
        app.buttons["I remembered"].tap()
        XCTAssertTrue(app.staticTexts["Done for today."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 word tomorrow."].exists, "the word is due again tomorrow")
        XCTAssertTrue(app.buttons["Back to Words"].exists, "the way out says where it goes")
    }

    /// S3: unsure, the guide says where the answer is, or asks when the sentence has no
    /// translation; a chosen reading says "No definition available." only once its look-up answered.
    func testTheUnsureCardsGuideFollowsTheSentencesTranslation() {
        relaunch("-ui-testing", "-ui-testing-tour")
        button(startingWith: "Test Story").tap()
        let left = app.links["left"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 10))
        left.tap()
        XCTAssertTrue(app.staticTexts["The sentence's translation tells you which one:"].waitForExistence(timeout: 10))
        button(startingWith: "the left").tap()
        let definition = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Definition of left")).firstMatch
        XCTAssertTrue(definition.waitForExistence(timeout: 10), "the chosen reading's definition")
        XCTAssertFalse(app.staticTexts["No definition available."].exists)
        relaunch("-ui-testing-offline", "-ui-testing-tour")
        button(startingWith: "Test Story").tap()
        XCTAssertTrue(left.waitForExistence(timeout: 10))
        left.tap()
        XCTAssertTrue(app.staticTexts["Which one is it in this sentence?"].waitForExistence(timeout: 10), "offline, the guide asks")
        XCTAssertFalse(app.staticTexts["The sentence's translation tells you which one:"].exists)
    }

    /// S4/S15/S18: Words names a sensed word as it shows it, and Undo of the corrections says what it did.
    func testWordsNamesSensesAndConfirmsTheCorrectionsUndo() {
        relaunch("-ui-testing", "-ui-testing-tour")
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.buttons["Listen to the wind"].waitForExistence(timeout: 10), "Listen names the sense")
        relaunch("-ui-testing", "-ui-testing-corrections-1")
        app.tabBars.buttons["Words"].tap()
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "the corrections card")
        let fixedRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "the left", "Fixed")).firstMatch
        XCTAssertTrue(fixedRow.exists, "the corrected word's row is tagged while the card is open")
        undo.tap()
        XCTAssertTrue(app.staticTexts["Words put back as before"].waitForExistence(timeout: 5))
    }

    /// About says the recommended books are public domain worldwide; the US-only notice is for search results.
    func testAboutSaysTheRecommendedBooksArePublicDomainWorldwide() {
        app.tabBars.buttons["Settings"].tap()
        let worldwide = app.staticTexts["Recommended books are public domain worldwide."]
        for _ in 0..<8 where !worldwide.exists { app.swipeUp() }
        XCTAssertTrue(worldwide.exists)
        XCTAssertFalse(app.staticTexts["Project Gutenberg books are public domain in the US. Elsewhere, check your country's laws."].exists)
    }

    /// A fast flick in the reader must leave the app idle: it used to stay busy for minutes (every
    /// visibility change re-ran the whole reader while `scrollPosition(id:)` followed the scroll).
    func testAFlickInTheReaderLeavesTheAppIdle() {
        button(startingWith: "A Day at the Market").tap()
        XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let start = Date()
        app.swipeUp()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "the app was busy after the flick")
    }

    func relaunch(_ arguments: String...) {
        app.terminate()
        app.launchArguments = arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testFilterRecommendedBooksByLevel() {
        app.tabBars.buttons["Discover"].tap()
        let b2 = app.buttons["level-filter-B2"]
        XCTAssertTrue(b2.waitForExistence(timeout: 10), "the level chips show above the recommended books")
        b2.tap()
        XCTAssertTrue(app.staticTexts["The Railway Children"].waitForExistence(timeout: 5), "B2 books stay")
        XCTAssertTrue(app.staticTexts["Little Wizard Stories of Oz"].waitForNonExistence(timeout: 5), "the B1 book is filtered out")
        app.buttons["level-filter-A2"].tap()
        let story = app.buttons["Read A Day at the Market"]
        XCTAssertTrue(story.waitForExistence(timeout: 5), "a level without classics lists the app's own story")
        app.buttons["level-filter-all"].tap()
        XCTAssertTrue(app.staticTexts["Little Wizard Stories of Oz"].waitForExistence(timeout: 5), "All shows every book again")
        XCTAssertTrue(story.waitForNonExistence(timeout: 5), "All keeps to the classics: the stories are in the library")
        app.buttons["level-filter-A2"].tap()
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        story.tap()
        XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 10), "Read opens the story in the reader")
    }

    /// S19: the app's own stories say so in the Library, and Discover lists all three of a level.
    func testTheOriginalStoriesAreMarkedAndListedByLevel() {
        XCTAssertTrue(button(startingWith: "The Red Boat").label.contains("Our story"), "the Library row says it is one of the app's stories")
        app.tabBars.buttons["Discover"].tap()
        let a1 = app.buttons["level-filter-A1"]
        XCTAssertTrue(a1.waitForExistence(timeout: 10))
        a1.tap()
        for title in ["A Shoe in the Fridge", "An Empty Apartment", "Nour's Long Race"] {
            XCTAssertTrue(app.buttons["Read \(title)"].waitForExistence(timeout: 5), "\(title) is in the A1 stories")
        }
        XCTAssertTrue(app.staticTexts[Self.storiesNoticeText].waitForExistence(timeout: 5), "the AI-help note shows with the stories")
        app.buttons["level-filter-C2"].tap()
        XCTAssertTrue(app.buttons["Read The Second Violin"].waitForExistence(timeout: 5), "the C2 stories are there too")
    }

    /// S19: a word the story has an entry for shows the story's sense, not the general translation.
    func testAStoryWordShowsItsSenseAndSavesIt() {
        app.tabBars.buttons["Discover"].tap()
        let a1 = app.buttons["level-filter-A1"]
        XCTAssertTrue(a1.waitForExistence(timeout: 10))
        a1.tap()
        let read = app.buttons["Read A Shoe in the Fridge"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        let word = app.links["mom"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10), "the story opens offline")
        word.tap()

        XCTAssertTrue(app.staticTexts["mamá"].waitForExistence(timeout: 10), "the story's own meaning")
        XCTAssertFalse(app.staticTexts["ES: mom"].exists, "not the general translation")
        XCTAssertTrue(app.staticTexts["US English"].exists, "a US word says so")
        let definition = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Definition of mom")).firstMatch
        XCTAssertTrue(definition.waitForExistence(timeout: 10), "the dictionary has a noun for it")
        attachScreenshot("en-light-16-story-word-card")
        app.buttons["Save word"].tap()
        XCTAssertTrue(app.staticTexts["“mom” saved to Words"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(element(labelled: "mom").waitForExistence(timeout: 5), "the word was saved")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "mamá")).firstMatch.exists,
                      "with the story's meaning")
    }

    /// S19: a name that is also a word is a name, with no translation.
    func testAStoryNameIsLabelledAsAName() {
        app.tabBars.buttons["Discover"].tap()
        let a2 = app.buttons["level-filter-A2"]
        XCTAssertTrue(a2.waitForExistence(timeout: 10))
        a2.tap()
        let read = app.buttons["Read The Oven Next Door"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        let word = app.links["Blue"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()
        XCTAssertTrue(app.staticTexts["Proper name"].waitForExistence(timeout: 10), "the card says it is a name")
        XCTAssertFalse(app.buttons["Save word"].exists, "a name is not offered to save")
        XCTAssertEqual(app.staticTexts.matching(identifier: "The Blue Table").count, 1, "the headword is not repeated")
        XCTAssertTrue(app.staticTexts["The Blue Table"].firstMatch.exists, "the whole name is the headword")
        XCTAssertFalse(app.staticTexts["ES: Blue"].exists, "a name is not translated")
        attachScreenshot("en-light-17-story-name-card")
    }

    /// S6 Listen. XCUITest can't hear the speaker, so in -ui-testing mode the app records
    /// the last spoken text and shows it in a test-only element (`LastSpokenProbe`).
    /// Each card is closed before the check, so the element is read from the main
    /// window rather than from behind the modal sheet.
    func testListenReadsTheWordTheSentenceAndTheParagraph() {
        button(startingWith: "The Red Boat").tap()

        let beach = app.links["beach"].firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 10))
        beach.tap()
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 10))
        app.buttons["Listen"].tap()
        closeCard()
        assertLastSpoken("beach", "Listen on the word card speaks the word")

        app.links["sea"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Listen to the sentence"].waitForExistence(timeout: 10))
        app.buttons["Listen to the sentence"].tap()
        closeCard()
        assertLastSpoken("Tom lives in a small house by the sea.", "the sentence button speaks the word's sentence")

        // Read aloud goes on sentence by sentence; the bar at the bottom pauses (issue #32).
        // The UI-test speaker ends each text after 2 s, so the checks read the spoken log.
        app.buttons["Read aloud"].tap()
        assertSpoken(["Tom lives in a small house by the sea.", "He is ten years old."], "Read aloud starts at the top of the screen and goes on")
        XCTAssertTrue(app.buttons["Pause"].exists, "while reading, the bar pauses")
        let reading = XCTAttachment(screenshot: app.screenshot())
        reading.name = "en-light-85-reading-aloud"
        reading.lifetime = .keepAlways
        add(reading)
        // Tapping a word pauses: nothing more is read while its card is open or after.
        app.links["dog"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Read from here"].waitForExistence(timeout: 10))
        closeCard()
        let paused = spokenLog()
        sleep(4)
        XCTAssertEqual(spokenLog(), paused, "tapping a word pauses reading aloud")
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "paused: the bar at the bottom stays, with Play")

        // The word card's Read from here starts at the word's sentence (issue #33).
        app.links["sand"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Read from here"].waitForExistence(timeout: 10))
        app.buttons["Read from here"].tap()
        assertSpoken(["The sand is warm."], "Read from here starts at the tapped word's sentence")

        // Repeat sentence loops the sentence being read; Add previous sentence grows the stretch
        // backwards and reads it from its new start (issue #33).
        element(labelled: "Repeat sentence").tap()
        XCTAssertTrue(app.staticTexts["Repeating 1 sentence"].waitForExistence(timeout: 5))
        let looped = app.staticTexts[Self.lastSpokenID].label
        assertSpoken([looped, looped], "Repeat sentence reads it again")
        app.buttons["Add previous sentence"].tap()
        XCTAssertTrue(app.staticTexts["Repeating 2 sentences"].waitForExistence(timeout: 5))
        waitForSpokenLog("the stretch: the previous sentence, the looped one, the previous one again") { log in
            guard let last = log.lastIndex(of: looped), last >= 1, last + 1 < log.count else { return false }
            return log[last - 1] != looped && log[last + 1] == log[last - 1]
        }
        let repeating = XCTAttachment(screenshot: app.screenshot())
        repeating.name = "en-light-86-repeating"
        repeating.lifetime = .keepAlways
        add(repeating)
        element(labelled: "Repeat sentence").tap()
        XCTAssertTrue(app.buttons["Previous sentence"].waitForExistence(timeout: 5), "repeat off: back to Previous sentence")
        app.buttons["Pause"].tap()
    }

    /// Everything the UI-test speaker was handed, in order.
    private func spokenLog() -> [String] {
        let probe = app.staticTexts[Self.spokenLogID]
        return probe.exists ? probe.label.components(separatedBy: "\n") : []
    }

    /// Waits (up to 15 s) until the spoken log satisfies `condition`.
    private func waitForSpokenLog(_ message: String, file: StaticString = #filePath, line: UInt = #line, _ condition: ([String]) -> Bool) {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if condition(spokenLog()) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("\(message); spoken: \(spokenLog())", file: file, line: line)
    }

    /// Evidence when an element is missing: the screen and its accessibility hierarchy,
    /// kept with the test results.
    func attachEvidence(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "evidence-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "evidence-\(name)-hierarchy"
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// S9: Get shows progress, then Read opens the book; a missing book says so in its row.
    func testDownloadABookFromDiscover() {
        app.tabBars.buttons["Discover"].tap()
        let get = app.buttons["Get Little Wizard Stories of Oz"]
        XCTAssertTrue(get.waitForExistence(timeout: 10), "recommended books are there at once")
        get.tap()
        let read = app.buttons["Read Little Wizard Stories of Oz"]
        XCTAssertTrue(read.waitForExistence(timeout: 10), "Get turns into Read")

        app.buttons["Get The Marvelous Land of Oz"].tap()
        XCTAssertTrue(app.staticTexts["This book isn't available right now."].waitForExistence(timeout: 10))

        read.tap()
        XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 10), "Read opens the book")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // The tab bar slides back in after the reader: wait for it, with evidence if it doesn't.
        if !app.tabBars.firstMatch.waitForExistence(timeout: 10) { attachEvidence("no-tab-bar-after-reader") }
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Little Wizard Stories of Oz")).firstMatch
        if !row.waitForExistence(timeout: 10) { attachEvidence("library-after-download") }
        XCTAssertTrue(row.exists, "the book is in the library")
    }

    // S10 Import goes through the system file picker, which XCUITest can't drive
    // reliably; its rules (title, Gutenberg header removal, empty files refused)
    // are covered by the importTitle/importText tests in LingleafCore's LibraryTests.

    /// S12 Offline (`-ui-testing-offline`: every request fails, translation throws):
    /// the card says what is unavailable, and the reader and saving words still work.
    func testOfflineCardSaysWhatIsUnavailableAndTheReaderStillWorks() {
        app.terminate()
        app.launchArguments = ["-ui-testing-offline", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        button(startingWith: "The Red Boat").tap()
        let word = app.links["beach"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10), "the reader opens offline")
        word.tap()
        XCTAssertTrue(app.staticTexts["No definition available."].waitForExistence(timeout: 10))
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Translation unavailable")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10), "the card says translation is unavailable")

        app.buttons["Save word"].tap()
        XCTAssertTrue(app.buttons["Save word"].waitForNonExistence(timeout: 10), "saving doesn't wait for the translation")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(element(labelled: "beach").waitForExistence(timeout: 5), "the word is saved offline")
    }

    /// S3 offline: the card's base form of an irregular form comes from the irregular-verb table,
    /// so this also proves the table is inside the built app ("sees" would show as "sees" without it).
    func testOfflineCardShowsTheBaseFormFromTheIrregularVerbTable() {
        relaunch("-ui-testing-offline")
        button(startingWith: "The Red Boat").tap()
        let word = app.links["sees"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10), "the reader opens offline")
        word.tap()
        XCTAssertTrue(app.staticTexts["In the text: sees"].waitForExistence(timeout: 10), "the card shows a base form")
        XCTAssertTrue(app.staticTexts["see"].exists, "the table's base form, without the dictionary")
    }

    /// S12: a word saved offline has no translation yet; Review says so when the meaning is shown.
    func testReviewSaysWhenAWordHasNoTranslationYet() {
        relaunch("-ui-testing-offline", "-ui-testing-due")
        app.tabBars.buttons["Words"].tap()
        button(startingWith: "Review now").tap()
        XCTAssertTrue(app.buttons["Show meaning"].waitForExistence(timeout: 5))
        app.buttons["Show meaning"].tap()
        let noTranslation = app.staticTexts["No translation yet. Connect to the internet once to get it."]
        XCTAssertTrue(noTranslation.waitForExistence(timeout: 5), "Review says the translation is missing")
    }

    /// S4/S15: Undo after Save word takes the word out again; Undo after changing a
    /// saved word puts back the previous record.
    func testUndoAfterSaveWordRestoresTheWord() {
        button(startingWith: "The Red Boat").tap()
        let beach = app.links["beach"].firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 10))

        beach.tap()
        XCTAssertTrue(app.buttons["Save word"].waitForExistence(timeout: 10))
        app.buttons["Save word"].tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the reader offers Undo")
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "the message closes after Undo")

        beach.tap()
        XCTAssertTrue(app.buttons["I know it"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["I know it"].isSelected, "after Undo the word is new again")
        app.buttons["I know it"].tap()
        XCTAssertTrue(app.staticTexts["“beach” marked as known"].waitForExistence(timeout: 5))

        beach.tap()
        XCTAssertTrue(app.buttons["I know it"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["I know it"].isSelected, "the card shows the word is known")
        app.buttons["Save word"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        beach.tap()
        XCTAssertTrue(app.buttons["I know it"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["I know it"].isSelected, "Undo put the word back as known")
        XCTAssertFalse(app.buttons["Saved"].exists)
        closeCard()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["No words yet. While reading, tap a word and choose Save word."].waitForExistence(timeout: 5))
    }

    /// Deleting a word in Words (swipe action) offers Undo, which puts the word back.
    func testDeletingAWordOffersUndo() {
        button(startingWith: "The Red Boat").tap()
        let beach = app.links["beach"].firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 10))
        beach.tap()
        XCTAssertTrue(app.buttons["Save word"].waitForExistence(timeout: 10))
        app.buttons["Save word"].tap()
        XCTAssertTrue(app.staticTexts["“beach” saved to Words"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Words"].tap()
        let row = element(labelled: "beach")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the word is in Words")
        row.swipeLeft()
        let delete = app.buttons["Delete word"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the swipe shows Delete word")
        delete.tap()

        XCTAssertTrue(app.staticTexts["“beach” deleted"].waitForExistence(timeout: 3), "Words confirms the delete")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Words offers Undo")
        undo.tap()
        XCTAssertTrue(element(labelled: "beach").waitForExistence(timeout: 5), "Undo puts the word back")
    }

    /// Tapping the checked "Saved" button on the card removes the word; Undo saves it again.
    func testTappingTheCheckedButtonRemovesTheWordWithUndo() {
        button(startingWith: "The Red Boat").tap()
        let beach = app.links["beach"].firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 10))
        beach.tap()
        XCTAssertTrue(app.buttons["Save word"].waitForExistence(timeout: 10))
        app.buttons["Save word"].tap()
        XCTAssertTrue(app.buttons["Save word"].waitForNonExistence(timeout: 10), "the card closes after Save word")

        beach.tap()
        let saved = app.buttons["Saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "the card shows the word is saved")
        XCTAssertTrue(saved.isSelected)
        saved.tap()
        XCTAssertTrue(app.staticTexts["“beach” removed from Words"].waitForExistence(timeout: 3), "the reader confirms the removal")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "the reader offers Undo")
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "the message closes after Undo")

        beach.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Undo saved the word again")
        XCTAssertTrue(saved.isSelected)
        XCTAssertFalse(app.buttons["Save word"].exists)
    }

    /// S14: with no language saved or picked from the device, the first card asks
    /// "Translate into:"; the choice is saved and translates the card in place.
    func testWithoutALanguageTheCardAsksAndTranslatesInPlace() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-ui-testing-no-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        button(startingWith: "The Red Boat").tap()
        let beach = app.links["beach"].firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 10))
        beach.tap()
        XCTAssertTrue(app.staticTexts["Translate into:"].waitForExistence(timeout: 10), "the card asks for a language")
        XCTAssertTrue(app.buttons["More languages"].exists)
        XCTAssertTrue(app.buttons["Save word"].isHittable, "the rest of the card works meanwhile")

        app.buttons["Español"].tap()
        XCTAssertTrue(app.staticTexts["ES: beach"].waitForExistence(timeout: 10), "the translation appears on the same card")
        XCTAssertFalse(app.staticTexts["Translate into:"].exists, "the question is gone")
        XCTAssertTrue(app.buttons["Translation language: Español"].exists, "a button to change the language replaces it")
    }

    /// How VoiceOver reads the fake dictionary's definition of "beach" on the word card.
    static let beachDefinitionLabel = "noun: Definition of beach. Source: Wiktionary."
    static let storiesNoticeText = "Our stories were written with AI help. Anyone can use them freely."

    /// Identifier of `LastSpokenProbe` in the app.
    static let lastSpokenID = "ui-test-last-spoken"
    static let spokenLogID = "ui-test-spoken-log"

    /// Waits until `texts` were spoken one after another (reading aloud moves on every 1.5 s,
    /// so checking only the last one would miss some).
    private func assertSpoken(_ texts: [String], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.staticTexts[Self.spokenLogID]
        let spoken = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", texts.joined(separator: "\n")), object: probe)
        let result = XCTWaiter().wait(for: [spoken], timeout: 15)
        XCTAssertEqual(result, .completed, "\(message); spoken: '\(probe.exists ? probe.label : "nothing")'", file: file, line: line)
    }

    /// Waits for the app's record of the last spoken text to equal `text`.
    private func assertLastSpoken(_ text: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.staticTexts[Self.lastSpokenID]
        let spoken = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: probe)
        let result = XCTWaiter().wait(for: [spoken], timeout: 5)
        XCTAssertEqual(result, .completed, "\(message); last spoken: '\(probe.exists ? probe.label : "nothing")'", file: file, line: line)
    }

    /// Closes the word card: "I know it" saves (or, when checked, removes) the word and dismisses the sheet.
    private func closeCard() {
        app.buttons["I know it"].tap()
        XCTAssertTrue(app.buttons["I know it"].waitForNonExistence(timeout: 10), "the card closes")
    }

    /// A word row in Words reads as one element whose label starts with the word.
    func element(labelled prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Rows combine their texts into one label ("The Red Boat, Level A1, …").
    /// The Library lists 21 stories, A1 to C2: a row further down is found by scrolling.
    func button(startingWith prefix: String) -> XCUIElement {
        let element = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<8 where !element.exists || !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 10), "button starting with \(prefix)")
        return element
    }
}

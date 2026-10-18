import XCTest
@testable import LingleafCore

final class TextToolsTests: XCTestCase {
    func testParagraphsJoinHardWrappedLinesAndHandleCRLF() {
        XCTAssertEqual(
            TextTools.splitParagraphs("Line one\r\nline two.\r\n\r\n   \nSecond paragraph.\n"),
            ["Line one line two.", "Second paragraph."]
        )
    }

    func testAParagraphTheSizeOfABookIsCutAtSentenceEndsOrSpaces() {
        let noStops = String(repeating: "word ", count: 5_000)
        let pieces = TextTools.splitParagraphs(noStops)
        XCTAssertGreaterThan(pieces.count, 1)
        XCTAssertTrue(pieces.allSatisfy { $0.utf16.count <= TextTools.maxParagraph })
        XCTAssertEqual(pieces.joined(separator: " "), noStops.trimmingCharacters(in: .whitespaces), "no word lost or cut")
        let sentences = TextTools.splitParagraphs(String(repeating: "A short sentence here. ", count: 300))
        XCTAssertTrue(sentences.allSatisfy { $0.hasSuffix(".") && $0.utf16.count <= TextTools.maxParagraph })
        let oneWord = TextTools.splitParagraphs(String(repeating: "a", count: 4_500))
        XCTAssertEqual(oneWord.map(\.count), [2_000, 2_000, 500])
    }

    func testALongRunOfMarksIsMatchedInLinearTime() {
        let hostile = String(repeating: "!", count: 50_000) + "x"
        let started = Date()
        XCTAssertEqual(TextTools.sentenceRanges(hostile).count, 1, "no sentence end: one sentence")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "not one scan of the run per mark")
        XCTAssertEqual(TextTools.sentenceRanges("Wait!!! He said “no.” Then?").count, 3, "runs and closing quotes still end sentences")
    }

    func testATenMegabyteTextWithoutBlankLinesSplitsInLinearTime() {
        let book = String(repeating: "word ", count: 2_000_000)
        let started = Date()
        let pieces = TextTools.splitParagraphs(book)
        XCTAssertEqual(pieces.count, 5_000, "2,000-unit pieces")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testALongSentenceIsCappedAroundTheTappedWord() {
        let paragraph = String(repeating: "word ", count: 500)
        let range = TextTools.sentenceRangeAt(paragraph, 1_200)
        XCTAssertLessThanOrEqual(range.end - range.start, TextTools.maxSentence)
        XCTAssertTrue(range.contains(1_200))
        XCTAssertEqual(TextTools.substring(paragraph, range).first, "w", "starts at a word")
        XCTAssertEqual(TextTools.sentenceAt("Short one. Here.", 2), "Short one.", "ordinary sentences are unchanged")
    }

    func testLabelsLoseInvisibleCharactersAndStayShort() {
        XCTAssertEqual(TextTools.cleanLabel("\u{202E}evil\u{200B} title\n  x"), "evil title x")
        XCTAssertEqual(TextTools.cleanLabel(String(repeating: "t", count: 300)).count, TextTools.maxLabel)
        XCTAssertEqual(TextTools.cleanLabel("Alice’s Adventures"), "Alice’s Adventures")
        let zalgo = TextTools.cleanLabel("a" + String(repeating: "\u{0301}", count: 100_000))
        XCTAssertEqual(zalgo.unicodeScalars.count, 1 + TextTools.maxCombiningMarks, "at most 4 accents on a letter")
        XCTAssertEqual(TextTools.cleanLabel("\u{3164}\u{115F}\u{2800}Fake"), "Fake", "blank fillers")
        XCTAssertEqual(TextTools.cleanLabel("\u{3000}\u{00A0}Alice\u{2003} x"), "Alice x", "Unicode spaces")
        XCTAssertEqual(TextTools.cleanLabel("Cafe\u{0301}"), "Cafe\u{0301}")
    }

    func testWordRangesKeepContractionsAndSkipNumbers() {
        let text = "Don’t stop, it's 10 o'clock!"
        XCTAssertEqual(TextTools.wordRanges(text).map { TextTools.substring(text, $0) }, ["Don’t", "stop", "it's", "o'clock"])
    }

    func testWordAtFindsTheWordIncludingItsTrailingEdge() {
        let text = "All animals are equal."
        XCTAssertEqual(TextTools.wordAt(text, 4), WordRange(4, 11))
        XCTAssertEqual(TextTools.wordAt(text, 11), WordRange(4, 11))
        XCTAssertEqual(TextTools.wordAt(text, 21), WordRange(16, 21))
        XCTAssertNil(TextTools.wordAt("  ...  ", 3))
        XCTAssertTrue(WordRange(4, 11).contains(5))
    }

    func testSentenceAtReturnsTheContainingSentence() {
        let p = "All animals are equal. Some are more equal than others! The end"
        let offset = (p as NSString).range(of: "more").location
        XCTAssertEqual(TextTools.sentenceAt(p, offset), "Some are more equal than others!")
        XCTAssertEqual(TextTools.sentenceAt(p, 0), "All animals are equal.")
        XCTAssertEqual(TextTools.sentenceAt(p, (p as NSString).range(of: "end").location), "The end")
        XCTAssertEqual(TextTools.sentenceAt("Just one.", 20), "Just one.")
    }

    func testBaseFormCandidates() {
        XCTAssertTrue(TextTools.baseFormCandidates("animals").contains("animal"))
        XCTAssertTrue(TextTools.baseFormCandidates("houses").contains("house"))
        XCTAssertEqual(TextTools.baseFormCandidates("stories"), ["story"])
        XCTAssertEqual(TextTools.baseFormCandidates("tried"), ["try"])
        XCTAssertTrue(TextTools.baseFormCandidates("walked").contains("walk"))
        XCTAssertEqual(TextTools.baseFormCandidates("stopped").first, "stop")
        XCTAssertEqual(TextTools.baseFormCandidates("running").first, "run")
        XCTAssertTrue(TextTools.baseFormCandidates("making").contains("make"))
        XCTAssertEqual(TextTools.baseFormCandidates("stood"), ["stand"])
        XCTAssertEqual(TextTools.baseFormCandidates("Children"), ["child"])
        XCTAssertEqual(TextTools.baseFormCandidates("cat's"), ["cat"])
        XCTAssertTrue(TextTools.baseFormCandidates("thing").isEmpty)
        XCTAssertTrue(TextTools.baseFormCandidates("glass").isEmpty)
    }

    func testOccurrencesFindTheSavedWordOrGroupInASentence() {
        let sentence = "All animals are equal, but some animal is more equal."
        XCTAssertEqual(TextTools.occurrences(of: "animal", in: sentence).map { TextTools.substring(sentence, $0) }, ["animals", "animal"])
        let group = "He did NOT go home."
        XCTAssertEqual(TextTools.occurrences(of: "did not go", in: group).map { TextTools.substring(group, $0) }, ["did NOT go"])
        XCTAssertTrue(TextTools.occurrences(of: "can we fix", in: group).isEmpty)
    }

    func testMatchKeysLinkInflectedFormsToTheBaseWord() {
        XCTAssertTrue(TextTools.matchKeys("Animals").isSuperset(of: ["animals", "animal"]))
        XCTAssertTrue(TextTools.matchKeys("was").contains("be"))
    }

    func testIrregularFormsComeFromTheTable() {
        XCTAssertEqual(TextTools.baseFormCandidates("stolen"), ["steal"])
        XCTAssertEqual(TextTools.baseFormCandidates("learnt").first, "learn")
        XCTAssertEqual(TextTools.baseFormCandidates("became"), ["become"])
        XCTAssertEqual(TextTools.baseFormCandidates("being"), ["be"])
        XCTAssertEqual(TextTools.baseFormCandidates("lying"), ["lie"])
        XCTAssertEqual(TextTools.baseFormCandidates("lied"), ["lie"])
        XCTAssertEqual(TextTools.baseFormCandidates("Knives"), ["knife", "knive", "kniv"])
    }

    func testDoubledLAfterTwoVowelGroupsGivesTheSingleL() {
        XCTAssertEqual(TextTools.baseFormCandidates("travelled").first, "travel")
        XCTAssertEqual(TextTools.baseFormCandidates("travelling").first, "travel")
        XCTAssertEqual(TextTools.baseFormCandidates("cancelled").first, "cancel")
        XCTAssertEqual(TextTools.baseFormCandidates("controlled").first, "control")
        XCTAssertEqual(TextTools.baseFormCandidates("quarrelling").first, "quarrel")
        XCTAssertEqual(TextTools.baseFormCandidates("called"), ["call", "calle"], "one vowel group: as before")
        XCTAssertEqual(TextTools.baseFormCandidates("filled"), ["fill", "fille"])
    }

    func testWithoutItsSentenceAHomographLinksOnlyToASharedBase() {
        XCTAssertTrue(TextTools.baseFormCandidates("left").isEmpty)
        XCTAssertTrue(TextTools.baseFormCandidates("leaves").isEmpty)
        XCTAssertTrue(TextTools.baseFormCandidates("found").isEmpty)
        XCTAssertEqual(TextTools.baseFormCandidates("tears"), ["tear"])
        XCTAssertEqual(TextTools.matchKeys("left"), ["left"])
    }

    private func range(_ word: String, in text: String) -> WordRange {
        let ranges = TextTools.wordRanges(text).filter { TextTools.substring(text, $0) == word }
        XCTAssertFalse(ranges.isEmpty, "\(word) not in \(text)")
        return ranges.last ?? WordRange(0, 0)
    }

    func testInItsSentenceAHomographLinksToItsReading() {
        let she = "She left early."
        XCTAssertEqual(TextTools.baseFormCandidates(in: she, at: range("left", in: she)), ["leave"])
        XCTAssertEqual(TextTools.matchKeys(in: she, at: range("left", in: she)), ["leave"], "a saved \"left\" (the side) is not marked")
        let turn = "Turn left here."
        XCTAssertTrue(TextTools.baseFormCandidates(in: turn, at: range("left", in: turn)).isEmpty)
        XCTAssertEqual(TextTools.matchKeys(in: turn, at: range("left", in: turn)), ["left"])
        let tears = "Tears fell."
        XCTAssertEqual(TextTools.matchKeys(in: tears, at: range("Tears", in: tears)), ["tears", "tear"], "unsure, one base")
        let leaves = "The dead leaves fell."
        XCTAssertEqual(TextTools.baseFormCandidates(in: leaves, at: range("leaves", in: leaves)), ["leaf"])
        let stolen = "It was stolen."
        XCTAssertEqual(TextTools.baseFormCandidates(in: stolen, at: range("stolen", in: stolen)), ["steal"])
        let drew = "I met Drew there."
        XCTAssertTrue(TextTools.baseFormCandidates(in: drew, at: range("Drew", in: drew)).isEmpty, "a name")
        let drawing = "Drew a line."
        XCTAssertEqual(TextTools.baseFormCandidates(in: drawing, at: range("Drew", in: drawing)), ["draw"])
        let animals = "All animals are equal."
        XCTAssertEqual(TextTools.matchKeys(in: animals, at: range("animals", in: animals)), TextTools.matchKeys("animals"))
        XCTAssertTrue(TextTools.matchKeys(in: animals, at: WordRange(4, 99)).isEmpty, "out of range")
        XCTAssertTrue(TextTools.baseFormCandidates(in: animals, at: WordRange(4, 4)).isEmpty, "empty")
    }

    /// A paragraph full of homographs and capitalised names, the worst case for reading words in
    /// their sentences: about `length` UTF-16 units.
    private func hostileParagraph(_ length: Int) -> String {
        let piece = "Rose left. Aunt Rose saw Drew and left, then Tom's leaves fell; they lay down. Left Felt Bound. "
        return String(String(repeating: piece, count: length / piece.count + 1).prefix(length))
    }

    func testAWholeParagraphIsReadInOnePass() {
        let text = hostileParagraph(TextTools.maxParagraph)
        let words = TextTools.wordRanges(text)
        let keys = TextTools.matchKeys(in: text, words: words)
        XCTAssertEqual(keys, words.map { TextTools.matchKeys(in: text, at: $0) }, "one pass gives what each word alone gives")
        XCTAssertEqual(TextTools.matchKeys(in: text, words: [WordRange(0, 4), WordRange(5, 999_999)]).last, Set<String>(),
                       "a range outside the text links nothing")
    }

    /// Linear time: ten times the text must not take a hundred times as long (it did when every
    /// word tokenized the whole paragraph again), and the reader's longest paragraph stays fast.
    func testReadingAParagraphTakesLinearTime() {
        func seconds(_ length: Int) -> Double {
            let text = hostileParagraph(length)
            let words = TextTools.wordRanges(text)
            let start = Date()
            _ = TextTools.matchKeys(in: text, words: words)
            _ = TextTools.occurrences(of: "leave", in: text)
            return Date().timeIntervalSince(start)
        }
        _ = seconds(500)  // warm up the shared table
        let short = seconds(TextTools.maxParagraph)
        let long = seconds(TextTools.maxParagraph * 10)
        XCTAssertLessThan(short, 0.5, "a 2000-unit paragraph took \(short) s")
        XCTAssertLessThan(long, max(short, 0.005) * 30, "10× the text took \(long / max(short, 0.005))× as long")
    }

    func testOccurrencesReadEachFormInTheSentence() {
        let sentence = "Turn left, then she left."
        let found = TextTools.occurrences(of: "leave", in: sentence)
        XCTAssertEqual(found, [range("left", in: sentence)], "only the verb")
        XCTAssertEqual(TextTools.occurrences(of: "left", in: sentence).count, 1, "only the side")
        let stolen = "He stole it; it was stolen."
        XCTAssertEqual(TextTools.occurrences(of: "steal", in: stolen).map { TextTools.substring(stolen, $0) }, ["stole", "stolen"])
        let travel = "We travelled far."
        XCTAssertEqual(TextTools.occurrences(of: "travel", in: travel).map { TextTools.substring(travel, $0) }, ["travelled"])
    }
}

final class LearningTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    func testCorrectAnswerMovesToTheNextBox() {
        let now = date("2026-10-09T08:00:00Z")
        XCTAssertEqual(Srs.review(box: 0, correct: true, now: now, calendar: calendar),
                       SrsResult(box: 1, nextReview: date("2026-10-10T04:00:00Z"), learned: false), "due from the start (04:00) of the next day")
    }

    func testReviewDaysStartAtFourInTheMorning() {
        XCTAssertEqual(Srs.startOfDay(1, after: date("2026-10-09T23:50:00Z"), calendar: calendar), date("2026-10-10T04:00:00Z"))
        XCTAssertEqual(Srs.startOfDay(1, after: date("2026-10-10T01:00:00Z"), calendar: calendar), date("2026-10-10T04:00:00Z"),
                       "01:00 still belongs to the day before")
        XCTAssertEqual(Srs.startOfDay(1, after: date("2026-10-10T04:00:00Z"), calendar: calendar), date("2026-10-11T04:00:00Z"))
    }

    func testWrongAnswerResets() {
        let now = date("2026-10-09T08:00:00Z")
        XCTAssertEqual(Srs.review(box: 3, correct: false, now: now, calendar: calendar), SrsResult(box: 0, nextReview: now, learned: false))
    }

    func testLastBoxMarksTheWordLearned() {
        XCTAssertTrue(Srs.review(box: Srs.intervals.count, correct: true, now: Date(), calendar: calendar).learned)
    }

    func testStreakCountsConsecutiveDays() {
        let log = ["2026-10-07": 600, "2026-10-08": 900, "2026-10-09": 600]
        XCTAssertEqual(readingStreak(log, goalSeconds: 600, today: date("2026-10-09T12:00:00Z"), calendar: calendar), 3)
    }

    func testUnfinishedTodayKeepsYesterdaysStreak() {
        let log = ["2026-10-07": 600, "2026-10-08": 600, "2026-10-09": 60]
        XCTAssertEqual(readingStreak(log, goalSeconds: 600, today: date("2026-10-09T12:00:00Z"), calendar: calendar), 2)
    }

    func testAGapBreaksTheStreakAndMonthsRollOver() {
        XCTAssertEqual(readingStreak(["2026-10-06": 600, "2026-10-08": 600], goalSeconds: 600,
                                     today: date("2026-10-09T12:00:00Z"), calendar: calendar), 1)
        XCTAssertEqual(readingStreak(["2026-09-30": 600, "2026-10-01": 600], goalSeconds: 600,
                                     today: date("2026-10-01T12:00:00Z"), calendar: calendar), 2)
    }
}

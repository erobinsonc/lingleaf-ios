#if DEBUG
import LingleafCore

/// UI tests and the screen tour only (debug builds, launch arguments): a story and saved words for
/// the screens of unsure readings, senses, expressions, corrections and Review (SPEC S3, S4, S7, S18).
extension Library {
    /// A short story with an unsure "left" ("Some left early.") and the expression "bound for".
    private static let testStory = """
    Some left early. The ship was bound for Spain.

    The wind blew all night.
    """

    func seedForUITests(_ arguments: [String], offline: Bool) {
        let spanish: (String) -> String? = { offline ? nil : $0 }
        if arguments.contains("-ui-testing-tour") {
            addBook(title: "Test Story", author: "Lingleaf", text: Self.testStory, level: "A1")
            // One spelling saved as two senses: Words shows "the wind" and "to wind".
            saveWord("wind", learned: false, translation: spanish("viento"), translationLanguage: "es",
                     context: "The wind blew all night.", sense: Sense.noun)
            saveWord("wind", learned: false, translation: spanish("enrollar, dar cuerda"), translationLanguage: "es",
                     context: "She wound the clock.", sense: Sense.verb)
        }
        if arguments.contains("-ui-testing-due-lie") {
            // A verb with a regular twin: Review's prompt shows its sentence (S7).
            saveWord("lie", learned: false, translation: "estar acostado, tumbarse", translationLanguage: "es",
                     context: "The cat likes to lie in the sun.", sense: Sense.verb)
            answerReview("lie", sense: Sense.verb, correct: false)
        }
        if arguments.contains("-ui-testing-due-unsure") {
            // Saved while its sentence didn't tell: Review shows both readings (S7).
            let meanings = [
                SavedMeaning(label: "to leave", sense: Sense.verb, base: "leave", text: "irse, salir", language: "es"),
                SavedMeaning(label: "the left", sense: Sense.noun, base: "left", text: "izquierda", language: "es"),
            ]
            saveWord("left", learned: false, translation: "irse, salir · izquierda", translationLanguage: "es",
                     context: "Some left early.", form: "left", formRange: WordRange(5, 9), meanings: meanings)
            answerReview("left", correct: false)
        }
        // Words saved before the table read their sentences: corrected once the app starts (S18).
        let old = [
            ("leave", "Turn left at the bank."), ("life", "Tom lives in a small house."), ("feel", "She wore a felt hat."),
            ("think", "They found it, the old thought."), ("wound", "She wound the clock."),
        ]
        let count = arguments.contains("-ui-testing-corrections-5") ? 5 : arguments.contains("-ui-testing-corrections-1") ? 1 : 0
        for (word, context) in old.prefix(count) {
            saveWord(word, learned: false, translation: spanish("ES: \(word)"), translationLanguage: "es", context: context)
        }
    }
}
#endif

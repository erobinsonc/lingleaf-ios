import SwiftUI
import LingleafCore

/// Where a push in the Grammar tab goes.
enum GrammarRoute: Hashable {
    case rule(String)
    case category(String)
}

/// Every content text of Grammar (a rule line, an example, a form) goes through here with the language it is
/// written in, so the system can read it in that language: English sentences and forms are "en" even on a
/// Spanish page, the Spanish rule text and translations are "es" (SPEC S21; PR2-DESIGN-v4.1 §2.6).
/// The way SwiftUI exposes a speech language is an exit criterion of the PR (a device spike): until then the
/// language is the text's locale, and this is the one place to change.
struct LangText: View {
    let text: String
    let language: String

    init(_ text: String, language: String) {
        self.text = text
        self.language = language
    }

    var body: some View {
        Text(verbatim: text).environment(\.locale, Locale(identifier: language))
    }
}

/// The words of Grammar that depend on a level or a state, in the language of the interface.
enum GrammarLabels {
    /// "A1" -> "Beginner" ...
    static func levelName(_ level: String) -> String {
        switch level {
        case "A1": String(localized: "Beginner")
        case "A2": String(localized: "Elementary")
        case "B1": String(localized: "Intermediate")
        case "B2": String(localized: "Upper intermediate")
        case "C1": String(localized: "Advanced")
        case "C2": String(localized: "Proficient")
        default: level
        }
    }

    /// "A1 · Beginner" (shown).
    static func level(_ level: String) -> String { "\(level) · \(levelName(level))" }

    /// "A1, Beginner" (read by VoiceOver: commas, no dot).
    static func levelSpoken(_ level: String) -> String { "\(level), \(levelName(level))" }

    /// What a screen reader says for a rule's state; the list draws nothing for New.
    static func state(_ state: RuleState) -> String {
        switch state {
        case .new: String(localized: "New")
        case .practised: String(localized: "Practiced")
        case .inReview: String(localized: "In Review")
        }
    }

    static func ruleCount(_ count: Int) -> String { String(localized: "\(count) rules") }
}

extension AppModel {
    /// The interface language the app runs in ("en" or "es"; any other falls back to English as the catalog does).
    var interfaceLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The language of the rule text: the learner's choice, else the default (SPEC S21).
    var grammarLanguage: GrammarLanguage {
        GrammarLanguage.effective(
            setting: state.settings.grammarInSpanish, translationLanguage: targetLanguage, interfaceLanguage: interfaceLanguage
        )
    }

    /// An item with a Spanish text is drawn only for a learner whose translation or interface language is Spanish.
    var spanishEligible: Bool { targetLanguage == "es" || interfaceLanguage == "es" }

    /// The language of titles and chrome that exist in both languages (the interface's).
    var chromeLanguage: String { interfaceLanguage == "es" ? "es" : "en" }
}

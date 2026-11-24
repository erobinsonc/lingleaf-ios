import Foundation

/// The language of the rule text (SPEC.md S21, Grammar rules data, "Language of the rule text"): the effective
/// value `es` or `en` of the one setting `grammarInSpanish`, an optional boolean.
public enum GrammarLanguage: String, Sendable {
    case en, es

    /// The settings key (`UserDefaults`). Only a real boolean counts; the rest reads as absent.
    public static let settingKey = "grammarInSpanish"

    /// `setting` is what the settings store holds for `grammarInSpanish`, as read (`UserDefaults.object(forKey:)`),
    /// or nil. Only a real boolean counts (not an NSNumber 1 or 0, a string, a decimal, null, an array, an object):
    /// true is `es`, false is `en`. Absent: `es` when the translation language is Spanish and the interface is
    /// English, else the interface language (`es` or `en`), and `en` for any other interface language. Language
    /// codes may carry a region ("es-419", "pt_BR"): only the language part counts.
    public static func effective(setting: Any?, translationLanguage: String?, interfaceLanguage: String) -> GrammarLanguage {
        if let chosen = boolean(setting) { return chosen ? .es : .en }
        let interface = code(interfaceLanguage)
        if interface == "es" { return .es }
        if interface == "en" { return translationLanguage.map(code) == "es" ? .es : .en }
        return .en
    }

    /// What the learner chose, to store: "Español" is true, "English" is false (and never absent again).
    public var stored: Bool { self == .es }

    /// A Boolean and nothing else. On Apple platforms a Boolean read from `UserDefaults` is an `NSNumber` that
    /// `as? Bool` would also accept for 1 and 0, so the number's own type decides.
    static func boolean(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        #if canImport(Darwin)
        if let number = value as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() ? number.boolValue : nil }
        return nil
        #else
        if type(of: value) == Bool.self { return value as? Bool }
        return nil
        #endif
    }

    private static func code(_ language: String) -> String {
        String(language.lowercased().prefix { $0 != "-" && $0 != "_" })
    }
}

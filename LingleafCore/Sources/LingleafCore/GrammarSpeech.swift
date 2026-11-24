import Foundation

/// A text to say and the language to say it in (a BCP 47 tag).
public struct SpokenText: Equatable, Sendable {
    public let text: String
    public let language: String
}

/// The slots of an irregular verb, as the table names them (`spokenAs`, `ipa`).
public enum VerbFormSlot: String, CaseIterable, Sendable {
    case base, past, participle, ing, s
}

/// What the voice says for Grammar (SPEC.md, Grammar rules data, "Speech"): always English, whatever the interface
/// language; the Spanish translation is never spoken by these.
public enum GrammarSpeech {
    public static let language = "en"

    /// The forms of a slot as written: one, or two for a slot with two forms ("learned", "learnt").
    public static func forms(of verb: IrregularVerb, slot: VerbFormSlot) -> [String] {
        switch slot {
        case .base: [verb.base]
        case .past: verb.past
        case .participle: verb.participle
        case .ing: [verb.ing]
        case .s: [verb.s]
        }
    }

    /// The form of a slot as the voice should say it: the table's `spokenAs` for that slot when it has one (for
    /// index 0 only, the first form of a slot with two forms), else the form as written. An index past the slot's
    /// forms gives nothing.
    public static func verbForm(_ verb: IrregularVerb, slot: VerbFormSlot, index: Int = 0) -> SpokenText? {
        let all = forms(of: verb, slot: slot)
        guard all.indices.contains(index) else { return nil }
        return SpokenText(text: index == 0 ? verb.spokenAs[slot.rawValue] ?? all[0] : all[index], language: language)
    }

    /// The three forms, first form of each slot: "take. took. taken." (the full stops are the pauses).
    public static func verbForms(_ verb: IrregularVerb) -> SpokenText {
        let parts = [VerbFormSlot.base, .past, .participle].compactMap { verbForm(verb, slot: $0)?.text }
        return SpokenText(text: parts.joined(separator: ". ") + ".", language: language)
    }

    /// An example sentence, as written (English).
    public static func example(_ sentence: String) -> SpokenText { SpokenText(text: sentence, language: language) }
}

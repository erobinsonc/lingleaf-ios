import SwiftUI
import LingleafCore

/// The word card for a word of a bundled story that has an entry (SPEC S19): the story's own sense
/// comes before the verb-or-noun rule.
extension WordCardView {
    /// The story's sense for the tapped word (SPEC S19), which comes before the verb-or-noun rule.
    var story: StorySenseHit? { selection.story }
    var storySense: StorySense? { selection.story?.sense }

    /// The card's language is Spanish: the story's meanings are in it.
    var isSpanish: Bool { ReadingTranslation.isSpanish(model.targetLanguage) }

    /// How the voice is told to say a story sense's word: its IPA (one word only).
    var spokenIPA: String? {
        storySense.flatMap { $0.speaksIPA ? $0.ipa : nil }
    }

    /// A story sense's meaning (SPEC S19): the file's, in Spanish; in another language the translation of
    /// the group or base form once it is there; none for a name.
    func storyTranslation(_ story: StorySenseHit) -> String? {
        if story.sense.kind == .name { return nil }
        if isSpanish { return story.sense.spanish }
        return story.translationSource.flatMap { translations[TextTools.normalize($0)] }
    }

    /// "In the text: …" adds nothing on a name, or when the headword holds the tapped word ("go red" / "red").
    var storyShowsTheWord: Bool {
        guard let story else { return false }
        return story.sense.kind == .name || story.sense.lemma.lowercased().contains(selection.word.lowercased())
    }

    /// A name, or a word from another language outside Spanish, has no meaning on the card.
    var storyHasNoMeaning: Bool {
        guard let story else { return false }
        return !isSpanish && story.translationSource == nil || story.sense.kind == .name
    }

    /// Save and I know it are for words and groups, not for names and words from another language.
    var storyAllowsSave: Bool {
        guard let kind = story?.sense.kind else { return true }
        return kind == .word || kind == .chunk
    }

    /// The small label under the headword: "Name", "Word from another language", "US English"…
    var storyLabel: Text? {
        guard let label = story?.label else { return nil }
        switch label {
        case .name: return Text("Proper name")
        case .foreign: return Text("Word from another language")
        case .american: return Text("US English")
        case .british: return Text("UK English")
        case .local: return Text("Local English")
        }
    }

    /// The group of words the tapped word belongs to, with its meaning on one line (Spanish), as it is in the story.
    var storyGroupLine: String? {
        guard let story, let group = story.group else { return nil }
        // The group is the headword already ("The Blue Table").
        if group.text.caseInsensitiveCompare(story.sense.lemma) == .orderedSame { return nil }
        return isSpanish && story.sense.kind != .name ? "\(group.text) — \(group.spanish)" : group.text
    }

    /// A story sense's remarks and definition (SPEC S19): what a name is and the note, in Spanish, then the
    /// dictionary's definition when it has one of the sense's part of speech, else none.
    @ViewBuilder
    var storyDefinition: some View {
        if isSpanish, let sense = storySense {
            if sense.kind == .name { storyRemark(sense.spanish) }
            if let note = sense.note { storyRemark(note) }
        }
        if let entry = storyEntry, let definition = entry.definition { definitionText(entry, definition) }
    }

    func storyRemark(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Brand.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

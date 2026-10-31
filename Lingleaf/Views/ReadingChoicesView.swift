import SwiftUI
import LingleafCore

/// The two readings of a word whose sentence doesn't tell (SPEC S3), as a single choice with none
/// chosen: "to leave — irse, salir", "the left — izquierda". The guide line above says where the
/// answer is: the sentence's translation, or asks when there is none.
struct ReadingChoicesView: View {
    let choices: [ReadingChoice]
    @Binding var chosen: ReadingChoice?
    /// Each reading's meaning by `ReadingChoice.id`, in `language`; missing while translating or offline.
    let meanings: [String: String]
    let language: String?
    /// Translating meanwhile: a small progress indicator stands in for a missing meaning.
    let translating: Bool
    /// The sentence's translation shows or is on its way, so it can tell which reading it is;
    /// offline, failed or with no language yet the guide asks instead.
    let sentenceTells: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if sentenceTells {
                    Text("The sentence's translation tells you which one:")
                } else {
                    Text("Which one is it in this sentence?")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Brand.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(choices) { choice in
                row(choice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ choice: ReadingChoice) -> some View {
        let isChosen = chosen == choice
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button {
            chosen = choice
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? Color.accentColor : Brand.secondaryText)
                    .accessibilityHidden(true)
                content(choice)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isChosen ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(choice))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// "to leave — irse, salir"; at accessibility sizes the meaning on its own line.
    @ViewBuilder
    private func content(_ choice: ReadingChoice) -> some View {
        let label = Text(verbatim: choice.label).font(.body.weight(.semibold))
        if let text = meaning(choice) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    label
                    Text(text).foregroundStyle(Brand.secondaryText)
                }
            } else {
                (label + Text(verbatim: " — ") + Text(text).foregroundStyle(Brand.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: 8) {
                label
                if translating { ProgressView().controlSize(.small).accessibilityLabel(Text("Translating…")) }
            }
        }
    }

    /// The meaning in its own language (so VoiceOver reads it with that voice), isolated from the
    /// English around it so a right-to-left language keeps its order.
    private func meaning(_ choice: ReadingChoice) -> AttributedString? {
        guard let text = meanings[choice.id], !text.isEmpty else { return nil }
        return Self.meaningText(text, language: language)
    }

    /// A meaning in `language`, tagged with it (VoiceOver reads it with that voice) and, among
    /// English, isolated, each meaning of "irse · izquierda" on its own (a right-to-left language
    /// keeps its order). Empty stays empty.
    static func meaningText(_ text: String, language: String?, isolated: Bool = true) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        let shown = isolated ? text.components(separatedBy: " · ").map { "\u{2068}\($0)\u{2069}" }.joined(separator: " · ") : text
        var meaning = AttributedString(shown)
        if let language { meaning.languageIdentifier = language }
        return meaning
    }

    /// "to leave, irse, salir".
    private func accessibilityLabel(_ choice: ReadingChoice) -> Text {
        guard let text = meaning(choice) else { return Text(verbatim: choice.label) }
        return Text(verbatim: "\(choice.label), ") + Text(text)
    }
}

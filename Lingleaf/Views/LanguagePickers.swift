import SwiftUI
import LingleafCore

/// Small button under the translation ("Português ˅") that changes the language in place.
/// iOS 26: a system glass capsule, legible on the glass card; earlier: a grey capsule.
struct LanguageMenu: View {
    let current: String
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            LanguageButtons()
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: AppModel.languageName(current))
                Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
            }
            .font(.footnote)
            .padding(.horizontal, WordCardView.hasGlass ? 0 : 12)
            .padding(.vertical, WordCardView.hasGlass ? 0 : 6)
            .background(WordCardView.hasGlass ? Color.clear : Color(uiColor: .tertiarySystemFill), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .modifier(GlassButtonStyle())
        .controlSize(.small)
        .tint(.primary)
        // The language name keeps its own language so VoiceOver reads it with the right voice.
        .accessibilityLabel(Text("Translation language: \(AppModel.languageLabel(current))"))
    }
}

/// Shown where the translation goes while no language is set; the rest of the card works meanwhile.
struct LanguageChooser: View {
    @Environment(AppModel.self) private var model

    /// Languages offered when none is set: the region's language first, then the usual ones.
    private static var suggestedLanguages: [String] {
        TranslationLanguages.suggestions(region: Locale.current.region?.identifier, supported: AppModel.translationLanguages)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Translate into:")
                .font(.subheadline)
                .foregroundStyle(Brand.secondaryText)
            FlowLayout(spacing: 8) {
                ForEach(Self.suggestedLanguages, id: \.self) { code in
                    Button {
                        model.setTargetLanguage(code)
                    } label: {
                        chip(Text(AppModel.languageLabel(code)))
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    LanguageButtons()
                } label: {
                    chip(Text("More languages"))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ label: Text) -> some View {
        label
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(Brand.secondaryText, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Every supported language, each named in its own language.
private struct LanguageButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(AppModel.translationLanguages, id: \.self) { code in
            Button {
                model.setTargetLanguage(code)
            } label: {
                Text(AppModel.languageLabel(code))
            }
        }
    }
}

import SwiftUI
import LingleafCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    private static let repositoryURL = URL(string: "https://github.com/erobinsonc/lingleaf-ios")!

    var body: some View {
        let settings = model.state.settings
        NavigationStack {
            Form {
                Section(header: SectionHeader("Daily goal")) {
                    Stepper(
                        "\(settings.dailyGoalMinutes) minutes a day",
                        value: binding(\.dailyGoalMinutes),
                        in: 5...60,
                        step: 5
                    )
                }

                Section(header: SectionHeader("Reading")) {
                    Slider(value: binding(\.fontSize), in: 14...34, step: 2) {
                        Text("Text size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(Brand.secondaryText).accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger").foregroundStyle(Brand.secondaryText).accessibilityHidden(true)
                    }
                    Text(verbatim: "All animals are equal.").font(readingFont(size: settings.fontSize))
                }

                Section {
                    Slider(value: binding(\.speechRate), in: 0.3...0.6) {
                        Text("Speech speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").foregroundStyle(Brand.secondaryText).accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "hare").foregroundStyle(Brand.secondaryText).accessibilityHidden(true)
                    }
                    Button("Test the voice", systemImage: "speaker.wave.2") {
                        model.speaker.speak("Reading ten minutes a day makes a big difference.", rate: settings.speechRate)
                    }
                } header: {
                    SectionHeader("Voice")
                }

                Section {
                    Picker("Translate into", selection: Binding<String?>(
                        get: { model.targetLanguage },
                        set: { code in
                            if let code { model.setTargetLanguage(code) }
                        }
                    )) {
                        // Until a language is chosen (or picked from the device), the word card asks.
                        if model.targetLanguage == nil {
                            Text("Ask me when I tap a word").tag(String?.none)
                        }
                        ForEach(AppModel.translationLanguages, id: \.self) { code in
                            Text(AppModel.languageLabel(code)).tag(String?.some(code))
                        }
                    }
                    // A row rather than a section footer: footers use a fixed style
                    // that fails the contrast and Dynamic Type audits.
                    Text("Translation happens on your iPhone. The first time, iOS asks to download the language; after that it works offline.")
                        .font(.footnote)
                        .foregroundStyle(Brand.secondaryText)
                } header: {
                    SectionHeader("Translation")
                }

                Section(header: SectionHeader("About")) {
                    Link(destination: Credits.privacyPolicyURL) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    Link(destination: Self.repositoryURL) {
                        Label("Source code (open source, MIT)", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No accounts, no ads, no tracking.")
                        Text(Credits.publicDomainNotice)
                        Text(Credits.definitionsCredit)
                            .accessibilityHint(Text("Contains links"))
                    }
                    .font(.footnote)
                    .foregroundStyle(Brand.secondaryText)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LingleafCore.Settings, Value>) -> Binding<Value> {
        Binding(
            get: { model.state.settings[keyPath: keyPath] },
            set: { value in model.library.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

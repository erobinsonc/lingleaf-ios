import SwiftUI
import Translation
import LingleafCore

/// The card shown when a word is tapped: pronunciation, translation (with its
/// language), definition, the sentence in context, and I know it / Save word.
struct WordCardView: View {
    let selection: WordSelection
    let source: String
    /// Called when a button changed the word, just before the card closes, with
    /// the message (and its Undo) the reader shows.
    let onAction: (UndoMessage) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var entry: DictionaryEntry?
    @State private var entryLoaded = false
    @State private var lookup: Task<DictionaryEntry?, Never>?
    /// Translations by normalized source text: the tapped form and, when the
    /// dictionary gives a different one, the base form ("animals", "animal").
    @State private var translations: [String: String] = [:]
    /// The language `translations` and `sentenceTranslation` are in.
    @State private var translatedInto: String?
    @State private var sentenceTranslation: String?
    @State private var translationFailed = false
    @State private var configuration: TranslationSession.Configuration?

    /// The dictionary's base form ("animal") when it differs from the tapped word ("animals").
    private var headword: String {
        guard let base = entry?.word, base != TextTools.normalize(selection.word) else { return selection.word }
        return base
    }

    /// The base form's translation, else the tapped form's while the base form's is on its way.
    private var translation: String? {
        translations[TextTools.normalize(headword)] ?? translations[TextTools.normalize(selection.word)]
    }

    /// Languages offered when none is set: the region's language first, then the usual ones.
    private static var suggestedLanguages: [String] {
        TranslationLanguages.suggestions(region: Locale.current.region?.identifier, supported: AppModel.translationLanguages)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    header
                    translationView
                    if let definition = entry?.definition {
                        Text("\(Text(entry?.partOfSpeech ?? "").italic()) · \(definition)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else if entryLoaded {
                        Text("No definition available.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical, 4)
                    contextView
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            actions
        }
        .translationTask(configuration) { session in
            await translate(using: session)
        }
        .task { await load() }
        // A language chosen on this card (or changed with its menu) translates in place.
        .onChange(of: model.targetLanguage) { _, _ in
            startTranslation()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    model.speaker.speak(headword, rate: model.state.settings.speechRate)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.largeTitle)
                }
                Text(headword).font(.largeTitle.weight(.semibold))
            }
            if let phonetic = entry?.phonetic {
                Text(phonetic).font(.title3).foregroundStyle(.secondary)
            }
            if headword != selection.word {
                Text("In the text: \(selection.word)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Translation

    @ViewBuilder
    private var translationView: some View {
        if let target = model.targetLanguage {
            VStack(spacing: 4) {
                if let translation {
                    Text(translation).font(.title2).multilineTextAlignment(.center)
                } else if translationFailed {
                    Text("Translation unavailable. Connect to the internet once to download the language.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }
                languageMenu(target)
            }
        } else {
            languageChooser
        }
    }

    /// Small button under the translation ("Português ˅") that changes the language in place.
    /// iOS 26: a system glass capsule, legible on the glass card; earlier: a grey capsule.
    private func languageMenu(_ current: String) -> some View {
        Menu {
            languageButtons
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: AppModel.languageName(current))
                Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
            }
            .font(.footnote)
            .padding(.horizontal, Self.hasGlass ? 0 : 12)
            .padding(.vertical, Self.hasGlass ? 0 : 6)
            .background(Self.hasGlass ? Color.clear : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .menuStyle(.button)
        .modifier(GlassButtonStyle())
        .controlSize(.small)
        .tint(.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        // The language name keeps its own language so VoiceOver reads it with the right voice.
        .accessibilityLabel(Text("Translation language: \(AppModel.languageLabel(current))"))
    }

    /// Shown where the translation goes while no language is set; the rest of the card works meanwhile.
    private var languageChooser: some View {
        VStack(spacing: 8) {
            Text("Translate into:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                    languageButtons
                } label: {
                    chip(Text("More languages"))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Every supported language, each named in its own language.
    private var languageButtons: some View {
        ForEach(AppModel.translationLanguages, id: \.self) { code in
            Button {
                model.setTargetLanguage(code)
            } label: {
                Text(AppModel.languageLabel(code))
            }
        }
    }

    private func chip(_ label: Text) -> some View {
        label
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(.secondary, lineWidth: 1))
            .contentShape(Capsule())
    }

    private var contextView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selection.sentence).font(readingFont(size: 17)).italic()
                    .fixedSize(horizontal: false, vertical: true)
                if let sentenceTranslation {
                    Text(sentenceTranslation).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.speaker.speak(selection.sentence, rate: model.state.settings.speechRate)
            } label: {
                Label("Listen to the sentence", systemImage: "speaker.wave.1")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    /// [I know it] [Save word]; the button matching the saved state is checked
    /// and tapping it removes the word.
    private var actions: some View {
        let saved = model.state.word(headword)
        let known = saved?.learned == true
        let learning = saved?.learned == false
        return HStack(spacing: 12) {
            if known {
                actionButton("I know it", checked: true, primary: false) { remove() }
            } else {
                actionButton("I know it", checked: false, primary: false) { save(learned: true) }
            }
            if learning {
                actionButton("Saved", checked: true, primary: true) { remove() }
            } else {
                actionButton("Save word", checked: false, primary: true) { save(learned: false) }
            }
        }
        .padding(16)
    }

    /// Primary: the yellow marker that underlines saved words, black text, opaque on any
    /// backdrop. Secondary: the system glass button on iOS 26, a neutral tonal one before.
    /// A checked button shows ✓, has the selected trait and
    /// a hint saying that tapping it removes the word.
    private func actionButton(
        _ title: LocalizedStringKey, checked: Bool, primary: Bool, action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let background = primary ? Brand.marker : Self.hasGlass ? Color.clear : Color(uiColor: .secondarySystemFill)
        return Button(action: action) {
            HStack(spacing: 6) {
                if checked {
                    Image(systemName: "checkmark").fontWeight(.bold).accessibilityHidden(true)
                }
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.headline)
            .foregroundStyle(primary ? Color.black : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(background, in: shape)
            .contentShape(shape)
        }
        .modifier(GlassButtonStyle(enabled: !primary))
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityHint(checked ? Text("Remove from Words") : Text(verbatim: ""))
    }

    private func save(learned: Bool) {
        let word = headword
        let translation = translations[TextTools.normalize(word)]
        let previous = model.library.saveWord(
            word,
            learned: learned,
            translation: translation,
            translationLanguage: translatedInto,
            phonetic: entry?.phonetic,
            context: selection.sentence,
            source: source
        )
        // Saving never waits: a translation still on its way is done by TranslationWorker.
        if translation == nil { model.translateMissing() }
        if learned {
            finish(String(localized: "“\(word)” marked as known"), word: word, previous: previous)
        } else {
            finish(String(localized: "“\(word)” saved to Words"), word: word, previous: previous)
        }
    }

    /// Tapping a checked button: the word leaves Words (Undo puts it back as it was).
    private func remove() {
        let word = headword
        let key = TextTools.normalize(word)
        let previous = model.state.word(key)
        model.library.deleteWord(key)
        finish(String(localized: "“\(word)” removed from Words"), word: word, previous: previous)
    }

    private func finish(_ text: String, word: String, previous: VocabWord?) {
        let library = model.library
        onAction(UndoMessage(text: text, seconds: 4) {
            library.restoreWord(word, previous: previous)
        })
        dismiss()
    }

    // MARK: Loading

    /// The dictionary lookup and the translation start together.
    private func load() async {
        let dictionary = model.dictionary
        let word = selection.word
        let task = Task { await dictionary.lookup(word) }
        lookup = task
        startTranslation()
        entry = await task.value
        entryLoaded = true
        // The base form needs its own translation ("animals" → "animal").
        if headword != selection.word, let fake = model.fakeTranslator, translatedInto != nil, !translationFailed {
            translations[TextTools.normalize(headword)] = try? fake(headword)
        }
    }

    /// (Re)translates the word and the sentence into the current language; with
    /// none set, the card asks instead.
    private func startTranslation() {
        translations = [:]
        sentenceTranslation = nil
        translationFailed = false
        translatedInto = model.targetLanguage
        guard let target = model.targetLanguage else {
            configuration = nil
            return
        }
        if let fake = model.fakeTranslator {
            var texts = [selection.word]
            if entryLoaded, headword != selection.word { texts.append(headword) }
            do {
                for text in texts { translations[TextTools.normalize(text)] = try fake(text) }
                sentenceTranslation = try fake(selection.sentence)
            } catch {
                translationFailed = true
            }
            return
        }
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: target)
        )
    }

    /// Runs in `.translationTask`: the tapped word and the sentence first, then the
    /// base form once the dictionary has given one that differs.
    private func translate(using session: TranslationSession) async {
        guard let target = translatedInto else { return }
        let tapped = TextTools.normalize(selection.word)
        do {
            let responses = try await session.translations(from: [
                TranslationSession.Request(sourceText: selection.word, clientIdentifier: "word"),
                TranslationSession.Request(sourceText: selection.sentence, clientIdentifier: "sentence"),
            ])
            // The language changed meanwhile: a newer run translates again.
            guard translatedInto == target else { return }
            for response in responses {
                if response.clientIdentifier == "sentence" {
                    sentenceTranslation = response.targetText
                } else {
                    translations[tapped] = response.targetText
                }
            }
            let looked: DictionaryEntry? = await lookup?.value
            guard let base = looked.map({ TextTools.normalize($0.word) }), base != tapped else { return }
            let response = try await session.translate(base)
            if translatedInto == target { translations[base] = response.targetText }
        } catch {
            if translatedInto == target, translation == nil { translationFailed = true }
        }
    }
}

extension WordCardView {
    /// Whether the system glass button style exists (iOS 26 and later).
    static var hasGlass: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }
}

/// The card sits on the iOS 26 glass sheet: its secondary buttons use the system glass
/// style, which keeps labels legible on it. Elsewhere, and before iOS 26, plain buttons
/// that draw their own background.
private struct GlassButtonStyle: ViewModifier {
    var enabled = true

    func body(content: Content) -> some View {
        if #available(iOS 26, *), enabled {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

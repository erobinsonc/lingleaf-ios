import SwiftUI
import Translation
import LingleafCore

/// The card shown when a word is tapped: pronunciation, translation (with its
/// language), definition, the sentence in context, and I know it / Save word.
struct WordCardView: View {
    let selection: WordSelection
    let source: String
    /// The sheet is at its full height: iOS 26 then draws it opaque, so the card needs no panel of its own.
    var fullHeight = false
    /// Reads the book aloud from this sentence on; nil hides the button.
    var onReadFromHere: (() -> Void)?
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

    /// The dictionary's base form ("animal") when it differs from the tapped word ("animals");
    /// for a helper or modal verb, its own base form ("do" for "did").
    private var headword: String {
        if let function = selection.function { return function.base }
        guard let base = entry?.word, base != TextTools.normalize(selection.word) else { return selection.word }
        return base
    }

    /// The headword as a screen reader says it: "he had or he would", not "slash".
    private var spokenHeadword: String {
        let parts = headword.components(separatedBy: " / ")
        guard parts.count == 2 else { return headword }
        return String(localized: "\(parts[0]) or \(parts[1])")
    }

    /// The base form's translation, else the tapped form's while the base form's is on its way.
    /// A helper or modal verb means little alone ("did" → "hizo"): its verb group's translation.
    private var translation: String? {
        if selection.function != nil { return selection.chunk.flatMap { translations[TextTools.normalize($0)] } }
        return translations[TextTools.normalize(headword)] ?? translations[TextTools.normalize(selection.word)]
    }

    /// What Save stores: the word's base form, or a helper or modal verb's verb group (the
    /// whole sentence when it has none, so there's always something to recall and translate).
    private var savedKey: String {
        guard selection.function != nil else { return headword }
        return selection.chunk ?? selection.sentence
    }

    /// How messages name what was saved: "did not go"; without a verb group, the start of the sentence.
    private var savedName: String {
        guard selection.function != nil else { return headword }
        if let chunk = selection.chunk { return chunk }
        return selection.sentence.count > 30 ? String(selection.sentence.prefix(30)) + "…" : selection.sentence
    }

    /// What the card translates as "the word": the tapped word, or a helper or modal verb's
    /// verb group (nil when it has none: the sentence's translation explains it).
    private var wordSource: String? {
        selection.function == nil ? selection.word : selection.chunk
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
                    if let function = selection.function {
                        Text(function.note(form: selection.word))
                            .font(.footnote)
                            .foregroundStyle(Brand.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let definition = entry?.definition {
                        Text("\(Text(entry?.partOfSpeech ?? "").italic()) · \(definition)")
                            .font(.footnote)
                            .foregroundStyle(Brand.secondaryText)
                            .multilineTextAlignment(.center)
                    } else if entryLoaded {
                        Text("No definition available.").font(.footnote).foregroundStyle(Brand.secondaryText)
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
        // iOS 26: the sheet stays system glass at its edge, but the content sits on one opaque
        // panel so the book never shows through the text (glass is for controls, not content).
        // A UIKit colour on purpose: inside a glass sheet `.background` resolves to the glass.
        // Only at half height: at full height the sheet is opaque and a panel would frame a card in a card.
        .modifier(ContentPanel(enabled: !fullHeight))
        .translationTask(configuration) { session in
            await translate(using: session)
        }
        .task { await load() }
        // A language chosen on this card (or changed with its menu) translates in place.
        .onChange(of: model.targetLanguage) { _, _ in
            startTranslation()
        }
        // Inside the sheet: an alert from under it would not show.
        .noVoiceAlert(model.speaker)
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    // A helper or modal verb: how the verb group sounds ("didn't go", not "do").
                    let spoken = selection.function == nil ? headword : selection.chunk ?? selection.word
                    model.speaker.speak(spoken, rate: model.state.settings.speechRate)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.largeTitle)
                }
                Text(headword).font(.largeTitle.weight(.semibold))
                    .accessibilityLabel(Text(spokenHeadword))
                    .accessibilityAddTraits(.isHeader)
            }
            if selection.function == nil, let phonetic = entry?.phonetic {
                Text(phonetic).font(.title3).foregroundStyle(Brand.secondaryText)
            }
            // A helper or modal verb shows its form in the verb group just below.
            if selection.function == nil, TextTools.normalize(headword) != TextTools.normalize(selection.word) {
                Text("In the text: \(selection.word)").font(.caption).foregroundStyle(Brand.secondaryText)
            }
            if let label = selection.function?.kind.label {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.secondaryText)
            }
        }
    }

    // MARK: Translation

    @ViewBuilder
    private var translationView: some View {
        if let target = model.targetLanguage {
            VStack(spacing: 4) {
                // The verb group it belongs to, then its translation; not when it is just the
                // tapped word ("That's"), which the headword and note already explain.
                if let chunk = selection.chunk, chunk != selection.word {
                    Text(verbatim: chunk).font(.headline).multilineTextAlignment(.center)
                }
                if let translation {
                    Text(translation).font(.title2).multilineTextAlignment(.center)
                } else if wordSource == nil {
                    EmptyView()
                } else if translationFailed {
                    Text("Translation unavailable. Connect to the internet once to download the language.")
                        .font(.footnote)
                        .foregroundStyle(Brand.secondaryText)
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

    /// Shown where the translation goes while no language is set; the rest of the card works meanwhile.
    private var languageChooser: some View {
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
            .overlay(Capsule().stroke(Brand.secondaryText, lineWidth: 1))
            .contentShape(Capsule())
    }

    private var contextView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(markedSentence).font(readingFont(size: 17)).italic()
                    .fixedSize(horizontal: false, vertical: true)
                if let sentenceTranslation {
                    Text(sentenceTranslation).font(.callout).foregroundStyle(Brand.secondaryText)
                }
                if let onReadFromHere {
                    // Back to an earlier point, or on from this one (SPEC S6).
                    Button {
                        dismiss()
                        onReadFromHere()
                    } label: {
                        Label("Read from here", systemImage: "play.fill")
                            .font(.callout.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .tint(.primary)
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

    /// The sentence with the tapped word in bold and underlined, so it's clear which one it is.
    private var markedSentence: AttributedString {
        var text = AttributedString(selection.sentence)
        func attributed(_ range: WordRange?) -> Range<AttributedString.Index>? {
            guard let range, let stringRange = Range(range.nsRange, in: selection.sentence) else { return nil }
            return Range(stringRange, in: text)
        }
        // A helper or modal verb: the whole verb group underlined, the tapped word in bold.
        if let underlined = attributed(selection.function?.chunk ?? selection.rangeInSentence) {
            text[underlined].underlineStyle = Text.LineStyle.single
        }
        if let marked = attributed(selection.rangeInSentence) {
            text[marked].inlinePresentationIntent = .stronglyEmphasized
            text[marked].accessibilityTextCustom = [String(localized: "Selected")]
        }
        return text
    }

    // MARK: Actions

    /// [I know it] [Save word]; the button matching the saved state is checked
    /// and tapping it removes the word.
    private var actions: some View {
        let saved = model.state.word(savedKey)
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
        // Equal heights when one label wraps (e.g. "Guardar palabra" in Spanish).
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }

    /// Primary: the yellow marker that underlines saved words, black text (on iOS 26 the
    /// prominent glass button tinted with it). Secondary: the system glass button on iOS 26,
    /// a neutral tonal one before. Both share the system's button metrics on iOS 26.
    /// A checked button shows ✓, has the selected trait and
    /// a hint saying that tapping it removes the word.
    private func actionButton(
        _ title: LocalizedStringKey, checked: Bool, primary: Bool, action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let background = Self.hasGlass ? Color.clear : primary ? Brand.marker : Color(uiColor: .secondarySystemFill)
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
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: .infinity)
            .background(background, in: shape)
            .contentShape(shape)
        }
        .modifier(GlassButtonStyle(prominent: primary))
        .tint(primary ? Brand.marker : nil)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityHint(checked ? Text("Remove from Words") : Text(verbatim: ""))
    }

    private func save(learned: Bool) {
        let word = savedKey
        // Without a verb group, the sentence is what's saved: its translation goes with it.
        let translation = selection.function == nil
            ? translations[TextTools.normalize(word)]
            : selection.chunk == nil ? sentenceTranslation : self.translation
        let previous = model.library.saveWord(
            word,
            learned: learned,
            translation: translation,
            translationLanguage: translatedInto,
            phonetic: entry?.phonetic,
            context: selection.sentence,
            contextTranslation: sentenceTranslation,
            source: source,
            kind: selection.function?.kind,
            base: selection.function?.base
        )
        // Saving never waits: a translation still on its way is done by TranslationWorker.
        if translation == nil { model.translateMissing() }
        if learned {
            finish(String(localized: "“\(savedName)” marked as known"), word: word, previous: previous)
        } else {
            finish(String(localized: "“\(savedName)” saved to Words"), word: word, previous: previous)
        }
    }

    /// Tapping a checked button: the word leaves Words (Undo puts it back as it was).
    private func remove() {
        let word = savedKey
        let key = TextTools.normalize(word)
        let previous = model.state.word(key)
        model.library.deleteWord(key)
        finish(String(localized: "“\(savedName)” removed from Words"), word: word, previous: previous)
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
        // A helper or modal verb needs no dictionary: its definition and IPA would be the
        // base form's ("do"), not what the learner sees ("didn't go").
        let isFunction = selection.function != nil
        let task = Task { () -> DictionaryEntry? in
            if isFunction { return nil }
            return await dictionary.lookup(word)
        }
        lookup = task
        startTranslation()
        entry = await task.value
        entryLoaded = true
        // The base form needs its own translation ("animals" → "animal").
        if selection.function == nil, headword != selection.word, let fake = model.fakeTranslator, translatedInto != nil, !translationFailed {
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
            var texts = wordSource.map { [$0] } ?? []
            if selection.function == nil, entryLoaded, headword != selection.word { texts.append(headword) }
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
        let tapped = wordSource.map(TextTools.normalize)
        var requests = [TranslationSession.Request(sourceText: selection.sentence, clientIdentifier: "sentence")]
        if let wordSource { requests.insert(TranslationSession.Request(sourceText: wordSource, clientIdentifier: "word"), at: 0) }
        do {
            let responses = try await session.translations(from: requests)
            // The language changed meanwhile: a newer run translates again.
            guard translatedInto == target else { return }
            for response in responses {
                if response.clientIdentifier == "sentence" {
                    sentenceTranslation = response.targetText
                } else if let tapped {
                    translations[tapped] = response.targetText
                }
            }
            guard selection.function == nil, let tapped else { return }
            let looked: DictionaryEntry? = await lookup?.value
            guard let base = looked.map({ TextTools.normalize($0.word) }), base != tapped else { return }
            let response = try await session.translate(base)
            if translatedInto == target { translations[base] = response.targetText }
        } catch {
            if translatedInto == target, translation == nil { translationFailed = true }
        }
    }
}

extension FunctionWord.Kind {
    /// Nil for a contraction: the card's headword ("it is") already says what it is.
    var label: String? {
        switch self {
        case .helper: String(localized: "Helper verb")
        case .modal: String(localized: "Modal verb")
        case .contraction: nil
        }
    }
}

extension FunctionWord {
    /// One short line on what the word does here. `form` is the word as tapped ("did", "didn't").
    func note(form: String) -> String {
        // "I'll" keeps its capital I; other words are shown in lower case.
        let word = form.hasPrefix("I'") || form.hasPrefix("I’") ? form : form.lowercased()
        if let expansion { return contractionNote(word, expansion) }
        let contracted = TextTools.normalize(word).hasSuffix("n't")
        let negative = contracted ? word : "\(word) not"
        let expanded = Self.expanded[TextTools.normalize(word)] ?? negative
        // A perfect's helper as tapped, with "not" when it follows: "has not" for "has not seen".
        let shown = self.negative && !contracted ? "\(word) not" : word
        switch use {
        case .pastNegative where contracted:
            return String(localized: "“\(negative)” (= “\(expanded)”) + base verb = past negative: “didn't go”, not “didn't went”.")
        case .pastNegative:
            return String(localized: "“\(negative)” + base verb = past negative: “did not go”, not “did not went”.")
        case .presentNegative where contracted:
            return String(localized: "“\(negative)” (= “\(expanded)”) + base verb = present negative: “\(negative) like”, not “\(negative) likes”.")
        case .presentNegative:
            return String(localized: "“\(negative)” + base verb = present negative: “\(negative) like”, not “\(negative) likes”.")
        case .prohibition:
            return String(localized: "“\(negative)” + base verb tells someone not to do it: “Don't touch”.")
        case .questionTag:
            return String(localized: "“\(word)” + pronoun at the end asks the listener to agree, like “right?”.")
        case .pastQuestion:
            return String(localized: "“\(word)” starts a question about the past.")
        case .presentQuestion:
            return String(localized: "“\(word)” starts a question about the present.")
        case .modal(let base) where self.negative:
            // The meaning can flip: "must" = necessary, "mustn't" = not allowed.
            let shown = contracted || word == "cannot" ? word : "\(word) not"
            if base == "must" { return String(localized: "“\(shown)” + verb: it is not allowed.") }
            if contracted || word == "cannot" {
                // One argument for "can not", so the key matches the translated one.
                let full = "\(base) not"
                return String(localized: "“\(shown)” (= “\(full)”): the negative of “\(base)” + verb.")
            }
            return String(localized: "“\(shown)”: the negative of “\(base)” + verb.")
        case .modal(let base):
            return Self.modalNote(base)
        case .presentPerfect:
            return String(localized: "“\(shown)” + past participle: it happened before now and still matters: “seen”, not “saw”.")
        case .pastPerfect:
            return String(localized: "“\(shown)” + past participle: it happened before another past moment: “had left”.")
        case .hadBetter:
            return String(localized: "“had better” + verb: strong advice: “You'd better go”.")
        case .contraction:
            return String(localized: "“\(word)” = “\(base)”.")
        }
    }

    /// A pronoun contraction: what it stands for, and what it does when it is a helper here.
    private func contractionNote(_ word: String, _ expansion: String) -> String {
        switch use {
        case .presentPerfect:
            return String(localized: "“\(word)” (= “\(expansion)”) + past participle: it happened before now and still matters: “seen”, not “saw”.")
        case .pastPerfect:
            return String(localized: "“\(word)” (= “\(expansion)”) + past participle: it happened before another past moment: “had left”.")
        case .hadBetter:
            return String(localized: "“'d better” (= “had better”) + verb: strong advice: “You'd better go”.")
        case .modal("will"):
            return String(localized: "“\(word)” (= “\(expansion)”) + verb: the future.")
        case .modal:
            return String(localized: "“\(word)” (= “\(expansion)”) + verb: an imagined result, or a polite request.")
        default:
            let key = TextTools.normalize(word)
            // "he'd put": had or would; the sentence's translation settles it.
            let both = expansion.components(separatedBy: " / ")
            if both.count == 2 {
                return String(localized: "“\(word)” can be “\(both[0])” or “\(both[1])”: the sentence's translation tells which.")
            }
            if key == "let's" { return String(localized: "“let's” (= “let us”) + verb: a suggestion to do something together: “Let's go”.") }
            // The lookalikes learners mix up.
            if key == "it's" { return String(localized: "“it's” = “\(expansion)”; “its” (no apostrophe) = belonging to it.") }
            if key == "who's" { return String(localized: "“who's” = “\(expansion)”; “whose” = of whom: “Whose book?”") }
            return String(localized: "“\(word)” = “\(expansion)”.")
        }
    }

    private static let expanded = ["didn't": "did not", "don't": "do not", "doesn't": "does not"]

    private static func modalNote(_ base: String) -> String {
        switch base {
        case "will": String(localized: "“will” + verb: the future.")
        case "would": String(localized: "“would” + verb: what would happen, or a polite request.")
        case "can": String(localized: "“can” + verb: be able to, or be allowed to.")
        case "could": String(localized: "“could” + verb: was able to, or it’s possible.")
        case "shall": String(localized: "“shall” + verb: the future, or an offer (“Shall we go?”).")
        case "should": String(localized: "“should” + verb: advice, what is right to do.")
        case "must": String(localized: "“must” + verb: it is necessary, or it is surely true.")
        case "may": String(localized: "“may” + verb: maybe, or permission.")
        default: String(localized: "“might” + verb: maybe.")
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

/// The card's buttons on iOS 26: system glass (prominent for the primary action), so they
/// share the system's metrics and stay legible on the glass sheet. Before iOS 26, plain
/// buttons that draw their own background.
private struct GlassButtonStyle: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(.plain)
        }
    }
}

/// iOS 26, half-height card: the sheet is glass and the book shows through it, so the
/// content sits on one opaque panel, concentric with the sheet (glass is for controls,
/// not content). A UIKit colour on purpose: inside a glass sheet `.background` is the glass.
private struct ContentPanel: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), enabled {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: ConcentricRectangle())
                .padding(8)
        } else {
            content
        }
    }
}

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
    /// The reading the learner chose when the sentence doesn't tell (SPEC S3), its dictionary
    /// entry, and each reading's meaning by `ReadingChoice.id`.
    @State private var chosen: ReadingChoice?
    @State private var choiceEntry: DictionaryEntry?
    @State private var choiceMeanings: [String: String] = [:]

    /// Where the translation of a reading ("to leave" → "irse") is kept in `translations`.
    private static let readingKey = "\u{1}reading"

    /// The dictionary's base form ("animal") when it differs from the tapped word ("animals");
    /// when the dictionary can't be reached or has no entry, the irregular-verb table's ("stolen" →
    /// "steal", "she left" → "leave"), never over an entry for the form itself ("a human being");
    /// for a helper or modal verb, its own base form ("do" for "did").
    private var headword: String {
        if let function = selection.function { return function.base }
        // Unsure: the tapped word stays the headword, chosen reading or not.
        if isUnsure { return selection.word }
        if let base = entry?.word { return base == TextTools.normalize(selection.word) ? selection.word : base }
        guard entryLoaded, let base = tableBase else { return selection.word }
        return base
    }

    /// How a form that is also another word reads in its sentence ("she left": the verb "leave").
    private var reading: Reading? {
        guard selection.function == nil, let range = selection.rangeInSentence else { return nil }
        return IrregularVerbs.shared.resolve(selection.sentence, range)
    }

    /// The irregular-verb table's base form of the tapped word in its sentence, if it has one.
    private var tableBase: String? {
        guard selection.function == nil else { return nil }
        guard let range = selection.rangeInSentence else { return IrregularVerbs.shared.formToBase[TextTools.normalize(selection.word)] }
        return IrregularVerbs.shared.base(in: selection.sentence, at: range)
    }

    /// The two readings when the sentence doesn't tell; empty otherwise.
    private var choices: [ReadingChoice] {
        guard selection.function == nil, let range = selection.rangeInSentence else { return [] }
        return IrregularVerbs.shared.choices(in: selection.sentence, at: range)
    }

    private var isUnsure: Bool { !choices.isEmpty }

    /// The verb or noun the word is read as, for its meaning (SPEC S3): its sentence's reading,
    /// or a form of the irregular-verb table ("stolen": the verb "steal").
    private var meaningReading: Reading? {
        guard selection.function == nil, !isUnsure else { return nil }
        // A name ("Aunt Rose") is no reading: it is looked up and translated as tapped.
        if let reading { return reading.kind == .unsure || reading.step == .name ? nil : reading }
        return tableBase.map { Reading(kind: .verb, base: $0, step: .subject) }
    }

    /// The sense a certain reading saves with (SPEC S4); nil for a word that isn't a homograph.
    private var certainSense: String? {
        reading.flatMap { IrregularVerbs.shared.sense(of: $0) }
    }

    /// What Listen says (SPEC S6): the headword, then the word as in the text when it differs, each
    /// respelled for its proven slot; unsure, the tapped form in each reading (or the chosen one).
    /// A helper or modal verb: how its verb group sounds ("didn't go", not "do").
    private var spokenHeadwordAloud: String {
        if selection.function != nil { return selection.chunk ?? selection.word }
        guard let range = selection.rangeInSentence else { return headword }
        return IrregularVerbs.shared.listenText(headword: headword, in: selection.sentence, at: range, chosen: chosen)
    }

    /// The IPA under the headword: unsure, only once a reading is chosen, the tapped form's in it;
    /// a verb's from the table when the table has its slot ("read": /riːd/), else the dictionary's.
    private var phonetic: String? {
        guard selection.function == nil else { return nil }
        let table = IrregularVerbs.shared
        if isUnsure {
            guard let chosen else { return nil }
            if chosen.kind == .verb, let ipa = table.ipa(of: selection.word, verb: chosen.base) { return ipa }
            return TextTools.normalize(selection.word) == chosen.base ? choiceEntry?.phonetic : nil
        }
        if let reading = meaningReading, reading.kind == .verb, TextTools.normalize(headword) == reading.base,
           let ipa = table.baseIPA(reading.base) {
            return ipa
        }
        return entry?.phonetic
    }

    /// The definition shown: unsure, only that of the chosen reading.
    private var shownEntry: DictionaryEntry? { isUnsure ? choiceEntry : entry }

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
        if isUnsure { return chosen.flatMap { choiceMeanings[$0.id] } }
        if meaningReading != nil { return translations[Self.readingKey] }
        return translations[TextTools.normalize(headword)] ?? translations[TextTools.normalize(selection.word)]
    }

    /// What Save stores: the word's base form, or a helper or modal verb's verb group (the
    /// whole sentence when it has none, so there's always something to recall and translate).
    private var savedKey: String {
        if isUnsure { return chosen?.base ?? TextTools.normalize(selection.word) }
        guard selection.function != nil else { return headword }
        return selection.chunk ?? selection.sentence
    }

    /// The sense Save stores (SPEC S4): the chosen or certain reading's; unsure with nothing
    /// chosen, none (the tapped form with both readings).
    private var savedSense: String? {
        if selection.function != nil { return nil }
        if isUnsure { return chosen?.sense }
        return certainSense
    }

    /// How messages name what was saved: "did not go"; without a verb group, the start of the sentence.
    private var savedName: String {
        if isUnsure { return chosen?.base ?? selection.word }
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
                    if isUnsure {
                        unsureContent
                    } else {
                        translationView
                        definitionView
                        Divider().padding(.vertical, 4)
                        contextView(readFromHere: true)
                    }
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
        // A chosen reading brings its own dictionary entry: definition and IPA (SPEC S3).
        .task(id: chosen) {
            guard let chosen else { return }
            choiceEntry = nil
            choiceEntry = await model.dictionary.lookup(selection.word, reading: chosen.reading)
        }
        // A language chosen on this card (or changed with its menu) translates in place.
        .onChange(of: model.targetLanguage) { _, _ in
            startTranslation()
        }
        // Inside the sheet: an alert from under it would not show.
        .noVoiceAlert(model.speaker)
    }

    /// The sentence doesn't tell (SPEC S3): the sentence and its translation, the guide line and
    /// the two readings; once one is chosen, its definition; then the language and Read from here.
    @ViewBuilder
    private var unsureContent: some View {
        Divider().padding(.vertical, 4)
        contextView(readFromHere: false)
        if translationFailed {
            Text("Translation unavailable. Connect to the internet once to download the language.")
                .font(.footnote)
                .foregroundStyle(Brand.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        ReadingChoicesView(
            choices: choices, chosen: $chosen, meanings: choiceMeanings, language: translatedInto,
            translating: translatedInto != nil && !translationFailed
        )
        .padding(.top, 4)
        if chosen != nil { definitionView }
        if let target = model.targetLanguage { languageMenu(target) } else { languageChooser }
        readFromHereButton
    }

    /// The note of a helper or modal verb, else the dictionary's definition.
    @ViewBuilder
    private var definitionView: some View {
        if let function = selection.function {
            Text(function.note(form: selection.word))
                .font(.footnote)
                .foregroundStyle(Brand.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else if let definition = shownEntry?.definition {
            Text("\(Text(shownEntry?.partOfSpeech ?? "").italic()) · \(definition)")
                .font(.footnote)
                .foregroundStyle(Brand.secondaryText)
                .multilineTextAlignment(.center)
        } else if entryLoaded {
            Text("No definition available.").font(.footnote).foregroundStyle(Brand.secondaryText)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    model.speaker.speak(spokenHeadwordAloud, rate: model.state.settings.speechRate)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.largeTitle)
                }
                Text(headword).font(.largeTitle.weight(.semibold))
                    .accessibilityLabel(Text(spokenHeadword))
                    .accessibilityAddTraits(.isHeader)
            }
            if let phonetic {
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

    private func contextView(readFromHere: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(markedSentence).font(readingFont(size: 17)).italic()
                    .fixedSize(horizontal: false, vertical: true)
                if let sentenceTranslation {
                    Text(sentenceTranslation).font(.callout).foregroundStyle(Brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if readFromHere { readFromHereButton }
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

    /// Back to an earlier point, or on from this one (SPEC S6).
    @ViewBuilder
    private var readFromHereButton: some View {
        if let onReadFromHere {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        let saved = model.state.saved(savedKey, sense: savedSense)
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
        let before = model.state.words
        let unsureForm = isUnsure && chosen == nil
        // Without a verb group, the sentence is what's saved: its translation goes with it.
        let translation: String? = if selection.function == nil {
            unsureForm ? joinedMeanings : self.translation
        } else {
            selection.chunk == nil ? sentenceTranslation : self.translation
        }
        let range = selection.function == nil ? selection.rangeInSentence : nil
        model.library.saveWord(
            word,
            learned: learned,
            translation: translation,
            translationLanguage: translatedInto,
            phonetic: phonetic,
            context: selection.sentence,
            contextTranslation: sentenceTranslation,
            source: source,
            kind: selection.function?.kind,
            base: selection.function?.base,
            sense: savedSense,
            form: range == nil ? nil : selection.word,
            formRange: range,
            meanings: unsureForm ? savedMeanings : nil
        )
        // Saving never waits: a translation still on its way is done by TranslationWorker.
        if translation == nil { model.translateMissing() }
        if learned {
            finish(String(localized: "“\(savedName)” marked as known"), before: before)
        } else {
            finish(String(localized: "“\(savedName)” saved to Words"), before: before)
        }
    }

    /// Both readings as the card shows them, for a word saved unsure.
    private var savedMeanings: [SavedMeaning] {
        choices.map { choice in
            let text = choiceMeanings[choice.id] ?? ""
            return SavedMeaning(label: choice.label, sense: choice.sense, base: choice.base, text: text,
                                language: text.isEmpty ? nil : translatedInto)
        }
    }

    /// "irse, salir · izquierda" once both meanings are there.
    private var joinedMeanings: String? {
        let texts = choices.compactMap { choiceMeanings[$0.id] }.filter { !$0.isEmpty }
        return texts.count == choices.count ? texts.joined(separator: " · ") : nil
    }

    /// Tapping a checked button: the word leaves Words (Undo puts it back as it was).
    private func remove() {
        let before = model.state.words
        let saved = model.state.saved(savedKey, sense: savedSense)
        model.library.deleteWord(saved?.word ?? TextTools.normalize(savedKey), sense: saved?.sense)
        finish(String(localized: "“\(savedName)” removed from Words"), before: before)
    }

    /// Undo puts every saved word back as it was: also a word saved unsure that a reading replaced.
    private func finish(_ text: String, before: [VocabWord]) {
        let library = model.library
        onAction(UndoMessage(text: text, seconds: 4) {
            library.restoreWords(before)
        })
        dismiss()
    }

    // MARK: Loading

    /// The dictionary lookup and the translation start together. Unsure, the dictionary waits for
    /// a reading to be chosen: nothing is guessed.
    private func load() async {
        let dictionary = model.dictionary
        let word = selection.word
        let reading = meaningReading
        // A helper or modal verb needs no dictionary: its definition and IPA would be the
        // base form's ("do"), not what the learner sees ("didn't go").
        let skip = selection.function != nil || isUnsure
        let task = Task { () -> DictionaryEntry? in
            if skip { return nil }
            return await dictionary.lookup(word, reading: reading)
        }
        lookup = task
        startTranslation()
        entry = await task.value
        entryLoaded = true
        // The base form needs its own translation ("animals" → "animal"); a reading has its own.
        if selection.function == nil, meaningReading == nil, !isUnsure, headword != selection.word,
           let fake = model.fakeTranslator, translatedInto != nil, !translationFailed {
            translations[TextTools.normalize(headword)] = try? fake(headword)
        }
    }

    /// What to translate for a reading's meaning ("to leave", "the left"), or nil when the table
    /// already has it in the target language (Spanish), which is then filled in.
    private func readingSource(kind: Reading.Kind, base: String, target: String, all: Bool) -> (text: String?, direct: String?) {
        if kind == .verb, ReadingTranslation.isSpanish(target),
           let spanish = IrregularVerbs.shared.spanishMeaning(of: base, all: all) {
            return (nil, spanish)
        }
        return (ReadingTranslation.source(word: base, sense: kind == .noun ? Sense.noun : Sense.verb), nil)
    }

    /// The texts to translate, by identifier: the word (or its reading), each unsure reading, and
    /// what the table fills in directly.
    private func pendingTexts(_ target: String) -> [String: String] {
        var texts: [String: String] = [:]
        if let reading = meaningReading {
            let source = readingSource(kind: reading.kind, base: reading.base, target: target, all: true)
            if let direct = source.direct { translations[Self.readingKey] = direct }
            if let text = source.text { texts["reading"] = text }
        } else if !isUnsure, let wordSource {
            texts["word"] = wordSource
        }
        for choice in choices {
            let source = readingSource(kind: choice.kind, base: choice.base, target: target, all: false)
            if let direct = source.direct { choiceMeanings[choice.id] = direct }
            if let text = source.text { texts["choice:\(choice.id)"] = text }
        }
        return texts
    }

    /// Records the translation of `id` (from `pendingTexts`) in `target`.
    private func record(_ id: String, _ text: String, _ target: String) {
        if id == "reading" {
            translations[Self.readingKey] = ReadingTranslation.cleaned(text, noun: meaningReading?.kind == .noun, language: target)
        } else if id.hasPrefix("choice:") {
            let choiceID = String(id.dropFirst("choice:".count))
            let noun = choices.first { $0.id == choiceID }?.kind == .noun
            choiceMeanings[choiceID] = ReadingTranslation.cleaned(text, noun: noun, language: target)
        } else if let wordSource {
            translations[TextTools.normalize(wordSource)] = text
        }
    }

    /// (Re)translates the word and the sentence into the current language; with
    /// none set, the card asks instead.
    private func startTranslation() {
        translations = [:]
        choiceMeanings = [:]
        sentenceTranslation = nil
        translationFailed = false
        translatedInto = model.targetLanguage
        guard let target = model.targetLanguage else {
            configuration = nil
            return
        }
        if let fake = model.fakeTranslator {
            do {
                for (id, text) in pendingTexts(target) { record(id, try fake(text), target) }
                if selection.function == nil, meaningReading == nil, !isUnsure, entryLoaded, headword != selection.word {
                    translations[TextTools.normalize(headword)] = try fake(headword)
                }
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

    /// Runs in `.translationTask`: the word (or its readings) and the sentence first, then the
    /// base form once the dictionary has given one that differs.
    private func translate(using session: TranslationSession) async {
        guard let target = translatedInto else { return }
        let texts = pendingTexts(target)
        var requests = [TranslationSession.Request(sourceText: selection.sentence, clientIdentifier: "sentence")]
        requests += texts.map { TranslationSession.Request(sourceText: $0.value, clientIdentifier: $0.key) }
        do {
            let responses = try await session.translations(from: requests)
            // The language changed meanwhile: a newer run translates again.
            guard translatedInto == target else { return }
            for response in responses {
                if response.clientIdentifier == "sentence" {
                    sentenceTranslation = response.targetText
                } else if let id = response.clientIdentifier {
                    record(id, response.targetText, target)
                }
            }
            guard selection.function == nil, meaningReading == nil, !isUnsure,
                  let tapped = wordSource.map(TextTools.normalize) else { return }
            let looked: DictionaryEntry? = await lookup?.value
            // The dictionary's base form, else (offline) the irregular-verb table's.
            guard let base = looked.map({ TextTools.normalize($0.word) }) ?? tableBase, base != tapped else { return }
            let response = try await session.translate(base)
            if translatedInto == target { translations[base] = response.targetText }
        } catch {
            if translatedInto == target, translation == nil || isUnsure { translationFailed = true }
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

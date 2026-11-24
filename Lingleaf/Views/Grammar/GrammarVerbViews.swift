import SwiftUI
import LingleafCore

/// A 44 pt Listen button that says `text` in English (S24): borderless, never inside a row's link, so tapping it never
/// navigates.
struct ListenButton: View {
    @Environment(AppModel.self) private var model
    let text: String
    /// What a screen reader calls it: "Listen, took".
    let name: String

    var body: some View {
        Button {
            model.speaker.speak(text, rate: model.state.settings.speechRate)
        } label: {
            Image(systemName: "speaker.wave.2").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Listen, \(name)"))
    }
}

/// One verb in a list: Listen at the leading edge (the three forms), then every form of each slot and the meanings.
struct IrregularVerbRow: View {
    @Environment(AppModel.self) private var model
    let verb: IrregularVerb
    /// The translation of "to take" in another translation language, when the list has it (installed on the device).
    var translated: String?

    var body: some View {
        let forms = IrregularVerbLine.forms(verb)
        // The table's Spanish meanings for a Spanish translation language, else the translation of "to take" (only when that
        // language is installed on the device), else nothing.
        let meanings = model.targetLanguage == "es" ? IrregularVerbLine.meanings(verb) : translated
        HStack(alignment: .top, spacing: 4) {
            ListenButton(text: GrammarSpeech.verbForms(verb).text, name: verb.base)
            NavigationLink(value: GrammarRoute.verb(verb.base)) {
                VStack(alignment: .leading, spacing: 2) {
                    LangText(forms, language: "en").font(.headline)
                    if let meanings {
                        LangText(meanings, language: model.targetLanguage ?? "es").font(.subheadline).foregroundStyle(Brand.secondaryText)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: forms.replacingOccurrences(of: " · ", with: ", ")))
                .accessibilityValue(Text(verbatim: meanings ?? ""))
                .accessibilityIdentifier("grammar-verb-row")
            }
        }
    }
}

/// Every irregular verb (S24): the table's pattern groups, most used first inside a group, with a search field.
struct IrregularVerbsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var translator = GrammarTranslations()

    var body: some View {
        let table = IrregularVerbs.shared
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(IrregularVerbOrder.sections(table), id: \.group.id) { section in
                    Section {
                        ForEach(section.verbs, id: \.base) { verb in
                            IrregularVerbRow(verb: verb, translated: translator.translations["to " + verb.base])
                        }
                    } header: {
                        // The group's title and its example are one heading.
                        Text(verbatim: "\(groupTitle(section.group)) · \(section.group.example)")
                            .foregroundStyle(Brand.secondaryText)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            } else {
                IrregularVerbResults(verbs: IrregularVerbSearch.search(query, in: table), translator: translator)
            }
        }
        .navigationTitle("Irregular verbs")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search verbs"))
        .grammarTranslations(translator, texts: table.verbs.map { "to " + $0.base }, model: model)
    }

    /// The group's title in the language of the interface.
    private func groupTitle(_ group: VerbGroup) -> String {
        model.chromeLanguage == "es" ? group.title.es : group.title.en
    }
}

/// The matching verbs under a header that is always there; no match says what to try.
struct IrregularVerbResults: View {
    let verbs: [IrregularVerb]
    var translator: GrammarTranslations?

    var body: some View {
        Section {
            if verbs.isEmpty {
                Text("Try the verb or its meaning, like go or ir.").foregroundStyle(Brand.secondaryText)
            }
            ForEach(verbs, id: \.base) { IrregularVerbRow(verb: $0, translated: translator?.translations["to " + $0.base]) }
        } header: {
            SectionHeader("Verbs").accessibilityAddTraits(.isHeader)
        }
    }
}

/// A verb page (S24): its level and its forms, each with Listen; a verb with a regular twin (lie, hang) shows the twin's
/// forms under its own heading. The sentences and Save word come with the sentences data.
struct VerbPageView: View {
    @Environment(AppModel.self) private var model
    let verb: IrregularVerb

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    LangText(verb.base, language: "en").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(verbatim: GrammarLabels.level(verb.level))
                        .foregroundStyle(Brand.secondaryText)
                        .accessibilityLabel(Text(verbatim: GrammarLabels.levelSpoken(verb.level)))
                }
                heading("Forms")
                formRow("Base form", forms: [verb.base], slot: .base)
                formRow("Past", forms: verb.past, slot: .past)
                formRow("Past participle", forms: verb.participle, slot: .participle, hint: IrregularVerbLine.participleHint(verb))
                formRow("-ing form", forms: [verb.ing], slot: .ing)
                formRow("He, she, it", forms: [verb.s], slot: .s)
                sentences(senseIndex: 0)
                if let twin = verb.homonym {
                    homonym(twin)
                    sentences(senseIndex: 1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(verb.base)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: In sentences

    /// "In sentences" (S24): the verb's original sentences in the fixed positions of the sentences data, each with its
    /// Spanish line only for a Spanish translation language, and Listen. A verb with no sentences in the data shows nothing.
    @ViewBuilder
    private func sentences(senseIndex: Int) -> some View {
        let list = VerbSentences.shared.entry(base: verb.base)?.sentences(senseIndex: senseIndex) ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if senseIndex == 0 { heading("In sentences") }
                ForEach(Array(list.enumerated()), id: \.offset) { _, sentence in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sentence.slot.label).font(.subheadline).foregroundStyle(Brand.secondaryText)
                            Text(bolded(sentence.en, form: sentence.form)).environment(\.locale, Locale(identifier: "en"))
                            if model.targetLanguage == "es" {
                                LangText(sentence.es, language: "es").font(.subheadline).foregroundStyle(Brand.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                        ListenButton(text: sentence.spoken ?? sentence.en, name: sentence.form)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    /// The sentence with the verb's form in bold (the first whole word that is it).
    private func bolded(_ text: String, form: String) -> AttributedString {
        var result = AttributedString(text)
        if let range = result.range(of: form, options: .caseInsensitive) { result[range].font = .body.bold() }
        return result
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
    }

    /// A form with its label, the hint under it when there is one, and a Listen for each form of the slot.
    private func formRow(_ label: LocalizedStringKey, forms: [String], slot: VerbFormSlot, hint: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(Brand.secondaryText)
                LangText(forms.joined(separator: " / "), language: "en").font(.title3.bold())
                if let hint { LangText(hint, language: "en").font(.footnote).foregroundStyle(Brand.secondaryText) }
            }
            Spacer(minLength: 0)
            ForEach(forms.indices, id: \.self) { index in
                ListenButton(text: GrammarSpeech.verbForm(verb, slot: slot, index: index)?.text ?? forms[index], name: forms[index])
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The regular verb with the same base ("lied", "hanged"): its forms and what it means.
    private func homonym(_ twin: IrregularVerb.Homonym) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "\(twin.past.first ?? verb.base) — \(twin.es.joined(separator: ", "))")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            LangText(([verb.base] + twin.past + twin.participle + [twin.ing, twin.s]).joined(separator: " · "), language: "en")
        }
    }
}

extension VerbSlot {
    /// What the position says about the sentence (SPEC S24, Verb sentences data): the label of the slot, or of its substitute.
    var label: LocalizedStringKey {
        switch self {
        case .habit: "Every day"
        case .third: "One person, every day"
        case .now: "Right now"
        case .gerund: "Used like a noun"
        case .past: "In the past"
        case .story: "In a story"
        case .didnt: "Didn't (past negative)"
        case .perfect: "Before now"
        case .passive: "Done to something"
        case .state: "A condition (how something is)"
        case .perfectq: "Asking about before now"
        case .pastperfect: "Before that"
        case .advice: "Should"
        }
    }
}

import SwiftUI
import LingleafCore

/// A rule page (SPEC S21): the rule, a line for Spanish speakers, examples with Listen, what not to mix up, an
/// optional note, how a rule becomes Practiced and the button to practise it. The rule text is in the language the
/// learner chose with the segmented control, kept in the setting `grammarInSpanish`.
struct GrammarRuleView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrammarModel.self) private var grammar
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    /// Opening a rule counts it for "Recent" once per push: coming back from a practice session or a verb page
    /// shows this page again but is not an opening (S20).
    @State private var opened = false

    let rule: GrammarRule

    /// The primary button is pinned to the bottom edge, except at accessibility text sizes and in landscape
    /// (compact height), where it would take too much of the screen and follows the content instead.
    private var isInline: Bool { typeSize.isAccessibilitySize || verticalSizeClass == .compact }

    var body: some View {
        let language = model.grammarLanguage
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                languagePicker(language)
                header(language)
                ruleLines(language)
                spanishLine(language)
                examples
                contrast(language)
                note(language)
                progressLines
                if isInline { bottomBar }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(PinnedBar(isPinned: !isInline) { bottomBar })
        .onAppear {
            guard !opened else { return }
            opened = true
            grammar.opened(rule)
        }
    }

    private var categoryTitle: String {
        grammar.grammar.categories.first { $0.id == rule.category }?.title.text(for: model.chromeLanguage) ?? ""
    }

    // MARK: Content

    private func languagePicker(_ language: GrammarLanguage) -> some View {
        Picker(selection: Binding(
            get: { language },
            set: { chosen in model.library.updateSettings { $0.grammarInSpanish = chosen.stored } }
        )) {
            // The same in both interface languages, each name in its own language.
            LangText("English", language: "en").tag(GrammarLanguage.en)
            LangText("Español", language: "es").tag(GrammarLanguage.es)
        } label: {
            Text("Rule language")
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        // The control's own name for a screen reader (the label of a segmented picker is not drawn).
        .accessibilityLabel(Text("Rule language"))
    }

    private func header(_ language: GrammarLanguage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LangText(rule.title.text(for: language.rawValue), language: language.rawValue)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: GrammarLabels.level(rule.level))
                .foregroundStyle(Brand.secondaryText)
                .accessibilityLabel(Text(verbatim: GrammarLabels.levelSpoken(rule.level)))
        }
    }

    private func ruleLines(_ language: GrammarLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rule.lines.lines(for: language.rawValue).enumerated()), id: \.offset) { _, line in
                LangText(line, language: language.rawValue).font(.body)
            }
        }
    }

    @ViewBuilder
    private func spanishLine(_ language: GrammarLanguage) -> some View {
        if let spanish = rule.spanish {
            VStack(alignment: .leading, spacing: 6) {
                heading("If you speak Spanish")
                LangText(spanish.text(for: language.rawValue), language: language.rawValue)
            }
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Examples")
            ForEach(Array(rule.examples.enumerated()), id: \.offset) { _, example in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        LangText(example.en, language: "en")
                        // The bundled translation is Spanish; another translation language is made on the device later.
                        if model.targetLanguage == "es" {
                            LangText(example.es, language: "es").font(.subheadline).foregroundStyle(Brand.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.speaker.speak(example.en, rate: model.state.settings.speechRate)
                    } label: {
                        Image(systemName: "speaker.wave.2").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Listen"))
                }
            }
        }
    }

    private func contrast(_ language: GrammarLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Don't mix up")
            ForEach(Array(rule.contrast.forms.enumerated()), id: \.offset) { _, form in
                LangText(form, language: "en").bold()
            }
            if let gloss = rule.contrast.gloss {
                LangText(gloss.text(for: language.rawValue), language: language.rawValue)
                    .font(.subheadline).foregroundStyle(Brand.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func note(_ language: GrammarLanguage) -> some View {
        if let note = rule.note {
            LangText(note.text(for: language.rawValue), language: language.rawValue)
                .font(.subheadline).foregroundStyle(Brand.secondaryText)
        }
    }

    /// How a rule becomes Practiced, always there; and what In Review means, only for a rule that is.
    private var progressLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Practiced: right answers on 2 different days.")
            if grammar.progress.state(of: rule.id) == .inReview {
                Text("In Review: this rule's questions will come back when you review.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Brand.secondaryText)
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
    }

    // MARK: The button

    private var answeredToday: Int { grammar.progress.answeredToday(rule.id, today: grammar.today) }

    /// "Try it" until the learner has been past the first item, then "Practice"; at 6 items answered today the
    /// button gives way to the limit text and "See other rules" (neutral: no nudge, no streak).
    private var bottomBar: some View {
        bottomBarContent
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("grammar-bottom-bar")
    }

    @ViewBuilder
    private var bottomBarContent: some View {
        let size = GrammarPractice.roundSize(answeredToday: answeredToday)
        if size == 0 {
            VStack(spacing: 10) {
                Text("You've finished today's practice for this rule. Try another rule, or come back tomorrow.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.secondaryText)
                Button("See other rules") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(isInline ? 0 : 12)
        } else if !GrammarPractice.draw(
            rule: rule, progress: grammar.progress[rule.id], spanishEligible: model.spanishEligible, excluding: [], count: size
        ).isEmpty {
            Group {
                switch GrammarPractice.label(for: rule, progress: grammar.progress[rule.id]) {
                case .tryIt: Button("Try it") { startPractice() }
                case .practice: Button("Practice") { startPractice() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(isInline ? 0 : 12)
        }
    }

    /// The pretest and the practice session open from here (the next commits).
    private func startPractice() {}
}

/// Pins its content to the bottom edge, under the content's scroll edge: the system scroll-edge effect on iOS 26, a bar
/// material before it. When not pinned the content is not shown here (the caller places it inline).
private struct PinnedBar<Bar: View>: ViewModifier {
    let isPinned: Bool
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if !isPinned {
            content
        } else if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom) { bar() }
        } else {
            content.safeAreaInset(edge: .bottom) { bar().background(.bar) }
        }
    }
}

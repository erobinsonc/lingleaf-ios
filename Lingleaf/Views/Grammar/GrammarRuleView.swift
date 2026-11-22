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
    /// Where the learner is on this page: the pretest (an item shown with the rule hidden), its answer, or the rule.
    /// Nil until something changes it: the pretest is offered while it was neither answered nor skipped (S22).
    @State private var stage: Stage?
    /// Items kept out of the rounds of this opening of the page (the pretest answered, or the item left on the page
    /// after "Skip", once answered); view state, never stored.
    @State private var excluded: Set<String> = []
    @State private var round: GrammarRound?

    private enum Stage { case pretest, answered, rule }

    private var currentStage: Stage { stage ?? (grammar.progress[rule.id].pretestOffered ? .pretest : .rule) }

    let rule: GrammarRule

    /// The primary button is pinned to the bottom edge, except at accessibility text sizes and in landscape
    /// (compact height), where it would take too much of the screen and follows the content instead.
    private var isInline: Bool { typeSize.isAccessibilitySize || verticalSizeClass == .compact }

    var body: some View {
        Group {
            if currentStage == .rule { ruleBody } else { pretestBody }
        }
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(PinnedBar(isPinned: !isInline) { bottomBar })
        .navigationDestination(item: $round) { _ in
            GrammarSessionView(
                rule: rule, language: model.grammarLanguage,
                drawRound: {
                    GrammarPractice.draw(
                        rule: rule, progress: grammar.progress[rule.id], spanishEligible: model.spanishEligible, excluding: excluded,
                        count: GrammarPractice.roundSize(answeredToday: answeredToday)
                    )
                },
                onAnswered: { id in if id == GrammarPretest.item(of: rule)?.id { excluded.insert(id) } }
            )
        }
        .onAppear {
            guard !opened else { return }
            opened = true
            grammar.opened(rule)
        }
    }

    private var ruleBody: some View {
        let language = model.grammarLanguage
        return ScrollView {
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
    }

    // MARK: The pretest

    /// A question first, with the rule hidden (S22): "Skip" ends it, an answer ends it and "See the rule" shows the rule.
    private var pretestBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Try a question first").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Guess, then read the rule. A wrong guess is fine.").font(.subheadline).foregroundStyle(Brand.secondaryText)
                // At accessibility sizes Skip moves to the navigation bar, so the question stays in view.
                if currentStage == .pretest && !typeSize.isAccessibilitySize { skipButton }
                if let item = GrammarPretest.item(of: rule) {
                    GrammarItemView(
                        item: item, language: model.grammarLanguage, allowsNotSure: false,
                        seenBefore: grammar.progress[rule.id].items[item.id]?.seen ?? 0,
                        onShown: { grammar.shown(rule, item: item) },
                        onAnswered: { right in
                            grammar.answeredPretest(rule, right: right)
                            excluded.insert(item.id)
                            stage = .answered
                        }
                    )
                }
                if isInline { bottomBar }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            if currentStage == .pretest && typeSize.isAccessibilitySize {
                ToolbarItem(placement: .topBarTrailing) { skipButton }
            }
        }
    }

    /// "Skip" is the visible word; a screen reader says "Skip to the rule" (it contains the visible text).
    private var skipButton: some View {
        Button("Skip") {
            grammar.skippedPretest(rule)
            stage = .rule
        }
        .buttonStyle(.borderless)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("Skip to the rule"))
        .accessibilityInputLabels([Text("Skip"), Text("Skip to the rule")])
        .accessibilityIdentifier("grammar-skip-pretest")
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
        if currentStage == .pretest {
            EmptyView()
        } else if currentStage == .answered {
            Button("See the rule") { stage = .rule }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(isInline ? 0 : 12)
        } else if size == 0 {
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

    private func startPractice() { round = GrammarRound() }
}

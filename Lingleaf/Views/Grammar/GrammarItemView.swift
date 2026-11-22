import SwiftUI
import LingleafCore

/// One practice item (SPEC S22): the learner chooses before anything is shown (no answer, no colour), the options in
/// the shuffled order of `GrammarOptionOrder`; then why, in the language of the rule text, with a cross or a check as
/// well as a colour. An item is a `gap` (a sentence with one "___") or a `choose` (the instruction `ask` and a visible
/// stimulus `text`). "Not sure" counts as wrong. Recording the answer is the caller's: this view only says right or not.
struct GrammarItemView: View {
    let item: PracticeItem
    let language: GrammarLanguage
    let allowsNotSure: Bool
    /// The item was shown (`seen` + 1), once, when it appears.
    let onShown: () -> Void
    /// The answer, once: whether it was right ("Not sure" is wrong).
    let onAnswered: (Bool) -> Void

    /// The order is fixed when the item is made: `seen` goes up when it is shown and must not reshuffle it.
    @State private var order: [Int]
    @State private var chosen: Int?
    @State private var isUnsure = false
    @State private var showsOthers = false
    @State private var hasShown = false
    @AccessibilityFocusState private var verdictFocused: Bool

    init(
        item: PracticeItem, language: GrammarLanguage, allowsNotSure: Bool, seenBefore: Int,
        onShown: @escaping () -> Void, onAnswered: @escaping (Bool) -> Void
    ) {
        self.item = item
        self.language = language
        self.allowsNotSure = allowsNotSure
        self.onShown = onShown
        self.onAnswered = onAnswered
        _order = State(initialValue: GrammarOptionOrder.order(for: item, seen: seenBefore))
    }

    private var isAnswered: Bool { chosen != nil || isUnsure }
    private var isRight: Bool { chosen == item.answer }
    private var rule: String { language.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stimulus
            VStack(spacing: 12) {
                ForEach(order, id: \.self) { index in optionRow(index) }
            }
            if isAnswered {
                feedbackBlock
            } else if allowsNotSure {
                Button("Not sure") { answerUnsure() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
        .sensoryFeedback(.selection, trigger: chosen)
        .onAppear {
            guard !hasShown else { return }
            hasShown = true
            onShown()
        }
    }

    // MARK: The question

    @ViewBuilder
    private var stimulus: some View {
        switch item.kind {
        case .gap:
            // Answered, the sentence is filled with the right option, in bold.
            let sentence = isAnswered ? item.filled(with: item.answer) : (item.text ?? "")
            LangText(sentence, language: "en").font(.title3).fontWeight(isAnswered ? .bold : .regular)
        case .choose:
            if let ask = item.ask { LangText(ask.text(for: rule), language: rule).font(.headline) }
            if let text = item.text { LangText(text, language: item.textLang ?? "en").font(.title3) }
        }
    }

    private func optionText(_ index: Int) -> String {
        item.options[index] == "(nothing)" ? String(localized: "(nothing)") : item.options[index]
    }

    // MARK: The options

    @ViewBuilder
    private func optionRow(_ index: Int) -> some View {
        if isAnswered {
            answeredRow(index)
        } else {
            Button { choose(index) } label: {
                HStack {
                    LangText(optionText(index), language: "en").font(.body)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("grammar-option-\(index)")
        }
    }

    /// After an answer the options are plain rows, not disabled controls: the chosen one says "Your answer", the right
    /// one "Right answer" when it was not chosen; a cross or a check says it too, never the colour alone.
    private func answeredRow(_ index: Int) -> some View {
        let isChosen = chosen == index
        let isAnswer = index == item.answer
        let note: String? = isChosen ? (isAnswer ? String(localized: "Your answer, right") : String(localized: "Your answer"))
            : (isAnswer ? String(localized: "Right answer") : nil)
        return HStack(alignment: .top, spacing: 10) {
            if isAnswer || isChosen {
                Image(systemName: isAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(Color(isAnswer ? "GrammarRight" : "GrammarWrong"))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                LangText(optionText(index), language: "en").font(.body)
                if let note { Text(verbatim: note).font(.caption).foregroundStyle(Brand.secondaryText) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: optionText(index)))
        .accessibilityValue(Text(verbatim: note ?? ""))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func choose(_ index: Int) {
        guard !isAnswered else { return }
        chosen = index
        onAnswered(index == item.answer)
        focusVerdict()
    }

    private func answerUnsure() {
        guard !isAnswered else { return }
        isUnsure = true
        onAnswered(false)
        focusVerdict()
    }

    private func focusVerdict() {
        // The block appears with the answer: focus moves to it once it is there.
        DispatchQueue.main.async { verdictFocused = true }
    }

    // MARK: Why

    private func feedback(_ index: Int) -> String { item.feedback[index].text(for: rule) }

    /// Right: only the chosen option's reason, the others one tap away. Wrong: the chosen reason, the right one, then every
    /// other. Not sure: "That's okay", the right one, then the others.
    private var feedbackBlock: some View {
        let others = item.options.indices.filter { $0 != chosen && $0 != item.answer }
        let verdict: String = isUnsure ? String(localized: "That's okay. Right:") + " " + feedback(item.answer)
            : isRight ? String(localized: "Right:") + " " + feedback(item.answer)
            : String(localized: "Not quite:") + " " + feedback(chosen ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            line(icon: isRight ? "checkmark.circle.fill" : (isUnsure ? "info.circle.fill" : "xmark.circle.fill"),
                 color: isRight ? "GrammarRight" : (isUnsure ? nil : "GrammarWrong"), text: verdict)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($verdictFocused)
            if !isRight && !isUnsure {
                line(icon: "checkmark.circle.fill", color: "GrammarRight", text: String(localized: "Right:") + " " + feedback(item.answer))
            }
            if isRight {
                Button { showsOthers.toggle() } label: {
                    Label("Why not the others?", systemImage: showsOthers ? "chevron.up" : "chevron.down")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityValue(showsOthers ? Text("expanded") : Text("collapsed"))
            }
            if !isRight || showsOthers {
                ForEach(isUnsure ? item.options.indices.filter { $0 != item.answer } : others, id: \.self) { index in
                    Text(other(index)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isRight ? Color("GrammarRight") : (isUnsure ? Color.secondary : Color("GrammarWrong"))).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func line(icon: String, color: String?, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color.map { Color($0) } ?? Brand.secondaryText).accessibilityHidden(true)
            LangText(text, language: rule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "<option in bold>: <why not>"
    private func other(_ index: Int) -> AttributedString {
        var name = AttributedString(optionText(index))
        name.font = .body.bold()
        return name + AttributedString(": " + feedback(index))
    }
}

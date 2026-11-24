import SwiftUI
import LingleafCore

/// Try it / Practice (SPEC S22): a round of up to 3 items, one at a time, then the result. Each item is shown before it is
/// answered (`seen` + 1) and recorded when answered; an item never grades by typing. The round is drawn by the rule
/// page (`drawRound`), which knows the items kept out of this opening of the page.
struct GrammarSessionView: View {
    @Environment(GrammarModel.self) private var grammar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let rule: GrammarRule
    let language: GrammarLanguage
    let drawRound: () -> [PracticeItem]
    /// An item of this round was answered (the page keeps the pretest item out of later rounds).
    let onAnswered: (String) -> Void

    @State private var items: [PracticeItem] = []
    @State private var index = 0
    @State private var rights = 0
    @State private var isAnswered = false
    @State private var isFinished = false
    @State private var wasNew = false
    @State private var started = false
    @AccessibilityFocusState private var resultFocused: Bool

    private var isInline: Bool { typeSize.isAccessibilitySize || verticalSizeClass == .compact }
    private var tabBarIsHidden: Bool { horizontalSizeClass == .compact || verticalSizeClass == .compact }
    private var answeredToday: Int { grammar.progress.answeredToday(rule.id, today: grammar.today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isFinished {
                    result
                } else if items.indices.contains(index) {
                    question(items[index])
                }
                if isInline { bottomBar }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(tabBarIsHidden ? .hidden : .automatic, for: .tabBar)
        .modifier(PinnedBar(isPinned: !isInline) { bottomBar })
        .onAppear {
            guard !started else { return }
            started = true
            startRound()
        }
    }

    // MARK: A round

    private func startRound() {
        items = drawRound()
        index = 0
        rights = 0
        isAnswered = false
        isFinished = items.isEmpty
        wasNew = grammar.progress.state(of: rule.id) == .new
    }

    private func question(_ item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(index), total: Double(max(items.count, 1)))
                .accessibilityHidden(true)
            Text("\(index + 1) of \(items.count)")
                .font(.subheadline)
                .foregroundStyle(Brand.secondaryText)
                .accessibilityLabel(Text("Question \(index + 1) of \(items.count)"))
            GrammarItemView(
                item: item, language: language, allowsNotSure: true,
                seenBefore: grammar.progress[rule.id].items[item.id]?.seen ?? 0,
                onShown: { grammar.shown(rule, item: item) },
                onAnswered: { right in
                    grammar.answeredPractice(rule, item: item, right: right)
                    if right { rights += 1 }
                    isAnswered = true
                    onAnswered(item.id)
                }
            )
            .id(item.id)
        }
    }

    // MARK: The result

    private var becamePracticed: Bool { wasNew && grammar.progress.state(of: rule.id) == .practised }

    /// "You got 2 of 3 right", the last-round line and the Practiced line are one heading for a screen reader.
    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You got \(rights) of \(items.count) right").font(.title2.bold())
            if answeredToday >= GrammarPractice.dailyMax {
                Text("That was the last round for today.").font(.subheadline).foregroundStyle(Brand.secondaryText)
            }
            if becamePracticed {
                Label("This rule is now Practiced", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color("GrammarRight"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($resultFocused)
    }

    private var hasAnotherRound: Bool {
        let size = GrammarPractice.roundSize(answeredToday: answeredToday)
        return size > 0 && !drawRound().isEmpty
    }

    // MARK: The buttons

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            if isFinished {
                VStack(spacing: 10) {
                    if hasAnotherRound {
                        Button("Practice") { startRound() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                    Button("Back to the rule") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            } else if isAnswered {
                // Two literals, not one conditional: a conditional would be a plain String and skip the catalog.
                if index + 1 < items.count {
                    Button("Next") { advance() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("grammar-next")
                } else {
                    Button("Finish") { advance() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("grammar-next")
                }
            }
        }
        .padding(isInline ? 0 : 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grammar-bottom-bar")
    }

    private func advance() {
        if index + 1 < items.count {
            index += 1
            isAnswered = false
        } else {
            isFinished = true
            DispatchQueue.main.async { resultFocused = true }
        }
    }
}

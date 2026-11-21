import SwiftUI
import LingleafCore

/// The Grammar tab (SPEC S20): "Recent", the categories with their rules (layout A) or with their counts (layout B),
/// and a search over the rules. Rules, examples and practice are bundled: nothing here uses the network.
struct GrammarView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrammarModel.self) private var grammar
    @State private var query = ""

    var body: some View {
        let rules = grammar.grammar
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    browse(rules)
                } else {
                    results(rules)
                }
            }
            .navigationTitle("Grammar")
            .searchable(text: $query, prompt: Text("Search rules"))
            .navigationDestination(for: GrammarRoute.self) { route in
                switch route {
                case .rule(let id):
                    if let rule = rules.rule(id: id) { GrammarRuleView(rule: rule) }
                case .category(let id):
                    GrammarCategoryView(categoryID: id)
                }
            }
        }
    }

    // MARK: Browsing

    @ViewBuilder
    private func browse(_ rules: GrammarRules) -> some View {
        let recent = GrammarRecent.rules(progress: grammar.progress, in: rules)
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.id) { GrammarRuleRow(rule: $0) }
            } header: {
                SectionHeader("Recent").accessibilityAddTraits(.isHeader)
            }
        }
        switch GrammarListLayout.layout(ruleCount: rules.rules.count) {
        case .a:
            ForEach(GrammarListLayout.sections(in: rules), id: \.category.id) { section in
                Section {
                    ForEach(section.rules, id: \.id) { GrammarRuleRow(rule: $0) }
                } header: {
                    Text(verbatim: section.category.title.text(for: model.chromeLanguage))
                        .foregroundStyle(Brand.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        case .b:
            Section {
                ForEach(GrammarListLayout.sections(in: rules), id: \.category.id) { section in
                    NavigationLink(value: GrammarRoute.category(section.category.id)) {
                        HStack {
                            Text(verbatim: section.category.title.text(for: model.chromeLanguage)).font(.headline)
                            Spacer(minLength: 8)
                            Text(verbatim: GrammarLabels.ruleCount(section.rules.count)).foregroundStyle(Brand.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: Search

    /// The matching rules under a header that is always there; no match says what to try.
    @ViewBuilder
    private func results(_ rules: GrammarRules) -> some View {
        let found = GrammarSearch.search(query, in: rules.rules)
        Section {
            if found.isEmpty {
                Text("No rules match. Try a shorter word, like in, on or at.")
                    .foregroundStyle(Brand.secondaryText)
            }
            ForEach(found, id: \.id) { GrammarRuleRow(rule: $0) }
        } header: {
            SectionHeader("Rules").accessibilityAddTraits(.isHeader)
        }
    }
}

/// A category opened from layout B: its rules as in layout A.
struct GrammarCategoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrammarModel.self) private var grammar
    let categoryID: String

    var body: some View {
        let rules = GrammarListLayout.sorted(grammar.grammar.rules(in: categoryID))
        let title = grammar.grammar.categories.first { $0.id == categoryID }?.title.text(for: model.chromeLanguage) ?? ""
        List {
            ForEach(rules, id: \.id) { GrammarRuleRow(rule: $0) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One rule in a list: its short title, its level and, at the end of the row, "Practiced" or "In Review"; a rule that is
/// neither (New) shows nothing there and a screen reader says "New" as the row's value (SPEC S20).
struct GrammarRuleRow: View {
    @Environment(AppModel.self) private var model
    @Environment(GrammarModel.self) private var grammar
    @Environment(\.dynamicTypeSize) private var typeSize
    let rule: GrammarRule

    var body: some View {
        let title = rule.title.text(for: model.chromeLanguage)
        let state = grammar.progress.state(of: rule.id)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        NavigationLink(value: GrammarRoute.rule(rule.id)) {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.headline)
                    Text(verbatim: GrammarLabels.level(rule.level)).font(.subheadline).foregroundStyle(Brand.secondaryText)
                }
                if state != .new {
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    stateLabel(state)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(title), \(GrammarLabels.levelSpoken(rule.level))"))
            .accessibilityValue(Text(verbatim: GrammarLabels.state(state)))
        }
    }

    @ViewBuilder
    private func stateLabel(_ state: RuleState) -> some View {
        switch state {
        case .practised:
            Label { Text("Practiced") } icon: { Image(systemName: "checkmark.circle.fill") }
                .font(.subheadline).foregroundStyle(Brand.secondaryText)
        case .inReview:
            Label { Text("In Review") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                .font(.subheadline).foregroundStyle(Brand.secondaryText)
        case .new:
            EmptyView()
        }
    }
}

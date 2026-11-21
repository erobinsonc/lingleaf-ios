import SwiftUI
import LingleafCore

/// A rule page (SPEC S21). This first version shows the title and counts the opening for "Recent"; the rule, its
/// examples and the button come in the next commit.
struct GrammarRuleView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrammarModel.self) private var grammar
    /// Opening a rule counts it for "Recent" once per push (S20).
    @State private var opened = false

    let rule: GrammarRule

    var body: some View {
        ScrollView {
            Text(verbatim: rule.title.text(for: model.chromeLanguage))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !opened else { return }
            opened = true
            grammar.opened(rule)
        }
    }
}

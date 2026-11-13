import Accessibility
import SwiftUI

/// The word card's definition: cut to three lines with "More" to read the rest, so the sentence's
/// translation stays in view at half height (SPEC S3). It is one Text for VoiceOver, which reads all of
/// it (`spoken`) whatever is shown; "More" appears only when something is cut.
struct ExpandableText: View {
    /// What is shown, with its source at the end.
    let text: Text
    /// What VoiceOver reads: the whole definition.
    let spoken: Text
    let alignment: TextAlignment
    /// Fill the width and line up with the leading edge (under the readings' rows); else as wide as it is.
    let fillsWidth: Bool

    @State private var expanded = false
    /// The text's height in full, and as shown now: more in full means something is cut.
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    private static let collapsedLines = 3

    /// Whether the limit cuts the text; known while collapsed, kept once it is expanded so it can fold again.
    @State private var foldable = false

    private func measured() {
        if !expanded { foldable = fullHeight > shownHeight + 1 }
    }

    var body: some View {
        VStack(alignment: fillsWidth ? .leading : .center, spacing: 0) {
            text
                .font(.footnote)
                .foregroundStyle(Brand.secondaryText)
                .multilineTextAlignment(alignment)
                .lineLimit(expanded ? nil : Self.collapsedLines)
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    shownHeight = $0
                    measured()
                }
                .accessibilityLabel(spoken)
                // The same text without a limit, unseen, to know whether the limit cuts it.
                .background {
                    text
                        .font(.footnote)
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            fullHeight = $0
                            measured()
                        }
                }
            if foldable {
                // LocalizedStringKey on purpose: a ternary of two literals would be a plain String, not localized.
                Button(expanded ? LocalizedStringKey("Less") : LocalizedStringKey("More")) {
                    expanded.toggle()
                    // VoiceOver reads the whole definition either way: say what changed.
                    AccessibilityNotification.Announcement(
                        String(localized: expanded ? "Full definition shown" : "Definition shortened")
                    ).post()
                }
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(expanded ? Text("Show less of the definition") : Text("Show the full definition"))
                // Voice Control says what is on screen: "tap More" ("tocar Más") must find it (WCAG 2.5.3).
                .accessibilityInputLabels([expanded ? Text("Less") : Text("More")])
            }
        }
    }
}

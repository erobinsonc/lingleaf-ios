import SwiftUI
import LingleafCore

/// Brand colours: dark-green ink and a highlighter yellow.
enum Brand {
    /// Adapts to dark mode (see AccentColor in the asset catalog).
    static let ink = Color.accentColor
    static let marker = Color(red: 0.96, green: 0.81, blue: 0.29)
    /// Underline of words being learned. The yellow marker is too light on a white page
    /// (≈1.5:1), so light mode uses dark amber #8A6A00; dark mode keeps the marker #F5CF4A.
    static let markerLine = dynamic(light: rgb(0x8A6A00), dark: rgb(0xF5CF4A))
    static let learned = Color(red: 0.16, green: 0.45, blue: 0.31)
    /// The sentence being read aloud: a warm grey on the paper (as on Android), not yellow.
    static let reading = dynamic(light: rgb(0xE4DFD3), dark: rgb(0x323A37))
    /// Streak text: #A0430A on light backgrounds, #FF8A50 on dark ones (both ≥4.5:1).
    static let streak = dynamic(light: rgb(0xA0430A), dark: rgb(0xFF8A50))
    /// Secondary text darker than the system's, so it passes WCAG AA (≥4.5:1) on list backgrounds.
    static let secondaryText = Color(uiColor: secondaryUIColor)
    /// Grey 0.30 / 0.74: ≈7.5:1 on grouped backgrounds, margin above AA that the audit's sampling needs.
    static let secondaryUIColor = dynamicUIColor(light: UIColor(white: 0.30, alpha: 1), dark: UIColor(white: 0.74, alpha: 1))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: dynamicUIColor(light: light, dark: dark))
    }

    private static func dynamicUIColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Credits and links shown in the app. Every address is a fixed constant here, never taken
/// from a server's answer, and opens in the system browser.
enum Credits {
    static let privacyPolicyURL = URL(string: "https://github.com/erobinsonc/lingleaf-ios/blob/main/PRIVACY.md")!
    /// Project Gutenberg vouches only for the US; the learner checks the rest.
    static let publicDomainNotice: LocalizedStringResource = "Public domain in the US. Outside the US, check your country's laws."
    /// Under a definition on the word card (Wiktionary's CC BY-SA asks for the source and any change).
    static let definitionNote: LocalizedStringResource = "Definition: Wiktionary (CC BY-SA), may be shortened"

    /// Names that keep their spelling in every language, so each one is found and linked.
    private static let definitionLinks: [(name: String, url: URL)] = [
        ("Wiktionary", URL(string: "https://en.wiktionary.org/")!),
        ("CC BY-SA 3.0/4.0", URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!),
        ("Free Dictionary API", URL(string: "https://dictionaryapi.dev/")!),
    ]

    /// "Definitions from Wiktionary, CC BY-SA 3.0/4.0, via Free Dictionary API.", each name a link.
    static var definitionsCredit: AttributedString {
        var text = AttributedString(localized: "Definitions from Wiktionary, CC BY-SA 3.0/4.0, via Free Dictionary API.")
        for link in definitionLinks {
            if let range = text.range(of: link.name) { text[range].link = link.url }
        }
        return text
    }
}

/// List section header with readable contrast.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title).foregroundStyle(Brand.secondaryText)
    }
}

/// Reading font: Georgia, scaled with Dynamic Type.
func readingFont(size: Double) -> Font {
    .custom("Georgia", size: size, relativeTo: .body)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// The time "due" is counted at: moves on when the app comes back and when the next word falls due.
    @State private var now = Date()

    var body: some View {
        // From the observed state, so the badge follows every review and save.
        let words = model.state.words
        let due = words.filter { $0.isDue(now) }.count
        let nextDue = words.filter { !$0.learned && $0.nextReview > now }.map(\.nextReview).min()
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            WordsView()
                .tabItem { Label("Words", systemImage: "rectangle.stack") }
                .badge(due)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // Inside `.environment(model)` (applied by LingleafApp), which the worker reads.
        .modifier(TranslationWorker())
        // Words saved offline or before a language was chosen get their translation.
        .task { model.translateMissing() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        // Sleeps until the next word falls due (a new review day), then counts again.
        // Keyed on the next due date, so an answer that moves it restarts the wait.
        .task(id: nextDue) {
            guard let nextDue else { return }
            try? await Task.sleep(for: .seconds(max(1, nextDue.timeIntervalSinceNow + 1)))
            if !Task.isCancelled { now = Date() }
        }
    }
}

struct BookCover: View {
    let title: String
    /// Dark tones only, so the white initial keeps ≥4.5:1 contrast.
    private static let palette: [Color] = [
        Color(red: 0.18, green: 0.42, blue: 0.37), Color(red: 0.24, green: 0.35, blue: 0.50),
        Color(red: 0.55, green: 0.27, blue: 0.07), Color(red: 0.56, green: 0.23, blue: 0.27),
        Color(red: 0.30, green: 0.36, blue: 0.15), Color(red: 0.43, green: 0.30, blue: 0.56),
    ]

    var body: some View {
        let seed = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        RoundedRectangle(cornerRadius: 6)
            .fill(Self.palette[seed % Self.palette.count])
            .frame(width: 44, height: 62)
            .overlay(Text(String(title.prefix(1))).font(.title2.bold()).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

struct LevelBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Brand.ink.opacity(0.15), in: Capsule())
            .foregroundStyle(Brand.ink)
            .accessibilityLabel(Text("Level \(level)"))
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            BookCover(title: book.title)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    if let level = book.level { LevelBadge(level: level) }
                    Text(book.author).font(.subheadline).foregroundStyle(Brand.secondaryText).lineLimit(1)
                }
                if book.progress > 0 {
                    ProgressView(value: book.progress).padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct DailyGoalCard: View {
    @Environment(AppModel.self) private var model
    /// The ring grows with Dynamic Type so the minutes inside it keep fitting.
    @ScaledMetric(relativeTo: .title2) private var ringSize: CGFloat = 64

    var body: some View {
        let goal = model.state.settings.dailyGoalMinutes
        let seconds = model.state.readingLog.isEmpty ? 0 : model.library.secondsToday()
        let streak = model.state.readingLog.isEmpty ? 0 : model.library.streak()
        let minutes = seconds / 60
        let fraction = min(1, Double(seconds) / Double(max(goal, 1) * 60))
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Brand.ink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // Hidden from VoiceOver: "N of M min today" below already says it.
                Text("\(minutes)").font(.title2.bold().monospacedDigit())
                    .accessibilityHidden(true)
            }
            .frame(width: ringSize, height: ringSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(fraction >= 1 ? "Today's goal done!" : "Read \(goal) minutes a day").font(.headline)
                Text("\(minutes) of \(goal) min today").foregroundStyle(Brand.secondaryText)
                if streak > 0 {
                    Label("\(streak) days in a row", systemImage: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(Brand.streak)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Lays its children out in rows, wrapping to a new row when one is full; rows are centred.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layoutRows(of: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layoutRows(of: subviews, width: bounds.width) {
            var x = bounds.minX + max(0, (bounds.width - row.width) / 2)
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutRows(of subviews: Subviews, width: CGFloat) -> [Row] {
        // A child wider than the row (very large text) is offered the row's width and wraps.
        let childProposal = ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(childProposal)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width += current.indices.isEmpty ? size.width : spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

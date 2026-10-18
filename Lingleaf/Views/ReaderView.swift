import Accessibility
import SwiftUI
import LingleafCore

/// A tapped word, ready for the word card.
struct WordSelection: Identifiable {
    let id = UUID()
    /// The word as it appears in the text ("animals").
    let word: String
    let sentence: String
    /// Where the word is in `sentence`, to mark it on the card.
    var rangeInSentence: WordRange?
    /// Set when the word is a helper or modal verb ("did" in "did not go").
    var function: FunctionWord?
    /// The paragraph and range the word came from, to mark it in the reader.
    var paragraph = 0
    var range = WordRange(0, 0)

    /// The verb group of a helper or modal verb ("did not go"), if there is one.
    var chunk: String? {
        function?.chunk.map { TextTools.substring(sentence, $0) }
    }
}

/// A paragraph ready for the reader: the linked text and the words in it being learned.
private struct MarkedParagraph {
    var text: AttributedString
    var learning: [LearningWord] = []
}

/// The words being learned in each paragraph, computed once per paragraph and set of learning
/// words. A class on purpose: filling it while the body runs changes no view state.
private final class LearningCache {
    private struct Entry {
        let text: String
        let learning: LearningIndex
        let ranges: Set<WordRange>
    }

    private var entries: [Int: Entry] = [:]

    func ranges(_ index: Int, _ text: String, _ learning: LearningIndex, compute: () -> Set<WordRange>) -> Set<WordRange> {
        if let entry = entries[index], entry.learning == learning, entry.text == text { return entry.ranges }
        let ranges = compute()
        entries[index] = Entry(text: text, learning: learning, ranges: ranges)
        return ranges
    }

    func clear() { entries = [:] }
}

/// A word being learned, located in its paragraph (for the VoiceOver rotor).
private struct LearningWord: Identifiable {
    let id: Int
    let word: String
    let range: Range<String.Index>
}

struct ReaderView: View {
    let bookID: String

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The word card's height, so the card drops its half-height panel when full height.
    @State private var cardDetent: PresentationDetent = .medium
    @State private var paragraphs: [String]?
    @State private var words: [[WordRange]] = []
    /// Each paragraph's words being learned, kept while the paragraph and the learning words stay
    /// the same: the body runs again on every step of reading aloud.
    @State private var learningCache = LearningCache()
    @State private var selection: WordSelection?
    @State private var position: Int?
    @State private var restored = false
    @State private var sessionStart: Date?
    /// "“beach” saved to Words" with Undo, after a word card button.
    @State private var undo: UndoMessage?
    /// The reader's visible height, to tell whether the half-height card covers the tapped word.
    @State private var viewportHeight: CGFloat = 0
    /// Reading aloud sentence by sentence (SPEC S6); made when the reader appears.
    @State private var reading: ReadAloudController?
    /// Paragraphs on screen, to start reading at the top of the screen and to follow the reading.
    @State private var visible: Set<Int> = []
    /// Whether the reader scrolls to follow the sentence being read; scrolling by hand stops it
    /// until that sentence is back on screen.
    @State private var following = true
    /// When the bottom bar appears, VoiceOver moves to Pause: the button it was on is gone.
    @AccessibilityFocusState private var pauseFocused: Bool

    private var book: Book? { model.state.books.first { $0.id == bookID } }

    var body: some View {
        Group {
            if let paragraphs {
                if paragraphs.isEmpty {
                    ContentUnavailableView("This book is empty.", systemImage: "doc.text")
                } else {
                    reader(paragraphs)
                }
            } else {
                ProgressView()
            }
        }
        .undoMessage($undo)
        .navigationTitle(book?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        // Once reading aloud starts, its controls sit at the bottom, in reach of the thumb (issue #33).
        .toolbar {
            if let reading, reading.current != nil { readAloudBar(reading) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let reading, reading.loop != nil {
                // Says how long the repeated stretch is.
                Text("Repeating \(reading.loopCount) sentences")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .modifier(BarBackground())
            }
        }
        .onChange(of: reading?.current == nil) { _, stopped in
            if !stopped { pauseFocused = true }
        }
        // VoiceOver hears the stretch grow.
        .onChange(of: reading?.loopCount) { _, count in
            guard let count, count > 0 else { return }
            AccessibilityNotification.Announcement(String(localized: "Repeating \(count) sentences")).post()
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selection) { selection in
            WordCardView(
                selection: selection, source: book?.title ?? "", fullHeight: cardDetent == .large,
                onReadFromHere: { readFrom(paragraph: selection.paragraph, offset: selection.range.start) }
            ) { message in
                undo = message
            }
            // With accessibility text sizes a half-height card shows almost nothing, and a word whose
            // sentence doesn't tell needs its readings in view (SPEC S3): open it full height.
            .presentationDetents(fullHeightCard(selection) ? [.large] : [.medium, .large], selection: $cardDetent)
            .onAppear { cardDetent = fullHeightCard(selection) ? .large : .medium }
            .presentationDragIndicator(.visible)
        }
        .environment(\.openURL, OpenURLAction { url in
            handle(url)
            return .handled
        })
        .task {
            let loaded = model.library.openBook(bookID)
            words = loaded.map(TextTools.wordRanges)
            learningCache.clear()
            paragraphs = loaded
        }
        .onAppear {
            startTimer()
            if reading == nil {
                let controller = ReadAloudController(speaker: model.speaker) { [model] in model.state.settings.speechRate }
                // Reading moves the saved position (SPEC S6).
                controller.onSentence = { [model, bookID] sentence in model.library.updateProgress(bookID, paragraph: sentence.paragraph) }
                reading = controller
            }
        }
        .onDisappear {
            stopTimer()
            reading?.pause()
            model.speaker.stop()
            model.library.flush()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startTimer()
            } else {
                stopTimer()
                // No reading aloud without the text on screen.
                reading?.pause()
            }
        }
        .onChange(of: position) { _, newValue in
            if restored, let newValue { model.library.updateProgress(bookID, paragraph: newValue) }
        }
    }

    private func reader(_ paragraphs: [String]) -> some View {
        let fontSize = model.state.settings.fontSize
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.9) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        let paragraph = marked(index, paragraphs[index])
                        Text(paragraph.text)
                            .font(readingFont(size: fontSize))
                            .lineSpacing(fontSize * 0.35)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tint(.primary)
                            // Each word being learned, announced as "<word>, learning".
                            .accessibilityRotor(Text("Learning words")) {
                                ForEach(paragraph.learning) { word in
                                    AccessibilityRotorEntry(Text("\(word.word), learning"), textRange: word.range)
                                }
                            }
                            .background {
                                // Each new sentence read in this paragraph: scroll if it left the screen.
                                if let current = reading?.current, current.paragraph == index {
                                    GeometryReader { geometry in
                                        Color.clear.onChange(of: current, initial: true) {
                                            follow(current, in: geometry.frame(in: .named(Self.readerSpace)), text: paragraphs[index], proxy: proxy)
                                        }
                                    }
                                }
                            }
                            .background {
                                // Measured once, when a word of this paragraph is tapped.
                                if let selected = selection, selected.paragraph == index {
                                    GeometryReader { geometry in
                                        Color.clear.onAppear {
                                            reveal(selected, in: geometry.frame(in: .named(Self.readerSpace)), text: paragraphs[index], proxy: proxy)
                                        }
                                    }
                                }
                            }
                            // A repeated stretch also gets a bar at the side, not only a fill.
                            .overlay(alignment: .leading) {
                                if let loop = reading?.loop, (loop.first.paragraph...loop.last.paragraph).contains(index) {
                                    Capsule().fill(Brand.secondaryText).frame(width: 3).offset(x: -10).accessibilityHidden(true)
                                }
                            }
                            .id(index)
                            .onScrollVisibilityChange(threshold: 0.01) { shown in
                                if shown { visible.insert(index) } else { visible.remove(index) }
                                // The sentence being read is back on screen: follow it again.
                                if shown, reading?.current?.paragraph == index { following = true }
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $position, anchor: .top)
            // Scrolling by hand while reading aloud: stop following until the sentence is back.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { following = false }
            }
            // The next sentence is in a paragraph off screen: bring it into view.
            .onChange(of: reading?.current?.paragraph) { _, paragraph in
                guard let paragraph, following, !visible.contains(paragraph) else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(paragraph, anchor: UnitPoint(x: 0, y: 0.1)) }
            }
            .coordinateSpace(.named(Self.readerSpace))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                ProgressView(value: book?.progress ?? 0)
                    .accessibilityLabel(Text("Reading progress"))
                    .accessibilityValue(Text(book?.progress ?? 0, format: .percent.precision(.fractionLength(0))))
            }
            .onAppear {
                proxy.scrollTo(min(book?.progressParagraph ?? 0, paragraphs.count - 1), anchor: .top)
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    restored = true
                }
            }
        }
    }

    private static let readerSpace = "reader"

    /// Keeps the sentence being read on screen: when it starts below 85 % of the visible
    /// height or above the top, scroll it to the upper third (estimated from its offset, as in
    /// `reveal`). Not while the reader is scrolled away by hand.
    private func follow(_ sentence: SentencePosition, in frame: CGRect, text: String, proxy: ScrollViewProxy) {
        let length = (text as NSString).length
        guard following, viewportHeight > 0, length > 0 else { return }
        let fraction = CGFloat(sentence.range.start) / CGFloat(length)
        let sentenceY = frame.minY + frame.height * fraction
        guard sentenceY > viewportHeight * 0.85 || sentenceY < 0 else { return }
        let target = viewportHeight / 3 - frame.height * fraction
        let difference = viewportHeight - frame.height
        let anchor = abs(difference) < 1 ? UnitPoint.top : UnitPoint(x: 0, y: target / difference)
        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(sentence.paragraph, anchor: anchor) }
    }

    /// Previous sentence · Pause/Play · Repeat sentence, while reading aloud or paused (SPEC S6).
    /// While repeating, Previous sentence adds one sentence to the stretch.
    @ToolbarContentBuilder
    private func readAloudBar(_ reading: ReadAloudController) -> some ToolbarContent {
        let repeating = reading.loop != nil
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            Button {
                following = true
                reading.previous()
            } label: {
                Label(repeating ? LocalizedStringKey("Add previous sentence") : "Previous sentence", systemImage: "backward.end")
            }
            Button {
                if reading.isReading {
                    reading.pause()
                } else {
                    following = true
                    reading.play()
                }
            } label: {
                if reading.isReading {
                    Label("Pause", systemImage: "pause.fill")
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .accessibilityFocused($pauseFocused)
            // A system toggle: VoiceOver says whether it is on.
            Toggle(isOn: Binding(get: { reading.loop != nil }, set: { _ in reading.toggleRepeat() })) {
                Label("Repeat sentence", systemImage: "repeat.1")
            }
            .toggleStyle(.button)
            Spacer()
        }
    }

    /// Starts reading aloud at the sentence holding `offset` of paragraph `paragraph`.
    private func readFrom(paragraph: Int, offset: Int) {
        guard let paragraphs, let start = ReadAloud.start(paragraphs, paragraph, offset: offset) else { return }
        following = true
        reading?.read(paragraphs, from: start)
    }

    /// The half-height card covers the lower half of the reader: when the tapped word is
    /// there, scroll so it sits near the top. Its height in the paragraph is estimated from
    /// its offset. A full-height card (accessibility text sizes) covers it anyway.
    private func reveal(_ selected: WordSelection, in frame: CGRect, text: String, proxy: ScrollViewProxy) {
        let length = (text as NSString).length
        guard !dynamicTypeSize.isAccessibilitySize, viewportHeight > 0, length > 0 else { return }
        let fraction = CGFloat(selected.range.start) / CGFloat(length)
        let wordY = frame.minY + frame.height * fraction
        guard wordY > viewportHeight * 0.4 || wordY < 0 else { return }
        // `scrollTo` lines up the same unit point of the paragraph and of the viewport;
        // this one puts the word at 20 % of the visible height.
        let target = viewportHeight * 0.2 - frame.height * fraction
        let difference = viewportHeight - frame.height
        let anchor = abs(difference) < 1 ? UnitPoint.top : UnitPoint(x: 0, y: target / difference)
        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(selected.paragraph, anchor: anchor) }
    }

    /// The sentences of paragraph `index` to highlight: the repeated stretch when repeating,
    /// else the sentence being read.
    private func highlighted(_ index: Int, _ text: String) -> [WordRange] {
        guard let loop = reading?.loop else {
            return reading?.current.flatMap { $0.paragraph == index ? [$0.range] : nil } ?? []
        }
        guard (loop.first.paragraph...loop.last.paragraph).contains(index) else { return [] }
        return ReadAloud.sentences(text).filter { range in
            (index > loop.first.paragraph || range.start >= loop.first.range.start)
                && (index < loop.last.paragraph || range.end <= loop.last.range.end)
        }
    }

    /// Every word is a link (`lingleaf://word?p=…&o=…&e=…`); words being learned are underlined
    /// (dark amber in light mode, the yellow marker in dark mode) on a light yellow tint.
    private func marked(_ index: Int, _ text: String) -> MarkedParagraph {
        var attributed = AttributedString(text)
        var learning: [LearningWord] = []
        let learningRanges = learningCache.ranges(index, text, model.state.learningIndex) {
            model.learningRanges(text, words[index])
        }
        for range in words[index] {
            guard let stringRange = Range(range.nsRange, in: text),
                  let attributedRange = Range(stringRange, in: attributed) else { continue }
            var components = URLComponents()
            components.scheme = "lingleaf"
            components.host = "word"
            components.queryItems = [
                URLQueryItem(name: "p", value: String(index)),
                URLQueryItem(name: "o", value: String(range.start)),
                URLQueryItem(name: "e", value: String(range.end)),
            ]
            attributed[attributedRange].link = components.url
            let word = String(text[stringRange])
            if let selected = selection, selected.paragraph == index, selected.range == range {
                // The word the card is about: solid marker with black text (≈13:1 in both modes),
                // distinct from the learning underline. Not a link meanwhile, or the link tint
                // would replace the black (the card is open over the reader anyway).
                attributed[attributedRange].link = nil
                attributed[attributedRange].backgroundColor = Brand.marker
                attributed[attributedRange].foregroundColor = .black
                attributed[attributedRange].accessibilityTextCustom = [String(localized: "Selected")]
            } else if learningRanges.contains(range) {
                attributed[attributedRange].underlineStyle = Text.LineStyle(pattern: .solid, color: Brand.markerLine)
                attributed[attributedRange].backgroundColor = Brand.marker.opacity(0.18)
                // Assistive technologies describe custom text attributes alongside the text.
                attributed[attributedRange].accessibilityTextCustom = [String(localized: "Learning")]
                learning.append(LearningWord(id: range.start, word: word, range: stringRange))
            }
        }
        // The sentences being read or repeated, on a neutral fill (yellow marks words being learned).
        for range in highlighted(index, text) {
            guard let stringRange = Range(range.nsRange, in: text), let sentence = Range(stringRange, in: attributed) else { continue }
            for run in attributed[sentence].runs where run.backgroundColor == nil {
                attributed[run.range].backgroundColor = Brand.reading
            }
        }
        return MarkedParagraph(text: attributed, learning: learning)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if reading?.current == nil {
                Button {
                    // From the top of the screen; once started, the bar at the bottom has the controls.
                    if let paragraphs, !paragraphs.isEmpty {
                        readFrom(paragraph: min(position ?? book?.progressParagraph ?? 0, paragraphs.count - 1), offset: 0)
                    }
                } label: {
                    Label { Text("Read aloud") } icon: { inkIcon("speaker.wave.2") }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
            Menu {
                Button("Larger text", systemImage: "plus.magnifyingglass") {
                    model.library.updateSettings { $0.fontSize = min($0.fontSize + 2, 34) }
                }
                Button("Smaller text", systemImage: "minus.magnifyingglass") {
                    model.library.updateSettings { $0.fontSize = max($0.fontSize - 2, 14) }
                }
            } label: {
                Label { Text("Text size") } icon: { inkIcon("textformat.size") }
            }
            .labelStyle(.iconOnly)
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    /// The default toolbar grey measured 2.75:1 and toolbar tint was lost after the word
    /// sheet closed, so these items use the plain style and colour the glyph themselves.
    private func inkIcon(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(Brand.ink)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func handle(_ url: URL) {
        guard url.scheme == "lingleaf",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let index = items.first(where: { $0.name == "p" })?.value.flatMap(Int.init),
              let start = items.first(where: { $0.name == "o" })?.value.flatMap(Int.init),
              let end = items.first(where: { $0.name == "e" })?.value.flatMap(Int.init),
              let paragraphs, paragraphs.indices.contains(index),
              0 <= start, start < end, end <= (paragraphs[index] as NSString).length
        else { return }
        // Tapping a word pauses reading aloud: its card has its own Listen.
        reading?.pause()
        let paragraph = paragraphs[index]
        let sentenceRange = TextTools.sentenceRangeAt(paragraph, start)
        let sentence = TextTools.substring(paragraph, sentenceRange)
        let inSentence = WordRange(start - sentenceRange.start, end - sentenceRange.start)
        let valid = sentenceRange.start <= start && end <= sentenceRange.end
        selection = WordSelection(
            word: TextTools.substring(paragraph, WordRange(start, end)),
            sentence: sentence,
            rangeInSentence: valid ? inSentence : nil,
            function: valid ? FunctionWords.analyze(sentence, inSentence) : nil,
            paragraph: index,
            range: WordRange(start, end)
        )
    }

    private func fullHeightCard(_ selection: WordSelection) -> Bool {
        if dynamicTypeSize.isAccessibilitySize { return true }
        guard selection.function == nil, let range = selection.rangeInSentence else { return false }
        return !IrregularVerbs.shared.choices(in: selection.sentence, at: range).isEmpty
    }

    private func startTimer() {
        if sessionStart == nil { sessionStart = .now }
    }

    private func stopTimer() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        model.library.addReadingTime(Int(Date.now.timeIntervalSince(start)))
    }
}

/// Behind the line above the bottom bar: glass on iOS 26, like the bar; the bar material before.
private struct BarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule()).padding(.horizontal, 16)
        } else {
            content.background(.bar)
        }
    }
}

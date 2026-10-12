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
    @State private var selection: WordSelection?
    @State private var position: Int?
    @State private var restored = false
    @State private var sessionStart: Date?
    /// "“beach” saved to Words" with Undo, after a word card button.
    @State private var undo: UndoMessage?
    /// The reader's visible height, to tell whether the half-height card covers the tapped word.
    @State private var viewportHeight: CGFloat = 0

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
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selection) { selection in
            WordCardView(selection: selection, source: book?.title ?? "", fullHeight: cardDetent == .large) { message in
                undo = message
            }
            // With accessibility text sizes a half-height card shows almost nothing; open it full height.
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large], selection: $cardDetent)
            .onAppear { cardDetent = dynamicTypeSize.isAccessibilitySize ? .large : .medium }
            .presentationDragIndicator(.visible)
        }
        .environment(\.openURL, OpenURLAction { url in
            handle(url)
            return .handled
        })
        .task {
            let loaded = model.library.openBook(bookID)
            words = loaded.map(TextTools.wordRanges)
            paragraphs = loaded
        }
        .onAppear { startTimer() }
        .onDisappear {
            stopTimer()
            model.speaker.stop()
            model.library.flush()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startTimer() } else { stopTimer() }
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
                                // Measured once, when a word of this paragraph is tapped.
                                if let selected = selection, selected.paragraph == index {
                                    GeometryReader { geometry in
                                        Color.clear.onAppear {
                                            reveal(selected, in: geometry.frame(in: .named(Self.readerSpace)), text: paragraphs[index], proxy: proxy)
                                        }
                                    }
                                }
                            }
                            .id(index)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $position, anchor: .top)
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

    /// Every word is a link (`lingleaf://word?p=…&o=…&e=…`); words being learned are underlined
    /// (dark amber in light mode, the yellow marker in dark mode) on a light yellow tint.
    private func marked(_ index: Int, _ text: String) -> MarkedParagraph {
        var attributed = AttributedString(text)
        var learning: [LearningWord] = []
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
            } else if model.isLearning(word) {
                attributed[attributedRange].underlineStyle = Text.LineStyle(pattern: .solid, color: Brand.markerLine)
                attributed[attributedRange].backgroundColor = Brand.marker.opacity(0.18)
                // Assistive technologies describe custom text attributes alongside the text.
                attributed[attributedRange].accessibilityTextCustom = [String(localized: "Learning")]
                learning.append(LearningWord(id: range.start, word: word, range: stringRange))
            }
        }
        return MarkedParagraph(text: attributed, learning: learning)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                if model.speaker.isSpeaking {
                    model.speaker.stop()
                } else if let paragraphs, !paragraphs.isEmpty {
                    let index = min(position ?? book?.progressParagraph ?? 0, paragraphs.count - 1)
                    model.speaker.speak(paragraphs[index], rate: model.state.settings.speechRate)
                }
            } label: {
                if model.speaker.isSpeaking {
                    Label { Text("Stop reading") } icon: { inkIcon("stop.circle") }
                } else {
                    Label { Text("Read aloud") } icon: { inkIcon("speaker.wave.2") }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
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

    private func startTimer() {
        if sessionStart == nil { sessionStart = .now }
    }

    private func stopTimer() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        model.library.addReadingTime(Int(Date.now.timeIntervalSince(start)))
    }
}

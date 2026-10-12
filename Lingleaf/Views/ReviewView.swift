import Accessibility
import SwiftUI
import LingleafCore

/// Recall-first review of due words with spaced repetition (S7): the word alone, then
/// "Show meaning" reveals the translation, the sentence it came from and that sentence's
/// translation; only then "Again" or "Got it".
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [VocabWord] = []
    @State private var total = 0
    @State private var reviewed = 0
    @State private var revealed = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 20) {
            if let word = queue.first {
                ProgressView(value: Double(reviewed), total: Double(max(total, 1)))
                    .accessibilityLabel(Text("Review progress"))
                    .accessibilityValue(Text("\(reviewed) of \(total)"))
                ScrollView {
                    // The saved record, not the queued copy: a translation may arrive while reviewing.
                    card(model.state.word(word.word) ?? word)
                        .padding(.vertical, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                if revealed { answers }
            } else if loaded {
                finished
            }
        }
        .padding()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.translateMissing()
            guard !loaded else { return }
            queue = model.library.reviewSession()
            total = queue.count
            loaded = true
        }
    }

    /// Only after the meaning is shown: recall comes first.
    private var answers: some View {
        HStack(spacing: 12) {
            Button { answer(correct: false) } label: {
                Text("Again").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button { answer(correct: true) } label: {
                Text("Got it").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.headline)
    }

    /// "Done for today. 12 more tomorrow."
    private var finished: some View {
        let tomorrow = model.library.dueByEndOfTomorrow()
        return ContentUnavailableView {
            Label("Done for today.", systemImage: "checkmark.seal.fill")
        } description: {
            if tomorrow > 0 { Text("\(tomorrow) more tomorrow.") }
        } actions: {
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private func card(_ word: VocabWord) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(word.word).font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
                Button {
                    model.speaker.speak(word.word, rate: model.state.settings.speechRate)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.circle.fill").labelStyle(.iconOnly).font(.title)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            if revealed {
                meaning(word)
            } else {
                Button {
                    withAnimation { revealed = true }
                    announceMeaning(of: word)
                } label: {
                    // Ink on the plain background (6:1), not ink on a light ink tint, which
                    // the audit measured just under 4.5:1; wraps at large text sizes.
                    Text("Show meaning")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Brand.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Color(uiColor: .systemBackground), in: Capsule())
                        .overlay(Capsule().stroke(Brand.ink, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }

    /// The translation, then the sentence the word was saved from (the word in bold),
    /// its translation and a button to hear it.
    @ViewBuilder
    private func meaning(_ word: VocabWord) -> some View {
        VStack(spacing: 4) {
            if !word.phonetic.isEmpty { Text(word.phonetic).foregroundStyle(Brand.secondaryText) }
            if word.translation.isEmpty {
                Text("No translation yet. Connect to the internet once to get it.")
                    .font(.callout)
                    .foregroundStyle(Brand.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(word.translation).font(.title2).multilineTextAlignment(.center)
            }
        }
        if !word.context.isEmpty {
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.marked(word.context, word: word.word)).font(readingFont(size: 17)).italic()
                        .fixedSize(horizontal: false, vertical: true)
                    if let translation = word.contextTranslation {
                        Text(translation).font(.callout).foregroundStyle(Brand.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    model.speaker.speak(word.context, rate: model.state.settings.speechRate)
                } label: {
                    Label("Listen to the sentence", systemImage: "speaker.wave.1")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `sentence` with the saved word in bold: its inflected forms ("animals" for "animal"),
    /// or, for a saved group of words, that group.
    static func marked(_ sentence: String, word: String) -> AttributedString {
        var text = AttributedString(sentence)
        var ranges: [Range<String.Index>] = []
        if word.contains(" ") {
            if let range = sentence.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) { ranges.append(range) }
        } else {
            for wordRange in TextTools.wordRanges(sentence) {
                let token = TextTools.substring(sentence, wordRange)
                if TextTools.matchKeys(token).contains(word), let range = Range(wordRange.nsRange, in: sentence) {
                    ranges.append(range)
                }
            }
        }
        for range in ranges {
            guard let marked = Range(range, in: text) else { continue }
            text[marked].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    /// The button VoiceOver was on disappears; say what appeared in its place.
    private func announceMeaning(of word: VocabWord) {
        var announcement = AttributedString(
            word.translation.isEmpty
                ? String(localized: "No translation yet. Connect to the internet once to get it.") : word.translation
        )
        // High priority: not cut off by VoiceOver moving focus away from the vanished button.
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func answer(correct: Bool) {
        guard !queue.isEmpty else { return }
        let word = queue.removeFirst()
        if correct {
            reviewed += 1
        } else {
            queue.append(word)
        }
        revealed = false
        model.library.answerReview(word.word, correct: correct)
    }
}

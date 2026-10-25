import Accessibility
import SwiftUI
import LingleafCore

/// Recall-first review of due words with spaced repetition (S7): the word alone, then
/// "Show meaning" reveals the translation, the sentence it came from and that sentence's
/// translation; only then "Again" or "I remembered".
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
                // The count beside the bar: at the start an empty bar alone can read as "done".
                HStack(spacing: 12) {
                    // The bar stays the accessible element (a progress indicator), with the count as its value.
                    ProgressView(value: Double(reviewed), total: Double(max(total, 1)))
                        .accessibilityLabel(Text("Review progress"))
                        .accessibilityValue(Text("\(reviewed) of \(total)"))
                    Text("\(reviewed) of \(total)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Brand.secondaryText)
                        .accessibilityHidden(true)
                }
                ScrollView {
                    // The saved record, not the queued copy: a translation may arrive while reviewing.
                    card(model.state.words.first { $0.id == word.id } ?? word)
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
            startSession()
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
                Text("I remembered").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.headline)
    }

    /// "Done for today. 12 words tomorrow.", or, when more words are due now than one
    /// session holds, "Done for now. 15 more due today." with Keep going.
    private var finished: some View {
        let dueNow = model.library.dueWords().count
        let tomorrow = model.library.dueByEndOfTomorrow()
        return ContentUnavailableView {
            // A solid seal in the brand colour (not the default grey, which reads as disabled,
            // nor hierarchical layers, which fade on black); the title keeps the primary colour.
            Label {
                if dueNow > 0 { Text("Done for now.") } else { Text("Done for today.") }
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Brand.ink)
            }
        } description: {
            if dueNow > 0 {
                Text("\(dueNow) more due today.")
            } else if tomorrow > 0 {
                Text("\(tomorrow) words tomorrow.")
            }
        } actions: {
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            if dueNow > 0 {
                Button("Keep going") { startSession() }.buttonStyle(.bordered)
            }
        }
    }

    private func startSession() {
        queue = model.library.reviewSession()
        total = queue.count
        reviewed = 0
        revealed = false
    }

    private func card(_ word: VocabWord) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // A helper or modal verb is saved as its verb group ("did not go").
                Text(verbatim: model.state.displayName(word)).font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
                Button {
                    // A verb with the table's spoken base ("tare" for "tear"), a noun as written (SPEC S7).
                    let spoken = word.kind == nil ? IrregularVerbs.shared.spokenHeadword(word.word, sense: word.sense) : word.word
                    model.speaker.speak(spoken, rate: model.state.settings.speechRate)
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
            if !word.phonetic.isEmpty, word.kind == nil { Text(word.phonetic).foregroundStyle(Brand.secondaryText) }
            if let meanings = word.meanings, word.isUnsure {
                // Saved while its sentence didn't tell: both readings, as on the card (SPEC S7).
                ForEach(Array(meanings.enumerated()), id: \.offset) { _, meaning in
                    (Text(verbatim: meaning.text.isEmpty ? meaning.label : "\(meaning.label) — ")
                        + Text(ReadingChoicesView.meaningText(meaning.text, language: meaning.language)))
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if word.translation.isEmpty {
                Text("No translation yet. Connect to the internet once to get it.")
                    .font(.callout)
                    .foregroundStyle(Brand.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(ReadingChoicesView.meaningText(word.translation, language: word.translationLanguage, isolated: false))
                    .font(.title2).multilineTextAlignment(.center)
            }
        }
        // A verb group saved without one is the sentence itself: not twice.
        if !word.context.isEmpty, TextTools.normalize(word.context) != word.word {
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.marked(word.context, word: word)).font(readingFont(size: 17)).italic()
                        .fixedSize(horizontal: false, vertical: true)
                    // Only in the current translation language; another one is translated meanwhile.
                    if let translation = word.contextTranslation(in: model.targetLanguage) {
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

    /// `sentence` with the saved word in bold: only the occurrence that was tapped when the record
    /// knows it (SPEC S7), else its forms read in the sentence, or the saved group of words.
    static func marked(_ sentence: String, word: VocabWord) -> AttributedString {
        var text = AttributedString(sentence)
        let ranges = word.formRange.map { [$0] } ?? TextTools.occurrences(of: word, in: sentence)
        for range in ranges {
            guard let stringRange = Range(range.nsRange, in: sentence), let marked = Range(stringRange, in: text) else { continue }
            text[marked].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    /// The button VoiceOver was on disappears; say what appeared in its place.
    private func announceMeaning(of word: VocabWord) {
        let readings = word.isUnsure ? word.meanings?.map { $0.text.isEmpty ? $0.label : "\($0.label), \($0.text)" } : nil
        var announcement = AttributedString(
            readings?.joined(separator: ". ") ?? (word.translation.isEmpty
                ? String(localized: "No translation yet. Connect to the internet once to get it.") : word.translation)
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
        model.library.answerReview(word.word, sense: word.sense, correct: correct)
    }
}

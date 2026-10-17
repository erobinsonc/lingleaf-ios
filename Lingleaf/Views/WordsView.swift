import SwiftUI
import LingleafCore

struct WordsView: View {
    @Environment(AppModel.self) private var model
    @State private var showLearned = false
    /// "“beach” deleted" with Undo, after deleting a word.
    @State private var undo: UndoMessage?

    var body: some View {
        let due = model.library.dueWords().count
        let words = model.state.words.filter { $0.learned == showLearned }
        NavigationStack {
            List {
                Section {
                    // A disabled link would be dimmed below readable contrast, so with
                    // nothing due the row is plain text instead.
                    if due > 0 {
                        NavigationLink {
                            ReviewView()
                        } label: {
                            reviewSummary(due: due)
                        }
                    } else {
                        reviewSummary(due: due)
                    }
                }

                Picker("Filter", selection: $showLearned) {
                    Text("Learning").tag(false)
                    Text("Known").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if words.isEmpty {
                    Group {
                        if showLearned {
                            Text("No known words yet.")
                        } else {
                            Text("No words yet. While reading, tap a word and choose Save word.")
                        }
                    }
                    .foregroundStyle(Brand.secondaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
                ForEach(words) { word in
                    WordRow(word: word) { delete(word) }
                }
            }
            .navigationTitle("Words")
            .undoMessage($undo)
        }
        // Words saved offline, or in another language, get their translation on the device.
        .onAppear { model.translateMissing() }
    }

    /// Deletes at once (no confirmation) and offers Undo for 5 s, which puts the word back as it was.
    private func delete(_ word: VocabWord) {
        let library = model.library
        library.deleteWord(word.word)
        undo = UndoMessage(text: String(localized: "“\(word.word)” deleted"), seconds: 5) {
            library.restoreWord(word.word, previous: word)
        }
    }

    private func reviewSummary(due: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack").foregroundStyle(Brand.ink).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review now").font(.body)
                Group {
                    if due > 0 {
                        Text("\(due) words to review")
                    } else if model.state.words.isEmpty {
                        Text("Save words while you read.")
                    } else {
                        Text("Nothing to review. Come back tomorrow!")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WordRow: View {
    let word: VocabWord
    let onDelete: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.word).font(.headline)
                    if !word.phonetic.isEmpty, word.kind == nil {
                        Text(word.phonetic).font(.caption).foregroundStyle(Brand.secondaryText)
                    }
                }
                // "do · Helper verb"; a contraction has no label: its base ("it is") says what it is.
                let detail = [word.base, word.kind.flatMap(\.label)].compactMap { $0 }.filter { !$0.isEmpty }
                if word.kind != nil, !detail.isEmpty {
                    Text(verbatim: detail.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Brand.secondaryText)
                }
                if !word.translation.isEmpty { Text(word.translation) }
                // A verb group saved without one is the sentence itself: not twice.
                if !word.context.isEmpty, TextTools.normalize(word.context) != word.word {
                    Text(word.context).font(.caption).italic().foregroundStyle(Brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // One VoiceOver element per word ("beach, /biːtʃ/, playa, …") instead of
            // several small text fragments; Listen stays a separate button.
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                model.speaker.speak(word.word, rate: model.state.settings.speechRate)
            } label: {
                Label { Text("Listen to \(word.word)") } icon: { Image(systemName: "speaker.wave.2") }.labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .leading) {
            Button {
                model.library.setLearned(word.word, !word.learned)
            } label: {
                stateActionTitle
            }
            .tint(word.learned ? .orange : Brand.learned)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete word", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: stateActionTitle) {
            model.library.setLearned(word.word, !word.learned)
        }
        .accessibilityAction(named: Text("Delete word"), onDelete)
    }

    /// Known words go back to review; the others are marked as known.
    private var stateActionTitle: Text {
        if word.learned {
            return Text("Review again")
        }
        return Text("Mark as known")
    }
}

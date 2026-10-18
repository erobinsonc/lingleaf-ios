import Foundation

/// A saved word corrected to match its sentence (SPEC S18): "leave" → "left".
public struct Correction: Codable, Hashable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The corrections still shown on Words and the words as they were, for Undo.
struct CorrectionsRecord: Codable {
    var corrections: [Correction]
    var before: [VocabWord]
    /// The ids of the corrected words, so Undo keeps words saved since.
    var corrected: [String]
}

/// A reading of a word saved unsure whose meaning is still to be translated.
public struct MeaningRequest: Equatable, Sendable {
    /// The saved word's `id`.
    public let id: String
    public let index: Int
    /// What to translate: "to leave", "the left".
    public let label: String
}

extension Library {
    static let correctionsFile = "corrections.json"
    static let correctionsDone = "corrections-v2"
    /// Most corrections kept for the card; Undo still puts every word back.
    static let maxCorrections = 500

    /// Spellings the irregular-verb list linked before the table (no sentence read): what a word
    /// saved then may have been tapped as.
    private static let oldLinks: [String: String] = [
        "left": "leave", "saw": "see", "thought": "think", "found": "find", "felt": "feel", "fell": "fall",
        "rose": "rise", "spoke": "speak", "lives": "life", "leaves": "leaf",
    ]

    func loadCorrections() -> CorrectionsRecord? {
        guard var record = decode(CorrectionsRecord.self, Self.correctionsFile) else { return nil }
        record.corrections = record.corrections.prefix(Self.maxCorrections).map {
            Correction(from: TextTools.truncated($0.from, 40), to: TextTools.truncated($0.to, 40))
        }
        record.before = record.before.map { $0.bounded() }
        record.corrected = record.corrected.map { TextTools.truncated($0, 60) }
        return record
    }

    /// Once after updating, on the device: re-reads each saved word against its sentence (SPEC S18).
    /// A certain different reading becomes that word with its sense; an unsure one whose base
    /// came from the old list becomes the tapped form with both readings. Corrected words are
    /// translated again and due now; one that becomes a word already saved merges into it.
    @discardableResult
    public func correctWordsIfNeeded() -> [Correction] {
        guard storage.read(Self.correctionsDone) == nil else { return [] }
        storage.write(Self.correctionsDone, "1")
        let before = state.words
        var corrections: [Correction] = []
        var unchanged: [VocabWord] = []
        var changed: [VocabWord] = []
        for word in before {
            if let corrected = corrected(word) {
                corrections.append(Correction(from: word.word, to: corrected.word))
                changed.append(corrected)
            } else {
                unchanged.append(word)
            }
        }
        guard !corrections.isEmpty else { return [] }
        // Merged into a word already saved under the same name and sense: that one stays.
        var ids = Set(unchanged.map(\.id))
        let merged = unchanged + changed.filter { ids.insert($0.id).inserted }
        state.words = merged.sorted { $0.createdAt > $1.createdAt }
        state.corrections = Array(corrections.prefix(Self.maxCorrections))
        save(state.words, "words.json")
        let record = CorrectionsRecord(corrections: state.corrections, before: before, corrected: changed.map(\.id))
        save(record, Self.correctionsFile)
        return corrections
    }

    /// `word` read again in its sentence, or nil when it stays as it is.
    func corrected(_ word: VocabWord) -> VocabWord? {
        guard word.kind == nil, word.sense == nil, word.meanings == nil, !word.context.isEmpty else { return nil }
        let table = IrregularVerbs.shared
        let words = Words(word.context as NSString)
        // The word as tapped: the first homograph of the sentence the old list linked to it.
        guard let i = words.ranges.indices.first(where: { k in
            let token = words.token(k)
            guard table.homographs[token] != nil else { return false }
            var old: Set<String> = [token]
            if let link = Self.oldLinks[token] { old.insert(link) }
            old.formUnion(TextTools.candidates(token, link: nil))
            return old.contains(word.word)
        }), let reading = table.resolve(words, i) else { return nil }
        let token = words.token(i)
        var corrected = word
        if reading.kind != .unsure {
            guard reading.base != word.word else { return nil }
            corrected.word = reading.base
            corrected.sense = table.sense(of: reading)
        } else {
            guard !TextTools.matchKeys(words, i).contains(word.word) else { return nil }
            let target = state.settings.targetLanguage
            corrected.word = token
            corrected.meanings = table.choices(words, i).map { choice in
                let spanish = ReadingTranslation.isSpanish(target) && choice.kind == .verb
                    ? table.spanishMeaning(of: choice.base, all: false) : nil
                return SavedMeaning(label: choice.label, sense: choice.sense, base: choice.base, text: spanish ?? "",
                                    language: spanish == nil ? nil : target)
            }
        }
        corrected.form = words.surface(i)
        corrected.formStart = words.ranges[i].start
        corrected.formEnd = words.ranges[i].end
        // Translated again (later when offline); due now: it was rehearsed with a wrong meaning.
        corrected.translation = ""
        corrected.translationLanguage = nil
        corrected.phonetic = ""
        if !corrected.learned { corrected.nextReview = min(corrected.nextReview, now()) }
        return corrected
    }

    /// Undo on the card: every word as it was before the corrections.
    public func undoCorrections() {
        guard let record = loadCorrections() else { return }
        let before = Set(record.before.map(\.id)), corrected = Set(record.corrected)
        // Words saved since stay; the corrected ones go back to what they were.
        let since = state.words.filter { !before.contains($0.id) && !corrected.contains($0.id) }
        state.words = (record.before + since).sorted { $0.createdAt > $1.createdAt }
        save(state.words, "words.json")
        closeCorrections()
    }

    /// Close on the card: the corrections stay.
    public func closeCorrections() {
        storage.delete(Self.correctionsFile)
        state.corrections = []
    }

    // MARK: Translations of readings

    /// Fills in, from the table, what needs no translator in `target` (Spanish): a saved verb's
    /// meanings and a verb reading of a word saved unsure.
    public func fillTableTranslations(_ target: String) {
        guard ReadingTranslation.isSpanish(target) else { return }
        let table = IrregularVerbs.shared
        for var word in state.words where word.kind == nil {
            var changed = false
            if let sense = word.sense, sense != Sense.noun, word.translation.isEmpty || word.translationLanguage != target,
               let spanish = table.spanishMeaning(of: word.word, sense: sense) {
                word.translation = spanish
                word.translationLanguage = target
                changed = true
            }
            if var meanings = word.meanings {
                for index in meanings.indices where meanings[index].sense != Sense.noun
                    && (meanings[index].text.isEmpty || meanings[index].language != target) {
                    if let spanish = table.spanishMeaning(of: meanings[index].base, sense: meanings[index].sense, all: false) {
                        meanings[index].text = spanish
                        meanings[index].language = target
                        changed = true
                    }
                }
                word.meanings = meanings
                word.translation = Self.joined(meanings, target) ?? word.translation
            }
            if changed { replace(word) }
        }
    }

    /// The readings of words saved unsure still to translate into `target`.
    public func meaningsNeedingTranslation(_ target: String) -> [MeaningRequest] {
        state.words.flatMap { word in
            (word.meanings ?? []).enumerated().compactMap { index, meaning in
                meaning.text.isEmpty || meaning.language != target ? MeaningRequest(id: word.id, index: index, label: meaning.label) : nil
            }
        }
    }

    /// Records the translation of a reading of a word saved unsure ("the left" → "la izquierda"),
    /// without the article or infinitive marker; the word's translation is then its readings'.
    public func setMeaning(_ id: String, index: Int, text: String, language: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, var word = state.words.first(where: { $0.id == id }),
              var meanings = word.meanings, meanings.indices.contains(index) else { return }
        let cleaned = ReadingTranslation.cleaned(text, noun: meanings[index].sense == Sense.noun, language: language)
        meanings[index].text = cleaned
        meanings[index].language = language
        word.meanings = meanings
        word.translation = Self.joined(meanings, language) ?? word.translation
        word.translationLanguage = language
        replace(word)
    }

    /// "irse, salir · izquierda" once every reading has its meaning in `language`.
    static func joined(_ meanings: [SavedMeaning], _ language: String?) -> String? {
        guard meanings.allSatisfy({ !$0.text.isEmpty && $0.language == language }) else { return nil }
        return meanings.map(\.text).joined(separator: " · ")
    }
}

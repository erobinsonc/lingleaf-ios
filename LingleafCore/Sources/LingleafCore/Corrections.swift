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

/// One word the correction changed: as it was, and what it became (nil when it merged into
/// `mergedInto`, an entry saved before).
struct CorrectionChange: Codable, Equatable, Sendable {
    var before: VocabWord
    var after: VocabWord?
    var mergedInto: String?
}

/// The corrections still shown on Words and what Undo puts back.
struct CorrectionsRecord: Codable {
    var corrections: [Correction]
    var changes: [CorrectionChange]
}

/// The saved words one run of the corrections reads (`Library.beginCorrections`).
public struct CorrectionsRun: Sendable {
    /// Newest first, at most `Library.maxCorrectedWords`.
    let words: [VocabWord]
    /// How many words are still to read, these and the next runs'.
    let eligible: Int
    /// How many more corrections Undo can hold.
    let room: Int
}

/// What a run changes (`Library.plannedCorrections`) and the flag for after it (nil: kept).
public struct CorrectionsPlan: Sendable {
    let changes: [(VocabWord, VocabWord)]
    let progress: String?
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
    /// "done" (or "1", before runs), or "after:" and where the next run starts.
    static let correctionsDone = "corrections-v2"
    static let correctionsAfter = "after:"
    /// A saved word's id: `VocabWord.maxWord` and its longest "#sense" (same limit as lingleaf-android).
    static let maxCursorID = VocabWord.maxWord + "#homonym".utf16.count
    /// Most corrections kept (what Undo can hold: a run stops there), and most words read again in
    /// one run (same limits as lingleaf-android).
    static let maxCorrections = 1000
    static let maxCorrectedWords = 5000

    /// Spellings the irregular-verb list linked before the table (no sentence read): what a word
    /// saved then may have been tapped as.
    private static let oldLinks: [String: String] = [
        "left": "leave", "saw": "see", "thought": "think", "found": "find", "felt": "feel", "fell": "fall",
        "rose": "rise", "spoke": "speak", "lives": "life", "leaves": "leaf",
    ]

    /// Dates a saved word can have; anything else in a restored file is refused.
    private static var dateRange: ClosedRange<Date> { VocabWord.dateRange }

    private static func bounded(_ word: VocabWord) -> VocabWord? {
        guard dateRange.contains(word.createdAt), dateRange.contains(word.nextReview) else { return nil }
        return word.bounded()
    }

    func loadCorrections() -> CorrectionsRecord? {
        guard var record = decode(CorrectionsRecord.self, Self.correctionsFile) else { return nil }
        record.corrections = record.corrections.prefix(Self.maxCorrections).map {
            Correction(
                from: TextTools.truncated(TextTools.cleanLabel($0.from), 40), to: TextTools.truncated(TextTools.cleanLabel($0.to), 40)
            )
        }
        record.changes = record.changes.prefix(Self.maxCorrections).compactMap { change in
            guard let before = Self.bounded(change.before) else { return nil }
            let after = change.after.flatMap(Self.bounded)
            guard change.after == nil || after != nil else { return nil }
            return CorrectionChange(before: before, after: after, mergedInto: change.mergedInto.map { TextTools.truncated($0, 80) })
        }
        return record
    }

    /// After updating (SPEC S18), one run per launch: the saved words still to read again, newest
    /// first (ties by id), at most `maxCorrectedWords`, and how many more corrections Undo can
    /// hold; nil when that is done or can't be done (the table didn't load). A flag that isn't
    /// "done" (or "1", before runs) or a readable "after:" starts over.
    public func beginCorrections() -> CorrectionsRun? {
        let flag = storage.read(Self.correctionsDone)
        guard flag != "done", flag != "1", !IrregularVerbs.shared.verbs.isEmpty else { return nil }
        let cursor = flag.flatMap(Self.cursor)
        let eligible = state.words.sorted(by: Self.newestFirst).filter { word in
            cursor.map { word.createdAt < $0.0 || (word.createdAt == $0.0 && word.id > $0.1) } ?? true
        }
        // What Undo holds: the card's lines and the changes behind them, whichever is more.
        let held = max(state.corrections.count, loadCorrections()?.changes.count ?? 0)
        return CorrectionsRun(
            words: Array(eligible.prefix(Self.maxCorrectedWords)), eligible: eligible.count,
            room: max(Self.maxCorrections - held, 0)
        )
    }

    private static func newestFirst(_ a: VocabWord, _ b: VocabWord) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id < b.id
    }

    /// "after:752000000.25\tleft#noun" (seconds since 2001, exact, and the id) → its date and id;
    /// nil for anything else.
    private static func cursor(_ flag: String) -> (Date, String)? {
        guard flag.hasPrefix(correctionsAfter) else { return nil }
        let value = flag.dropFirst(correctionsAfter.count)
        guard let tab = value.firstIndex(of: "\t"), let seconds = Double(value[..<tab]), seconds.isFinite else { return nil }
        let id = String(value[value.index(after: tab)...])
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        guard !id.isEmpty, id.utf16.count <= maxCursorID, dateRange.contains(date) else { return nil }
        return (date, id)
    }

    /// Each word of `run` read again in its sentence, as it was and what it becomes, until Undo
    /// has no room for more; and the flag for after it. Pure, so it can run off the main thread.
    public static func plannedCorrections(_ run: CorrectionsRun, target: String?, now: Date) -> CorrectionsPlan {
        var changes: [(VocabWord, VocabWord)] = []
        var read = 0
        for word in run.words {
            if changes.count >= run.room { break }
            read += 1
            if let after = corrected(word, target: target, now: now) { changes.append((word, after)) }
        }
        let progress: String? = if read == run.eligible {
            "done"
        } else if read == 0 {
            // No room to undo anything: the next launch, once the card is closed.
            nil
        } else {
            correctionsAfter + "\(run.words[read - 1].createdAt.timeIntervalSinceReferenceDate)\t\(run.words[read - 1].id)"
        }
        return CorrectionsPlan(changes: changes, progress: progress)
    }

    /// Applies `plan` to the words as they are now: a word changed or deleted meanwhile is left
    /// alone; one that becomes a word already saved merges into it. The flag is written first, so
    /// a crash while saving doesn't run the same words on every launch.
    @discardableResult
    public func applyCorrections(_ plan: CorrectionsPlan) -> [Correction] {
        if let progress = plan.progress { storage.write(Self.correctionsDone, progress) }
        var words = state.words
        var corrections: [Correction] = []
        var changes: [CorrectionChange] = []
        // Only words still as they were read; all of them leave first, so a word merges only into
        // an entry that stays ("leave" → "left" while that "left" itself becomes "leave").
        let current = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let valid = plan.changes.filter { before, _ in current[before.id] == before }
        let leaving = Set(valid.map { $0.0.id })
        words.removeAll { leaving.contains($0.id) }
        for (before, after) in valid {
            if words.contains(where: { $0.id == after.id }) {
                changes.append(CorrectionChange(before: before, after: nil, mergedInto: after.id))
            } else {
                words.append(after)
                changes.append(CorrectionChange(before: before, after: after, mergedInto: nil))
            }
            corrections.append(Correction(from: before.word, to: after.word))
        }
        guard !corrections.isEmpty else { return [] }
        // Added to the card of an earlier run still open.
        let open = loadCorrections()
        state.words = words.sorted { $0.createdAt > $1.createdAt }
        state.corrections = Array(((open?.corrections ?? []) + corrections).prefix(Self.maxCorrections))
        save(state.words, "words.json")
        let record = CorrectionsRecord(
            corrections: state.corrections, changes: Array(((open?.changes ?? []) + changes).prefix(Self.maxCorrections))
        )
        save(record, Self.correctionsFile)
        return corrections
    }

    /// `beginCorrections`, `plannedCorrections` and `applyCorrections` at once, for one batch
    /// (tests, and when there is no other thread to use).
    @discardableResult
    public func correctWordsIfNeeded() -> [Correction] {
        guard let run = beginCorrections() else { return [] }
        return applyCorrections(Self.plannedCorrections(run, target: state.settings.targetLanguage, now: now()))
    }

    /// `word` read again in its sentence, or nil when it stays as it is.
    static func corrected(_ word: VocabWord, target: String?, now: Date) -> VocabWord? {
        guard word.kind == nil, word.sense == nil, word.meanings == nil, !word.context.isEmpty else { return nil }
        let table = IrregularVerbs.shared
        let words = Words(word.context as NSString)
        // The word as tapped: the first homograph of the sentence the old list linked to it.
        guard let i = words.ranges.indices.first(where: { k in
            let token = words.token(k)
            guard table.homographs[token] != nil else { return false }
            var old: Set<String> = [token]
            if let link = oldLinks[token] { old.insert(link) }
            old.formUnion(TextTools.candidates(token, link: nil))
            return old.contains(word.word)
        }), let reading = table.resolve(words, i) else { return nil }
        // Another word of the sentence still leads to it: it may have been tapped there.
        let elsewhere = words.ranges.indices.contains { k in
            k != i && table.homographs[words.token(k)] == nil && TextTools.matchKeys(words, k).contains(word.word)
        }
        guard !elsewhere else { return nil }
        let token = words.token(i)
        var corrected = word
        if reading.kind != .unsure {
            guard reading.base != word.word else { return nil }
            corrected.word = reading.base
            corrected.sense = table.sense(of: reading)
        } else {
            guard !TextTools.matchKeys(words, i).contains(word.word) else { return nil }
            corrected.word = token
            corrected.meanings = table.choices(words, i).map { choice in
                let spanish = ReadingTranslation.isSpanish(target)
                    ? table.tableMeaning(choice.kind, base: choice.base, form: choice.form, first: true) : nil
                return SavedMeaning(label: choice.label, sense: choice.sense, base: choice.base, text: spanish ?? "",
                                    language: spanish == nil ? nil : target)
            }
        }
        corrected.form = words.surface(i)
        corrected.formStart = words.ranges[i].start
        corrected.formEnd = words.ranges[i].end
        // Translated again: a verb or an expression ("bound for") in Spanish from the table now, the
        // rest later (S12).
        let sense = corrected.sense
        let spanish: String? = if !ReadingTranslation.isSpanish(target) {
            nil
        } else if reading.kind == .expression {
            table.tableMeaning(.expression, base: corrected.word)
        } else {
            // The twin's noun has its own ("lie": "mentira"); another noun is translated later.
            sense == Sense.noun ? table.tableMeaning(.noun, base: corrected.word)
                : sense.flatMap { table.spanishMeaning(of: corrected.word, sense: $0) }
        }
        corrected.translation = corrected.meanings.flatMap { joined($0, target) } ?? spanish ?? ""
        corrected.translationLanguage = corrected.translation.isEmpty ? nil : target
        // A verb the table's IPA for its base; a noun of tear, lead or wind its sentence's.
        corrected.phonetic = if sense == Sense.verb || sense == Sense.homonym {
            table.baseIPA(corrected.word) ?? ""
        } else {
            sense == Sense.noun ? table.nounIPA(words, i).map { "/\($0)/" } ?? "" : ""
        }
        // In Learning it starts again: it was rehearsed with a wrong meaning. Due now, once it has one.
        if !corrected.learned {
            corrected.box = 0
            corrected.nextReview = now
            corrected.waitsForMeaning = corrected.translation.isEmpty ? true : nil
        }
        return corrected
    }

    /// Undo on the card (SPEC S18): each entry the correction changed or merged back as it was,
    /// latest first; one changed since (reviewed) or deleted since stays as it is now.
    /// Returns how many corrected entries stay as they are now (reviewed or deleted since), for the
    /// message after Undo.
    @discardableResult
    public func undoCorrections() -> Int {
        guard let record = loadCorrections() else { return 0 }
        var words = state.words
        // What can be undone: an entry still as the correction left it, or one merged into an
        // entry still there. Every such entry leaves first, so an original whose id another
        // correction took ("left" saved unsure from "leave") comes back too.
        let undone = record.changes.filter { change in
            if let after = change.after {
                return words.contains { $0.id == after.id && Self.sameProgress($0, after) }
            }
            return change.mergedInto.map { target in words.contains { $0.id == target } } ?? false
        }
        let leaving = Set(undone.compactMap { $0.after?.id })
        words.removeAll { leaving.contains($0.id) }
        for change in undone.reversed() where !words.contains(where: { $0.id == change.before.id }) {
            words.append(change.before.bounded())
        }
        state.words = words.sorted { $0.createdAt > $1.createdAt }
        save(state.words, "words.json")
        closeCorrections()
        return record.changes.count - undone.count
    }

    /// Not reviewed or moved since: a translation that arrived meanwhile doesn't count.
    private static func sameProgress(_ a: VocabWord, _ b: VocabWord) -> Bool {
        a.box == b.box && a.learned == b.learned && a.nextReview == b.nextReview && a.sense == b.sense
    }

    /// Close on the card: the corrections stay.
    public func closeCorrections() {
        storage.delete(Self.correctionsFile)
        state.corrections = []
    }

    // MARK: Translations of readings

    /// Fills in, from the table, what needs no translator in `target` (Spanish): a saved verb's
    /// meanings, an expression's ("bound for"), the twin's noun's ("lie": "mentira") and the
    /// readings of a word saved unsure.
    public func fillTableTranslations(_ target: String) {
        guard ReadingTranslation.isSpanish(target) else { return }
        let table = IrregularVerbs.shared
        for var word in state.words where word.kind == nil {
            var changed = false
            if let kind = Self.readingKind(word), word.translation.isEmpty || word.translationLanguage != target,
               let spanish = table.tableMeaning(kind, base: word.word) {
                word.translation = spanish
                word.translationLanguage = target
                changed = true
            }
            if var meanings = word.meanings {
                // The first group of the table's meaning: a verb's, the twin's or the twin's noun's ("mentira").
                for index in meanings.indices where meanings[index].text.isEmpty || meanings[index].language != target {
                    // The tapped form ("lies"): the -s form's own meaning ("estar, encontrarse").
                    let kind = Self.kind(of: meanings[index])
                    if let spanish = table.tableMeaning(kind, base: meanings[index].base, form: word.form ?? word.word, first: true) {
                        meanings[index].text = spanish
                        meanings[index].language = target
                        changed = true
                    }
                }
                word.meanings = meanings
                word.translation = Self.joined(meanings, target) ?? word.translation
            }
            if changed, !word.translation.isEmpty { word.waitsForMeaning = nil }
            if changed { replace(word) }
        }
    }

    /// The reading a saved word is, for its table meaning: its sense's, or an expression saved as
    /// a unit ("bound for"); nil for any other word.
    static func readingKind(_ word: VocabWord) -> Reading.Kind? {
        switch word.sense {
        case Sense.noun: .noun
        case Sense.homonym: .homonym
        case Sense.verb: .verb
        default: word.meanings == nil && IrregularVerbs.shared.expression(word.word) != nil ? .expression : nil
        }
    }

    /// The readings of words saved unsure still to translate into `target`, each as its sense's
    /// English query ("to lie down", "the left").
    public func meaningsNeedingTranslation(_ target: String) -> [MeaningRequest] {
        state.words.flatMap { word in
            (word.meanings ?? []).enumerated().compactMap { index, meaning -> MeaningRequest? in
                guard meaning.text.isEmpty || meaning.language != target else { return nil }
                let query = IrregularVerbs.shared.query(Self.kind(of: meaning), base: meaning.base)
                return MeaningRequest(id: word.id, index: index, label: query)
            }
        }
    }

    static func kind(of meaning: SavedMeaning) -> Reading.Kind {
        meaning.sense == Sense.noun ? .noun : meaning.sense == Sense.homonym ? .homonym : .verb
    }

    /// Records the translation of a reading of a word saved unsure ("the left" → "la izquierda"),
    /// without the article or infinitive marker; the word's translation is then its readings'.
    public func setMeaning(_ id: String, index: Int, text: String, language: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, var word = state.words.first(where: { $0.id == id }),
              var meanings = word.meanings, meanings.indices.contains(index) else { return }
        let cleaned = ReadingTranslation.cleaned(text, noun: meanings[index].sense == Sense.noun, language: language)
        meanings[index].text = cleaned
        meanings[index].language = language
        // Two readings that come out the same each add their sense's gloss ("mentir (recline)").
        if meanings.count == 2, meanings.allSatisfy({ $0.language == language && !$0.text.isEmpty }) {
            let rows = meanings.map { ReadingChoice(kind: Self.kind(of: $0), base: $0.base, sense: $0.sense) }
            let told = IrregularVerbs.shared.distinguished(rows, meanings.map(\.text))
            for k in meanings.indices { meanings[k].text = told[k] ?? meanings[k].text }
        }
        word.meanings = meanings
        word.translation = Self.joined(meanings, language) ?? word.translation
        word.translationLanguage = language
        if !word.translation.isEmpty { word.waitsForMeaning = nil }
        replace(word)
    }

    /// "irse, salir · izquierda" once every reading has its meaning in `language`.
    static func joined(_ meanings: [SavedMeaning], _ language: String?) -> String? {
        guard meanings.allSatisfy({ !$0.text.isEmpty && $0.language == language }) else { return nil }
        return meanings.map(\.text).joined(separator: " · ")
    }
}

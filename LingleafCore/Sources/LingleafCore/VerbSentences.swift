import Foundation
import os

/// The sentences of the irregular verbs (`Resources/irregular-verb-sentences.json`, identical in lingleaf-android):
/// up to ten original sentences per verb in fixed positions, for the verb page's "In sentences" (SPEC.md, Verb
/// sentences data). Read once and strictly, with the byte rules of `tips.json`; anything unexpected refuses the
/// whole file. This file is the reader (bytes, shape, caps, text safety, slot ids, positions, forms); the content
/// rules a sentence must also meet (bold form, cues, `perfectq`, `spoken`, length, `context`, sense, completeness)
/// are the linter, `VerbSentencesLint`, run by the tests and never at launch.
public struct VerbSentences: Equatable, Sendable {
    /// Largest file accepted, in bytes (the first complete version is about 410 KB).
    static let maxBytes = 512 * 1024
    static let maxDepth = 8
    static let schemaVersion = 1
    static let maxSentencesPerVerb = 14
    static let maxEnglish = 120
    static let maxSpanish = 160
    static let maxSpoken = 200
    static let reasonLength = 3...140
    static let levels: Set<String> = ["A1", "A2", "B1", "B2", "C1", "C2"]

    /// The shipped sentences, read once. A file that is missing, unreadable or refused stops debug builds and
    /// tests; a release build gets no sentences instead (a verb page then has no "In sentences").
    public static let shared: VerbSentences = {
        do {
            guard let url = Bundle.module.url(forResource: "irregular-verb-sentences", withExtension: "json") else {
                throw VerbSentencesError.invalid(["irregular-verb-sentences.json is missing"])
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // One byte past the cap is enough to know the file is too large.
            return try load(handle.read(upToCount: maxBytes + 1) ?? Data())
        } catch {
            // A static message: nothing from the file reaches the log.
            Logger(subsystem: "app.lingleaf", category: "VerbSentences").fault("irregular-verb-sentences.json refused; using none")
            assertionFailure("irregular-verb-sentences.json: \(error)")
            return VerbSentences(verbs: [])
        }
    }()

    public let verbs: [VerbSentenceEntry]

    /// The sentences of the verb whose base is `base`.
    public func entry(base: String) -> VerbSentenceEntry? { verbs.first { $0.base == base } }

    // MARK: Loading

    /// Reads the sentences, refusing the file whole at the first problem. `table` is the irregular-verb table the
    /// verbs and forms are checked against.
    static func load(_ data: Data, table: IrregularVerbs = .shared) throws -> VerbSentences {
        if let refusal = refusal(of: data) { throw refusal }
        let file = try decode(data)
        let problems = problems(in: file, table: table)
        guard problems.isEmpty else { throw VerbSentencesError.invalid(problems) }
        return file
    }

    /// The bytes rules, in the order they are checked (the first that holds is the refusal).
    static func refusal(of data: Data) -> VerbSentencesError? {
        guard data.count <= maxBytes else { return .tooLarge }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .malformed("a byte order mark") }
        guard !data.contains(0) else { return .malformed("a NUL byte") }
        // Only valid UTF-8 survives the round trip (anything else is replaced by U+FFFD).
        // swiftlint:disable:next optional_data_string_conversion
        guard Data(String(decoding: data, as: UTF8.self).utf8) == data else { return .malformed("not UTF-8") }
        guard JSONGuard.isShallow(data, maxDepth: maxDepth) else { return .tooDeep }
        // The grammar is checked here, not left to `JSONSerialization` (which reads `{"a":1,}` on Linux): the same
        // verdict on every platform, and everything below sees valid JSON.
        guard GrammarJSON.isStrictJSON(data) else { return .malformed("not strict JSON") }
        guard data.first(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }) == 0x7B else { return .malformed("not a JSON object") }
        guard !GrammarJSON.hasDuplicateKey(data) else { return .malformed("a duplicate key") }
        guard !GrammarJSON.hasLoneSurrogateEscape(data) else { return .malformed("a lone surrogate") }
        // A raw control character in a string, a JSON null, and a `schema` or `senseIndex` that is not an integer
        // literal (`1.0`) refuse the file.
        guard GrammarJSON.scrubbed(data, integerKeys: ["schema", "senseIndex"], policy: .strict) != nil else {
            return .malformed("a control character, a null or a number that is not an integer")
        }
        return nil
    }

    private static func decode(_ data: Data) throws -> VerbSentences {
        guard let clean = GrammarJSON.scrubbed(data, integerKeys: ["schema", "senseIndex"], policy: .strict) else {
            throw VerbSentencesError.malformed("not strict JSON")
        }
        do {
            return try JSONDecoder().decode(VerbSentencesFile.self, from: clean).sentences
        } catch let error as VerbSentencesError {
            throw error
        } catch GrammarRulesError.malformed(let problem) {
            throw VerbSentencesError.malformed(problem)
        } catch {
            throw VerbSentencesError.malformed("a field of the wrong shape")
        }
    }

    // MARK: Reader rules (SPEC.md, "Refused")

    /// Every problem of the shape of the file against the table, in file order; empty when the file is valid.
    static func problems(in file: VerbSentences, table: IrregularVerbs) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for entry in file.verbs {
            let name = String(entry.base.prefix(30))
            guard let verb = table.verb(base: entry.base) else {
                out.append("base-unknown: \(name)")
                continue
            }
            if !seen.insert(entry.base).inserted { out.append("base-twice: \(name)") }
            out += entryProblems(entry, verb: verb)
        }
        let cap = table.verbs.count / 10
        if file.verbs.filter({ !$0.omitted.isEmpty }).count > cap { out.append("omission-cap: more than \(cap) verbs have an omission") }
        return out
    }

    private static func entryProblems(_ entry: VerbSentenceEntry, verb: IrregularVerb) -> [String] {
        let name = entry.base
        var out: [String] = []
        if entry.sentences.count > maxSentencesPerVerb { out.append("too-many-sentences: \(name)") }
        out += orderProblems(entry.sentences, name: name)
        out += senseProblems(entry.sentences, verb: verb)
        for sentence in entry.sentences { out += sentenceProblems(sentence, verb: verb) }
        out += omissionProblems(entry)
        return out
    }

    /// Sentences are in position order: the sentences of sense 0, then those of sense 1, each with strictly
    /// increasing positions (two sentences of one sense in one position are refused, with any id).
    private static func orderProblems(_ sentences: [VerbSentence], name: String) -> [String] {
        var out: [String] = []
        for (before, after) in zip(sentences, sentences.dropFirst()) {
            if after.senseIndex < before.senseIndex {
                out.append("order: \(name) has a sense 0 sentence after a sense 1 sentence")
            } else if after.senseIndex == before.senseIndex {
                if after.slot.position == before.slot.position {
                    out.append("position-twice: \(name) sense \(after.senseIndex) position \(after.slot.position)")
                } else if after.slot.position < before.slot.position {
                    out.append("order: \(name) position \(after.slot.position) after \(before.slot.position)")
                }
            }
        }
        return out
    }

    /// `senseIndex` is 0, or 1 for a verb with a homonym; sense 1 has up to 4 sentences: positions 4, 7, 8 and
    /// one base-form position among 1, 6 and 10.
    private static func senseProblems(_ sentences: [VerbSentence], verb: IrregularVerb) -> [String] {
        var out: [String] = []
        for sentence in sentences where sentence.senseIndex != 0 && !(sentence.senseIndex == 1 && verb.homonym != nil) {
            out.append("sense-unknown: \(verb.base) senseIndex \(sentence.senseIndex)")
        }
        let second = sentences.filter { $0.senseIndex == 1 }
        let positions = second.map(\.slot.position)
        let baseForm = positions.filter { [1, 6, 10].contains($0) }.count
        if second.count > 4 || !Set(positions).isSubset(of: [1, 4, 6, 7, 8, 10]) || baseForm > 1 {
            out.append("sense-one-shape: \(verb.base) sense 1 holds positions 4, 7, 8 and one of 1, 6 or 10 only")
        }
        return out
    }

    private static func sentenceProblems(_ sentence: VerbSentence, verb: IrregularVerb) -> [String] {
        var out: [String] = []
        let tag = "\(verb.base) \(sentence.slot.rawValue)"
        if !levels.contains(sentence.level) { out.append("level-unknown: \(tag)") }
        let forms = verb.forms(of: sentence.slot.formClass, sense: sentence.senseIndex)
        if !forms.contains(sentence.form) { out.append("form-class: \(tag) form is not a \(sentence.slot.formClass) form of the verb") }
        if !GrammarRules.isText(sentence.en, max: maxEnglish) { out.append("text-en: \(tag)") }
        if !GrammarRules.isText(sentence.es, max: maxSpanish) { out.append("text-es: \(tag)") }
        if let spoken = sentence.spoken, !GrammarRules.isText(spoken, max: maxSpoken) { out.append("text-spoken: \(tag)") }
        return out
    }

    /// `omitted`: only `now` and `advice`, each once, with a reason of 3 to 140 code points, and not also a sentence
    /// of sense 0 at that position.
    private static func omissionProblems(_ entry: VerbSentenceEntry) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for omission in entry.omitted {
            let tag = "\(entry.base) \(omission.slot)"
            guard ["now", "advice"].contains(omission.slot) else {
                out.append("omitted-slot: \(String(tag.prefix(60)))")
                continue
            }
            if !seen.insert(omission.slot).inserted { out.append("omitted-twice: \(tag)") }
            let position = omission.slot == "now" ? 3 : 10
            if entry.sentences.contains(where: { $0.senseIndex == 0 && $0.slot.position == position }) {
                out.append("omitted-and-present: \(tag) has a sentence in the position it omits")
            }
            let reason = omission.reason
            if reason.unicodeScalars.count < reasonLength.lowerBound || !GrammarRules.isText(reason, max: reasonLength.upperBound) {
                out.append("omitted-reason: \(tag)")
            }
        }
        return out
    }
}

public enum VerbSentencesError: Error, Equatable {
    case tooLarge
    case tooDeep
    case malformed(String)
    /// Every problem found, in file order.
    case invalid([String])
}

// MARK: Model

/// The closed list of slot ids, by position in the verb page (SPEC.md, Verb sentences data).
public enum VerbSlot: String, CaseIterable, Sendable {
    case habit, third, now, gerund, past, story, didnt, perfect, passive, state, perfectq, pastperfect, advice

    /// Which of the verb's forms the sentence's `form` is.
    public enum FormClass: String, Sendable { case base, s, ing, past, participle }

    public var position: Int {
        switch self {
        case .habit: 1
        case .third: 2
        case .now, .gerund: 3
        case .past: 4
        case .story: 5
        case .didnt: 6
        case .perfect: 7
        case .passive, .state, .perfectq: 8
        case .pastperfect: 9
        case .advice: 10
        }
    }

    public var formClass: FormClass {
        switch position {
        case 2: .s
        case 3: .ing
        case 4, 5: .past
        case 7, 8, 9: .participle
        default: .base
        }
    }
}

extension IrregularVerb {
    /// The verb's forms of a class for a sense: the verb's for 0, its regular homonym's for 1 (the base is shared).
    func forms(of formClass: VerbSlot.FormClass, sense: Int) -> [String] {
        let twin = sense == 1 ? homonym : nil
        switch formClass {
        case .base: return [base]
        case .s: return [twin?.s ?? s]
        case .ing: return [twin?.ing ?? ing]
        case .past: return twin?.past ?? past
        case .participle: return twin?.participle ?? participle
        }
    }
}

public struct VerbSentence: Equatable, Sendable {
    public let slot: VerbSlot
    public let form: String
    public let en: String
    public let es: String
    /// What Listen says when a voice would read `form` wrong; never shown.
    public let spoken: String?
    /// 0: the verb; 1: its regular homonym (lie/lied, hang/hanged).
    public let senseIndex: Int
    public let level: String
    /// The sentence Save word stores for this verb and sense.
    public let context: Bool

    public init(
        slot: VerbSlot, form: String, en: String, es: String, spoken: String? = nil, senseIndex: Int = 0, level: String,
        context: Bool = false
    ) {
        self.slot = slot
        self.form = form
        self.en = en
        self.es = es
        self.spoken = spoken
        self.senseIndex = senseIndex
        self.level = level
        self.context = context
    }
}

/// A position the verb has no sentence for, and why (only `now` and `advice` may be left out).
public struct VerbOmission: Equatable, Sendable {
    public let slot: String
    public let reason: String

    public init(slot: String, reason: String) {
        self.slot = slot
        self.reason = reason
    }
}

public struct VerbSentenceEntry: Equatable, Sendable {
    public let base: String
    public let sentences: [VerbSentence]
    public let omitted: [VerbOmission]

    public init(base: String, sentences: [VerbSentence], omitted: [VerbOmission] = []) {
        self.base = base
        self.sentences = sentences
        self.omitted = omitted
    }

    public func sentences(senseIndex: Int) -> [VerbSentence] { sentences.filter { $0.senseIndex == senseIndex } }
}

// MARK: Strict decoding

private struct VerbSentencesFile: Decodable {
    let sentences: VerbSentences

    init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["schema", "verbs"])
        // Read first: a schema other than 1 is refused as such.
        let version: Int = try c.value("schema")
        guard version == VerbSentences.schemaVersion else { throw VerbSentencesError.invalid(["schema \(version)"]) }
        sentences = VerbSentences(verbs: try c.value("verbs"))
    }
}

extension VerbSentenceEntry: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["base", "sentences"], optional: ["omitted"])
        self.init(base: try c.value("base"), sentences: try c.value("sentences"), omitted: try c.optional("omitted") ?? [])
    }
}

extension VerbOmission: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["slot", "reason"])
        self.init(slot: try c.value("slot"), reason: try c.value("reason"))
    }
}

extension VerbSentence: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strictObject(["slot", "form", "en", "es", "senseIndex", "level"], optional: ["spoken", "context"])
        let id: String = try c.value("slot")
        guard let slot = VerbSlot(rawValue: id) else { throw VerbSentencesError.invalid(["slot-unknown: \(id.prefix(30))"]) }
        self.init(
            slot: slot, form: try c.value("form"), en: try c.value("en"), es: try c.value("es"), spoken: try c.optional("spoken"),
            senseIndex: try c.value("senseIndex"), level: try c.value("level"), context: try c.optional("context") ?? false
        )
    }
}

import Foundation
import os

/// The irregular-verb table (`Resources/irregular-verbs.json`, identical in lingleaf-android):
/// the only list of irregular forms. Base forms (`TextTools`), past participles and base forms
/// (`Verbs`) and the verb-or-noun rule (`resolve`) all come from it. Read once and strictly
/// (SPEC.md, Shared logic): anything unexpected refuses the whole file.
public struct IrregularVerbs: Sendable {
    /// Largest table accepted, in bytes (the shipped one is about 43 KB).
    static let maxBytes = 256 * 1024
    /// Deepest nesting accepted (the shipped table nests 5 levels).
    static let maxDepth = 8
    static let schemaVersion = 1
    static let levels: Set<String> = ["A1", "A2", "B1", "B2", "C1", "C2"]
    static let spokenSlots: Set<String> = ["base", "past", "participle", "ing", "s"]
    /// Longest Spanish meaning, group title or example kept.
    static let maxText = 100
    /// Letters an IPA transcription may use (no slashes): a–z, the IPA letters and marks English
    /// needs, and the combining syllabic mark and tilde.
    static let ipaScalars: Set<Unicode.Scalar> = {
        var set = Set((UInt32(0x61)...UInt32(0x7A)).compactMap { Unicode.Scalar($0) })
        for scalar in "æðŋɑɒɔəɚɛɜɝɡɪɹɾʃʊʌʒʔθʤʧˈˌːˑ.".unicodeScalars { set.insert(scalar) }
        set.insert("\u{0329}")
        set.insert("\u{0303}")
        return set
    }()

    /// The shipped table, read once. `Bundle.module` itself stops the app if the package's
    /// resource bundle is not in it (an app UI test checks it is). A file that is missing from the
    /// bundle, unreadable or refused stops debug builds and tests; a reader in a release build
    /// gets an empty table instead: base forms then come from the regular rules alone.
    public static let shared: IrregularVerbs = {
        do {
            guard let url = Bundle.module.url(forResource: "irregular-verbs", withExtension: "json") else {
                throw IrregularVerbsError.invalid("irregular-verbs.json is missing")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // One byte past the cap is enough to know the file is too large.
            return try load(handle.read(upToCount: maxBytes + 1) ?? Data())
        } catch {
            // A static message: nothing from the file reaches the log.
            Logger(subsystem: "app.lingleaf", category: "IrregularVerbs").fault("irregular-verbs.json refused; using an empty table")
            assertionFailure("irregular-verbs.json: \(error)")
            return IrregularVerbs()
        }
    }()

    public let groups: [VerbGroup]
    public let verbs: [IrregularVerb]
    /// Every form that leads to one base ("stole" → "steal", "lied" → "lie"), homographs excluded.
    public let formToBase: [String: String]
    /// Every past participle of the table, "got" excluded ("have got" means "have").
    public let participles: Set<String>
    /// The participles spelled like a base of the table ("come", "read", "bet").
    public let baseLikeParticiples: Set<String>
    /// Every base of the table.
    public let bases: Set<String>
    /// The bases not marked as mostly nouns: verbs after "had better" ("light" is not one).
    let hadBetterBases: Set<String>
    /// Forms of have and be before a participle, for respellings; not get ("got read" is rare),
    /// not 'd ("I'd read" can be "I would read").
    let participleHelpers: Set<String>
    let homographs: [String: Homograph]
    let context: Context
    /// US double-l bases tried before the single-l stem ("installed" → "install", then "instal").
    let llBases: Set<String>
    /// Past forms that are not also a base or a homograph ("shone", "told", "went"): a finite verb.
    let pastForms: Set<String>
    /// Forms only of a verb's regular homonym ("lied", "hanged"), and forms of both ("lying", "lies").
    let homonymOnlyForms: Set<String>
    let sharedHomonymForms: Set<String>
    private let verbsByBase: [String: IrregularVerb]

    /// An empty table.
    init() {
        self.init(groups: [], verbs: [], homographs: [], context: Context(), llBases: [])
    }

    /// The table and what is derived from it (SPEC.md, Shared logic). `validate` checks it.
    private init(groups: [VerbGroup], verbs: [IrregularVerb], homographs: [Homograph], context: Context, llBases: [String]) {
        let byForm = Dictionary(homographs.map { ($0.form, $0) }) { first, _ in first }
        let bases = Set(verbs.map(\.base))
        let participles = Set(verbs.flatMap { $0.participle + ($0.homonym?.participle ?? []) }).subtracting(["got"])
        var links: [String: String] = [:]
        for verb in verbs {
            for form in verb.forms where form != verb.base && byForm[form] == nil { links[form] = verb.base }
        }
        self.groups = groups
        self.verbs = verbs
        self.homographs = byForm
        self.context = context
        self.bases = bases
        self.participles = participles
        formToBase = links
        baseLikeParticiples = participles.intersection(bases)
        hadBetterBases = Set(verbs.filter { !$0.nounFirst }.map(\.base))
        verbsByBase = Dictionary(verbs.map { ($0.base, $0) }) { first, _ in first }
        let getForms: Set<String> = ["get", "gets", "got", "getting", "gotten"]
        participleHelpers = context.haveAndBe.filter { !getForms.contains($0) && !$0.hasSuffix("'d") }
        self.llBases = Set(llBases)
        pastForms = Set(verbs.flatMap(\.past)).subtracting(bases).filter { byForm[$0] == nil }
        var homonymOnly: Set<String> = [], shared: Set<String> = []
        for verb in verbs {
            guard let homonym = verb.homonym else { continue }
            let own = Set(verb.past + verb.participle + [verb.ing, verb.s] + verb.present)
            for form in homonym.past + homonym.participle + [homonym.ing, homonym.s] {
                if own.contains(form) { shared.insert(form) } else { homonymOnly.insert(form) }
            }
        }
        homonymOnlyForms = homonymOnly
        sharedHomonymForms = shared
    }

    /// The verb whose base is `base`, for its forms, meanings and spoken forms.
    public func verb(base: String) -> IrregularVerb? { verbsByBase[base] }

    /// The table's base form of the word at `range` in `text`, read in its sentence: a
    /// homograph's reading when it has another base ("she left" → "leave"; nil when unsure), else
    /// the form's verb ("stolen" → "steal"); nil for a word the table doesn't link, or a name
    /// ("Uncle Drew"). Same as `baseAt` in lingleaf-android.
    public func base(in text: String, at range: WordRange) -> String? {
        let ns = text as NSString
        guard range.start >= 0, range.start < range.end, range.end <= ns.length else { return nil }
        let w = TextTools.normalize(ns.substring(with: range.nsRange))
        guard homographs[w] != nil || formToBase[w] != nil else { return nil }
        let words = Words(ns)
        guard let i = words.index(of: range) else { return nil }
        return base(words, i)
    }

    /// `base(in:at:)` for word `i` of `words`.
    func base(_ words: Words, _ i: Int) -> String? {
        let w = words.token(i)
        if homographs[w] != nil {
            guard let reading = resolve(words, i), reading.kind != .unsure, reading.base != w else { return nil }
            return reading.base
        }
        guard let base = formToBase[w], !isName(words, i) else { return nil }
        return base
    }

    // MARK: Loading

    /// Reads a table, refusing it whole at the first problem.
    static func load(_ data: Data) throws -> IrregularVerbs {
        guard data.count <= maxBytes else { throw IrregularVerbsError.tooLarge }
        guard JSONGuard.isShallow(data, maxDepth: maxDepth) else { throw IrregularVerbsError.tooDeep }
        let file = try JSONDecoder().decode(TableFile.self, from: data)
        let table = IrregularVerbs(
            groups: file.groups, verbs: file.verbs, homographs: file.homographs, context: file.context, llBases: file.llBases
        )
        try table.validate(homographList: file.homographs, llBaseList: file.llBases)
        return table
    }

    private func validate(homographList: [Homograph], llBaseList: [String]) throws {
        func check(_ ok: Bool, _ problem: @autoclosure () -> String) throws {
            if !ok { throw IrregularVerbsError.invalid(problem()) }
        }
        let groupIDs = Set(groups.map(\.id))
        try check(groupIDs.count == groups.count, "duplicate group")
        for group in groups {
            let idOK = (1...20).contains(group.id.utf8.count) && group.id.utf8.allSatisfy { (0x61...0x7A).contains($0) || $0 == 0x2D }
            try check(idOK, "group \(group.id)")
            try check([group.example, group.title.en, group.title.es].allSatisfy(Self.isText), "group \(group.id) text")
        }
        try check(verbsByBase.count == verbs.count, "duplicate base")
        var seen: [String: String] = [:]
        for verb in verbs {
            try check(([verb.base] + verb.forms).allSatisfy(Self.isForm), "\(verb.base): a form that is not a–z")
            try check(Self.isFormList(verb.past) && Self.isFormList(verb.participle), "\(verb.base): 1–2 distinct past/participle forms")
            try check(Self.isMeanings(verb.es), "\(verb.base): 1–2 meanings")
            try check(groupIDs.contains(verb.group), "\(verb.base): unknown group \(verb.group)")
            try check(Self.levels.contains(verb.level), "\(verb.base): unknown level \(verb.level)")
            try check(Set(verb.spokenAs.keys).isSubset(of: Self.spokenSlots), "\(verb.base): unknown spokenAs slot")
            try check(verb.spokenAs.values.allSatisfy(Self.isForm), "\(verb.base): spokenAs not a–z")
            try check(Set(verb.ipa.keys).isSubset(of: Self.spokenSlots), "\(verb.base): unknown ipa slot")
            try check(verb.ipa.values.allSatisfy(Self.isIPA), "\(verb.base): ipa")
            try check(verb.present.count <= 2 && (verb.freq ?? 0) >= 0, "\(verb.base): present or freq")
            if let homonym = verb.homonym {
                try check(Self.isFormList(homonym.past) && Self.isFormList(homonym.participle), "\(verb.base): homonym forms")
                try check(Self.isMeanings(homonym.es), "\(verb.base): homonym meanings")
            }
            // A form leads to one base, and is no other verb's base, unless context decides (homographs).
            for form in verb.forms where form != verb.base && homographs[form] == nil {
                try check(seen[form, default: verb.base] == verb.base && !bases.contains(form), "\(form) leads to two bases")
                seen[form] = verb.base
            }
        }
        try check(homographs.count == homographList.count, "duplicate homograph")
        for h in homographList {
            var words: [String] = [h.form, h.verb] + [h.noun, h.baseVerb, h.nounPair].compactMap { $0 }
            words += Array(h.nounAfter) + Array(h.nounBefore) + Array(h.verbAfter)
            try check(words.allSatisfy(Self.isForm), "homograph \(h.form): a word that is not a–z")
            try check(bases.contains(h.verb) || Verbs.regular.contains(h.verb), "homograph \(h.form): unknown verb \(h.verb)")
            if let verb = verbsByBase[h.verb] {
                try check(h.form == verb.base || verb.forms.contains(h.form), "homograph \(h.form): not a form of \(h.verb)")
            }
            try check(!h.rules.contains(.imperative) || h.baseVerb != nil, "homograph \(h.form): imperative without baseVerb")
            for phrase in h.nounPhrases {
                try check((2...4).contains(phrase.count) && phrase.contains(h.form) && phrase.allSatisfy(Self.isForm),
                          "homograph \(h.form): noun phrase")
            }
            try check((h.subjectNounNext ?? []).allSatisfy(Self.isForm), "homograph \(h.form): subjectNounNext")
        }
        try check(Set(llBaseList).count == llBaseList.count, "duplicate llBase")
        let tableForms = bases.union(verbs.flatMap(\.forms)).union(homographs.keys)
        for base in llBaseList {
            let shape = (3...20).contains(base.utf8.count) && Self.isForm(base) && base.hasSuffix("ll")
            try check(shape && TextTools.vowelGroups(String(base.dropLast())) >= 2, "llBase \(base)")
            try check(!tableForms.contains(base), "llBase \(base) is a form of the table")
        }
        try check(context.allWords.allSatisfy(Self.isContextWord), "context: a word that is not a–z")
    }

    /// A form: 1–20 letters a–z.
    static func isForm(_ s: String) -> Bool {
        (1...20).contains(s.utf8.count) && s.utf8.allSatisfy { (0x61...0x7A).contains($0) }
    }

    /// A context word: letters a–z with apostrophes inside ("can't"), at most 20.
    static func isContextWord(_ s: String) -> Bool {
        s.utf8.count <= 20 && s.split(separator: "'", omittingEmptySubsequences: false).allSatisfy { isForm(String($0)) }
    }

    private static func isFormList(_ forms: [String]) -> Bool {
        (1...2).contains(forms.count) && Set(forms).count == forms.count
    }

    private static func isMeanings(_ es: [String]) -> Bool {
        (1...2).contains(es.count) && es.allSatisfy(isText)
    }

    /// An IPA transcription: 1–40 allowed characters, already in NFC.
    static func isIPA(_ s: String) -> Bool {
        let count = s.unicodeScalars.count
        return (1...40).contains(count) && s.unicodeScalars.allSatisfy(ipaScalars.contains)
            && s.precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual(s.unicodeScalars)
    }

    private static func isText(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= maxText
            && !s.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }
    }
}

enum IrregularVerbsError: Error, Equatable {
    case tooLarge
    case tooDeep
    case malformed(String)
    case invalid(String)
}

/// A verb of the table.
public struct IrregularVerb: Equatable, Sendable {
    public let base: String
    /// Most common first; US spelling before UK ("gotten", "got").
    public let past: [String]
    public let participle: [String]
    public let ing: String
    public let s: String
    public let group: String
    /// Approximate CEFR band of its common meaning (A1–C2).
    public let level: String
    /// Its most common meanings in Spanish.
    public let es: [String]
    /// Present forms besides the base and -s ("am", "are" for "be").
    public let present: [String]
    /// What a voice should say instead of a form it reads wrong, by slot (base, past, participle, ing, s).
    public let spokenAs: [String: String]
    /// IPA of a slot's first form, without slashes, where the dictionary can't tell (read: "rɛd").
    public let ipa: [String: String]
    /// A regular verb with the same base and another meaning (lie/lied "mentir").
    public let homonym: Homonym?
    /// The base is used more often as a noun ("light"): not a verb after "had better".
    public let nounFirst: Bool
    /// Lemma frequency per million, for ordering only.
    public let freq: Int?

    public struct Homonym: Equatable, Sendable {
        public let es: [String]
        public let past: [String]
        public let participle: [String]
        public let ing: String
        public let s: String
    }

    /// Every form: past, participle, -ing, -s, present forms and the homonym's (may repeat the base).
    var forms: [String] {
        var out = past + participle + [ing, s] + present
        if let homonym { out += homonym.past + homonym.participle + [homonym.ing, homonym.s] }
        return out
    }
}

/// A pattern group ("think · thought · thought").
public struct VerbGroup: Equatable, Sendable {
    public let id: String
    public let example: String
    public let title: Title

    public struct Title: Equatable, Sendable {
        public let en: String
        public let es: String
    }
}

/// A form that is also another word ("left", "saw", "leaves"): its sentence decides.
struct Homograph: Sendable {
    enum Rule: String, Sendable {
        case participle, subjectNoun, conjunction, imperative, plural, sVerb, quantifier
    }

    let form: String
    /// The noun's base ("leaf" for "leaves"); nil when the form is not a noun ("found").
    let noun: String?
    /// The base of the verb the form is a form of ("leave").
    let verb: String
    /// The form as a verb of its own ("to saw", "to found").
    let baseVerb: String?
    let rules: Set<Rule>
    let nounAfter: Set<String>
    let nounBefore: Set<String>
    let verbAfter: Set<String>
    let nounPair: String?
    let noTo: Bool
    /// Noun phrases holding the form ("lost and found"): the word itself, not a verb.
    let nounPhrases: [[String]]
    /// When set, step 7 (subject noun) needs one of these words right after the form ("The dog bit him").
    let subjectNounNext: Set<String>?
}

/// The word lists of the verb-or-noun rule.
struct Context: Sendable {
    static let names: Set<String> = [
        "determiners", "pluralDeterminers", "prepositions", "adjectives", "pluralAdjectives", "subjects",
        "singularSubjects", "skip", "toAndModals", "haveAndBe", "subjectDeterminers", "oneAfter", "clauseOpeners",
        "lieAfter", "conjunctions", "notNames", "objectStarts", "layTime", "boundAdjective",
        "sFormNext", "notNameStarts", "nameOrPlant", "pluralNouns", "notPlural", "quantifiers",
        "quantifiersBeforeDeterminer", "quantifiersBeforeOf", "finiteVerbs", "participleOpenNext",
    ]

    private let lists: [String: Set<String>]
    let determiners, pluralDeterminers, prepositions, adjectives, pluralAdjectives, subjects: Set<String>
    let singularSubjects, skip, toAndModals, haveAndBe, subjectDeterminers, oneAfter, clauseOpeners: Set<String>
    let lieAfter, conjunctions, notNames, objectStarts, layTime, boundAdjective: Set<String>
    let sFormNext, notNameStarts, nameOrPlant, pluralNouns, notPlural, quantifiers: Set<String>
    let quantifiersBeforeDeterminer, quantifiersBeforeOf, finiteVerbs, participleOpenNext: Set<String>
    /// Words that can't be the noun of a subject ("the finest felt" aside): function words and listed adjectives.
    let closed: Set<String>
    /// `closed` and the adjectives only listed before plurals: words that can't head a noun phrase.
    let nounClosed: Set<String>

    init(_ lists: [String: [String]] = [:]) {
        let sets = lists.mapValues { Set($0) }
        self.lists = sets
        func list(_ name: String) -> Set<String> { sets[name] ?? [] }
        determiners = list("determiners")
        pluralDeterminers = list("pluralDeterminers")
        prepositions = list("prepositions")
        adjectives = list("adjectives")
        pluralAdjectives = list("pluralAdjectives")
        subjects = list("subjects")
        singularSubjects = list("singularSubjects")
        skip = list("skip")
        toAndModals = list("toAndModals")
        haveAndBe = list("haveAndBe")
        subjectDeterminers = list("subjectDeterminers")
        oneAfter = list("oneAfter")
        clauseOpeners = list("clauseOpeners")
        lieAfter = list("lieAfter")
        conjunctions = list("conjunctions")
        notNames = list("notNames")
        objectStarts = list("objectStarts")
        layTime = list("layTime")
        boundAdjective = list("boundAdjective")
        sFormNext = list("sFormNext")
        notNameStarts = list("notNameStarts")
        nameOrPlant = list("nameOrPlant")
        pluralNouns = list("pluralNouns")
        notPlural = list("notPlural")
        quantifiers = list("quantifiers")
        quantifiersBeforeDeterminer = list("quantifiersBeforeDeterminer")
        quantifiersBeforeOf = list("quantifiersBeforeOf")
        finiteVerbs = list("finiteVerbs")
        participleOpenNext = list("participleOpenNext")
        closed = determiners.union(pluralDeterminers).union(adjectives).union(subjects).union(notNames).union(skip)
            .union(prepositions).union(toAndModals).union(haveAndBe).union(conjunctions)
        nounClosed = closed.union(pluralAdjectives)
    }

    var allWords: [String] { lists.values.flatMap { $0 } }
}

// MARK: Strict decoding

/// Any key, so a container can list every key of an object, also the unknown ones
/// (a container keyed by `CodingKeys` silently drops them).
private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension Decoder {
    /// The object's container, refusing a key outside `required` + `optional` or a missing required one.
    func strict(_ required: Set<String>, optional: Set<String> = []) throws -> KeyedDecodingContainer<AnyKey> {
        let keyed = try self.container(keyedBy: AnyKey.self)
        let keys = Set(keyed.allKeys.map(\.stringValue))
        if let unknown = keys.subtracting(required).subtracting(optional).min() {
            throw IrregularVerbsError.malformed("unknown key \(unknown)")
        }
        if let missing = required.subtracting(keys).min() { throw IrregularVerbsError.malformed("missing key \(missing)") }
        return keyed
    }
}

private extension KeyedDecodingContainer where K == AnyKey {
    func value<T: Decodable>(_ key: String) throws -> T { try decode(T.self, forKey: AnyKey(key)) }
    func optional<T: Decodable>(_ key: String) throws -> T? { try decodeIfPresent(T.self, forKey: AnyKey(key)) }
}

private struct TableFile: Decodable {
    let groups: [VerbGroup]
    let verbs: [IrregularVerb]
    let homographs: [Homograph]
    let context: Context
    let llBases: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["schemaVersion", "about", "groups", "verbs", "homographs", "context", "llBases"])
        // First: a future schema is refused as such, whatever else it holds.
        let version: Int = try c.value("schemaVersion")
        guard version == IrregularVerbs.schemaVersion else { throw IrregularVerbsError.invalid("schemaVersion \(version)") }
        let about: String = try c.value("about")
        guard about.count <= 4000 else { throw IrregularVerbsError.invalid("about") }
        groups = try c.value("groups")
        verbs = try c.value("verbs")
        homographs = try c.value("homographs")
        context = try c.value("context")
        llBases = try c.value("llBases")
    }
}

extension VerbGroup: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "example", "title"])
        id = try c.value("id")
        example = try c.value("example")
        title = try c.value("title")
    }
}

extension VerbGroup.Title: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strict(["en", "es"])
        en = try c.value("en")
        es = try c.value("es")
    }
}

extension IrregularVerb: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strict(
            ["base", "past", "participle", "ing", "s", "group", "level", "es"],
            optional: ["present", "spokenAs", "ipa", "homonym", "nounFirst", "freq"]
        )
        base = try c.value("base")
        past = try c.value("past")
        participle = try c.value("participle")
        ing = try c.value("ing")
        s = try c.value("s")
        group = try c.value("group")
        level = try c.value("level")
        es = try c.value("es")
        present = try c.optional("present") ?? []
        spokenAs = try c.optional("spokenAs") ?? [:]
        ipa = try c.optional("ipa") ?? [:]
        homonym = try c.optional("homonym")
        nounFirst = try c.optional("nounFirst") ?? false
        freq = try c.optional("freq")
    }
}

extension IrregularVerb.Homonym: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.strict(["es", "past", "participle", "ing", "s"])
        es = try c.value("es")
        past = try c.value("past")
        participle = try c.value("participle")
        ing = try c.value("ing")
        s = try c.value("s")
    }
}

extension Homograph: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.strict(
            ["form", "noun", "verb", "rules"],
            optional: ["baseVerb", "nounAfter", "nounBefore", "verbAfter", "nounPair", "noTo", "nounPhrases", "subjectNounNext"]
        )
        form = try c.value("form")
        // Required, but null when the form is not a noun.
        noun = try c.optional("noun")
        verb = try c.value("verb")
        baseVerb = try c.optional("baseVerb")
        let names: [String] = try c.value("rules")
        let rules = names.compactMap(Rule.init(rawValue:))
        guard rules.count == names.count else { throw IrregularVerbsError.invalid("homograph \(form): unknown rule") }
        self.rules = Set(rules)
        let after: [String] = try c.optional("nounAfter") ?? []
        let before: [String] = try c.optional("nounBefore") ?? []
        let verbAfter: [String] = try c.optional("verbAfter") ?? []
        nounAfter = Set(after)
        nounBefore = Set(before)
        self.verbAfter = Set(verbAfter)
        nounPair = try c.optional("nounPair")
        noTo = try c.optional("noTo") ?? false
        nounPhrases = try c.optional("nounPhrases") ?? []
        let next: [String]? = try c.optional("subjectNounNext")
        subjectNounNext = next.map { Set($0) }
    }
}

extension Context: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.strict(Self.names)
        var lists: [String: [String]] = [:]
        for name in Self.names {
            let words: [String] = try c.value(name)
            lists[name] = words
        }
        self.init(lists)
    }
}

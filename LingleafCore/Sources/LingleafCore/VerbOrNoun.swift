import Foundation

/// How a homograph of the irregular-verb table ("left", "saw", "leaves") reads in its sentence
/// (SPEC.md, Shared logic, "Verb or noun"). Same names as `Reading` in lingleaf-android.
public struct Reading: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case noun, verb, unsure
    }

    /// The step that decided (`unsure` when none did).
    public enum Step: String, Sendable, CaseIterable {
        case name, phrase, fixed, noun, participleOpen, base, participle, subject, nameS, subjectNoun, nounS, quantifier
        case conjunction, unsure
    }

    public let kind: Kind
    /// The base form in this sentence ("leave" in "she left", "left" in "turn left"); the word
    /// itself when unsure.
    public let base: String
    public let step: Step

    public init(kind: Kind, base: String, step: Step) {
        self.kind = kind
        self.base = base
        self.step = step
    }

    public var isVerb: Bool { kind == .verb }
}

extension IrregularVerbs {
    /// How the word at `range` of `text` reads, or nil when it is not a homograph of the table.
    /// Only the words next to it (spaces between) count, so a paragraph works as well as its sentence.
    /// For every word of a paragraph, tokenize once and use `resolve(_:_:)` with `Words`.
    public func resolve(_ text: String, _ range: WordRange) -> Reading? {
        let ns = text as NSString
        guard range.start >= 0, range.start < range.end, range.end <= ns.length else { return nil }
        guard homographs[TextTools.normalize(ns.substring(with: range.nsRange))] != nil else { return nil }
        let words = Words(ns)
        return words.index(of: range).flatMap { resolve(words, $0) }
    }

    /// How word `i` of `words` reads: nil when it is not a homograph. Looks only at its neighbours.
    func resolve(_ words: Words, _ i: Int) -> Reading? {
        let form = words.token(i)
        guard let homograph = homographs[form] else { return nil }
        return Resolver(table: self, h: homograph, form: form, words: words, i: i).reading()
    }

    /// A word capitalised mid-sentence, not all capitals ("Aunt Rose", "Drew"): a name.
    func isName(_ text: String, _ range: WordRange) -> Bool {
        let ns = text as NSString
        // Most words aren't capitalised: no need to find the words around them.
        guard range.start >= 0, range.start < ns.length, (0x41...0x5A).contains(ns.character(at: range.start)) else { return false }
        let words = Words(ns)
        return words.index(of: range).map { isName(words, $0) } ?? false
    }

    func isName(_ words: Words, _ i: Int) -> Bool {
        !words.startsSentence(i) && words.titlecase(i) && words.surface(i).contains(where: \.isLowercase)
    }

    /// What the voice says for the word at `range` of `text`: the table's respelling of its slot
    /// only when the reading proves the slot (SPEC.md: the base after to, a modal or do, or opening
    /// a command; the past, or the -s form, in a verb reading of a homograph; the participle after
    /// have or a passive be), else the word as written ("I read every day" → "read"). The respelling
    /// is looked up by the reading's base and slot, never by the spelling alone: "to wound" (hurt)
    /// is not "wownd". Same rule as `spokenAt` in lingleaf-android.
    public func spokenForm(in text: String, at range: WordRange) -> String {
        let ns = text as NSString
        guard range.start >= 0, range.start < range.end, range.end <= ns.length else { return "" }
        let surface = ns.substring(with: range.nsRange)
        let words = Words(ns)
        guard let i = words.index(of: range) else { return surface }
        return spokenForm(words, i) ?? surface
    }

    /// The respelling of word `i` of `words`, or nil to speak it as written.
    func spokenForm(_ words: Words, _ i: Int) -> String? {
        let w = words.token(i)
        if homographs[w] != nil {
            guard let reading = resolve(words, i), reading.kind == .verb, let entry = verb(base: reading.base) else { return nil }
            return Self.slot(of: w, in: entry, step: reading.step).flatMap { entry.spokenAs[$0] }
        }
        guard let entry = verb(base: formToBase[w] ?? w), !entry.spokenAs.isEmpty, !isName(words, i),
              let head = words.head(before: i, skip: context.skip) else { return nil }
        let slot: String? = if context.toAndModals.contains(head.token) && w == entry.base {
            "base"
        } else if participleHelpers.contains(head.token) && entry.participle.contains(w) {
            "participle"
        } else {
            nil
        }
        return slot.flatMap { entry.spokenAs[$0] }
    }

    /// The slot of a homograph read as a verb, from the step that read it.
    private static func slot(of w: String, in verb: IrregularVerb, step: Reading.Step) -> String? {
        switch step {
        case .base: w == verb.base ? "base" : nil
        case .participle: verb.participle.contains(w) ? "participle" : nil
        default: verb.past.contains(w) ? "past" : w == verb.s ? "s" : nil
        }
    }
}

/// The words of a text, for looking at a word's neighbours.
/// Tokenized once per text: every look at a word's neighbours is then constant time.
struct Words {
    let ns: NSString
    let ranges: [WordRange]

    init(_ ns: NSString, ranges: [WordRange]? = nil) {
        self.ns = ns
        self.ranges = ranges ?? TextTools.wordRanges(ns as String)
    }

    /// Which word `range` is (binary search: the ranges are in order).
    func index(of range: WordRange) -> Int? {
        var low = 0, high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if ranges[mid].start < range.start { low = mid + 1 } else { high = mid }
        }
        return low < ranges.count && ranges[low] == range ? low : nil
    }

    var count: Int { ranges.count }

    func surface(_ k: Int) -> String { ns.substring(with: ranges[k].nsRange) }

    func token(_ k: Int) -> String { TextTools.normalize(surface(k)) }

    /// The text between word `a` and the next word `b` (empty if they overlap).
    func gap(_ a: Int, _ b: Int) -> String {
        guard ranges[b].start >= ranges[a].end else { return "" }
        return ns.substring(with: NSRange(location: ranges[a].end, length: ranges[b].start - ranges[a].end))
    }

    /// Words `a` and `b` (= a + 1) exist and only spaces are between them.
    func gapOK(_ a: Int, _ b: Int) -> Bool {
        a >= 0 && b < count && gap(a, b).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startsSentence(_ k: Int) -> Bool {
        k == 0 || gap(k - 1, k).contains { ".!?:;“\"‘(".contains($0) }
    }

    /// Capitalised like a name or a sentence start ("Rose", "Tom's"; not "NASA").
    func titlecase(_ k: Int) -> Bool {
        let s = surface(k)
        guard let first = s.first, first.isUppercase else { return false }
        return s.count == 1 || s.contains("'") || s.contains("’") || !s.dropFirst().contains(where: \.isUppercase)
    }

    /// A listed adverb, or a lower-case word in -ly ("slowly"; not "Polly").
    func isSkip(_ k: Int, _ skip: Set<String>) -> Bool {
        let t = token(k)
        return skip.contains(t) || (t.hasSuffix("ly") && t.count > 3 && !titlecase(k))
    }

    /// The nearest word before word `i` past up to `limit` skip words, with only spaces between.
    func head(before i: Int, skip: Set<String>, limit: Int = 2) -> (index: Int, token: String)? {
        var k = i - 1
        var skipped = 0
        while k >= 0, gapOK(k, k + 1) {
            if isSkip(k, skip), skipped < limit {
                skipped += 1
                k -= 1
                continue
            }
            return (k, token(k))
        }
        return nil
    }
}

/// The verb-or-noun rule for one homograph, step by step (SPEC.md, steps 1–9; reference
/// implementation shared with lingleaf-android).
private struct Resolver {
    let table: IrregularVerbs
    let h: Homograph
    let form: String
    let words: Words
    let i: Int

    private var c: Context { table.context }
    private var plural: Bool { h.rules.contains(.plural) }

    /// The `n`th word before the form, when only spaces are between them.
    private func previous(_ n: Int) -> String? {
        let k = i - n
        guard k >= 0, (k..<i).allSatisfy({ words.gapOK($0, $0 + 1) }) else { return nil }
        return words.token(k)
    }

    /// The `n`th word after the form, when only spaces are between them.
    private func next(_ n: Int) -> String? {
        let k = i + n
        guard k < words.count, (i..<k).allSatisfy({ words.gapOK($0, $0 + 1) }) else { return nil }
        return words.token(k)
    }

    private var unsure: Reading { Reading(kind: .unsure, base: form, step: .unsure) }

    private func noun(_ step: Reading.Step) -> Reading? {
        h.noun.map { Reading(kind: .noun, base: $0, step: step) }
    }

    /// The form as the verb it is a form of; "lay" is "lay" (put) before an object, else "lie".
    private func verb(_ step: Reading.Step, subject: String? = nil) -> Reading {
        guard form == "lay" else { return Reading(kind: .verb, base: h.verb, step: step) }
        let n1 = next(1), n2 = next(2)
        let article = n1.map { ["the", "a", "an"].contains($0) } == true
        let object = n1.map(c.objectStarts.contains) == true && !(article && n2.map(c.layTime.contains) == true)
        // "they lay bricks": the present of "lay" or the past of "lie".
        if let subject, ["i", "you", "we", "they"].contains(subject), !object, n1.map(c.lieAfter.contains) != true {
            return unsure
        }
        return Reading(kind: .verb, base: object ? (h.baseVerb ?? h.verb) : h.verb, step: step)
    }

    func reading() -> Reading {
        if let reading = name() ?? phrase() ?? fixed() ?? afterDeterminer() ?? openingParticiple() { return reading }
        let head = words.head(before: i, skip: c.skip)
        return baseOrParticiple(head) ?? afterSubject(head) ?? unsure
    }

    /// 1. A name ("Aunt Rose") or part of a hyphenated word ("left-handed").
    private func name() -> Reading? {
        let surface = words.surface(i)
        if !words.startsSentence(i), words.titlecase(i), surface.contains(where: \.isLowercase) {
            return Reading(kind: .noun, base: form, step: .name)
        }
        let range = words.ranges[i]
        let hyphen: unichar = 0x2D
        if (range.end < words.ns.length && words.ns.character(at: range.end) == hyphen)
            || (range.start > 0 && words.ns.character(at: range.start - 1) == hyphen) {
            return Reading(kind: .noun, base: form, step: .name)
        }
        return nil
    }

    /// 2. A listed phrase ("turn left", "left hand", "right and left"); "bound for", "bound to" + a verb.
    private func fixed() -> Reading? {
        let p1 = previous(1), p2 = previous(2), n1 = next(1), n2 = next(2)
        if h.noun != nil {
            // A capitalised plant word that is also a name ("Holly leaves at six") is not the plant.
            let plantName = p1.map(c.nameOrPlant.contains) == true && words.titlecase(i - 1)
            if let p1, h.nounAfter.contains(p1), !plantName { return noun(.fixed) }
            if let n1, h.nounBefore.contains(n1) { return noun(.fixed) }
            if let pair = h.nounPair {
                let joiners: Set<String> = ["and", "or"]
                if (p1.map(joiners.contains) == true && p2 == pair) || (n1.map(joiners.contains) == true && n2 == pair) {
                    return noun(.fixed)
                }
            }
        }
        if form == "bound", let n1 {
            let toVerb = n1 == "to" && n2.map { table.bases.contains($0) || Verbs.regular.contains($0) } == true
            if c.boundAdjective.contains(n1) || toVerb { return Reading(kind: .noun, base: "bound", step: .fixed) }
        }
        return nil
    }

    /// 3. A noun after a determiner (+ one listed adjective); an -s form also after a quantifier or a preposition.
    private func afterDeterminer() -> Reading? {
        guard h.noun != nil else { return nil }
        let determiners = plural ? c.determiners.union(c.pluralDeterminers).union(c.prepositions) : c.determiners
        let adjectives = plural ? c.adjectives.union(c.pluralAdjectives) : c.adjectives
        // A possessive too ("the soldier's"), unless the form can follow "has" ("John's left").
        func isDeterminer(_ t: String?) -> Bool {
            guard let t else { return false }
            return determiners.contains(t) || (t.hasSuffix("'s") && !c.haveAndBe.contains(t) && !h.rules.contains(.participle))
        }
        let p1 = previous(1)
        if isDeterminer(p1) || (p1.map(adjectives.contains) == true && isDeterminer(previous(2))) { return noun(.noun) }
        return nil
    }

    /// 4. A base form after to / a modal / do, or opening a command; 5. a participle after have/be.
    private func baseOrParticiple(_ head: (index: Int, token: String)?) -> Reading? {
        let t = head?.token
        if let baseVerb = h.baseVerb, let t, c.toAndModals.contains(t), !(t == "to" && h.noTo) {
            return Reading(kind: .verb, base: baseVerb, step: .base)
        }
        if h.rules.contains(.imperative), words.startsSentence(i) || (previous(1) == "please" && words.startsSentence(i - 1)),
           let n1 = next(1), c.objectStarts.contains(n1) {
            return Reading(kind: .verb, base: h.baseVerb ?? h.verb, step: .base)
        }
        if h.rules.contains(.participle), let t, c.haveAndBe.contains(t) { return verb(.participle) }
        return nil
    }

    /// 6. After a subject; 7. after a determiner + noun opening the sentence or a clause; 8. after and/but/then.
    private func afterSubject(_ head: (index: Int, token: String)?) -> Reading? {
        guard let head else { return nil }
        let k = head.index, t = head.token
        if h.verbAfter.contains(t) { return Reading(kind: .verb, base: h.verb, step: .subject) }
        // "one" is a subject in "no one saw", not in "with one bound" or "One spoke had come loose".
        let oneOK = t != "one" || (k >= 1 && words.gapOK(k - 1, k) && c.oneAfter.contains(words.token(k - 1)))
        if (c.subjects.contains(t) && oneOK) || (plural && c.singularSubjects.contains(t)) { return verb(.subject, subject: t) }
        if words.titlecase(k), t != "i", !c.subjects.contains(t) {
            let opensSentence = words.startsSentence(k)
            if !opensSentence || (!c.notNames.contains(t) && !c.adjectives.contains(t) && !t.hasSuffix("ly") && !plural) {
                return verb(.subject)
            }
            // nameS: a name opening the sentence + an -s form + a preposition or adverb ("Tom lives in…").
            if h.rules.contains(.sVerb), sFormNext, looksLikeName(k), !finiteVerbLater() { return verb(.nameS) }
        }
        if h.rules.contains(.subjectNoun), !words.titlecase(k), let d = subjectDeterminer(k, t), opensClause(d),
           h.subjectNounNext.map({ allowed in next(1).map(allowed.contains) == true }) ?? true {
            return verb(.subjectNoun)
        }
        return nounAndSForm(k, t) ?? quantifierSubject(k, t) ?? conjunction(t)
    }

    private func conjunction(_ t: String) -> Reading? {
        h.rules.contains(.conjunction) && c.conjunctions.contains(t) ? verb(.conjunction) : nil
    }

    /// The determiner before the noun `t` at `k` ("the sun", "the red sun"), if `t` can be a noun.
    private func subjectDeterminer(_ k: Int, _ t: String) -> Int? {
        guard !c.closed.contains(t), !t.hasSuffix("ly"), k >= 1, words.gapOK(k - 1, k) else { return nil }
        if c.subjectDeterminers.contains(words.token(k - 1)) { return k - 1 }
        if c.adjectives.contains(words.token(k - 1)), k >= 2, words.gapOK(k - 2, k - 1),
           c.subjectDeterminers.contains(words.token(k - 2)) {
            return k - 2
        }
        return nil
    }

    /// The determiner at `d` starts the sentence or a clause (after , ; — – or a listed word).
    private func opensClause(_ d: Int) -> Bool {
        if words.startsSentence(d) { return true }
        if words.gap(d - 1, d).contains(where: { ",;—–".contains($0) }) { return true }
        return words.gapOK(d - 1, d) && c.clauseOpeners.contains(words.token(d - 1))
    }
}

// MARK: Steps added with the table's v2 lists (SPEC.md: 2, 3b, 6 nameS, 7b, 7c)

private extension Resolver {
    /// An -s form before a listed preposition or adverb (not "of") or a word in -ly: "lives in", "leaves at".
    var sFormNext: Bool {
        guard let n1 = next(1), n1 != "of" else { return false }
        return c.sFormNext.contains(n1) || (n1.hasSuffix("ly") && n1.count > 3)
    }

    /// 2. A listed noun phrase ("the lost and found") → the word itself, not a verb, unless what is
    /// before the phrase makes it a verb ("she lost and found her keys") or an object word follows it.
    func phrase() -> Reading? {
        for phrase in h.nounPhrases {
            guard let at = phrase.firstIndex(of: form) else { continue }
            let first = i - at, last = i - at + phrase.count - 1
            guard first >= 0, last < words.count, (first..<last).allSatisfy({ words.gapOK($0, $0 + 1) }),
                  (first...last).map(words.token) == phrase else { continue }
            let before = first >= 1 && words.gapOK(first - 1, first) ? words.token(first - 1) : nil
            let after = last + 1 < words.count && words.gapOK(last, last + 1) ? words.token(last + 1) : nil
            let verbal = before.map { word in
                c.subjects.contains(word) || c.haveAndBe.contains(word) || words.isSkip(first - 1, c.skip)
                    || (words.titlecase(first - 1) && !words.startsSentence(first - 1))
            } ?? false
            if !verbal, after.map(c.objectStarts.contains) != true {
                return Reading(kind: .noun, base: h.noun ?? form, step: .phrase)
            }
        }
        return nil
    }

    /// 3b. A participle opening the sentence, before a listed word or a word in -ly, with a comma later
    /// in the sentence ("Left alone, she cried"; not "Felt hats, …").
    func openingParticiple() -> Reading? {
        guard h.rules.contains(.participle), words.startsSentence(i), let n1 = next(1), next(2) != form,
              c.participleOpenNext.contains(n1) || (n1.hasSuffix("ly") && n1.count > 3) else { return nil }
        let rest = words.ns.substring(from: words.ranges[i].end)
        let clause = rest.prefix { !".!?".contains($0) }
        return clause.contains(",") ? verb(.participleOpen) : nil
    }

    /// 7b. Determiner (+ adjective) + a singular noun + an -s form + a preposition or adverb, the
    /// determiner opening the sentence or a clause ("The old man lives alone", "The bus leaves at six").
    func nounAndSForm(_ k: Int, _ t: String) -> Reading? {
        guard h.rules.contains(.sVerb), sFormNext, !words.titlecase(k), isNounWord(t), !isPlural(t),
              let d = nounPhraseStart(k), opensClause(d), !finiteVerbLater() else { return nil }
        return verb(.nounS)
    }

    /// 7c. A quantifier or number (+ of (+ determiner)) (+ adjective) + a plural noun, the quantifier
    /// opening the sentence or a clause ("Many people left", "Some of the guests left").
    func quantifierSubject(_ k: Int, _ t: String) -> Reading? {
        guard h.rules.contains(.quantifier), !words.titlecase(k), isNounWord(t), isPlural(t),
              let q = quantifierStart(k), opensClause(q) else { return nil }
        return verb(.quantifier, subject: "they")
    }

    /// A word that can head a noun phrase: not a listed function word or adjective, not in -ly or 's.
    func isNounWord(_ t: String) -> Bool {
        !c.nounClosed.contains(t) && !t.hasSuffix("ly") && !t.hasSuffix("'s")
    }

    /// "men", "people", "girls", "buses"; not "bus", "glass", "news".
    func isPlural(_ t: String) -> Bool {
        if c.pluralNouns.contains(t) { return true }
        let singularEnding = ["ss", "us", "is", "'s"].contains { t.hasSuffix($0) }
        return t.count > 3 && t.hasSuffix("s") && !singularEnding && !c.notPlural.contains(t)
    }

    /// The word before `k` when only spaces are between them.
    func back(_ k: Int) -> Int? {
        k >= 1 && words.gapOK(k - 1, k) ? k - 1 : nil
    }

    /// The determiner of "determiner (+ adjective) + the noun at `k`".
    func nounPhraseStart(_ k: Int) -> Int? {
        var j = back(k)
        if let adjective = j, c.adjectives.contains(words.token(adjective)) { j = back(adjective) }
        guard let j, c.subjectDeterminers.contains(words.token(j)) else { return nil }
        return j
    }

    /// The quantifier of "Q [of] [determiner] (+ adjective) + the plural noun at `k`".
    func quantifierStart(_ k: Int) -> Int? {
        var j = back(k)
        if let adjective = j {
            let word = words.token(adjective)
            if (c.adjectives.contains(word) || c.pluralAdjectives.contains(word)) && !c.quantifiers.contains(word) {
                j = back(adjective)
            }
        }
        guard let start = j else { return nil }
        var q: Int?
        var current: Int? = start
        if c.quantifiers.contains(words.token(start)) {
            q = start  // "many people", "these boys"
        } else if c.determiners.contains(words.token(start)) {
            // "all the guests", "both my sisters", "some of the guests"
            let before = back(start)
            if let before, c.quantifiersBeforeDeterminer.contains(words.token(before)) { q = before }
            current = before
        }
        guard let current else { return q }
        // "hundreds of people", "some of these people"
        let of = words.token(current) == "of" ? current : back(current)
        if let of, words.token(of) == "of", let before = back(of) {
            let word = words.token(before)
            if c.quantifiers.contains(word) || c.quantifiersBeforeOf.contains(word) { return before }
        }
        return q
    }

    /// A finite verb after the form in its clause: the form is then a noun ("Double lives in fiction
    /// are common"); the clause ends at punctuation or a clause opener.
    func finiteVerbLater() -> Bool {
        var j = i + 1
        while j < words.count {
            if words.gap(j - 1, j).contains(where: { ",;:.!?—–()".contains($0) }) { return false }
            let t = words.token(j)
            if c.clauseOpeners.contains(t) || ["who", "which", "whose", "whom"].contains(t) { return false }
            if c.finiteVerbs.contains(t) || table.pastForms.contains(t) { return true }
            j += 1
        }
        return false
    }

    /// A capitalised word opening the sentence that is probably a name ("Tom", "Mrs"), not a verb form.
    func looksLikeName(_ k: Int) -> Bool {
        let t = words.token(k)
        if c.nounClosed.contains(t) || c.notNameStarts.contains(t) || c.nameOrPlant.contains(t)
            || ["ly", "ful", "less", "ous"].contains(where: { t.hasSuffix($0) }) {
            return false
        }
        func isVerb(_ stem: String) -> Bool { table.bases.contains(stem) || Verbs.regular.contains(stem) }
        // "Wasted", "Saved", "Saving": a verb form, not a name.
        for (suffix, cut) in [("ed", 2), ("ed", 1), ("ing", 3)] where t.hasSuffix(suffix) && t.count > suffix.count + 2 {
            let stem = String(t.dropLast(cut))
            let doubled = stem.count > 2 && stem.last == stem.dropLast().last && isVerb(String(stem.dropLast()))
            if isVerb(stem) || isVerb(stem + "e") || doubled { return false }
        }
        return true
    }
}

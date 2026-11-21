import Foundation
@testable import LingleafCore

/// The cue rule of the verbs with a homonym, lie and hang (SPEC.md, Verb sentences data): the file says which sense a
/// sentence is, and the sentence must not leave a reader in doubt. Where the form is the same in both senses (positions 1,
/// 2, 3, 6 and 10: the base, the -s and the -ing form) the sentence needs a cue of its own sense and none of the other's;
/// where the form proves the sense (lay, lain, lied; hung, hanged) only the check of no cue of the other sense applies.
/// The particles come from irregular-verbs.json (`homonym.verbBefore` and `homonymBefore`): one source of truth.
extension VerbSentencesLint {
    private static var lie: IrregularVerb.Homonym { IrregularVerbs.shared.verb(base: "lie")!.homonym! }
    private static var hang: IrregularVerb.Homonym { IrregularVerbs.shared.verb(base: "hang")!.homonym! }

    /// lie, sense 0: a place or posture right after the verb (within 2 words: "lie quietly on"). The table's `verbBefore`.
    static var liePlaces: Set<String> { lie.verbBefore }
    /// lie, sense 1: the next word that makes it "to deceive" (to, about, through). The table's `homonymBefore`.
    static var lieDeceivesBefore: Set<String> { lie.homonymBefore }
    /// "to the north" is a direction, not a person.
    static let lieDirections: Set<String> = ["north", "south", "east", "west", "left", "right", "end", "top"]
    /// hang, sense 0: a particle right after the verb ("hang up", "hang from"). The table's `verbBefore`.
    static var hangParticles: Set<String> { hang.verbBefore }
    /// hang, sense 1: himself, herself and the like. Refused after hang: no suicide in the sentences.
    static var hangReflexives: Set<String> { hang.homonymBefore }

    static let hangThingWords = [
        "coat", "picture", "painting", "photo", "mirror", "flag", "sign", "clothes", "washing", "towel", "curtains", "lamp",
        "laundry", "jacket", "shirt", "dress", "hat", "keys", "bag", "poster", "clock", "map", "calendar", "lights", "decorations",
        "banner", "bell", "curtain",
    ]
    static let hangExecutedWords = [
        "murderer", "killer", "thief", "criminal", "prisoner", "traitor", "outlaw", "pirate", "spy", "soldier", "witch", "robber",
        "bandit", "rebel", "slave", "convict", "villain",
    ]

    /// hang, sense 0: a thing that is hung, anywhere in the sentence, with its plural.
    static let hangThings: Set<String> = Set(hangThingWords.flatMap { [$0, plural($0)] })
    /// hang, sense 1: a person who is executed, anywhere in the sentence, with its plural.
    static let hangExecuted: Set<String> = Set(hangExecutedWords.flatMap { [$0, plural($0)] })
    /// After "hanged": him, her, them.
    static let hangedObjects: Set<String> = ["him", "her", "them"]

    static func plural(_ word: String) -> String {
        if word == "thief" { return "thieves" }
        if word.hasSuffix("y"), let before = word.dropLast().last, !"aeiou".contains(before) { return word.dropLast() + "ies" }
        if ["s", "x", "ch", "sh"].contains(where: word.hasSuffix) { return word + "es" }
        return word + "s"
    }

    /// Whether the sentence has a cue of sense 0 and one of sense 1, read around the word at `index` (the form; when nil, the
    /// first form of the verb in the sentence); nil for a verb without cue lists.
    static func cues(_ view: SentenceView, base: String, at index: Int? = nil) -> (sense0: Bool, sense1: Bool)? {
        guard base == "lie" || base == "hang", let verb = IrregularVerbs.shared.verb(base: base) else { return nil }
        let forms = Set([verb.base] + verb.forms)
        guard let k = index ?? view.tokens.firstIndex(where: forms.contains) else { return (false, false) }
        return base == "lie" ? lieCues(view.tokens, k) : hangCues(view.tokens, k)
    }

    private static func lieCues(_ tokens: [String], _ k: Int) -> (sense0: Bool, sense1: Bool) {
        let after = tokens[min(k + 1, tokens.count)..<min(k + 3, tokens.count)]
        return (after.contains(where: liePlaces.contains), deceives(tokens, k))
    }

    /// The form followed by "to" and anything but "the" + a direction, or by "about" or "through" (not "lying about": it can
    /// be things lying about, a cue of neither sense).
    private static func deceives(_ tokens: [String], _ k: Int) -> Bool {
        guard k + 1 < tokens.count, lieDeceivesBefore.contains(tokens[k + 1]) else { return false }
        if tokens[k + 1] != "to" { return tokens[k] != "lying" }
        guard k + 2 < tokens.count else { return false }
        return !(tokens[k + 2] == "the" && k + 3 < tokens.count && lieDirections.contains(tokens[k + 3]))
    }

    private static func hangCues(_ tokens: [String], _ k: Int) -> (sense0: Bool, sense1: Bool) {
        let next = k + 1 < tokens.count ? tokens[k + 1] : nil
        let thing = tokens.contains(where: hangThings.contains) || next.map(hangParticles.contains) == true
        let executed = tokens.contains(where: hangExecuted.contains) || (tokens[k] == "hanged" && next.map(hangedObjects.contains) == true)
        return (thing, executed)
    }

    /// The cue rule for the sentence whose form is at `index`: `cue-sense`, and `hang-reflexive` for "hung himself".
    static func cueProblem(_ sentence: VerbSentence, view: SentenceView, index: Int, verb: IrregularVerb) -> [String] {
        guard verb.homonym != nil, let found = cues(view, base: verb.base, at: index) else { return [] }
        var out: [String] = []
        let next = index + 1 < view.tokens.count ? view.tokens[index + 1] : nil
        if verb.base == "hang", next.map(hangReflexives.contains) == true { out.append("hang-reflexive") }
        let own = sentence.senseIndex == 1 ? found.sense1 : found.sense0
        let other = sentence.senseIndex == 1 ? found.sense0 : found.sense1
        let needsCue = [1, 2, 3, 6, 10].contains(sentence.slot.position)
        if other || (needsCue && !own) { out.append("cue-sense") }
        return out
    }
}

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

    /// Sense 0 (the cue a sense-0 sentence needs): a place word within 2 words after the form, or "to the" + a direction
    /// ("The town lies to the north."). "lied" is only the twin, so its "to the north" is never a direction: "He lied to the
    /// north team." is sense 1, by design.
    private static func lieCues(_ tokens: [String], _ k: Int) -> (sense0: Bool, sense1: Bool) {
        let after = tokens[min(k + 1, tokens.count)..<min(k + 3, tokens.count)]
        return (after.contains(where: liePlaces.contains) || isDirection(tokens, k), deceives(tokens, k))
    }

    /// The check AGAINST a sense-1 sentence is narrower: only the word right after the verb (or "to the" + a direction) counts,
    /// so "He lied about it there." is not contradicted by a place two words away.
    static func lieSenseZeroAdjacent(_ tokens: [String], _ k: Int) -> Bool {
        (k + 1 < tokens.count && liePlaces.contains(tokens[k + 1])) || isDirection(tokens, k)
    }

    /// The forms of the verb that can also be sense 0 and are the same in both senses: lie, lies, lying. "lied" is only the twin.
    static let lieSharedForms: Set<String> = ["lie", "lies", "lying"]

    /// The form (lie, lies, lying) followed by "to the" and a direction word; never for "lied" or another form.
    private static func isDirection(_ tokens: [String], _ k: Int) -> Bool {
        guard lieSharedForms.contains(tokens[k]), k + 3 < tokens.count else { return false }
        return tokens[k + 1] == "to" && tokens[k + 2] == "the" && lieDirections.contains(tokens[k + 3])
    }

    /// The form followed by "to" and anything but "the" + a direction (for lie, lies, lying), or by "about" or "through" (not
    /// "lying about": it can be things lying about, a cue of neither sense).
    private static func deceives(_ tokens: [String], _ k: Int) -> Bool {
        guard k + 1 < tokens.count, lieDeceivesBefore.contains(tokens[k + 1]) else { return false }
        if tokens[k + 1] != "to" { return tokens[k] != "lying" }
        return k + 2 < tokens.count && !isDirection(tokens, k)
    }

    private static func hangCues(_ tokens: [String], _ k: Int) -> (sense0: Bool, sense1: Bool) {
        let next = k + 1 < tokens.count ? tokens[k + 1] : nil
        // "hanged" proves sense 1 by itself: "The thief was hanged on Friday." has no sense-0 particle.
        let particle = tokens[k] != "hanged" && next.map(hangParticles.contains) == true
        let thing = tokens.contains(where: hangThings.contains) || particle
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
        var other = sentence.senseIndex == 1 ? found.sense0 : found.sense1
        // Against a sense-1 sentence of lie, only a place right after the verb counts (the cue a sense-0 sentence needs is wider),
        // and only where the form is shared (lie, lies, lying): "lied" proves sense 1 by itself, so no place contradicts it.
        if verb.base == "lie", sentence.senseIndex == 1 {
            other = lieSharedForms.contains(view.tokens[index]) && lieSenseZeroAdjacent(view.tokens, index)
        }
        let needsCue = [1, 2, 3, 6, 10].contains(sentence.slot.position)
        if other || (needsCue && !own) { out.append("cue-sense") }
        return out
    }
}

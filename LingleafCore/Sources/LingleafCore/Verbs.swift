import Foundation

/// Verb forms used to tell a helper verb from a main verb ("has seen" vs "has a dog").
/// Same lists as `Verbs` in lingleaf-android; the irregular ones come from `IrregularVerbs`.
enum Verbs {
    /// Irregular past participles ("seen", "made"), from the irregular-verb table. "got" is left
    /// out: "have got" means "have".
    static let irregularParticiples: Set<String> = IrregularVerbs.shared.participles

    /// Participles that are also base forms: after "'d" they mean "would" or "had" ("I'd come").
    static let baseLikeParticiples: Set<String> = IrregularVerbs.shared.baseLikeParticiples

    /// Frequent regular verbs, to tell a past participle ("had finished") from a word that
    /// only ends in -ed ("had red hair"). Irregular verbs are in `IrregularVerbs`.
    static let regular: Set<String> = [
        "accept", "add", "admire", "admit", "advise", "agree", "allow", "announce", "answer",
        "apologise", "apologize", "appear", "arrange", "arrive", "ask", "attack", "attempt",
        "avoid", "beg", "believe", "belong", "blame", "boil", "borrow", "bow", "burn", "call",
        "calm", "care", "carry", "cause", "change", "charge", "chase", "cheat", "check", "cheer",
        "clean", "clear", "climb", "close", "collect", "comb", "complain", "complete", "concern",
        "confess", "consider", "contain", "continue", "cook", "copy", "count", "cover", "crash",
        "crawl", "create", "cross", "cry", "dance", "dare", "deceive", "decide", "declare",
        "delay", "deliver", "deny", "depend", "describe", "deserve", "desire", "destroy",
        "determine", "die", "disappear", "discover", "dislike", "divide", "doubt", "drag", "dress",
        "drop", "dry", "earn", "employ", "end", "enjoy", "enter", "escape", "examine", "excite",
        "excuse", "expect", "explain", "express", "fail", "fasten", "fear", "fetch", "fill",
        "finish", "fix", "follow", "force", "form", "gather", "glance", "grab", "greet", "guess",
        "hand", "handle", "happen", "hate", "help", "hope", "hunt", "hurry", "imagine", "improve",
        "include", "inform", "insist", "install", "intend", "interest", "introduce", "invite",
        "join", "joke", "judge", "jump", "kick", "kill", "kiss", "knock", "land", "last", "laugh",
        "learn", "lift", "like", "listen", "live", "lock", "look", "love", "manage", "mark",
        "marry", "matter", "mention", "mind", "miss", "move", "murder", "name", "need", "notice",
        "obey", "object", "observe", "obtain", "offer", "open", "order", "own", "pack", "pass",
        "pause", "perform", "permit", "persuade", "pick", "place", "plan", "plant", "play",
        "please", "point", "possess", "pour", "pray", "prefer", "prepare", "present", "press",
        "pretend", "prevent", "produce", "promise", "protect", "prove", "provide", "pull",
        "punish", "push", "question", "rain", "raise", "reach", "realise", "realize", "receive",
        "recognise", "recognize", "recover", "refuse", "regard", "reject", "rejoice", "relieve",
        "remain", "remark", "remember", "remove", "repeat", "replace", "reply", "report",
        "request", "rescue", "resolve", "rest", "retire", "return", "reveal", "rob", "roll",
        "rush", "sail", "save", "scream", "search", "seem", "seize", "serve", "settle", "share",
        "shout", "sign", "signal", "smile", "smoke", "sound", "stare", "start", "starve", "stay",
        "step", "stop", "study", "succeed", "suffer", "suggest", "supply", "suppose", "surprise",
        "surround", "suspect", "talk", "taste", "thank", "touch", "travel", "treat", "tremble",
        "trouble", "trust", "try", "turn", "use", "visit", "wait", "walk", "want", "warn", "wash",
        "watch", "wave", "welcome", "whisper", "wish", "wonder", "work", "worry", "yield",
    ]

    /// A past participle: irregular ("seen"), or -ed from a known verb ("finished", "tried").
    /// `baseLike` false leaves out forms that are also base forms ("come", "read").
    static func isParticiple(_ token: String, baseLike: Bool = true) -> Bool {
        if irregularParticiples.contains(token) { return baseLike || !baseLikeParticiples.contains(token) }
        guard token.hasSuffix("ed") else { return false }
        // Short forms too ("used" from "use"), which base-form rules leave alone.
        return regular.contains(String(token.dropLast())) || TextTools.baseFormCandidates(token).contains { regular.contains($0) }
    }

    /// Irregular verbs in their base form, from the table, leaving out those used mostly as
    /// nouns ("light": "had better light" is ordinary).
    static let irregularBases: Set<String> = IrregularVerbs.shared.hadBetterBases

    /// A base form, for "had better" + verb.
    static func isBase(_ token: String) -> Bool {
        regular.contains(token) || irregularBases.contains(token)
    }
}

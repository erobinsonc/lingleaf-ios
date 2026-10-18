import Foundation

/// A word inside a paragraph, as UTF-16 offsets (the units `NSString` and
/// `NSAttributedString` use). Same rules as `TextTools` in lingleaf-android.
public struct WordRange: Hashable, Sendable {
    public let start: Int
    public let end: Int

    public init(_ start: Int, _ end: Int) {
        self.start = start
        self.end = end
    }

    public func contains(_ offset: Int) -> Bool { offset >= start && offset < end }

    public var nsRange: NSRange { NSRange(location: start, length: end - start) }
}

public enum TextTools {
    private static let wordPattern = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)*")
    /// Starts only at the first mark of a run and never backtracks into it, so a long run of
    /// marks ("!!!!…x") is matched in one pass, not once per mark.
    private static let sentenceEnd = try! NSRegularExpression(pattern: "(?<![.!?])[.!?]++[\"”’)\\]]*+(?=\\s|$)")

    /// Longest paragraph kept whole, in UTF-16 units: a text without blank lines can't
    /// become one paragraph the size of a book.
    public static let maxParagraph = 2000
    /// Longest sentence kept as a word's context, in UTF-16 units.
    public static let maxSentence = 600
    /// Longest title or author shown or saved, in characters.
    public static let maxLabel = 200

    /// Splits text on blank lines and joins hard-wrapped lines
    /// (Project Gutenberg wraps at ~70 columns). Paragraphs over `maxParagraph` are cut
    /// after their last sentence end that fits, else at a space.
    public static func splitParagraphs(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [String] = []
        var current: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(contentsOf: bounded(current.joined(separator: " ")))
                    current.removeAll()
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { paragraphs.append(contentsOf: bounded(current.joined(separator: " "))) }
        return paragraphs
    }

    /// `paragraph` in pieces of at most `maxParagraph` UTF-16 units, each cut after the last
    /// sentence end that fits, else at the last space, else (no spaces at all) at the limit.
    /// Walks the text once with an index, so a 10 MB text without blank lines splits in linear time.
    static func bounded(_ paragraph: String) -> [String] {
        // One real NSString, made once: every regex and substring below works on it in place.
        let ns = NSString(string: paragraph)
        guard ns.length > maxParagraph else { return [paragraph] }
        let text = ns as String
        var pieces: [String] = []
        var start = 0
        while true {
            while start < ns.length, isSpace(ns.character(at: start)) { start += 1 }
            if ns.length - start <= maxParagraph {
                let last = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
                if !last.isEmpty { pieces.append(last) }
                return pieces
            }
            // One unit past the limit, so the sentence-end lookahead can see what follows.
            let window = NSRange(location: start, length: maxParagraph + 1)
            var cut = sentenceEnd.matches(in: text, range: window)
                .map { $0.range.location + $0.range.length - start }
                .last { $0 <= maxParagraph } ?? 0
            if cut == 0 {
                let space = ns.rangeOfCharacter(
                    from: .whitespaces, options: .backwards, range: NSRange(location: start + 1, length: maxParagraph - 1)
                )
                cut = space.location == NSNotFound ? maxParagraph : space.location - start
            }
            // Never between the halves of a surrogate pair, and always forward.
            if cut > 1, UTF16.isLeadSurrogate(ns.character(at: start + cut - 1)) { cut -= 1 }
            let piece = ns.substring(with: NSRange(location: start, length: cut)).trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { pieces.append(piece) }
            start += cut
        }
    }

    /// At most `max` UTF-16 units of `text`, never splitting a surrogate pair.
    public static func truncated(_ text: String, _ max: Int) -> String {
        let units = text.utf16
        guard units.count > max else { return text }
        var end = max
        if end > 1, UTF16.isLeadSurrogate(units[units.index(units.startIndex, offsetBy: end - 1)]) { end -= 1 }
        return String(decoding: units.prefix(end), as: UTF16.self)
    }

    /// Accents kept on one letter: real text needs two or three; "Zalgo" text piles up thousands.
    public static let maxCombiningMarks = 4
    /// Characters that show as blank space but are letters or symbols, not whitespace.
    private static let blankFillers: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800]

    /// Outside text shown as a title or author: no control, invisible formatting or blank
    /// filler characters (bidi overrides, zero-width, Hangul fillers), at most
    /// `maxCombiningMarks` accents on one letter, single spaces, at most `maxLabel` UTF-16 units.
    public static func cleanLabel(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var marks = 0
        for scalar in text.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .nonspacingMark || category == .enclosingMark {
                marks += 1
                if marks <= maxCombiningMarks { scalars.append(scalar) }
                continue
            }
            marks = 0
            switch category {
            case .format: continue
            case .control, .lineSeparator, .paragraphSeparator: scalars.append(" ")
            default: if !blankFillers.contains(scalar.value) { scalars.append(scalar) }
            }
        }
        return truncated(String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " "), maxLabel)
    }

    /// Every English word; contractions such as "don't" stay whole.
    public static func wordRanges(_ text: String) -> [WordRange] {
        let ns = text as NSString
        return wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { WordRange($0.range.location, $0.range.location + $0.range.length) }
    }

    /// The word under `offset`. An offset right after the last letter still
    /// counts, which matches how hit-testing reports taps on a word's right half.
    public static func wordAt(_ text: String, _ offset: Int) -> WordRange? {
        var trailing: WordRange?
        for range in wordRanges(text) {
            if range.contains(offset) { return range }
            if range.end == offset { trailing = range }
            if range.start > offset { break }
        }
        return trailing
    }

    public static func substring(_ text: String, _ range: WordRange) -> String {
        (text as NSString).substring(with: range.nsRange)
    }

    public static func normalize(_ word: String) -> String {
        word.replacingOccurrences(of: "’", with: "'").lowercased()
    }

    /// The sentence of `paragraph` that contains `offset`.
    public static func sentenceAt(_ paragraph: String, _ offset: Int) -> String {
        substring(paragraph, sentenceRangeAt(paragraph, offset))
    }

    /// Where `sentenceAt` is in `paragraph`, without surrounding whitespace, so a
    /// word's offset in the paragraph can be turned into its offset in the sentence.
    public static func sentenceRangeAt(_ paragraph: String, _ offset: Int) -> WordRange {
        capped(paragraph as NSString, sentenceBounds(paragraph, offset), around: offset)
    }

    /// Every sentence of `paragraph` in one pass, trimmed and not capped: the text between
    /// sentence ends, as `sentenceRangeAt` finds them, skipping blank stretches.
    static func sentenceRanges(_ paragraph: String) -> [WordRange] {
        let ns = paragraph as NSString
        let ends = sentenceEnd.matches(in: paragraph, range: NSRange(location: 0, length: ns.length))
            .map { $0.range.location + $0.range.length } + [ns.length]
        var out: [WordRange] = []
        var start = 0
        for end in ends where end > start {
            let sentence = trimmed(ns, WordRange(start, end))
            if sentence.start < sentence.end { out.append(sentence) }
            start = end
        }
        return out
    }

    /// The whole sentence of `paragraph` at `offset`, trimmed and not capped.
    private static func sentenceBounds(_ paragraph: String, _ offset: Int) -> WordRange {
        let ns = paragraph as NSString
        var start = 0
        var end = ns.length
        for match in sentenceEnd.matches(in: paragraph, range: NSRange(location: 0, length: ns.length)) {
            let matchEnd = match.range.location + match.range.length
            if matchEnd > offset {
                end = matchEnd
                break
            }
            start = matchEnd
        }
        // Nothing left after the last sentence end: the whole paragraph.
        let sentence = trimmed(ns, WordRange(start, end))
        return sentence.start == sentence.end ? trimmed(ns, WordRange(0, ns.length)) : sentence
    }

    /// At most `maxSentence` units of `range` around `offset`, cut at spaces: a word's saved
    /// context stays a readable snippet even in a text without sentence ends.
    private static func capped(_ ns: NSString, _ range: WordRange, around offset: Int) -> WordRange {
        guard range.end - range.start > maxSentence else { return range }
        let end = min(range.end, max(range.start, min(offset, range.end) - maxSentence / 2) + maxSentence)
        let start = max(range.start, end - maxSentence)
        var s = start
        var e = end
        // Start just after a space and end just before one, so no word is cut in half.
        if s > range.start { while s < e, !isSpace(ns.character(at: s - 1)) { s += 1 } }
        if e < range.end { while e > s, !isSpace(ns.character(at: e)) { e -= 1 } }
        if s >= e { (s, e) = (start, end) }
        return trimmed(ns, WordRange(s, e))
    }

    private static func trimmed(_ ns: NSString, _ range: WordRange) -> WordRange {
        var start = range.start
        var end = range.end
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        return WordRange(start, end)
    }

    static func isSpace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Likely dictionary forms of `word`, most likely first, never the word
    /// itself. Used to look words up and to recognise inflected forms
    /// ("animals", "walked") of a word being learned. Without its sentence, a form that is also
    /// another word ("left", "leaves") is unsure: it links only when both its readings share a base.
    public static func baseFormCandidates(_ word: String) -> [String] {
        let w = normalize(word)
        let table = IrregularVerbs.shared
        if let homograph = table.homographs[w] {
            return filtered(homograph.noun == homograph.verb ? [homograph.verb] : [], w)
        }
        return candidates(w, link: table.formToBase[w] ?? nonVerb[w])
    }

    /// Likely dictionary forms of the word at `range` of `text`, read in its sentence: a form that
    /// is also another word by the verb-or-noun rule ("she left" → "leave", "turn left" → none), a
    /// form of the irregular-verb table except as a name ("Drew"), then the regular rules.
    public static func baseFormCandidates(in text: String, at range: WordRange) -> [String] {
        guard isInside(text, range) else { return [] }
        let words = Words(text as NSString)
        guard let i = words.index(of: range) else { return baseFormCandidates(substring(text, range)) }
        return baseFormCandidates(words, i)
    }

    /// `baseFormCandidates(in:at:)` for word `i` of `words`: only its neighbours are looked at.
    static func baseFormCandidates(_ words: Words, _ i: Int) -> [String] {
        let w = words.token(i)
        let table = IrregularVerbs.shared
        if let homograph = table.homographs[w] {
            return filtered(homographBase(homograph, table.resolve(words, i)).map { [$0] } ?? [], w)
        }
        let verbLink = table.formToBase[w].flatMap { table.isName(words, i) ? nil : $0 }
        return candidates(w, link: verbLink ?? nonVerb[w])
    }

    /// The base a homograph's reading gives: its noun's or its verb's; when unsure, the base both
    /// share ("tears" → "tear"), else none.
    private static func homographBase(_ homograph: Homograph, _ reading: Reading?) -> String? {
        guard let reading, reading.kind != .unsure else { return homograph.noun == homograph.verb ? homograph.verb : nil }
        return reading.base
    }

    private static func filtered(_ bases: [String], _ w: String) -> [String] {
        bases.filter { $0.count >= 2 && $0 != w }
    }

    /// `link` (an irregular form's base), then the plural, past and -ing rules.
    private static func candidates(_ w: String, link: String?) -> [String] {
        var out: [String] = []
        func add(_ candidate: String) {
            if candidate.count >= 2, candidate != w, !out.contains(candidate) { out.append(candidate) }
        }
        // A stem that doubled its last letter also gives the single one, first: stopped → stop,
        // and -ll after two vowel groups: travelled → travel (not called → cal).
        func addStem(_ stem: String) {
            if stem.hasSuffix("ll"), vowelGroups(String(stem.dropLast())) >= 2 {
                add(String(stem.dropLast()))
            } else if isDoubled(stem) {
                add(String(stem.dropLast()))
            }
            add(stem)
            add(stem + "e")
        }

        if let link { add(link) }

        if w.hasSuffix("'s") {
            add(String(w.dropLast(2)))
        } else if w.hasSuffix("ies"), w.count > 4 {
            add(String(w.dropLast(3)) + "y")
        } else if w.hasSuffix("es"), w.count > 3 {
            add(String(w.dropLast(1)))
            add(String(w.dropLast(2)))
        } else if w.hasSuffix("s"), !w.hasSuffix("ss"), w.count > 3 {
            add(String(w.dropLast(1)))
        }

        if w.hasSuffix("ied"), w.count > 4 {
            add(String(w.dropLast(3)) + "y")
        } else if w.hasSuffix("ed"), w.count > 4 {
            let stem = String(w.dropLast(2))
            if hasVowel(stem) { addStem(stem) }
        }

        if w.hasSuffix("ing"), w.count > 5 {
            let stem = String(w.dropLast(3))
            if stem.count >= 3, hasVowel(stem) { addStem(stem) }
        }
        return out
    }

    /// Where a saved word appears in `sentence`, to mark it: its forms ("animals" for
    /// "animal"), read in the sentence ("leave" marks "she left", not "turn left"), or, for a
    /// saved group of words ("did not go"), that group (ignoring case).
    public static func occurrences(of word: String, in sentence: String) -> [WordRange] {
        let key = normalize(word)
        if key.contains(" ") {
            let range = (normalize(sentence) as NSString).range(of: key)
            return range.location == NSNotFound ? [] : [WordRange(range.location, range.location + range.length)]
        }
        let words = Words(sentence as NSString)
        return words.ranges.indices.filter { matchKeys(words, $0).contains(key) }.map { words.ranges[$0] }
    }

    /// The word plus its likely base forms, without its sentence: what to match against saved words.
    public static func matchKeys(_ word: String) -> Set<String> {
        Set([normalize(word)] + baseFormCandidates(word))
    }

    /// The word at `range` of `text` plus its likely base forms, read in its sentence. A form that
    /// is also another word, read as the one with another base, leaves out its own spelling: a saved
    /// "left" (the side) doesn't mark "she left". For every word of a paragraph, use
    /// `matchKeys(in:words:)`: it reads the paragraph once.
    public static func matchKeys(in text: String, at range: WordRange) -> Set<String> {
        guard isInside(text, range) else { return [] }
        let words = Words(text as NSString)
        guard let i = words.index(of: range) else { return matchKeys(substring(text, range)) }
        return matchKeys(words, i)
    }

    /// The match keys of every word of `text` (`words`: its `wordRanges`), in one pass.
    public static func matchKeys(in text: String, words ranges: [WordRange]) -> [Set<String>] {
        let words = Words(text as NSString, ranges: ranges.filter { isInside(text, $0) })
        guard words.ranges.count == ranges.count else { return ranges.map { matchKeys(in: text, at: $0) } }
        return words.ranges.indices.map { matchKeys(words, $0) }
    }

    /// `matchKeys(in:at:)` for word `i` of `words`.
    static func matchKeys(_ words: Words, _ i: Int) -> Set<String> {
        let w = words.token(i)
        let candidates = baseFormCandidates(words, i)
        if IrregularVerbs.shared.homographs[w] != nil, let reading = IrregularVerbs.shared.resolve(words, i),
           reading.kind != .unsure, reading.base != w {
            return Set(candidates)
        }
        return Set([w] + candidates)
    }

    /// `range` is a non-empty stretch of `text`.
    private static func isInside(_ text: String, _ range: WordRange) -> Bool {
        range.start >= 0 && range.start < range.end && range.end <= (text as NSString).length
    }

    private static func hasVowel(_ s: String) -> Bool { s.contains { "aeiouy".contains($0) } }

    /// Runs of vowels ("travel" has 2, "call" 1).
    private static func vowelGroups(_ s: String) -> Int {
        var groups = 0
        var inGroup = false
        for c in s {
            let vowel = "aeiouy".contains(c)
            if vowel, !inGroup { groups += 1 }
            inGroup = vowel
        }
        return groups
    }

    private static func isDoubled(_ stem: String) -> Bool {
        let chars = Array(stem)
        guard chars.count >= 3, let last = chars.last else { return false }
        return last == chars[chars.count - 2] && !"aeiouslz".contains(last)
    }

    /// Irregular nouns and comparatives; irregular verbs come from `IrregularVerbs`.
    /// ("lives", "leaves" are homographs: their sentence decides.)
    private static let nonVerb: [String: String] = [
        "children": "child", "men": "man", "women": "woman", "feet": "foot",
        "teeth": "tooth", "mice": "mouse", "geese": "goose",
        "wives": "wife", "knives": "knife", "wolves": "wolf",
        "better": "good", "best": "good", "worse": "bad", "worst": "bad",
    ]
}

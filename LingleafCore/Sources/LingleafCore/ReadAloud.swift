import Foundation

/// A sentence of a book: its paragraph and where it is in that paragraph.
public struct SentencePosition: Equatable, Sendable {
    public let paragraph: Int
    public let range: WordRange

    public init(_ paragraph: Int, _ range: WordRange) {
        self.paragraph = paragraph
        self.range = range
    }
}

/// Reading aloud sentence by sentence (SPEC S6): where to start and what comes next.
/// Same rules as `ReadAloud` in lingleaf-android.
public enum ReadAloud {
    /// The sentences of `paragraph`, in order and trimmed, as `TextTools.sentenceRangeAt`
    /// finds them; a very long one comes in consecutive pieces of at most
    /// `TextTools.maxSentence` units, cut at spaces, so nothing is read twice or skipped.
    public static func sentences(_ paragraph: String) -> [WordRange] {
        let ns = paragraph as NSString
        var out: [WordRange] = []
        var at = 0
        while true {
            while at < ns.length, TextTools.isSpace(ns.character(at: at)) { at += 1 }
            if at >= ns.length { break }
            let sentence = TextTools.sentenceBounds(paragraph, at)
            // Each sentence ends after the last one; anything else would read a sentence twice.
            if sentence.end <= at { break }
            out += pieces(ns, WordRange(max(at, sentence.start), sentence.end))
            at = sentence.end
        }
        return out
    }

    /// `range` in pieces of at most `TextTools.maxSentence` units, cut before a space when there is one.
    private static func pieces(_ ns: NSString, _ range: WordRange) -> [WordRange] {
        var out: [WordRange] = []
        var start = range.start
        while range.end - start > TextTools.maxSentence {
            var end = start + TextTools.maxSentence
            while end > start, !TextTools.isSpace(ns.character(at: end)) { end -= 1 }
            if end == start { end = start + TextTools.maxSentence }
            out.append(WordRange(start, end))
            start = end
            while start < range.end, TextTools.isSpace(ns.character(at: start)) { start += 1 }
        }
        if start < range.end { out.append(WordRange(start, range.end)) }
        return out
    }

    /// The first sentence to read from `offset` of paragraph `index`: the one there, or the
    /// next one, skipping empty paragraphs; nil after the last sentence.
    public static func start(_ paragraphs: [String], _ index: Int, offset: Int = 0) -> SentencePosition? {
        var paragraph = max(index, 0)
        while paragraph < paragraphs.count {
            let from = paragraph == index ? offset : 0
            if let range = sentences(paragraphs[paragraph]).first(where: { $0.end > from }) {
                return SentencePosition(paragraph, range)
            }
            paragraph += 1
        }
        return nil
    }

    /// The sentence after `current`, or nil when it was the book's last.
    public static func next(_ paragraphs: [String], after current: SentencePosition) -> SentencePosition? {
        start(paragraphs, current.paragraph, offset: current.range.end)
    }
}

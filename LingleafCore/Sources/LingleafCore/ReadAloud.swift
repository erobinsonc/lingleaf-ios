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
        // One pass over the paragraph: a hostile one ("a. a. a. …") stays linear.
        let ns = paragraph as NSString
        return TextTools.sentenceRanges(paragraph).flatMap { pieces(ns, $0) }
    }

    /// `range` in pieces of at most `TextTools.maxSentence` units, cut before a space when there is one.
    private static func pieces(_ ns: NSString, _ range: WordRange) -> [WordRange] {
        var out: [WordRange] = []
        var start = range.start
        while range.end - start > TextTools.maxSentence {
            var end = start + TextTools.maxSentence
            while end > start, !TextTools.isSpace(ns.character(at: end)) { end -= 1 }
            if end == start {
                end = start + TextTools.maxSentence
                // No space to cut at: keep a surrogate pair (an emoji) whole.
                if UTF16.isTrailSurrogate(ns.character(at: end)) { end -= 1 }
            }
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

    /// The sentence before `current`, skipping empty paragraphs, or nil when it was the book's first.
    public static func previous(_ paragraphs: [String], before current: SentencePosition) -> SentencePosition? {
        let own = paragraphs.indices.contains(current.paragraph) ? paragraphs[current.paragraph] : ""
        if let range = sentences(own).last(where: { $0.end <= current.range.start }) {
            return SentencePosition(current.paragraph, range)
        }
        var paragraph = min(current.paragraph, paragraphs.count) - 1
        while paragraph >= 0 {
            if let range = sentences(paragraphs[paragraph]).last { return SentencePosition(paragraph, range) }
            paragraph -= 1
        }
        return nil
    }

    /// How many sentences there are from `first` to `last`, both included (a repeated stretch:
    /// "Repeating 3 sentences"); 0 when `last` comes before `first`.
    public static func count(_ paragraphs: [String], from first: SentencePosition, to last: SentencePosition) -> Int {
        guard first.paragraph >= 0, last.paragraph < paragraphs.count, first.paragraph <= last.paragraph,
              sentences(paragraphs[last.paragraph]).contains(last.range) else { return 0 }
        // One split per paragraph of the stretch, not one per sentence.
        var count = 0
        for paragraph in first.paragraph...last.paragraph {
            count += sentences(paragraphs[paragraph]).filter {
                (paragraph > first.paragraph || $0.start >= first.range.start)
                    && (paragraph < last.paragraph || $0.end <= last.range.end)
            }.count
        }
        return count
    }

    /// The sentence after `current`, or nil when it was the book's last.
    public static func next(_ paragraphs: [String], after current: SentencePosition) -> SentencePosition? {
        start(paragraphs, current.paragraph, offset: current.range.end)
    }
}

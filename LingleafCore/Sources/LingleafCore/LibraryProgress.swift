import Foundation

extension Book {
    /// How much has been read, 0...1: up to the furthest paragraph seen, so a book whose last paragraph has
    /// been on screen is at 100%. A one-paragraph book is 0 until it is opened, then 1 (also one opened by a
    /// version that did not keep the furthest paragraph: `lastOpenedAt` says so).
    public var progress: Double {
        guard paragraphCount > 0 else { return 0 }
        let reached = max(furthestParagraph ?? 0, progressParagraph)
        guard paragraphCount > 1 else { return furthestParagraph == nil && lastOpenedAt == nil ? 0 : 1 }
        return min(1, max(0, Double(reached) / Double(paragraphCount - 1)))
    }
}

/// Reading progress (SPEC S2): where to resume, and how much has been read.
extension Library {
    /// The book at `index` now has `count` paragraphs because its stored text lost invisible
    /// characters. The place in the book moves back by the paragraphs before it that were made only
    /// of them (a place on one of them goes to the next paragraph, one past the end to the last).
    func followStrippedText(_ index: Int, stored: String, count: Int) {
        let all = TextTools.splitParagraphs(stored)
        func moved(_ place: Int) -> Int {
            let removed = all.prefix(max(place, 0)).filter {
                TextTools.stripFormat($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            return min(max(place - removed, 0), max(count - 1, 0))
        }
        state.books[index].paragraphCount = count
        state.books[index].progressParagraph = moved(state.books[index].progressParagraph)
        state.books[index].furthestParagraph = state.books[index].furthestParagraph.map(moved)
    }

    /// Updates progress in memory; call `flush()` to persist (e.g. when leaving the reader).
    public func updateProgress(_ id: String, paragraph: Int) {
        guard let index = state.books.firstIndex(where: { $0.id == id }),
              state.books[index].progressParagraph != paragraph else { return }
        state.books[index].progressParagraph = paragraph
        // What has been on screen includes where the reader is.
        raiseFurthest(index, paragraph)
    }

    /// A paragraph of the book has been on screen (SPEC S2): the furthest seen only grows, and stays inside
    /// the book. In memory; `flush()` persists.
    public func markSeen(_ id: String, paragraph: Int) {
        guard let index = state.books.firstIndex(where: { $0.id == id }) else { return }
        raiseFurthest(index, paragraph)
    }

    private func raiseFurthest(_ index: Int, _ paragraph: Int) {
        let last = max(state.books[index].paragraphCount - 1, 0)
        let seen = min(max(paragraph, 0), last)
        if seen > (state.books[index].furthestParagraph ?? -1) { state.books[index].furthestParagraph = seen }
    }
}

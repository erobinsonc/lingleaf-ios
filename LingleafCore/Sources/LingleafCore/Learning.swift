import Foundation

public struct SrsResult: Equatable, Sendable {
    public let box: Int
    public let nextReview: Date
    public let learned: Bool

    public init(box: Int, nextReview: Date, learned: Bool) {
        self.box = box
        self.nextReview = nextReview
        self.learned = learned
    }
}

/// Minimal Leitner spaced repetition.
public enum Srs {
    /// Days until the next review for each box.
    public static let intervals = [1, 3, 7, 14, 30]

    /// Max words in one review session.
    public static let sessionLimit = 20

    /// Review days start at 04:00 local time, so a word saved late at night still gets a
    /// night's sleep before its first review.
    public static let dayStartHour = 4

    /// "Got it" moves the word to the next box, due at the start of the day `intervals[box]`
    /// days ahead (reviews land after a night's sleep, at any hour of that day); after the
    /// last box it is learned. "Again" sends it back to the first box, due now (repeated in the session).
    public static func review(box: Int, correct: Bool, now: Date, calendar: Calendar = .current) -> SrsResult {
        guard correct else { return SrsResult(box: 0, nextReview: now, learned: false) }
        guard box < intervals.count else { return SrsResult(box: box, nextReview: now, learned: true) }
        return SrsResult(box: box + 1, nextReview: startOfDay(intervals[box], after: now, calendar: calendar), learned: false)
    }

    /// The start (04:00) of the review day `days` after `date`'s review day; a review day
    /// runs from 04:00 to 04:00, so 01:00 still belongs to the day before.
    public static func startOfDay(_ days: Int, after date: Date, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -dayStartHour, to: date) ?? date
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: shifted)) ?? shifted
        return calendar.date(byAdding: .hour, value: dayStartHour, to: day) ?? day
    }

    /// Up to `limit` words, interleaved by source (book) so one book doesn't fill the
    /// session; within a book, the longest-due first.
    public static func session(_ due: [VocabWord], limit: Int = sessionLimit) -> [VocabWord] {
        var bySource: [(String, [VocabWord])] = []
        for word in due.sorted(by: { $0.nextReview < $1.nextReview }) {
            if let index = bySource.firstIndex(where: { $0.0 == word.source }) {
                bySource[index].1.append(word)
            } else {
                bySource.append((word.source, [word]))
            }
        }
        var out: [VocabWord] = []
        var round = 0
        while out.count < limit, bySource.contains(where: { $0.1.count > round }) {
            for (_, words) in bySource where round < words.count && out.count < limit {
                out.append(words[round])
            }
            round += 1
        }
        return out
    }
}

/// "yyyy-MM-dd" in the given calendar's time zone.
public func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// Consecutive days meeting the goal. Today only counts once it's met, so an
/// unfinished today doesn't break yesterday's streak.
public func readingStreak(_ secondsByDay: [String: Int], goalSeconds: Int, today: Date, calendar: Calendar = .current) -> Int {
    func met(_ day: Date) -> Bool { (secondsByDay[dayKey(day, calendar: calendar)] ?? 0) >= goalSeconds }
    func previous(_ day: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: day) ?? day }
    var day = met(today) ? today : previous(today)
    var count = 0
    while met(day) {
        count += 1
        day = previous(day)
    }
    return count
}

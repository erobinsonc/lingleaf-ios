import Foundation

/// The Grammar day (SPEC.md, Grammar rules data, "Day"): a day starts at 04:00 in the device's local time zone.
/// The day number of an instant is the number of whole days between 2001-01-01 and the local calendar date of
/// (the instant - 4 hours). The shared reference vectors are in the tests.
public enum GrammarDay {
    public static func number(of date: Date, in zone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-4 * 3600))
        return daysSinceCivilEpoch(parts.year ?? 2001, parts.month ?? 1, parts.day ?? 1) - daysSinceCivilEpoch(2001, 1, 1)
    }

    /// Days of the proleptic Gregorian calendar from 0000-03-01 (integer arithmetic, no time zone involved).
    private static func daysSinceCivilEpoch(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        return era * 146_097 + yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    }
}

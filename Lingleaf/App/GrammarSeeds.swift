#if DEBUG
import Foundation
import LingleafCore

/// UI tests and the screen tour only (debug builds, launch arguments): Grammar progress for the screens that need
/// some (SPEC S20-S22). Every seed writes through the model, so it is saved like the learner's own progress.
extension GrammarModel {
    func seedForUITests(_ arguments: [String]) {
        let rules = grammar
        func rule(_ id: String) -> GrammarRule? { rules.rule(id: id) }
        if arguments.contains("-ui-testing-grammar-recent") {
            // Three rules opened: "Recent" shows, newest first.
            update { progress, _ in
                for (index, id) in ["his-her-its", "irregular-past", "do-does-did"].enumerated() {
                    progress.opened(id, at: Date().addingTimeInterval(Double(index - 10)))
                }
            }
        }
        if arguments.contains("-ui-testing-grammar-states") {
            // irregular-past is Practiced (2 right answers on 2 days to 2 items); present-s is In Review.
            update { progress, today in
                if let practiced = rule("irregular-past") {
                    progress.answered(practiced, item: practiced.practice[1].id, right: true, day: today - 2, in: .tryIt)
                    progress.answered(practiced, item: practiced.practice[2].id, right: true, day: today - 1, in: .tryIt)
                }
                if let inReview = rule("present-s") { progress.addToReview(inReview, today: today) }
            }
        }
        if arguments.contains("-ui-testing-grammar-seen") {
            // An item after the first has been shown: the button says "Practice" (S22).
            update { progress, _ in
                if let seen = rule("his-her-its") { progress.shown(seen, item: seen.practice[1].id) }
            }
        }
        let answered = arguments.contains("-ui-testing-grammar-limit") ? 6 : arguments.contains("-ui-testing-grammar-answered-4") ? 4 : 0
        if answered > 0, let limited = rule("time-prepositions") {
            // `answered` practice items today on time-prepositions: 6 is the daily limit, 4 leaves a round of 2.
            update { progress, today in
                for index in 0..<answered {
                    let item = limited.practice[1 + index % (limited.practice.count - 1)]
                    progress.shown(limited, item: item.id)
                    progress.answered(limited, item: item.id, right: true, day: today, in: .tryIt)
                }
            }
        }
    }
}
#endif

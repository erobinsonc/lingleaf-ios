import Foundation
import Observation
import LingleafCore

/// The Grammar tab's state: the bundled rules and the learner's progress (SPEC.md S20-S22). Views read `progress`
/// and change it only through the methods here, which go through `store`: it saves at once (at show, at answer),
/// and `flush()` saves what a failed save left behind when the app leaves the foreground.
@Observable
@MainActor
final class GrammarModel {
    private let store: GrammarStore
    /// What the views read. The store's progress, copied after each change so SwiftUI sees it.
    private(set) var progress: GrammarProgress

    var grammar: GrammarRules { store.grammar }
    /// The Grammar day number now (a day starts at 04:00).
    var today: Int { store.today }

    init(store: GrammarStore) {
        self.store = store
        progress = store.progress
    }

    // MARK: Changes

    /// The rule page appeared after it was pushed (an opening, S20).
    func opened(_ rule: GrammarRule) {
        store.opened(rule)
        progress = store.progress
    }

    /// An item is shown, before any answer.
    func shown(_ rule: GrammarRule, item: PracticeItem) {
        store.shown(rule, item: item)
        progress = store.progress
    }

    @discardableResult
    func answeredPretest(_ rule: GrammarRule, right: Bool) -> Bool {
        let recorded = store.answeredPretest(rule, right: right)
        progress = store.progress
        return recorded
    }

    func skippedPretest(_ rule: GrammarRule) {
        store.skippedPretest(rule)
        progress = store.progress
    }

    /// An answer in Try it or Practice ("Not sure" is `right: false`).
    func answeredPractice(_ rule: GrammarRule, item: PracticeItem, right: Bool) {
        store.answeredPractice(rule, item: item, right: right)
        progress = store.progress
    }

    /// Any other change (seeds for UI tests, Add to Review in a later slice), saved the same way; it gets today's day number.
    func update(_ change: (inout GrammarProgress, Int) -> Void) {
        store.update(change)
        progress = store.progress
    }

    /// The app is leaving the foreground: save what has not been saved.
    func flush() {
        store.flush()
    }

    // MARK: Making it

    static func make() -> GrammarModel {
        #if DEBUG
        // UI tests only: a fresh folder per launch, so progress never leaks between tests or into a real install.
        if UITestMode.isOn {
            let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let model = GrammarModel(store: GrammarStore(directory: temporary))
            model.seedForUITests(UITestMode.arguments)
            return model
        }
        #endif
        let support = URL.applicationSupportDirectory.appending(path: "Lingleaf", directoryHint: .isDirectory)
        return GrammarModel(store: GrammarStore(directory: support))
    }
}

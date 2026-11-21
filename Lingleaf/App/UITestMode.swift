#if DEBUG
import Foundation

/// UI tests only (debug builds, launch arguments): the one place that decides whether the app runs in test mode, so
/// the models that make themselves from it (`AppModel`, `GrammarModel`) can never disagree. Release builds take no
/// launch arguments at all.
enum UITestMode {
    static let arguments = ProcessInfo.processInfo.arguments

    /// `-ui-testing-offline`: test mode with every request failing.
    static var isOffline: Bool { arguments.contains("-ui-testing-offline") }

    /// `-ui-testing` or `-ui-testing-offline`: fresh storage, canned answers.
    static var isOn: Bool { isOffline || arguments.contains("-ui-testing") }
}
#endif

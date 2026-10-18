import SwiftUI
import Translation
import LingleafCore

@main
struct LingleafApp: App {
    @State private var model = AppModel.make()

    init() {
        // Unselected tabs use the system grey, measured at 2.77:1 on the light tab bar;
        // the brand secondary text colour passes WCAG AA (6:1 light, 9:1 dark).
        UITabBar.appearance().unselectedItemTintColor = Brand.secondaryUIColor
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .overlay(alignment: .topLeading) { LastSpokenProbe() }
                #endif
                // After the overlay, so the probe reads the model from the environment too.
                .environment(model)
                .noVoiceAlert(model.speaker)
                .tint(Brand.ink)
                .preferredColorScheme(Self.forcedColorScheme)
        }
    }

    /// Lets UI tests and the screenshot tour render dark mode on any simulator. Release
    /// builds take no launch arguments: they follow the system setting.
    private static var forcedColorScheme: ColorScheme? {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-dark-mode") ? .dark : nil
        #else
        nil
        #endif
    }
}

/// App-wide state and services. Views read `state`; mutations go through `library`.
@Observable
@MainActor
final class AppModel {
    private(set) var state: LibraryState
    let library: Library
    let dictionary: DictionaryClient
    let gutenberg: GutenbergClient
    let speaker: Speaker
    /// UI tests replace on-device translation with this function; it throws to simulate being offline.
    let fakeTranslator: (@Sendable (String) throws -> String)?
    /// The language picked from the device's preferred languages; nil when none is supported (then the app asks).
    let autoLanguage: String?
    /// Book covers from Project Gutenberg; nil in UI tests, so they never depend on the network.
    let covers: CoverLoader?
    /// Drives `TranslationWorker`: each new or invalidated value translates the saved words that need it.
    private(set) var workerConfiguration: TranslationSession.Configuration?
    /// UI tests only: the last text handed to the fake speaker, shown by `LastSpokenProbe`.
    /// Always nil in live mode. (Not inside `#if`: `@Observable` must see it to track it.)
    private(set) var lastSpoken: String?
    /// UI tests only: every text handed to the fake speaker, in order, so a test can check a
    /// sequence (reading aloud moves on every 1.5 s, faster than a test can look at each one).
    private(set) var spokenLog: [String] = []

    /// UI tests only: what the fake speaker was handed.
    func recordSpoken(_ text: String) {
        lastSpoken = text
        spokenLog.append(text)
    }

    init(
        library: Library, http: HttpFetcher, speaker: Speaker, autoLanguage: String?,
        fakeTranslator: (@Sendable (String) throws -> String)? = nil, covers: CoverLoader? = CoverLoader()
    ) {
        self.covers = covers
        self.library = library
        self.dictionary = DictionaryClient(http: http)
        self.gutenberg = GutenbergClient(http: http)
        self.speaker = speaker
        self.fakeTranslator = fakeTranslator
        self.autoLanguage = autoLanguage
        library.load()
        library.seedIfNeeded(Self.bundledStories)
        self.state = library.state
        library.onChange = { [weak self] newState in
            MainActor.assumeIsolated { self?.state = newState }
        }
        // Read the irregular-verb table now, off the main thread, not on the first word shown.
        Task.detached(priority: .utility) { _ = IrregularVerbs.shared }
    }

    static func make() -> AppModel {
        #if DEBUG
        // UI tests only: release builds never take the offline, fake-data path.
        let arguments = ProcessInfo.processInfo.arguments
        // With -ui-testing-no-language no translation language is saved, so the word card asks.
        let language = arguments.contains("-ui-testing-no-language") ? nil : "es"
        // With -ui-testing-due a word is waiting for review (new words are first due tomorrow).
        let due = arguments.contains("-ui-testing-due")
        if arguments.contains("-ui-testing-offline") { return uiTesting(offline: true, language: language, due: due) }
        if arguments.contains("-ui-testing") { return uiTesting(offline: false, language: language, due: due) }
        #endif
        return live()
    }

    private static func live() -> AppModel {
        let support = URL.applicationSupportDirectory.appending(path: "Lingleaf", directoryHint: .isDirectory)
        // The preferred-language list, not `Locale.current`: that is the app's own UI
        // language, English for a Brazilian since the app only speaks English and Spanish.
        let language = TranslationLanguages.pick(preferred: Locale.preferredLanguages, supported: TranslationLanguages.supported)
        return AppModel(
            library: Library(storage: FileStorage(directory: support)), http: URLSessionFetcher(), speaker: Speaker(),
            autoLanguage: language
        )
    }

    #if DEBUG
    /// Fresh, offline and deterministic: canned dictionary answers, catalog, book text
    /// and translations. With `offline`, every request fails and translation throws,
    /// as on a device without internet. The speaker records instead of speaking.
    /// `language` is saved as the translation language; nothing is picked from the device.
    private static func uiTesting(offline: Bool, language: String?, due: Bool) -> AppModel {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let http = ClosureFetcher { url in
            if offline { throw NetworkError("The Internet connection appears to be offline.") }
            if url.contains("gutendex") { return HttpResponse(status: 200, text: fakeCatalog) }
            // Peter Pan is "not available right now", to show that message.
            if url.contains("gutenberg.org/cache/epub/16/") { return HttpResponse(status: 404, text: "") }
            if url.contains("gutenberg.org/cache/epub/") { return HttpResponse(status: 200, text: fakeBookText) }
            guard url.contains("dictionaryapi.dev") else { return HttpResponse(status: 404, text: "") }
            let word = url.split(separator: "/").last.map(String.init) ?? ""
            let json = #"[{"word": "\#(word)", "phonetic": "/test/", "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "Definition of \#(word)."}]}]}]"#
            return HttpResponse(status: 200, text: json)
        }
        let translator: @Sendable (String) throws -> String
        if offline {
            translator = { _ in throw NetworkError("Translation unavailable offline") }
        } else {
            translator = { text in "ES: \(text)" }
        }
        let speaker = Speaker()
        let library = Library(storage: FileStorage(directory: dir))
        let model = AppModel(library: library, http: http, speaker: speaker, autoLanguage: nil, fakeTranslator: translator, covers: nil)
        speaker.record = { [weak model] text in model?.recordSpoken(text) }
        if let language { library.updateSettings { $0.targetLanguage = language } }
        if due {
            let sentence = "Tom lives in a small house by the sea."
            library.saveWord(
                "sea", learned: false, translation: offline ? nil : "ES: sea", translationLanguage: "es",
                context: sentence, contextTranslation: offline ? nil : "ES: \(sentence)", source: "The Red Boat"
            )
            // "Again" makes it due now.
            library.answerReview("sea", correct: false)
        }
        return model
    }

    /// A small Gutendex answer so Discover has books to show in UI tests.
    nonisolated private static let fakeCatalog = #"""
    {"results": [
      {"id": 21, "title": "Aesop's Fables", "authors": [{"name": "Aesop"}],
       "formats": {"text/plain; charset=us-ascii": "https://www.gutenberg.org/ebooks/21.txt.utf-8"}},
      {"id": 55, "title": "The Wonderful Wizard of Oz", "authors": [{"name": "Baum, L. Frank"}],
       "formats": {"text/plain; charset=us-ascii": "https://www.gutenberg.org/ebooks/55.txt.utf-8"}},
      {"id": 16, "title": "Peter Pan", "authors": [{"name": "Barrie, J. M."}],
       "formats": {"text/plain; charset=us-ascii": "https://www.gutenberg.org/ebooks/16.txt.utf-8"}},
      {"id": 2701, "title": "Moby-Dick; Or, The Whale", "authors": [{"name": "Melville, Herman"}],
       "formats": {"text/plain; charset=us-ascii": "https://www.gutenberg.org/ebooks/2701.txt.utf-8"}}
    ]}
    """#

    /// What the fake http answers for any book's text: a short Gutenberg-style file.
    nonisolated private static let fakeBookText = """
    The Project Gutenberg eBook
    License header.
    *** START OF THE PROJECT GUTENBERG EBOOK TEST ***

    The Fox and the Grapes

    A fox saw some grapes hanging high on a vine. He jumped, but he could not reach them.

    *** END OF THE PROJECT GUTENBERG EBOOK TEST ***
    License footer.
    """
    #endif

    private static func bundledStories() -> [BundledStory] {
        [
            ("the-red-boat", "The Red Boat", "A1"),
            ("a-day-at-the-market", "A Day at the Market", "A2"),
            ("the-lighthouse-keeper", "The Lighthouse Keeper", "B1"),
        ].compactMap { resource, title, level in
            guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return BundledStory(title: title, level: level, text: text)
        }
    }

    /// The words of `text` (`words`: its `wordRanges`) that are forms of words being learned,
    /// read in their sentences, in one pass over the paragraph.
    func learningRanges(_ text: String, _ words: [WordRange]) -> Set<WordRange> {
        library.learningRanges(text, words)
    }

    /// The saved choice, else the one picked from the device; nil means ask on the word card.
    var targetLanguage: String? { state.settings.targetLanguage ?? autoLanguage }

    /// Saves the translation language and translates the saved words into it.
    func setTargetLanguage(_ code: String) {
        library.updateSettings { $0.targetLanguage = code }
        translateMissing()
    }

    /// Languages Apple Translation can translate English into.
    static let translationLanguages = TranslationLanguages.supported

    /// The language's name in that language: "Español", "Português", "中文".
    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        let language = locale.language.languageCode?.identifier ?? code
        return locale.localizedString(forLanguageCode: language)?.capitalized(with: locale) ?? code
    }

    /// `languageName`, marked as being in that language so VoiceOver reads it with the right voice.
    static func languageLabel(_ code: String) -> AttributedString {
        var label = AttributedString(languageName(code))
        label.languageIdentifier = code
        return label
    }

    // MARK: Translations that arrive after saving

    /// Translates, on the device, saved words with no translation or one in another
    /// language (just saved, saved offline, or the language changed). UI tests use
    /// the fake translator; otherwise `TranslationWorker` runs `translatePending`.
    func translateMissing() {
        guard let target = targetLanguage,
              !library.wordsNeedingTranslation(target).isEmpty || !library.contextsNeedingTranslation(target).isEmpty else { return }
        if let fakeTranslator {
            for word in library.wordsNeedingTranslation(target) {
                guard let text = try? fakeTranslator(word.word) else { return }
                library.setTranslation(word.word, text, language: target)
            }
            for word in library.contextsNeedingTranslation(target) {
                guard let text = try? fakeTranslator(word.context) else { return }
                library.setContextTranslation(word.word, text, language: target)
            }
            return
        }
        let language = Locale.Language(identifier: target)
        if workerConfiguration?.target == language {
            workerConfiguration?.invalidate()
        } else {
            workerConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: "en"), target: language)
        }
    }

    /// Called by `TranslationWorker` with a session for `workerConfiguration`.
    /// Failures leave the words as they are; they are tried again the next time.
    func translatePending(using session: TranslationSession) async {
        guard let target = targetLanguage else { return }
        let language = Locale.Language(identifier: target)
        let words = library.wordsNeedingTranslation(target)
        let contexts = library.contextsNeedingTranslation(target)
        guard workerConfiguration?.target == language, !words.isEmpty || !contexts.isEmpty else { return }
        // Only with the language already on the device: in the background the app
        // doesn't ask to download it (the word card does).
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: language)
        guard status == .installed else { return }
        // A saved sentence is told apart from its word by a prefix on the identifier.
        let requests = words.map { TranslationSession.Request(sourceText: $0.word, clientIdentifier: $0.word) }
            + contexts.map { TranslationSession.Request(sourceText: $0.context, clientIdentifier: "context:\($0.word)") }
        guard let responses = try? await session.translations(from: requests) else { return }
        for response in responses {
            guard let id = response.clientIdentifier else { continue }
            if id.hasPrefix("context:") {
                library.setContextTranslation(String(id.dropFirst("context:".count)), response.targetText, language: target)
            } else {
                library.setTranslation(id, response.targetText, language: target)
            }
        }
    }
}

/// Gives `AppModel` a translation session whenever `workerConfiguration` changes, so saved
/// words get their missing translations on the device: iOS 18 only hands out a
/// `TranslationSession` to a view's `.translationTask`. Applied once, at the root.
struct TranslationWorker: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.translationTask(model.workerConfiguration) { session in
            await model.translatePending(using: session)
        }
    }
}

#if DEBUG
/// UI tests only: XCUITest can't hear the speaker, so the last spoken text is
/// rendered here, practically invisible, for tests to read by identifier.
/// Not hidden from accessibility, or XCUITest couldn't read it either.
private struct LastSpokenProbe: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let spoken = model.lastSpoken {
            Text(spoken)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("ui-test-last-spoken")
            // Everything spoken so far, one text per line.
            Text(model.spokenLog.joined(separator: "\n"))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("ui-test-spoken-log")
        }
    }
}
#endif

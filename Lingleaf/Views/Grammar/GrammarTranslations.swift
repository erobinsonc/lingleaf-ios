import SwiftUI
import Translation
import LingleafCore

/// On-device translations of Grammar texts (the examples of a rule, the meanings in the verb list) for a translation
/// language other than Spanish (SPEC S21, S24; Spanish has its bundled lines). Only with the language installed on the
/// device; if it is only supported, a line offers to download it and only that tap starts the download. Offline or failed:
/// nothing is shown and no error (the screens work without it). UI tests use the fake translator.
@Observable
@MainActor
final class GrammarTranslations {
    /// The translation of each source text asked for.
    private(set) var translations: [String: String] = [:]
    /// The language can be downloaded but is not on the device: show the Download line.
    private(set) var needsDownload = false
    private(set) var downloadFailed = false
    /// Set when a download the learner asked for finished.
    private(set) var justFinished = false
    var configuration: TranslationSession.Configuration?

    private var texts: [String] = []
    private var target: String?
    private var wantsDownload = false

    func prepare(texts: [String], model: AppModel) async {
        self.texts = texts
        translations = [:]
        needsDownload = false
        downloadFailed = false
        justFinished = false
        configuration = nil
        guard let target = model.targetLanguage, target != "es", target != "en" else { return }
        self.target = target
        if let fake = model.fakeTranslator {
            for text in texts {
                if let translated = try? fake(text) { translations[text] = translated }
            }
            return
        }
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: target))
        switch status {
        case .installed: start()
        case .supported: needsDownload = true
        default: break
        }
    }

    /// The Download button: the system asks, then the texts are translated.
    func download() {
        wantsDownload = true
        downloadFailed = false
        if configuration != nil { configuration?.invalidate() } else { start() }
    }

    private func start() {
        guard let target else { return }
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: target)
        )
    }

    /// Runs in `.translationTask`.
    func run(_ session: TranslationSession) async {
        do {
            if wantsDownload { try await session.prepareTranslation() }
            let requests = texts.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
            for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier { translations[id] = response.targetText }
            }
            if wantsDownload {
                needsDownload = false
                justFinished = true
            }
        } catch {
            if wantsDownload { downloadFailed = true }
        }
        wantsDownload = false
    }
}

/// "To see translations, download your language once." with its Download button, or the line saying it did not work.
struct GrammarDownloadLine: View {
    let translator: GrammarTranslations

    var body: some View {
        if translator.needsDownload {
            VStack(alignment: .leading, spacing: 4) {
                Text("To see translations, download your language once.").font(.footnote).foregroundStyle(Brand.secondaryText)
                if translator.downloadFailed {
                    Text("The language wasn't downloaded. Try again later.").font(.footnote).foregroundStyle(Brand.secondaryText)
                }
                Button("Download") { translator.download() }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Text("Download language"))
            }
        }
    }
}

extension View {
    /// Translates `texts` on the device for the learner's translation language (see `GrammarTranslations`).
    func grammarTranslations(_ translator: GrammarTranslations, texts: [String], model: AppModel) -> some View {
        self
            .task(id: model.targetLanguage) { await translator.prepare(texts: texts, model: model) }
            .translationTask(translator.configuration) { session in await translator.run(session) }
            .onChange(of: translator.justFinished) { _, finished in
                if finished { AccessibilityNotification.Announcement(String(localized: "Translations ready")).post() }
            }
    }
}

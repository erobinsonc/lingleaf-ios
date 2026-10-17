import AVFoundation
import LingleafCore

/// English text-to-speech with the system voice. Plays even with the ringer muted.
@Observable
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// UI tests only (honoured in DEBUG builds): when set, text is handed to this
    /// instead of being spoken, because XCUITest can't hear the speaker.
    @ObservationIgnored var record: ((String) -> Void)?
    /// Runs when the utterance being spoken ends by itself (not when stopped): reading aloud
    /// goes on with the next sentence.
    @ObservationIgnored private var onFinish: (() -> Void)?
    @ObservationIgnored private var spoken: AVSpeechUtterance?
    /// UI tests: counts recorded texts, so only the latest one "ends".
    @ObservationIgnored private var recorded = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, stopping anything being said. `onFinish` runs when it ends by itself.
    func speak(_ text: String, rate: Double, onFinish: (() -> Void)? = nil) {
        self.onFinish = nil
        #if DEBUG
        if let record {
            record(text)
            // UI tests: a recorded sentence "ends" after a moment, so reading aloud moves on.
            if let onFinish {
                self.onFinish = onFinish
                recorded += 1
                let current = recorded
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    if self.recorded == current { self.finish(nil) }
                }
            }
            return
        }
        #endif
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Float(rate)
        spoken = utterance
        self.onFinish = onFinish
        synthesizer.speak(utterance)
    }

    func stop() {
        onFinish = nil
        recorded += 1
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// The utterance ended by itself: run its `onFinish` (only for the one still current).
    private func finish(_ utterance: AVSpeechUtterance?) {
        refresh()
        guard utterance == nil || utterance === spoken, let onFinish else { return }
        self.onFinish = nil
        onFinish()
    }

    private func refresh() { isSpeaking = synthesizer.isSpeaking }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.refresh() }
    }
}

/// Reads a book aloud sentence by sentence (SPEC S6), with the sentence being read for the reader
/// to highlight. Pausing keeps the sentence, so reading goes on from it.
@Observable
@MainActor
final class ReadAloudController {
    private(set) var current: SentencePosition?
    private(set) var isReading = false
    @ObservationIgnored private var paragraphs: [String] = []
    @ObservationIgnored private let speaker: Speaker
    @ObservationIgnored private let rate: () -> Double
    /// Called with each sentence as it starts, to save the reading position.
    @ObservationIgnored var onSentence: (SentencePosition) -> Void = { _ in }

    init(speaker: Speaker, rate: @escaping () -> Double) {
        self.speaker = speaker
        self.rate = rate
    }

    func read(_ paragraphs: [String], from position: SentencePosition) {
        self.paragraphs = paragraphs
        isReading = true
        speak(position)
    }

    func pause() {
        guard isReading else { return }
        isReading = false
        speaker.stop()
    }

    private func speak(_ position: SentencePosition) {
        current = position
        onSentence(position)
        let text = TextTools.substring(paragraphs[position.paragraph], position.range)
        // The speed setting applies from the next sentence on.
        speaker.speak(text, rate: rate()) { [weak self] in
            guard let self, self.isReading else { return }
            if let next = ReadAloud.next(self.paragraphs, after: position) {
                self.speak(next)
            } else {
                // The end of the book.
                self.isReading = false
                self.current = nil
            }
        }
    }
}

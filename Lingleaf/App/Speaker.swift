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
    /// Runs when the system cuts the speech off (a call, an alarm, Siri): reading aloud pauses,
    /// so the bar doesn't show Pause while nothing is heard.
    @ObservationIgnored var onInterruption: (() -> Void)?
    /// Set when something was to be said but the device has no English voice: an alert says so.
    var missedVoice = false

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(interrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
    }

    @objc nonisolated private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor in
            self.stop()
            self.onInterruption?()
        }
    }

    /// Speaks `text`, stopping anything being said. `onFinish` runs when it ends by itself.
    func speak(_ text: String, rate: Double, onFinish: (() -> Void)? = nil) {
        self.onFinish = nil
        #if DEBUG
        if let record {
            record(text)
            // UI tests: a recorded text "ends" after 2 s, as a short sentence would, so
            // reading aloud moves on; tests check the spoken log, not the moment.
            self.onFinish = onFinish
            if onFinish != nil {
                recorded += 1
                let current = recorded
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if self.recorded == current { self.finish(nil) }
                }
            }
            return
        }
        #endif
        guard !noVoice else {
            stop()
            missedVoice = true
            return
        }
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
        release()
    }

    /// The utterance ended by itself: run its `onFinish` (only for the one still current).
    private func finish(_ utterance: AVSpeechUtterance?) {
        refresh()
        guard utterance == nil || utterance === spoken else { return }
        let onFinish = self.onFinish
        self.onFinish = nil
        onFinish?()
        // Nothing more to say (no next sentence was started): give the audio back.
        if utterance != nil, spoken === utterance { release() }
    }

    /// Ends our audio session, so the music of other apps comes back to its full volume.
    private func release() {
        spoken = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func refresh() { isSpeaking = synthesizer.isSpeaking }

    /// No English voice on this device: reading aloud and Listen say so instead of staying silent.
    var noVoice: Bool {
        #if DEBUG
        if record != nil { return false }
        #endif
        return AVSpeechSynthesisVoice(language: "en-US") == nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.refresh()
            // Our own stops forget the utterance first: a cancel of the current one came from the system.
            if utterance === self.spoken {
                self.stop()
                self.onInterruption?()
            }
        }
    }
}

/// A repeated stretch of sentences, from `first` to `last`.
struct RepeatedStretch: Equatable {
    var first: SentencePosition
    var last: SentencePosition
}

/// Reads a book aloud sentence by sentence (SPEC S6), with the sentence being read for the reader
/// to highlight. Pausing keeps the sentence, so reading goes on from it. Repeat loops the sentence
/// being read; Previous sentence then adds one more before it to the stretch.
@Observable
@MainActor
final class ReadAloudController {
    private(set) var current: SentencePosition?
    private(set) var isReading = false
    /// The repeated stretch; nil when not repeating. Its sentences are counted when it changes.
    private(set) var loop: RepeatedStretch? {
        didSet { loopCount = loop.map { ReadAloud.count(paragraphs, from: $0.first, to: $0.last) } ?? 0 }
    }
    /// How many sentences are repeated: "Repeating 3 sentences".
    private(set) var loopCount = 0
    @ObservationIgnored private var paragraphs: [String] = []
    @ObservationIgnored private let speaker: Speaker
    @ObservationIgnored private let rate: () -> Double
    /// Called with each sentence as it starts, to save the reading position.
    @ObservationIgnored var onSentence: (SentencePosition) -> Void = { _ in }

    init(speaker: Speaker, rate: @escaping () -> Double) {
        self.speaker = speaker
        self.rate = rate
        speaker.onInterruption = { [weak self] in self?.interrupted() }
    }

    /// The system cut the speech off: show it paused, on the same sentence.
    private func interrupted() { isReading = false }

    func read(_ paragraphs: [String], from position: SentencePosition) {
        self.paragraphs = paragraphs
        loop = nil
        isReading = true
        speak(position)
    }

    /// Goes on from the start of the paused sentence.
    func play() {
        guard let current else { return }
        isReading = true
        speak(current)
    }

    /// Back to the start of the previous sentence and reads on. While repeating, it adds that
    /// sentence to the repeated stretch instead and reads the stretch from its new start.
    func previous() {
        guard let current else { return }
        let back = ReadAloud.previous(paragraphs, before: loop?.first ?? current)
        if loop != nil {
            guard let back else { return }
            loop?.first = back
        }
        isReading = true
        speak(back ?? current)
    }

    /// Repeats the sentence being read until turned off; then reading goes on forward.
    func toggleRepeat() {
        guard let current else { return }
        loop = loop == nil ? RepeatedStretch(first: current, last: current) : nil
    }

    func pause() {
        guard isReading else { return }
        isReading = false
        speaker.stop()
    }

    private func speak(_ position: SentencePosition) {
        // No English voice: stop, and the speaker's alert says why (SPEC S6).
        guard !speaker.noVoice else {
            isReading = false
            current = nil
            loop = nil
            speaker.missedVoice = true
            return
        }
        current = position
        onSentence(position)
        let text = TextTools.substring(paragraphs[position.paragraph], position.range)
        // The speed setting applies from the next sentence on.
        speaker.speak(text, rate: rate()) { [weak self] in
            guard let self, self.isReading else { return }
            if let loop = self.loop, position == loop.last {
                self.speak(loop.first)
            } else if let next = ReadAloud.next(self.paragraphs, after: position) {
                self.speak(next)
            } else {
                // The end of the book.
                self.isReading = false
                self.current = nil
            }
        }
    }
}

import Accessibility
import SwiftUI

/// A short message at the bottom of the screen with an Undo button, e.g.
/// "“beach” saved to Words". It is announced to VoiceOver and disappears after
/// `seconds`; with VoiceOver or Switch Control on it stays until Undo or Close is
/// tapped or a newer message replaces it.
struct UndoMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let seconds: Double
    let undo: () -> Void

    static func == (lhs: UndoMessage, rhs: UndoMessage) -> Bool { lhs.id == rhs.id }
}

extension View {
    /// Shows `message` at the bottom of this view until it times out or Undo is tapped.
    func undoMessage(_ message: Binding<UndoMessage?>) -> some View {
        modifier(UndoMessageModifier(message: message))
    }
}

private struct UndoMessageModifier: ViewModifier {
    @Binding var message: UndoMessage?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    /// Assistive tech that may need more time to reach Undo: the message doesn't time out.
    private var staysOpen: Bool {
        voiceOver || switchControl || UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    #if DEBUG
    /// UI tests only: the message doesn't time out, so a slow simulator can't miss it.
    /// No Close button is shown, so screenshots match what learners see.
    private static let keepForUITests = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-ui-testing") }
    #else
    private static let keepForUITests = false
    #endif

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let current = message {
                    UndoBanner(message: current, showsClose: staysOpen) {
                        current.undo()
                        message = nil
                    } onClose: {
                        message = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: message?.id)
            .task(id: message?.id) {
                guard let current = message else { return }
                var announcement = AttributedString(current.text)
                // High priority: not cut off by VoiceOver moving focus as a sheet closes.
                announcement.accessibilitySpeechAnnouncementPriority = .high
                AccessibilityNotification.Announcement(announcement).post()
            }
            // Restarts when assistive tech is turned on or off while the message shows.
            .task(id: Timeout(id: message?.id, staysOpen: staysOpen)) {
                guard let current = message, !staysOpen, !Self.keepForUITests else { return }
                try? await Task.sleep(for: .seconds(current.seconds))
                // A newer message (or Undo) cancels this task; only time out this one.
                if !Task.isCancelled, message?.id == current.id { message = nil }
            }
    }
}

private struct Timeout: Equatable {
    let id: UUID?
    let staysOpen: Bool
}

/// Inverted colours (label on background), so text and button keep the system's
/// highest contrast in light and dark mode.
private struct UndoBanner: View {
    let message: UndoMessage
    /// When the message doesn't time out, a close button lets the learner dismiss it.
    let showsClose: Bool
    let onUndo: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.headline)
                    .underline()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .foregroundStyle(Color(uiColor: .systemBackground))
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .label), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

extension View {
    /// Says the device has no English voice when something couldn't be read aloud (SPEC S6).
    func noVoiceAlert(_ speaker: Speaker) -> some View {
        modifier(NoVoiceAlert(speaker: speaker))
    }
}

private struct NoVoiceAlert: ViewModifier {
    @Bindable var speaker: Speaker

    func body(content: Content) -> some View {
        content.alert(String(localized: "Can't read aloud: this device has no English voice."), isPresented: $speaker.missedVoice) {
            Button(String(localized: "OK"), role: .cancel) {}
        }
    }
}

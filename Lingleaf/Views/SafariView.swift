import SafariServices
import SwiftUI

/// A page of the app's own fixed links in the system's in-app browser (Safari View Controller), so the
/// learner reads it without leaving the app. It runs in Safari's process: the app cannot see what is
/// browsed, and cookies and history are Safari's own.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        // SFSafariViewController refuses anything but http(s); the links are constants over https.
        let safe = url.scheme == "https" ? url : Credits.privacyPolicyURL
        return SFSafariViewController(url: safe, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

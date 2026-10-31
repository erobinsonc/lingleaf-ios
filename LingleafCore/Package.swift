// swift-tools-version:6.0
import PackageDescription

// Pure-Foundation logic shared by the app: text tools, base forms, spaced
// repetition, streak, Gutenberg catalog, dictionary client and the library.
// Mirrors `core/` in lingleaf-android, with the same tests.
let package = Package(
    name: "LingleafCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "LingleafCore", targets: ["LingleafCore"])],
    targets: [
        // The irregular-verb table, shared with lingleaf-android (core/src/main/resources): identical file.
        .target(name: "LingleafCore", resources: [.copy("Resources/irregular-verbs.json")]),
        .testTarget(
            name: "LingleafCoreTests",
            dependencies: ["LingleafCore"],
            // Shared with lingleaf-android (core/src/test/resources): identical files.
            resources: [
                .copy("Resources/function-words-corpus.json"), .copy("Resources/homograph-corpus.json"),
                // dictionary/: lingleaf-android's real answers (identical) and tear-reversed.json.
                .copy("Resources/dictionary"),
            ]
        ),
    ],
    // Swift 6 strict concurrency can come later; the app target also uses Swift 5 mode.
    swiftLanguageModes: [.v5]
)

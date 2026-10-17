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
        .target(name: "LingleafCore"),
        .testTarget(
            name: "LingleafCoreTests",
            dependencies: ["LingleafCore"],
            // Shared with lingleaf-android (core/src/test/resources): identical file.
            resources: [.copy("Resources/function-words-corpus.json")]
        ),
    ],
    // Swift 6 strict concurrency can come later; the app target also uses Swift 5 mode.
    swiftLanguageModes: [.v5]
)

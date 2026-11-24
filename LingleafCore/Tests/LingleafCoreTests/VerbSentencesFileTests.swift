#if canImport(CryptoKit)
import CryptoKit
#endif
import XCTest
@testable import LingleafCore

/// The gate of the bundled `irregular-verb-sentences.json` (SPEC.md, Verb sentences data): the bytes are the ones the
/// SPEC names (SHA-256) and nothing converted them, what is in the file is valid, and, on release pull requests only,
/// the file is complete. Identical intent in lingleaf-android.
final class VerbSentencesFileTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardizedFileURL
    private static let url = root.appending(path: "LingleafCore/Sources/LingleafCore/Resources/irregular-verb-sentences.json")

    private func data() throws -> Data { try Data(contentsOf: Self.url) }

    private func specText() throws -> String { try String(contentsOf: Self.root.appending(path: "SPEC.md"), encoding: .utf8) }

    // MARK: The bytes

    /// The SHA-256 below is checked on every platform with a small reference implementation (CryptoKit is Apple-only).
    func testTheSHA256ReferenceMatchesTheKnownVectors() {
        XCTAssertEqual(TestSHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(TestSHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        XCTAssertEqual(TestSHA256.hex(long), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(TestSHA256.hex(Data(repeating: 0x61, count: 1000)),
            "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
        #if canImport(CryptoKit)
        let sample = Data((0..<500).map { UInt8($0 % 251) })
        XCTAssertEqual(TestSHA256.hex(sample), SHA256.hash(data: sample).map { String(format: "%02x", $0) }.joined())
        #endif
    }

    /// A tripwire, not a lock: whoever changes the file changes the hash in SPEC.md too, so human review of a changed
    /// SHA in the pull request is the real barrier.
    func testTheFileIsTheOneTheSpecNames() throws {
        let hash = TestSHA256.hex(try data())
        XCTAssertTrue(try specText().contains("`\(hash)`"), "SPEC.md must name the SHA-256 of irregular-verb-sentences.json: \(hash)")
    }

    func testTheFirstVersionIsTheEmptyFileWithAFinalNewline() throws {
        XCTAssertEqual(try data(), Data("{\"schema\":1,\"verbs\":[]}\n".utf8))
        XCTAssertEqual(TestSHA256.hex(try data()), "59f90deccb4e3f06702500c1da4d31ed1b96c4b327b1d3cd009e2cf84390e16e")
    }

    /// `.gitattributes` keeps the bytes (no line-ending conversion): the file is named on its own, and the pattern for
    /// every JSON is there too.
    func testGitAttributesKeepTheBytes() throws {
        let attributes = try String(contentsOf: Self.root.appending(path: ".gitattributes"), encoding: .utf8)
        let lines = attributes.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        XCTAssertTrue(lines.contains(["*.json", "-text"]))
        XCTAssertTrue(lines.contains(["LingleafCore/Sources/LingleafCore/Resources/irregular-verb-sentences.json", "-text"]))
        XCTAssertFalse(try data().contains(0x0D), "no carriage return")
    }

    func testTheFileIsWithinTheCapAndInThePackage() throws {
        XCTAssertLessThanOrEqual(try data().count, VerbSentences.maxBytes)
        let package = try String(contentsOf: Self.root.appending(path: "LingleafCore/Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(#".copy("Resources/irregular-verb-sentences.json")"#), "bundled as a resource of the core")
        XCTAssertEqual(VerbSentences.maxBytes, 512 * 1024)
    }

    // MARK: What is in the file

    func testWhatIsInTheFileIsValid() throws {
        let file = try VerbSentences.load(data())
        XCTAssertEqual(VerbSentencesLint.problems(in: file), [])
        XCTAssertEqual(VerbSentences.shared, file, "the shipped file is read the same way")
        XCTAssertEqual(VerbSentences.shared.verbs.count, file.verbs.count)
    }

    /// The SPEC names the cap ("17 as of this version") and the table decides it: 10% of its verbs, rounded down.
    func testTheOmissionCapIsTenPercentOfTheTable() throws {
        XCTAssertEqual(IrregularVerbs.shared.verbs.count / 10, 17)
        XCTAssertTrue(try specText().contains("(17 as of this version)"))
    }

    /// SPEC.md, cue rule: every sentence of lie and hang has a cue of its sense and none of the other's. The bundled file
    /// first (no sentences yet), then the SPEC's own examples, and the closed lists the SPEC names.
    func testHomonymSentencesCarryTheirCue() throws {
        let table = IrregularVerbs.shared
        for entry in try VerbSentences.load(data()).verbs {
            guard let verb = table.verb(base: entry.base), verb.homonym != nil else { continue }
            for sentence in entry.sentences {
                let found = try XCTUnwrap(VerbSentencesLint.cues(SentenceView(sentence.en), base: entry.base))
                XCTAssertTrue(sentence.senseIndex == 1 ? found.sense1 && !found.sense0 : found.sense0 && !found.sense1, sentence.en)
            }
        }
        XCTAssertEqual(table.verbs.filter { $0.homonym != nil }.map(\.base).sorted(), ["hang", "lie"], "the cue lists cover these two")
        let f = VerbSentencesFixtures.self
        let examples: [(verb: String, sentence: [String: Any])] = [
            ("lie", f.sentence("didnt", "lie", "She didn't lie to me.", sense: 1, context: true)),
            ("lie", f.sentence("advice", "lie", "You should never lie to her.", sense: 1, context: true)),
            ("hang", f.sentence("didnt", "hang", "They didn't hang the thief.", sense: 1, context: true)),
            ("lie", f.sentence("advice", "lie", "You should lie down for an hour.", context: true)),
            ("hang", f.sentence("habit", "hang", "I hang my coat here every day.", context: true)),
        ]
        for example in examples {
            XCTAssertEqual(f.problems(f.file(of: example.verb, [example.sentence])), [], example.sentence["en"] as? String ?? "")
        }
        XCTAssertEqual(VerbSentencesLint.hangExecuted.intersection(["man", "men"]), [], "man can read as a painting or a figure")
    }

    // MARK: The text allowlist

    /// SPEC.md: a fixed allowlist of whole blocks. Every non-ASCII code point of the three bundled files and of the SPEC's
    /// own section "Verb sentences data" is inside it (so the same files load on every platform and OS version).
    func testEveryNonASCIIScalarOfTheBundledFilesIsInTheAllowlist() throws {
        let resources = Self.root.appending(path: "LingleafCore/Sources/LingleafCore/Resources")
        var texts: [(String, String)] = try ["grammar-rules", "irregular-verbs", "irregular-verb-sentences"].map {
            ($0, try String(contentsOf: resources.appending(path: "\($0).json"), encoding: .utf8))
        }
        let spec = try specText()
        let section = try XCTUnwrap(spec.range(of: "Verb sentences data (shared logic"))
        texts.append(("SPEC.md, Verb sentences data", String(spec[section.lowerBound...])))
        for (name, text) in texts {
            let outside = Set(text.unicodeScalars.filter { $0.value > 0x7F && !GrammarRules.isAllowed($0) })
            XCTAssertEqual(outside, [], "\(name) holds code points outside the allowlist")
        }
        XCTAssertGreaterThan(texts[0].1.unicodeScalars.filter { $0.value > 0x7F }.count, 100, "the scan saw the rules' non-ASCII text")
        XCTAssertEqual(GrammarRules.allowedBlocks, [0x0000...0x036F, 0x2000...0x206F, 0x2190...0x21FF])
    }

    func testTheAllowlistIsExactlyTheBlocksTheSpecNames() throws {
        let inside: [UInt32] = [0x00, 0x7F, 0x80, 0xFF, 0x100, 0x17F, 0x24F, 0x250, 0x2AF, 0x2B0, 0x2FF, 0x300, 0x36F]
        for value in inside + [0x2000, 0x206F, 0x2190, 0x21FF] {
            XCTAssertTrue(GrammarRules.isAllowed(try XCTUnwrap(Unicode.Scalar(value))), String(value, radix: 16))
        }
        let outside: [UInt32] = [
            0x370, 0x378, 0x3B1, 0x400, 0x2E80, 0x1FFF, 0x2070, 0x218F, 0x2200, 0x4E2D, 0xFDD0, 0xFFFE, 0xFFFF, 0x1F600, 0x10FFFF,
        ]
        for value in outside {
            XCTAssertFalse(GrammarRules.isAllowed(try XCTUnwrap(Unicode.Scalar(value))), String(value, radix: 16))
        }
        XCTAssertTrue(try specText().contains("Basic Latin, Latin-1 Supplement, Latin Extended-A, Latin Extended-B (U+0000 to U+024F)"))
    }

    // MARK: Release pull requests

    /// Completeness runs on release pull requests only (CI sets `LINGLEAF_RELEASE_PR=1` when the pull request is
    /// against main); before that the test above checks only that what is in the file is valid.
    func testTheFileIsCompleteOnReleasePullRequests() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LINGLEAF_RELEASE_PR"] == "1", "release pull requests only")
        let problems = VerbSentencesLint.completenessProblems(in: try VerbSentences.load(data()))
        XCTAssertEqual(problems, [], "every verb of the table needs its sentences before a release")
    }
}

/// SHA-256 (FIPS 180-4), for the file hash on every platform.
enum TestSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be,
        0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa,
        0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85,
        0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f,
        0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hex(_ data: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data) + [0x80]
        while message.count % 64 != 56 { message.append(0) }
        let bits = UInt64(data.count) * 8
        message += (0..<8).map { UInt8(truncatingIfNeeded: bits >> UInt64(56 - 8 * $0)) }
        for chunk in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                w[i] = (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(message[chunk + 4 * i + $1]) }
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var v = h
            for i in 0..<64 {
                let s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25)
                let ch = (v[4] & v[5]) ^ (~v[4] & v[6])
                let t1 = v[7] &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22)
                let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
                let t2 = s0 &+ maj
                v = [t1 &+ t2, v[0], v[1], v[2], v[3] &+ t1, v[4], v[5], v[6]]
            }
            for i in 0..<8 { h[i] = h[i] &+ v[i] }
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}

import XCTest
@testable import LingleafCore

/// Precision of the verb-or-noun rule on the shared annotated corpus (same file and thresholds as
/// lingleaf-android, SPEC.md): each step must claim at least 15 cases and be right (base and verb)
/// in at least 95% of them, "bit" after a noun subject too; each family needs at least 30 cases and
/// the corpus at least 150; every homograph of the bundled stories must be read right (no unsure).
/// Every miss is printed.
///
/// Known residual (no rule change): a present-tense verb after a plural or "you" subject
/// ("they smelt", "deer bound", "you saw") can be read as the past ("smell", "bind", "see").
final class HomographCorpusTests: XCTestCase {
    private struct Case: Decodable {
        let source: String
        let sentence: String
        let word: String
        let expectedBase: String
        let expectedVerb: Bool
    }

    private struct Corpus: Decodable {
        let about: String
        let cases: [Case]
    }

    private static let families: [String: String] = {
        var out: [String: String] = [:]
        for form in ["lives", "leaves", "tears", "winds", "leads"] { out[form] = "plural" }
        for form in ["left", "saw", "felt", "rose", "fell", "ground", "wound", "spoke", "bit", "shot", "dove", "thought",
                     "stole", "slew", "spat", "spelt", "smelt"] {
            out[form] = "pastOrNoun"
        }
        for form in ["found", "lay", "bore", "bound"] { out[form] = "twoVerbs" }
        for form in ["lead", "tear", "wind"] { out[form] = "sameBase" }
        return out
    }()

    func testEachStepIsPreciseOnTheSharedCorpus() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "homograph-corpus", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        var claimed: [Reading.Step: Int] = [:], right: [Reading.Step: Int] = [:], family: [String: Int] = [:]
        var unsure = 0, bitClaimed = 0, bitRight = 0
        let sources: Set<String> = ["constructed", "heldout1", "heldout2", "heldout3", "v2", "v2heldout", "stories"]
        for item in corpus.cases {
            XCTAssertTrue(sources.contains(item.source), "source \(item.source)")
            let pattern = "(?<![A-Za-z'’])" + NSRegularExpression.escapedPattern(for: item.word) + "(?![A-Za-z'’])"
            let found = try NSRegularExpression(pattern: pattern).firstMatch(
                in: item.sentence, range: NSRange(location: 0, length: (item.sentence as NSString).length)
            )
            let match = try XCTUnwrap(found, "'\(item.word)' not in '\(item.sentence)'")
            let range = WordRange(match.range.location, match.range.location + match.range.length)
            let reading = try XCTUnwrap(IrregularVerbs.shared.resolve(item.sentence, range), "'\(item.word)' is not a homograph")
            let name = try XCTUnwrap(Self.families[TextTools.normalize(item.word)], "'\(item.word)' has no family")
            family[name, default: 0] += 1
            let correct = reading.kind != .unsure && reading.base == item.expectedBase && reading.isVerb == item.expectedVerb
            if item.source == "stories" {
                XCTAssertTrue(correct, "a story's sentence must be read right: \(item.sentence) [\(item.word)] → \(reading)")
            }
            guard reading.kind != .unsure else {
                unsure += 1
                continue
            }
            claimed[reading.step, default: 0] += 1
            if item.word == "bit", reading.step == .subjectNoun {
                bitClaimed += 1
                if correct { bitRight += 1 }
            }
            if correct {
                right[reading.step, default: 0] += 1
            } else {
                let got = "\(reading.base)/\(reading.isVerb)", expected = "\(item.expectedBase)/\(item.expectedVerb)"
                print("homograph corpus miss (\(reading.step.rawValue)): \(item.sentence) [\(item.word)]: got \(got), expected \(expected)")
            }
        }
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 150)
        for name in Set(Self.families.values) {
            XCTAssertGreaterThanOrEqual(family[name] ?? 0, 30, "family \(name): only \(family[name] ?? 0) cases (need 30)")
        }
        for step in Reading.Step.allCases where step != .unsure {
            let count = claimed[step] ?? 0
            let precision = Double(right[step] ?? 0) / Double(max(count, 1))
            print("homograph corpus \(step.rawValue): \(right[step] ?? 0)/\(count) right")
            XCTAssertGreaterThanOrEqual(count, 15, "\(step.rawValue): only \(count) claims (need 15)")
            XCTAssertGreaterThanOrEqual(precision, 0.95, "\(step.rawValue) precision \(precision) < 0.95")
        }
        XCTAssertGreaterThanOrEqual(bitClaimed, 15, "bit after a noun subject: only \(bitClaimed) claims (need 15)")
        let bitPrecision = Double(bitRight) / Double(max(bitClaimed, 1))
        XCTAssertGreaterThanOrEqual(bitPrecision, 0.95, "bit after a noun subject: \(bitRight)/\(bitClaimed)")
        print("homograph corpus: \(corpus.cases.count) cases, \(unsure) unsure")
    }
}

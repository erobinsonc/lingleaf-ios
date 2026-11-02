import XCTest
@testable import LingleafCore

/// Precision of the verb-or-noun rule on the shared annotated corpus (same file and thresholds as
/// lingleaf-android, SPEC.md): each step must claim at least 15 cases and be right (base and verb)
/// in at least 95% of them, "bit" after a noun subject too; each family needs at least 30 cases and
/// the corpus at least 150; every homograph and form of the table in the bundled stories must be
/// read right (unsure, or an -s/-ing verb no step proved, is an error there). A verb with a regular
/// twin must also have the right sense (`expectedSense`). Every miss is printed.
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
        let expectedSense: String?
        /// v4: the noun's pronunciation in this sentence; `.some(nil)` when nothing proves it (JSON null),
        /// nil when the case doesn't say.
        let expectedNounIpa: String??

        private enum CodingKeys: String, CodingKey {
            case source, sentence, word, expectedBase, expectedVerb, expectedSense, expectedNounIpa
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = try c.decode(String.self, forKey: .source)
            sentence = try c.decode(String.self, forKey: .sentence)
            word = try c.decode(String.self, forKey: .word)
            expectedBase = try c.decode(String.self, forKey: .expectedBase)
            expectedVerb = try c.decode(Bool.self, forKey: .expectedVerb)
            expectedSense = try c.decodeIfPresent(String.self, forKey: .expectedSense)
            if c.contains(.expectedNounIpa) {
                expectedNounIpa = .some(try c.decodeNil(forKey: .expectedNounIpa) ? nil : c.decode(String.self, forKey: .expectedNounIpa))
            } else {
                expectedNounIpa = nil
            }
        }
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
        var unsure = 0, bitClaimed = 0, bitRight = 0, ipaFired = 0, ipaRight = 0
        let sources: Set<String> = [
            "constructed", "heldout1", "heldout2", "heldout3", "v2", "v2heldout", "v3", "v3heldout", "v4", "v4heldout", "v5", "stories",
        ]
        for item in corpus.cases {
            XCTAssertTrue(sources.contains(item.source), "source \(item.source)")
            let pattern = "(?<![A-Za-z'’])" + NSRegularExpression.escapedPattern(for: item.word) + "(?![A-Za-z'’])"
            let found = try NSRegularExpression(pattern: pattern).firstMatch(
                in: item.sentence, range: NSRange(location: 0, length: (item.sentence as NSString).length)
            )
            let match = try XCTUnwrap(found, "'\(item.word)' not in '\(item.sentence)'")
            let range = WordRange(match.range.location, match.range.location + match.range.length)
            let reading = try XCTUnwrap(IrregularVerbs.shared.resolve(item.sentence, range), "'\(item.word)' is not of the table")
            // The noun's pronunciation, measured on its own (v4).
            if let want = item.expectedNounIpa {
                let got = IrregularVerbs.shared.nounIPA(in: item.sentence, at: range)
                if got != nil || want == nil {
                    ipaFired += 1
                    if got == want {
                        ipaRight += 1
                    } else {
                        print("homograph corpus nounIpa miss: \(item.sentence) [\(item.word)]: got \(got ?? "none")")
                    }
                }
            }
            // Unsure between two rows ("She tells lies", "The bell rings"): right when the sentence's reading is a row.
            if reading.step == .unsureNoun || reading.step == .unsureNounFirst {
                let rows = IrregularVerbs.shared.choices(in: item.sentence, at: range).map { "\($0.base)/\($0.kind != .noun)" }
                claimed[reading.step, default: 0] += 1
                let ok = rows.contains("\(item.expectedBase)/\(item.expectedVerb)")
                    && (item.expectedSense ?? Sense.verb) == Sense.verb
                if ok {
                    right[reading.step, default: 0] += 1
                } else {
                    print("homograph corpus miss (\(reading.step.rawValue)): \(item.sentence) \(rows)")
                }
                XCTAssertNotEqual(item.source, "stories", "a story's sentence is unsure: \(item.sentence) [\(item.word)]")
                continue
            }
            // The four families of homographs; other forms of the table aren't counted in them.
            if let name = Self.families[TextTools.normalize(item.word)] { family[name, default: 0] += 1 }
            let senseRight = item.expectedSense.map { ($0 == Sense.homonym) == (reading.kind == .homonym) } ?? true
            let correct = reading.kind != .unsure && reading.base == item.expectedBase && reading.isVerb == item.expectedVerb && senseRight
            if item.source == "stories" {
                XCTAssertTrue(correct, "a story's sentence must be read right: \(item.sentence) [\(item.word)] → \(reading)")
            }
            // Unsure, or an -s/-ing verb no step proved (an ordinary word): no claim, a miss but not an error.
            guard reading.kind != .unsure, !(reading.kind == .word && item.expectedVerb) else {
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
        print("homograph corpus noun IPA: \(ipaRight)/\(ipaFired) right")
        XCTAssertTrue(ipaFired >= 15 && Double(ipaRight) / Double(max(ipaFired, 1)) >= 0.95, "noun IPA: \(ipaRight)/\(ipaFired)")
        // The twin's noun is measured as one: after a determiner, and unsure with the verb.
        let twin = (claimed[.twinNoun] ?? 0) + (claimed[.unsureNoun] ?? 0)
        XCTAssertGreaterThanOrEqual(twin, 15, "the twin's noun claims only \(twin) cases (need 15)")
        for step in Reading.Step.allCases where step != .unsure {
            let count = claimed[step] ?? 0
            let precision = Double(right[step] ?? 0) / Double(max(count, 1))
            print("homograph corpus \(step.rawValue): \(right[step] ?? 0)/\(count) right")
            // A quote before an -s form is rare (5 cases); the twin's noun steps count together (above).
            let least = step == .quote ? 5 : step == .twinNoun || step == .unsureNoun ? 1 : 15
            XCTAssertGreaterThanOrEqual(count, least, "\(step.rawValue): only \(count) claims (need \(least))")
            XCTAssertGreaterThanOrEqual(precision, 0.95, "\(step.rawValue) precision \(precision) < 0.95")
        }
        XCTAssertGreaterThanOrEqual(bitClaimed, 15, "bit after a noun subject: only \(bitClaimed) claims (need 15)")
        let bitPrecision = Double(bitRight) / Double(max(bitClaimed, 1))
        XCTAssertGreaterThanOrEqual(bitPrecision, 0.95, "bit after a noun subject: \(bitRight)/\(bitClaimed)")
        print("homograph corpus: \(corpus.cases.count) cases, \(unsure) unsure")
    }
}

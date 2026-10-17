import XCTest
@testable import LingleafCore

/// Precision of each rule on the shared annotated corpus (same file and thresholds as
/// lingleaf-android): a rule must be right in at least 95% of the cases where it fires, and the
/// corpus must expect it at least 30 times. Every mismatch is printed.
final class FunctionWordsCorpusTests: XCTestCase {
    private struct Case: Decodable {
        let source: String
        let sentence: String
        let word: String
        let use: String?
        let base: String?
        let chunk: String?
        let note: String?
    }

    private struct Corpus: Decodable {
        let about: String
        let cases: [Case]
    }

    private let measured = ["presentPerfect", "pastPerfect", "hadBetter", "contraction", "modal"]

    private func name(_ use: FunctionWord.Use) -> String {
        switch use {
        case .pastNegative: "pastNegative"
        case .presentNegative: "presentNegative"
        case .pastQuestion: "pastQuestion"
        case .presentQuestion: "presentQuestion"
        case .prohibition: "prohibition"
        case .questionTag: "questionTag"
        case .modal: "modal"
        case .presentPerfect: "presentPerfect"
        case .pastPerfect: "pastPerfect"
        case .hadBetter: "hadBetter"
        case .contraction: "contraction"
        }
    }

    func testEachRuleIsPreciseOnTheSharedCorpus() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "function-words-corpus", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        var fired: [String: Int] = [:], right: [String: Int] = [:], expected: [String: Int] = [:]
        for item in corpus.cases {
            let pattern = "(?<![A-Za-z'’])" + NSRegularExpression.escapedPattern(for: item.word) + "(?![A-Za-z'’])"
            let found = try NSRegularExpression(pattern: pattern).firstMatch(
                in: item.sentence, range: NSRange(location: 0, length: (item.sentence as NSString).length)
            )
            let match = try XCTUnwrap(found, "'\(item.word)' not in '\(item.sentence)'")
            let range = try XCTUnwrap(TextTools.wordAt(item.sentence, match.range.location))
            let result = FunctionWords.analyze(item.sentence, range)
            let got = result.map { name($0.use) }
            let chunk = result?.chunk.map { TextTools.substring(item.sentence, $0) }
            if let use = item.use { expected[use, default: 0] += 1 }
            let correct = got == item.use && (got == nil || (result?.base == item.base && chunk == item.chunk))
            if let got {
                fired[got, default: 0] += 1
                if correct { right[got, default: 0] += 1 }
            }
            if !correct {
                let wanted = "\(item.use ?? "nil") \(item.base ?? "nil") '\(item.chunk ?? "nil")'"
                let found = "\(got ?? "nil") \(result?.base ?? "nil") '\(chunk ?? "nil")'"
                print("corpus mismatch: \(item.sentence) [\(item.word)]: expected \(wanted), got \(found)")
            }
        }
        for rule in measured {
            let count = expected[rule] ?? 0
            XCTAssertGreaterThanOrEqual(count, 30, "\(rule): only \(count) cases expect it (need 30)")
            let precision = Double(right[rule] ?? 0) / Double(max(fired[rule] ?? 0, 1))
            print("corpus \(rule): \(right[rule] ?? 0)/\(fired[rule] ?? 0) right, \(count) expected")
            XCTAssertGreaterThanOrEqual(precision, 0.95, "\(rule) precision \(precision) < 0.95")
        }
    }
}

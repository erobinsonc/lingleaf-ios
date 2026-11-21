import Foundation
import XCTest
@testable import LingleafCore

/// Small `irregular-verb-sentences.json` files built in the tests (never in the bundle), so each rule of the reader
/// and the linter has a vector that fails for that rule alone. Their sentences are only test data.
enum VerbSentencesFixtures {
    typealias Json = [String: Any]

    static func sentence(
        _ slot: String, _ form: String, _ en: String, level: String = "A2", sense: Int = 0, context: Bool = false, spoken: String? = nil
    ) -> Json {
        var json: Json = ["slot": slot, "form": form, "en": en, "es": "texto", "senseIndex": sense, "level": level]
        if context { json["context"] = true }
        if let spoken { json["spoken"] = spoken }
        return json
    }

    static func entry(_ base: String, _ sentences: [Json], omitted: [Json]? = nil) -> Json {
        var json: Json = ["base": base, "sentences": sentences]
        if let omitted { json["omitted"] = omitted }
        return json
    }

    static func file(_ verbs: [Json], schema: Any = 1) -> Json { ["schema": schema, "verbs": verbs] }

    static func data(_ json: Json) -> Data { (try? JSONSerialization.data(withJSONObject: json)) ?? Data() }

    /// A valid verb with all ten positions (the SPEC's own examples, with the level that holds their length).
    static let take: [Json] = [
        sentence("habit", "take", "I take the bus every day.", context: true),
        sentence("third", "takes", "She takes her dog out at six."),
        sentence("now", "taking", "He is taking a photo now."),
        sentence("past", "took", "Yesterday I took the train."),
        sentence("story", "took", "She took her bag and left."),
        sentence("didnt", "take", "We didn't take a taxi."),
        sentence("perfect", "taken", "I have taken my medicine."),
        sentence("passive", "taken", "The photo was taken in May."),
        sentence("pastperfect", "taken", "She had taken the key before I came."),
        sentence("advice", "take", "You should take a break."),
    ]

    static func file(of verb: String, _ sentences: [Json], omitted: [Json]? = nil) -> Json {
        file([entry(verb, sentences, omitted: omitted)])
    }

    static func problems(_ json: Json) -> [String] {
        guard let file = try? VerbSentences.load(data(json)) else { return ["did not load"] }
        return VerbSentencesLint.problems(in: file)
    }
}

/// The helpers of the linter's tests: the problem codes of one verb's sentences against the real table.
class VerbSentencesLintCase: XCTestCase {
    typealias Json = [String: Any]
    let f = VerbSentencesFixtures.self

    /// The codes ("cue-past", "bold-twice") of the problems of one verb's sentences. `context-count` and `length` are left
    /// out unless asked for in `keep`: a vector of a few words and no context sentence is not about them, and each rule has
    /// its own tests.
    func codes(_ verb: String, _ sentences: [Json], keep: Set<String> = []) -> Set<String> {
        guard let file = try? VerbSentences.load(f.data(f.file(of: verb, sentences))) else { return ["did not load"] }
        let list = VerbSentencesLint.problems(in: file)
        let names = list.map { $0.split(separator: ":", maxSplits: 1)[0].split(separator: "(")[0] }.map(String.init)
        return Set(names).subtracting(Set(["context-count", "length"]).subtracting(keep))
    }

    func clean(_ verb: String, _ sentences: [Json], line: UInt = #line) {
        XCTAssertEqual(codes(verb, sentences), [], line: line)
    }

    func refused(_ verb: String, _ sentences: [Json], _ code: String, line: UInt = #line) {
        XCTAssertEqual(codes(verb, sentences), [code], line: line)
    }

    /// Refused for `code` (and for something that comes with it: a form read without its auxiliary is also unproven).
    func flagged(_ verb: String, _ sentences: [Json], _ code: String, line: UInt = #line) {
        XCTAssertTrue(codes(verb, sentences).contains(code), "\(codes(verb, sentences)) lacks \(code)", line: line)
    }
}

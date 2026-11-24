import XCTest
@testable import LingleafCore

/// The completeness rules of `irregular-verb-sentences.json` (SPEC.md, Verb sentences data): run on release pull requests
/// against the real file; here against small files built in the tests.
final class VerbSentencesCompletenessTests: VerbSentencesLintCase {
    // MARK: Completeness

    private func complete(_ verb: String, _ sentences: [Json], omitted: [Json]? = nil, extra: [Json] = []) -> [String] {
        guard let file = try? VerbSentences.load(f.data(f.file([f.entry(verb, sentences + extra,
            omitted: omitted)]))) else { return ["did not load"] }
        return VerbSentencesLint.completenessProblems(in: file).filter { $0.contains(": \(verb) ") }
    }

    func testCompletenessNeedsEveryPositionOrAnOmissionOfNowOrAdvice() {
        XCTAssertEqual(complete("take", f.take), [])
        XCTAssertEqual(complete("take", Array(f.take[0..<9]), omitted: [["slot": "advice", "reason": "no natural sentence"]]), [])
        XCTAssertEqual(complete("take", Array(f.take[0..<2] + f.take[3...]), omitted: [["slot": "now", "reason": "no natural sentence"]]),
            [])
        XCTAssertEqual(complete("take", Array(f.take[0..<9])).count, 1, "advice has neither")
        XCTAssertTrue(complete("take", Array(f.take[0..<9])).first?.hasPrefix("complete-position") == true)
        XCTAssertEqual(complete("take", Array(f.take[0..<2] + f.take[3...])).count, 1, "now has neither")
    }

    func testPositionsOneTwoAndFourToNineAreNeverOmitted() {
        for (index, position) in zip([0, 1, 3, 4, 5, 6, 7, 8], [1, 2, 4, 5, 6, 7, 8, 9]) {
            var sentences = f.take
            sentences.remove(at: index)
            let problems = complete("take", sentences)
            let found = problems.contains { $0.hasPrefix("complete-required") && $0.contains("position \(position)") }
            XCTAssertTrue(found, "\(position): \(problems)")
        }
    }

    func testSevenAndNineAreNeverOmittedForAnyVerb() {
        for slot in ["perfect", "pastperfect"] {
            var sentences = f.take
            sentences.removeAll { $0["slot"] as? String == slot }
            XCTAssertTrue(complete("take", sentences).contains { $0.hasPrefix("complete-required") }, slot)
        }
    }

    func testEveryVerbOfTheTableIsRequired() {
        let table = IrregularVerbs.shared
        let empty = VerbSentences(verbs: [])
        XCTAssertEqual(VerbSentencesLint.completenessProblems(in: empty).count, table.verbs.count)
        XCTAssertTrue(VerbSentencesLint.completenessProblems(in: empty).allSatisfy { $0.hasPrefix("complete-missing") })
    }

    func testAHomonymVerbNeedsFourSentencesOfSenseOne() {
        let zero: [Json] = [
            f.sentence("habit", "lie", "I lie on the bed every day."), f.sentence("third", "lies", "She lies on the couch at six."),
            f.sentence("now", "lying", "He is lying on the grass now."), f.sentence("past", "lay", "Yesterday I lay on the bed."),
            f.sentence("story", "lay", "She lay down and slept."), f.sentence("didnt", "lie", "We didn't lie on the grass."),
            f.sentence("perfect", "lain", "The dog has lain here since noon."), f.sentence("passive", "lain",
                "The bed was lain on in May."),
            f.sentence("pastperfect", "lain", "She had lain there before I came."), f.sentence("advice", "lie",
                "You should lie down for an hour."),
        ]
        let one = { (slot: String, form: String, en: String) in self.f.sentence(slot, form, en, sense: 1) }
        let four: [Json] = [
            one("past", "lied", "Yesterday he lied to me."), one("didnt", "lie", "She didn't lie to me."),
            one("perfect", "lied", "He has lied to us before."), one("perfectq", "lied", "Have you ever lied to him?"),
        ]
        // Position order inside sense 1: 4, 6, 7, 8.
        XCTAssertEqual(complete("lie", zero, extra: four), [])
        XCTAssertTrue(complete("lie", zero).contains { $0.hasPrefix("complete-sense-one") }, "sense 1 missing")
        XCTAssertTrue(complete("lie", zero, extra: Array(four[0..<3])).contains { $0.hasPrefix("complete-sense-one") },
            "position 8 missing")
        XCTAssertTrue(complete("lie", zero, extra: [four[0], four[2], four[3]]).contains { $0.hasPrefix("complete-sense-one") },
            "no base-form position")
        let advice = one("advice", "lie", "You should never lie to her.")
        XCTAssertEqual(complete("lie", zero, extra: [four[0], advice, four[2], four[3]].sorted { position($0) < position($1) }), [],
            "advice is a base-form position too")
    }

    private func position(_ json: Json) -> Int { VerbSlot(rawValue: json["slot"] as? String ?? "")?.position ?? 0 }
}

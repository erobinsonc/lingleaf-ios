import XCTest
@testable import LingleafCore

/// Every refusal of the reader of `irregular-verb-sentences.json` (SPEC.md, Verb sentences data), one vector each.
/// Each refusal is paired with the same edit made valid, so a test cannot pass for another reason.
final class VerbSentencesRefusalTests: VerbSentencesReaderCase {
    // MARK: The shape that loads

    func testAnEmptyFileAndACompleteVerbLoad() throws {
        XCTAssertEqual(try VerbSentences.load(bytes("{\"schema\":1,\"verbs\":[]}\n")).verbs, [])
        let file = try load(take())
        XCTAssertEqual(file.verbs.count, 1)
        XCTAssertEqual(file.entry(base: "take")?.sentences.count, 10)
        XCTAssertEqual(file.entry(base: "take")?.sentences(senseIndex: 1).count, 0)
        XCTAssertNil(file.entry(base: "give"))
        XCTAssertNoThrow(try VerbSentences.load(raw()), "the raw vector used below is valid")
    }

    func testAVerbWithNoSentencesLoads() {
        loads(f.file([f.entry("take", [])]), "listed, nothing written yet")
    }

    // MARK: Bytes

    func testAFileOverTheCapIsRefusedAndOneAtTheCapLoads() {
        let base = bytes("{\"schema\":1,\"verbs\":[]}")
        let pad = { (total: Int) in base + Data(repeating: 0x20, count: total - base.count) }
        XCTAssertNoThrow(try VerbSentences.load(pad(512 * 1024)))
        XCTAssertThrowsError(try VerbSentences.load(pad(512 * 1024 + 1))) { XCTAssertEqual($0 as? VerbSentencesError, .tooLarge) }
    }

    func testAByteOrderMarkIsRefused() {
        refusedBytes(Data([0xEF, 0xBB, 0xBF]) + bytes("{\"schema\":1,\"verbs\":[]}"), "byte order mark")
    }

    func testANULByteIsRefusedAnywhere() {
        refusedBytes(bytes("{\"schema\":1,\"verbs\":[]}") + Data([0]), "NUL")
        refusedBytes(bytes(#"{"schema":1,"verbs":[],"a":"#) + Data([0x22, 0, 0x22]) + bytes("}"), "NUL")
        // UTF-16 holds NUL bytes: refused as such, not read as something else.
        refusedBytes(Data("{\"schema\":1,\"verbs\":[]}".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }), "NUL")
    }

    func testBytesThatAreNotUTF8AreRefused() {
        refusedBytes(bytes("{\"schema\":1,\"verbs\":[],\"x\":\"") + Data([0xFF, 0xFE]) + bytes("\"}"), "not UTF-8")
        // An overlong encoding of "/" and a UTF-8 encoded surrogate are not UTF-8 either.
        refusedBytes(bytes("{\"schema\":1,\"verbs\":[],\"x\":\"") + Data([0xC0, 0xAF]) + bytes("\"}"), "not UTF-8")
        refusedBytes(bytes("{\"schema\":1,\"verbs\":[],\"x\":\"") + Data([0xED, 0xA0, 0x80]) + bytes("\"}"), "not UTF-8")
        XCTAssertNoThrow(try VerbSentences.load(raw(sentence: sentenceJSON.replacingOccurrences(of: "bus", with: "bús"))),
            "valid UTF-8 loads")
    }

    func testARawControlCharacterInAStringIsRefused() {
        for control in [0x09, 0x0A, 0x0D, 0x01, 0x1F] as [UInt8] {
            let sentence = bytes(#"{"slot":"habit","form":"take","en":"I take the b"#) + Data([control])
                + bytes(#"us every day.","es":"x","senseIndex":0,"level":"A2","context":true}"#)
            refusedBytes(bytes(#"{"schema":1,"verbs":[{"base":"take","sentences":["#) + sentence + bytes("]}]}"), "not strict JSON")
        }
        // The same characters as escapes are valid JSON; the text rule still refuses them in `en`.
        refusedBytes(raw(sentence: sentenceJSON.replacingOccurrences(of: "I take", with: "I\\u0007take")), "text-en")
        // Whitespace between tokens is not inside a string.
        XCTAssertNoThrow(try VerbSentences.load(bytes("{\n\t\"schema\": 1,\r\n \"verbs\": [ ]\n}\n")))
    }

    func testADuplicateKeyIsRefused() {
        refusedBytes(bytes(#"{"schema":1,"schema":1,"verbs":[]}"#), "duplicate key")
        refusedBytes(bytes(#"{"schema":1,"verbs":[],"verbs":[]}"#), "duplicate key")
        // Escapes are resolved: "schema" is "schema".
        refusedBytes(bytes(#"{"schema":1,"schema":1,"verbs":[]}"#), "duplicate key")
        refusedBytes(raw(sentence: String(sentenceJSON.dropLast()) + #","en":"I take the bus every day."}"#), "duplicate key")
    }

    func testTheSameKeyInDifferentObjectsIsNotADuplicate() {
        let two = #"{"schema":1,"verbs":[{"base":"take","sentences":[]},{"base":"give","sentences":[]}]}"#
        XCTAssertNoThrow(try VerbSentences.load(bytes(two)))
    }

    func testNestingDeeperThanEightLevelsIsRefused() {
        let deep = { (levels: Int) in self.bytes(#"{"schema":1,"verbs":[],"x":"# + String(repeating: "[",
            count: levels - 1) + String(repeating: "]", count: levels - 1) + "}") }
        // The root is level 1: eight levels pass the depth gate (and then fail on the unknown key), nine do not.
        XCTAssertThrowsError(try VerbSentences.load(deep(9))) { XCTAssertEqual($0 as? VerbSentencesError, .tooDeep) }
        XCTAssertThrowsError(try VerbSentences.load(deep(8))) { XCTAssertNotEqual($0 as? VerbSentencesError, .tooDeep) }
    }

    func testBracketsInsideStringsDoNotCountAsDepth() {
        let text = String(repeating: "[", count: 30)
        XCTAssertNoThrow(try VerbSentences.load(raw(sentence: sentenceJSON.replacingOccurrences(of: "bus", with: text))))
    }

    func testSchemaAndSenseIndexAreIntegersOnlyAsIntegerLiterals() {
        for literal in ["1.0", "1e0", "1E0", "10e-1", "1.00"] {
            refusedBytes(raw(schema: literal), "control character, a null or a number")
            refusedBytes(raw(sentence: sentenceJSON.replacingOccurrences(of: #""senseIndex":0"#, with: #""senseIndex":\#(literal)"#)),
                "a number")
        }
        refusedBytes(raw(schema: "\"1\""), "wrong shape")
        refusedBytes(raw(schema: "true"), "wrong shape")
        refusedBytes(raw(sentence: sentenceJSON.replacingOccurrences(of: #""senseIndex":0"#, with: #""senseIndex":"0""#)), "wrong shape")
        XCTAssertNoThrow(try VerbSentences.load(raw(schema: "1")))
    }

    func testANullAnywhereIsRefused() {
        refusedBytes(bytes(#"{"schema":1,"verbs":null}"#), "null")
        refusedBytes(raw(sentence: sentenceJSON.replacingOccurrences(of: #""context":true"#, with: #""context":null"#)), "null")
        refusedBytes(raw(sentence: String(sentenceJSON.dropLast()) + #","spoken":null}"#), "null")
    }

    func testAFileThatIsNotAJSONObjectIsRefused() {
        for text in ["[]", "1", "\"x\"", "null", " [{\"schema\":1,\"verbs\":[]}]"] { refusedBytes(bytes(text), "not a JSON object") }
        for text in ["{\"schema\":1,\"verbs\":[]} x", "{\"schema\":1,\"verbs\":[],}", "", "{", "nul", "{\"schema\":1,\"verbs\":[]}{}"] {
            refusedBytes(bytes(text), "not strict JSON")
        }
    }

    func testALoneSurrogateEscapeIsRefusedAndAPairLoads() {
        for escape in [#"\ud800"#, #"\udc00"#, #"\ud800x"#, #"\udbff\u0041"#, #"\ud800\ud800"#, #"\u00e9\udfff"#] {
            refusedBytes(raw(sentence: sentenceJSON.replacingOccurrences(of: "bus", with: "b\(escape)s")), "lone surrogate")
        }
        // A valid pair passes the byte rule (no "lone surrogate"); its character (an emoji) is outside the text allowlist.
        refusedBytes(raw(sentence: sentenceJSON.replacingOccurrences(of: "bus", with: #"b\ud83d\ude00s"#)), "text-en")
        XCTAssertNoThrow(try VerbSentences.load(raw(sentence: sentenceJSON.replacingOccurrences(of: "bus", with: #"b\u00e9s"#))))
        XCTAssertNoThrow(try VerbSentences.load(raw(sentence: sentenceJSON.replacingOccurrences(of: "bus", with: #"b\\ud800s"#))),
            "an escaped backslash")
    }

    // MARK: Schema, fields and keys

    func testASchemaOtherThanOneIsRefusedWhateverElseTheFileHolds() {
        for schema in ["0", "2", "-1", "100"] { refusedBytes(raw(schema: schema), "schema \(schema)") }
    }

    func testAMissingOrUnknownFieldAtAnyLevelIsRefused() {
        refusedBytes(bytes(#"{"schema":1}"#), "missing key verbs")
        refusedBytes(bytes(#"{"verbs":[]}"#), "missing key schema")
        refusedBytes(bytes(#"{"schema":1,"verbs":[],"extra":1}"#), "unknown key extra")
        refusedBytes(bytes(#"{"schema":1,"verbs":[{"sentences":[]}]}"#), "missing key base")
        refusedBytes(bytes(#"{"schema":1,"verbs":[{"base":"take"}]}"#), "missing key sentences")
        refusedBytes(bytes(#"{"schema":1,"verbs":[{"base":"take","sentences":[],"extra":[]}]}"#), "unknown key extra")
        for key in ["slot", "form", "en", "es", "senseIndex", "level"] {
            let without = sentenceJSON.replacingOccurrences(of: #""\#(key)":"#, with: #""x\#(key)":"#)
            refusedBytes(raw(sentence: without), "unknown key x\(key)")
        }
        for key in ["slot", "form", "en", "es", "level"] {
            let regex = try? NSRegularExpression(pattern: #""\#(key)":"[^"]*","#)
            let ns = sentenceJSON as NSString
            let cut = regex.map { $0.stringByReplacingMatches(in: sentenceJSON, range: NSRange(location: 0, length: ns.length),
                withTemplate: "") } ?? ""
            refusedBytes(raw(sentence: cut), "missing key \(key)")
        }
        refusedBytes(raw(sentence: String(sentenceJSON.dropLast()) + #","extra":1}"#), "unknown key extra")
    }

    func testAnOmissionHasExactlySlotAndReason() {
        let entry = { (omission: String) in self.bytes(#"{"schema":1,"verbs":[{"base":"take","sentences":[],"omitted":[\#(omission)]}]}"#) }
        XCTAssertNoThrow(try VerbSentences.load(entry(#"{"slot":"advice","reason":"no natural sentence"}"#)))
        refusedBytes(entry(#"{"slot":"advice"}"#), "missing key reason")
        refusedBytes(entry(#"{"reason":"no natural sentence"}"#), "missing key slot")
        refusedBytes(entry(#"{"slot":"advice","reason":"no natural sentence","x":1}"#), "unknown key x")
    }

    // MARK: Closed lists

    func testAnUnknownSlotIdIsRefused() {
        refused(take { $0[0]["slot"] = "usually" }, "slot-unknown")
        refused(take { $0[0]["slot"] = "Habit" }, "slot-unknown")
        refused(take { $0[0]["slot"] = "" }, "slot-unknown")
        for slot in VerbSlot.allCases { XCTAssertEqual(VerbSlot(rawValue: slot.rawValue), slot) }
        XCTAssertEqual(VerbSlot.allCases.count, 13)
    }

    func testEverySlotIdIsInItsPositionWithItsFormClass() {
        let positions: [VerbSlot: Int] = [
            .habit: 1, .third: 2, .now: 3, .gerund: 3, .past: 4, .story: 5, .didnt: 6, .perfect: 7, .passive: 8, .state: 8,
            .perfectq: 8, .pastperfect: 9, .advice: 10,
        ]
        let classes: [VerbSlot.FormClass: [VerbSlot]] = [
            .base: [.habit, .didnt, .advice], .s: [.third], .ing: [.now, .gerund], .past: [.past, .story],
            .participle: [.perfect, .passive, .state, .perfectq, .pastperfect],
        ]
        XCTAssertEqual(Set(positions.keys), Set(VerbSlot.allCases))
        for (slot, position) in positions { XCTAssertEqual(slot.position, position, slot.rawValue) }
        for (formClass, slots) in classes { for slot in slots { XCTAssertEqual(slot.formClass, formClass, slot.rawValue) } }
        XCTAssertEqual(classes.values.flatMap { $0 }.count, VerbSlot.allCases.count)
    }

    func testAnUnknownLevelIsRefused() {
        for level in ["", "a1", "D1", "A3", "A1 ", "B"] { refused(take { $0[0]["level"] = level }, "level-unknown") }
        for level in ["A1", "A2", "B1", "B2", "C1", "C2"] { loads(take { $0[0]["level"] = level }, level) }
    }

    func testABaseNotInTheTableIsRefusedAndABaseTwiceToo() {
        refused(f.file([f.entry("taek", [])]), "base-unknown")
        refused(f.file([f.entry("Take", [])]), "base-unknown")
        refused(f.file([f.entry("", [])]), "base-unknown")
        refused(f.file([f.entry("take", []), f.entry("take", [])]), "base-twice")
        loads(f.file([f.entry("take", []), f.entry("give", [])]), "two verbs")
    }

    // MARK: Positions and senses

    func testTwoSentencesOfOneSenseInOnePositionAreRefused() {
        refused(take { $0.insert($0[0], at: 1) }, "position-twice")
        refused(take { $0.append($0[0]) }, "order")
        // Two ids of one position (8): passive and state, or passive and perfectq.
        refused(take { $0.insert(self.f.sentence("state", "taken", "The shop was taken."), at: 8) }, "position-twice")
        refused(take { $0.insert(self.f.sentence("perfectq", "taken", "Have you ever taken it?"), at: 8) }, "position-twice")
    }

    func testPositionsOutOfOrderAreRefused() {
        refused(take { $0.swapAt(0, 1) }, "order")
        refused(take { $0.swapAt(8, 9) }, "order")
        refused(take { $0.reverse() }, "order")
        loads(take { $0.remove(at: 2) }, "a gap is fine: positions only have to increase")
    }

    func testASenseIndexOtherThanZeroIsRefusedAndOneNeedsAHomonym() {
        for sense in [2, -1, 1_000_000, Int(Int32.max)] { refused(take { $0[0]["senseIndex"] = sense }, "sense-unknown") }
        refused(take { $0[0]["senseIndex"] = 1 }, "sense-unknown")
        XCTAssertNoThrow(try load(f.file(of: "lie", [f.sentence("didnt", "lie", "She didn't lie to me.", sense: 1, context: true)])))
    }

    func testSenseOneHoldsOnlyItsFourPositions() {
        let sense1 = { (slot: String, form: String, en: String) in self.f.sentence(slot, form, en, sense: 1) }
        let valid = [
            sense1("didnt", "lie", "She didn't lie to me."), sense1("past", "lied", "She lied to me last week."),
            sense1("perfect", "lied", "He has lied to us before."), sense1("perfectq", "lied", "Have you ever lied to him?"),
        ]
        // Position order: 4, 6, 7, 8.
        loads(f.file(of: "lie", [valid[1], valid[0], valid[2], valid[3]]), "the four positions of sense 1")
        for slot in ["third", "story", "pastperfect", "gerund"] {
            let form = ["third": "lies", "story": "lied", "pastperfect": "lied", "gerund": "lying"][slot] ?? "lied"
            let extra = sense1(slot, form, "She lied to me and left.")
            refused(f.file(of: "lie", [extra]), "sense-one-shape")
        }
        // Two of the base-form positions 1, 6, 10; and five sentences.
        refused(f.file(of: "lie", [sense1("habit", "lie", "I lie to her."), sense1("didnt", "lie", "She didn't lie to me.")]),
            "sense-one-shape")
        refused(f.file(of: "lie", valid + [sense1("advice", "lie", "You should never lie to her.")]), "sense-one-shape")
        loads(f.file(of: "lie", [sense1("advice", "lie", "You should never lie to her.")]), "one base-form position")
    }

    func testSenseZeroSentencesComeBeforeSenseOneSentences() {
        let zero = f.sentence("past", "lay", "Yesterday I lay on the bed.")
        let one = f.sentence("didnt", "lie", "She didn't lie to me.", sense: 1)
        loads(f.file(of: "lie", [zero, one]), "sense 0 then sense 1")
        refused(f.file(of: "lie", [one, zero]), "order")
    }

    func testMoreThanFourteenSentencesAreRefused() {
        let many = (0..<15).map { f.sentence("habit", "take", "I take the bus every day.\($0)") }
        refused(f.file(of: "take", many), "too-many-sentences")
        let fourteen = f.take + (0..<4).map { f.sentence("habit", "lie", "x\($0)", sense: 1) }
        XCTAssertEqual(fourteen.count, 14)
        // 14 is the cap: the count alone does not refuse (other rules do for this made-up list).
        XCTAssertFalse(problems(f.file(of: "lie", fourteen)).contains { $0.hasPrefix("too-many-sentences") })
        XCTAssertTrue(problems(f.file(of: "lie", fourteen + [f.sentence("habit", "lie", "x",
            sense: 1)])).contains { $0.hasPrefix("too-many-sentences") })
    }

    private func problems(_ json: Json) -> [String] {
        do {
            _ = try load(json)
            return []
        } catch VerbSentencesError.invalid(let problems) {
            return problems
        } catch {
            return ["\(error)"]
        }
    }

    func testEveryProblemIsListedNotOnlyTheFirst() {
        let json = take {
            $0[0]["level"] = "Z9"
            $0[1]["slot"] = "third"
            $0[2]["form"] = "take"
        }
        let list = problems(json)
        XCTAssertTrue(list.contains { $0.hasPrefix("level-unknown") })
        XCTAssertTrue(list.contains { $0.hasPrefix("form-class") })
        XCTAssertGreaterThanOrEqual(list.count, 2)
    }

    // MARK: Forms

    func testFormMustBeAFormOfTheVerbOfTheClassOfItsSlot() {
        refused(take { $0[0]["form"] = "took" }, "form-class")
        refused(take { $0[1]["form"] = "take" }, "form-class")
        refused(take { $0[2]["form"] = "takes" }, "form-class")
        refused(take { $0[3]["form"] = "taken" }, "form-class")
        refused(take { $0[6]["form"] = "took" }, "form-class")
        refused(take { $0[0]["form"] = "give" }, "form-class")
        refused(take { $0[0]["form"] = "" }, "form-class")
        refused(take { $0[0]["form"] = "Take" }, "form-class")
        loads(take { $0[3]["form"] = "took" }, "a past form")
    }

    func testFormsOfTheHomonymAreForSenseOneOnly() {
        let lied = f.sentence("past", "lied", "She lied to me last week.", sense: 1)
        loads(f.file(of: "lie", [lied]), "lied is the homonym's past")
        refused(f.file(of: "lie", [f.sentence("past", "lied", "She lied to me last week.")]), "form-class")
        refused(f.file(of: "lie", [f.sentence("past", "lay", "Yesterday I lay down.", sense: 1)]), "form-class")
        loads(f.file(of: "lie", [f.sentence("past", "lay", "Yesterday I lay down.")]), "lay is the verb's past")
    }

    func testAVerbWithTwoPastFormsAcceptsEither() {
        for form in ["learned", "learnt"] {
            loads(f.file(of: "learn", [f.sentence("past", form, "Yesterday I \(form) it.")]), form)
        }
        refused(f.file(of: "learn", [f.sentence("past", "learns", "Yesterday I learns it.")]), "form-class")
    }

    // MARK: context

    func testContextMustBeABoolean() {
        for value in [1, 0, "true", "yes", [true], ["a": true]] as [Any] {
            refused(take { $0[0]["context"] = value }, "wrong shape")
        }
        loads(take { $0[0]["context"] = true }, "true")
        loads(take { $0[0]["context"] = false; $0[9]["context"] = true }, "false")
    }

    // MARK: omitted

    private func omitted(_ slot: String, _ reason: String = "no natural sentence") -> Json { ["slot": slot, "reason": reason] }

    private func withoutPosition(_ position: Int, omitted list: [Json]) -> Json {
        let drop = [3: 2, 10: 9][position] ?? 0
        var sentences = f.take
        sentences.remove(at: drop)
        return f.file(of: "take", sentences, omitted: list)
    }

    func testOnlyNowAndAdviceMayBeOmitted() {
        loads(withoutPosition(3, omitted: [omitted("now")]), "now")
        loads(withoutPosition(10, omitted: [omitted("advice")]), "advice")
        for slot in ["habit", "third", "past", "story", "didnt", "perfect", "passive", "pastperfect", "gerund", "state", "perfectq", ""] {
            refused(f.file(of: "take", [], omitted: [omitted(slot)]), "omitted-slot")
        }
    }

    func testAnOmissionIsNotAlsoASentenceInThatPosition() {
        refused(f.file(of: "take", f.take, omitted: [omitted("now")]), "omitted-and-present")
        refused(f.file(of: "take", f.take, omitted: [omitted("advice")]), "omitted-and-present")
        // A gerund is a sentence of position 3 as well.
        var gerund = f.take
        gerund[2] = f.sentence("gerund", "taking", "Taking photos is fun.")
        refused(f.file(of: "take", gerund, omitted: [omitted("now")]), "omitted-and-present")
    }

    func testAnOmissionIsListedOnce() {
        refused(f.file(of: "take", [], omitted: [omitted("now"), omitted("now")]), "omitted-twice")
        loads(f.file(of: "take", [], omitted: [omitted("now"), omitted("advice")]), "both")
    }

    func testTheReasonIs3To140CodePoints() {
        for length in [0, 1, 2] { refused(f.file(of: "take", [], omitted: [omitted("now", String(repeating: "r", count: length))]),
            "omitted-reason") }
        for length in [3, 4, 140] { loads(f.file(of: "take", [], omitted: [omitted("now", String(repeating: "r", count: length))]),
            "\(length)") }
        refused(f.file(of: "take", [], omitted: [omitted("now", String(repeating: "r", count: 141))]), "omitted-reason")
        refused(f.file(of: "take", [], omitted: [omitted("now", "   ")]), "omitted-reason")
        loads(f.file(of: "take", [], omitted: [omitted("now", "a b")]), "3 with a space inside")
    }

    func testAtMostATenthOfTheTablesVerbsHaveAnOmission() {
        let bases = IrregularVerbs.shared.verbs.map(\.base)
        let cap = bases.count / 10
        XCTAssertEqual(cap, 17)
        let withOmission = { (count: Int) in self.f.file(bases.prefix(count).map { self.f.entry($0, [], omitted: [self.omitted("now")]) }) }
        XCTAssertNoThrow(try load(withOmission(cap)))
        refused(withOmission(cap + 1), "omission-cap")
        // Verbs without an omission do not count.
        XCTAssertNoThrow(try load(f.file(bases.map { f.entry($0, []) })))
    }
}

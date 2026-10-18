import XCTest
@testable import LingleafCore

/// The irregular-verb table: the bundled file loads, a crafted one is refused at the first
/// problem, and the lists derived from it keep what the old hand-written lists had.
final class IrregularVerbsTests: XCTestCase {
    // MARK: Loading

    func testTheBundledTableLoads() {
        let table = IrregularVerbs.shared
        XCTAssertFalse(table.verbs.isEmpty, "the bundled irregular-verbs.json must load")
        XCTAssertFalse(table.groups.isEmpty)
        XCTAssertFalse(table.homographs.isEmpty)
        XCTAssertFalse(table.formToBase.isEmpty)
        XCTAssertTrue(table.verbs.allSatisfy { IrregularVerbs.levels.contains($0.level) })
        XCTAssertEqual(table.verb(base: "steal")?.past, ["stole"])
        XCTAssertNil(table.verb(base: "walk"))
    }

    /// The smallest valid table, edited by `edit` before it is encoded.
    private func table(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var context: [String: Any] = [:]
        for name in Context.names { context[name] = [String]() }
        context["subjects"] = ["she"]
        var json: [String: Any] = [
            "schemaVersion": 1,
            "about": "Test table.",
            "groups": [["id": "abb", "example": "leave · left · left", "title": ["en": "Two alike", "es": "Dos iguales"]]],
            "verbs": [
                [
                    "base": "steal", "past": ["stole"], "participle": ["stolen"], "ing": "stealing", "s": "steals",
                    "group": "abb", "level": "C2", "es": ["robar"], "freq": 40,
                ],
                [
                    "base": "leave", "past": ["left"], "participle": ["left"], "ing": "leaving", "s": "leaves",
                    "group": "abb", "level": "A1", "es": ["irse", "dejar"], "nounFirst": false,
                    "spokenAs": ["base": "leev"],
                ],
            ],
            "homographs": [["form": "left", "noun": "left", "verb": "leave", "rules": ["participle"]]],
            "context": context,
            "llBases": ["install"],
        ]
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// `json` with the first verb edited.
    private func editVerb(_ json: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
        var verbs = json["verbs"] as? [[String: Any]] ?? []
        edit(&verbs[0])
        json["verbs"] = verbs
    }

    private func editHomograph(_ json: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
        var homographs = json["homographs"] as? [[String: Any]] ?? []
        edit(&homographs[0])
        json["homographs"] = homographs
    }

    private func assertRefused(_ data: Data, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try IrregularVerbs.load(data), message, file: file, line: line)
    }

    func testAValidTableLoadsAndDerivesItsLists() throws {
        let table = try IrregularVerbs.load(table())
        XCTAssertEqual(table.formToBase["stole"], "steal")
        XCTAssertEqual(table.formToBase["leaves"], "leave")
        XCTAssertNil(table.formToBase["left"], "a homograph: its sentence decides")
        XCTAssertEqual(table.participles, ["stolen", "left"])
        XCTAssertTrue(table.baseLikeParticiples.isEmpty)
        XCTAssertEqual(table.hadBetterBases, ["steal", "leave"])
        XCTAssertEqual(table.verb(base: "steal")?.level, "C2", "levels A1–C2 are accepted")
        XCTAssertEqual(table.verb(base: "steal")?.freq, 40)
        XCTAssertEqual(table.verb(base: "leave")?.spokenAs, ["base": "leev"])
        XCTAssertEqual(table.groups.first?.title.es, "Dos iguales")
    }

    func testTheEmptyTableLinksNothing() {
        let empty = IrregularVerbs()
        XCTAssertTrue(empty.verbs.isEmpty)
        XCTAssertNil(empty.resolve("She left.", WordRange(4, 8)))
        XCTAssertNil(empty.base(in: "He stole it.", at: WordRange(3, 8)))
    }

    func testOversizedOrDeepOrBrokenFilesAreRefused() throws {
        XCTAssertThrowsError(try IrregularVerbs.load(Data(repeating: 0x20, count: IrregularVerbs.maxBytes + 1))) {
            XCTAssertEqual($0 as? IrregularVerbsError, .tooLarge)
        }
        let deep = Data((String(repeating: "[", count: 9) + String(repeating: "]", count: 9)).utf8)
        XCTAssertThrowsError(try IrregularVerbs.load(deep)) { XCTAssertEqual($0 as? IrregularVerbsError, .tooDeep) }
        assertRefused(Data("not json".utf8), "not JSON")
        assertRefused(Data("[]".utf8), "not an object")
    }

    func testAnotherSchemaVersionIsRefused() throws {
        XCTAssertThrowsError(try IrregularVerbs.load(table { $0["schemaVersion"] = 2 })) {
            XCTAssertEqual($0 as? IrregularVerbsError, .invalid("schemaVersion 2"))
        }
    }

    func testUnknownAndMissingKeysAreRefused() throws {
        XCTAssertThrowsError(try IrregularVerbs.load(table { $0["extra"] = true })) {
            XCTAssertEqual($0 as? IrregularVerbsError, .malformed("unknown key extra"))
        }
        assertRefused(try table { $0["about"] = nil }, "missing about")
        assertRefused(try table { self.editVerb(&$0) { $0["future"] = ["will steal"] } }, "unknown verb key")
        assertRefused(try table { self.editVerb(&$0) { $0["es"] = nil } }, "missing es")
        assertRefused(try table { self.editVerb(&$0) { $0["homonym"] = ["es": ["x"], "past": ["stealed"]] } }, "homonym without forms")
        assertRefused(try table { self.editHomograph(&$0) { $0["noun"] = nil } }, "noun must be there (null when none)")
        assertRefused(try table { self.editHomograph(&$0) { $0["nounLater"] = ["x"] } }, "unknown homograph key")
        assertRefused(try table { $0["groups"] = [["id": "abb", "example": "x", "title": ["en": "x"]]] }, "title without es")
        assertRefused(try table { $0["groups"] = [["id": "abb", "example": "x", "title": ["en": "x", "es": "x"], "n": 1]] }, "group key")
        assertRefused(try table {
            var context = $0["context"] as? [String: Any] ?? [:]
            context["skip"] = nil
            $0["context"] = context
        }, "missing context list")
        assertRefused(try table {
            var context = $0["context"] as? [String: Any] ?? [:]
            context["adverbs"] = ["slowly"]
            $0["context"] = context
        }, "unknown context list")
        assertRefused(try table { self.editVerb(&$0) { $0["es"] = "robar" } }, "wrong type")
    }

    func testBadFormsMeaningsGroupsAndLevelsAreRefused() throws {
        assertRefused(try table { self.editVerb(&$0) { $0["past"] = ["Stole"] } }, "a form not a–z")
        assertRefused(try table { self.editVerb(&$0) { $0["ing"] = String(repeating: "a", count: 21) } }, "a form over 20 letters")
        assertRefused(try table { self.editVerb(&$0) { $0["past"] = ["stole", "stole"] } }, "repeated past")
        assertRefused(try table { self.editVerb(&$0) { $0["participle"] = [String]() } }, "no participle")
        assertRefused(try table { self.editVerb(&$0) { $0["es"] = [String]() } }, "empty es")
        assertRefused(try table { self.editVerb(&$0) { $0["es"] = [" "] } }, "blank meaning")
        assertRefused(try table { self.editVerb(&$0) { $0["es"] = ["robar\u{202E}"] } }, "invisible formatting")
        assertRefused(try table { self.editVerb(&$0) { $0["group"] = "xyz" } }, "unknown group")
        assertRefused(try table { self.editVerb(&$0) { $0["level"] = "D1" } }, "unknown level")
        assertRefused(try table { self.editVerb(&$0) { $0["spokenAs"] = ["future": "x"] } }, "bad spokenAs slot")
        assertRefused(try table { self.editVerb(&$0) { $0["spokenAs"] = ["past": "sto le"] } }, "spokenAs not a–z")
        assertRefused(try table { self.editVerb(&$0) { $0["freq"] = -1 } }, "negative freq")
        assertRefused(try table { self.editVerb(&$0) { $0["present"] = ["a", "b", "c"] } }, "three present forms")
        assertRefused(try table {
            self.editVerb(&$0) {
                $0["homonym"] = ["es": [String](), "past": ["stealed"], "participle": ["stealed"], "ing": "stealing", "s": "steals"]
            }
        }, "homonym without meanings")
        assertRefused(try table {
            self.editVerb(&$0) { $0["homonym"] = ["es": ["x"], "past": [String](), "participle": ["x"], "ing": "x", "s": "x"] }
        }, "homonym without past")
        assertRefused(try table { $0["groups"] = [["id": "A B", "example": "x", "title": ["en": "x", "es": "x"]]] }, "group id")
        assertRefused(try table { $0["groups"] = [["id": "abb", "example": "", "title": ["en": "x", "es": "x"]]] }, "empty example")
        assertRefused(try table {
            let group: [String: Any] = ["id": "abb", "example": "x", "title": ["en": "x", "es": "x"]]
            $0["groups"] = [group, group]
        }, "duplicate group")
        assertRefused(try table { $0["about"] = String(repeating: "x", count: 4001) }, "about too long")
        assertRefused(try table {
            var context = $0["context"] as? [String: Any] ?? [:]
            context["skip"] = ["Not"]
            $0["context"] = context
        }, "context word not a–z")
    }

    func testConflictingFormsAndHomographsAreRefused() throws {
        let other: [String: Any] = [
            "base": "stale", "past": ["stole"], "participle": ["staled"], "ing": "staling", "s": "stales",
            "group": "abb", "level": "B1", "es": ["x"],
        ]
        assertRefused(try table { $0["verbs"] = ($0["verbs"] as? [[String: Any]] ?? []) + [other] }, "stole leads to two bases")
        let baseAsForm: [String: Any] = [
            "base": "stole", "past": ["stoled"], "participle": ["stoled"], "ing": "stoling", "s": "stoles",
            "group": "abb", "level": "B1", "es": ["x"],
        ]
        assertRefused(try table { $0["verbs"] = ($0["verbs"] as? [[String: Any]] ?? []) + [baseAsForm] }, "a form that is a base")
        assertRefused(try table {
            let verbs = $0["verbs"] as? [[String: Any]] ?? []
            $0["verbs"] = verbs + verbs.prefix(1)
        }, "duplicate base")
        assertRefused(try table {
            let again: [String: Any] = ["form": "left", "noun": "left", "verb": "leave", "rules": [String]()]
            $0["homographs"] = ($0["homographs"] as? [[String: Any]] ?? []) + [again]
        }, "duplicate homograph")
        assertRefused(try table { self.editHomograph(&$0) { $0["verb"] = "zork" } }, "unknown verb")
        assertRefused(try table { self.editHomograph(&$0) { $0["verb"] = "steal" } }, "not a form of that verb")
        assertRefused(try table { self.editHomograph(&$0) { $0["rules"] = ["sometimes"] } }, "unknown rule")
        assertRefused(try table { self.editHomograph(&$0) { $0["rules"] = ["imperative"] } }, "imperative without baseVerb")
        assertRefused(try table { self.editHomograph(&$0) { $0["nounBefore"] = ["Hand"] } }, "a listed word not a–z")
        // Null is how a form that is not a noun says so.
        let noNoun = try IrregularVerbs.load(table { self.editHomograph(&$0) { $0["noun"] = NSNull() } })
        XCTAssertNil(noNoun.homographs["left"]?.noun)
        // A homograph of a regular verb ("lives" → "live") is fine.
        XCTAssertNoThrow(try IrregularVerbs.load(table {
            let lives: [String: Any] = ["form": "lives", "noun": "life", "verb": "live", "rules": ["plural"]]
            $0["homographs"] = ($0["homographs"] as? [[String: Any]] ?? []) + [lives]
        }))
    }

    func testV2FieldsLoadAndAreChecked() throws {
        let loaded = try IrregularVerbs.load(table {
            self.editVerb(&$0) { $0["ipa"] = ["base": "stiːl", "past": "stoʊl"] }
            self.editHomograph(&$0) {
                $0["rules"] = ["participle", "sVerb", "quantifier"]
                $0["nounPhrases"] = [["left", "and", "right"]]
                $0["subjectNounNext"] = ["him"]
            }
        })
        XCTAssertEqual(loaded.verb(base: "steal")?.ipa["past"], "stoʊl")
        XCTAssertEqual(loaded.llBases, ["install"])
        XCTAssertEqual(loaded.homographs["left"]?.nounPhrases, [["left", "and", "right"]])
        XCTAssertEqual(loaded.homographs["left"]?.subjectNounNext, ["him"])
        XCTAssertNil(try IrregularVerbs.load(table()).homographs["left"]?.subjectNounNext, "absent: no condition")
        assertRefused(try table { $0["llBases"] = nil }, "llBases is required")
        assertRefused(try table { self.editVerb(&$0) { $0["ipa"] = ["future": "x"] } }, "unknown ipa slot")
        assertRefused(try table { self.editVerb(&$0) { $0["ipa"] = ["base": "/stiːl/"] } }, "slashes")
        assertRefused(try table { self.editVerb(&$0) { $0["ipa"] = ["base": "STEAL"] } }, "not IPA")
        assertRefused(try table { self.editVerb(&$0) { $0["ipa"] = ["base": String(repeating: "a", count: 41)] } }, "over 40")
        assertRefused(try table { self.editVerb(&$0) { $0["ipa"] = ["base": "e\u{0303}"] } }, "not NFC (ẽ is precomposed)")
        XCTAssertNoThrow(try IrregularVerbs.load(table { self.editVerb(&$0) { $0["ipa"] = ["base": "n\u{0329}"] } }), "a syllabic n")
        for bad in ["stall", "inst", "toll", "leaves", "Install"] {
            assertRefused(try table { $0["llBases"] = [bad] }, "llBase \(bad)")
        }
        assertRefused(try table { $0["llBases"] = ["install", "install"] }, "duplicate llBase")
        assertRefused(try table {
            $0["llBases"] = ["leavell"]
            self.editVerb(&$0) { $0["s"] = "leavell" }
        }, "an llBase that is a form of the table")
        assertRefused(try table { self.editHomograph(&$0) { $0["nounPhrases"] = [["left"]] } }, "one word")
        assertRefused(try table { self.editHomograph(&$0) { $0["nounPhrases"] = [["right", "and", "wrong"]] } }, "without the form")
        assertRefused(try table { self.editHomograph(&$0) { $0["nounPhrases"] = [["a", "b", "c", "d", "left"]] } }, "five words")
        assertRefused(try table { self.editHomograph(&$0) { $0["subjectNounNext"] = ["Him"] } }, "not a–z")
        assertRefused(try table { self.editHomograph(&$0) { $0["rules"] = ["sverb"] } }, "unknown rule")
        assertRefused(try table {
            var context = $0["context"] as? [String: Any] ?? [:]
            context["finiteVerbs"] = nil
            $0["context"] = context
        }, "a v2 context list is required")
    }

    func testIsFormAndIsContextWord() {
        XCTAssertTrue(IrregularVerbs.isForm("stole"))
        XCTAssertFalse(IrregularVerbs.isForm(""))
        XCTAssertFalse(IrregularVerbs.isForm("stolé"))
        XCTAssertTrue(IrregularVerbs.isContextWord("can't"))
        XCTAssertFalse(IrregularVerbs.isContextWord("can'"))
        XCTAssertFalse(IrregularVerbs.isContextWord("'s"))
    }

    // MARK: Derivation

    /// The old hand-written lists (before the table): all of them must still be there.
    private let oldParticiples: Set<String> = [
        "beaten", "become", "been", "begun", "bent", "bitten", "bought", "bound", "broken",
        "brought", "built", "burnt", "burst", "cast", "caught", "chosen", "come", "cost", "crept",
        "cut", "dealt", "done", "drawn", "dreamt", "driven", "drunk", "dug", "eaten", "fallen",
        "fed", "felt", "fled", "flown", "forgiven", "forgotten", "fought", "found", "frozen",
        "given", "gone", "gotten", "grown", "had", "heard", "held", "hidden", "hit", "hung",
        "hurt", "kept", "known", "laid", "lain", "learnt", "led", "left", "lent", "let", "lit",
        "lost", "made", "meant", "met", "mistaken", "overcome", "paid", "put", "quit", "read",
        "ridden", "risen", "run", "said", "sat", "seen", "sent", "set", "shaken", "shed", "shot",
        "shown", "shut", "slept", "sold", "sought", "spent", "spoken", "spread", "stolen", "stood",
        "struck", "stuck", "sung", "swept", "sworn", "swum", "taken", "taught", "thought",
        "thrown", "told", "torn", "understood", "wept", "woken", "won", "worn", "wound", "written",
    ]
    private let oldBaseLike: Set<String> = [
        "become", "burst", "cast", "come", "cost", "cut", "hit", "hurt", "let", "overcome", "put",
        "quit", "read", "run", "set", "shed", "shut", "spread",
    ]
    private let oldBases: Set<String> = [
        "be", "beat", "become", "begin", "bite", "break", "bring", "build", "buy", "catch",
        "choose", "come", "cut", "do", "draw", "drink", "drive", "eat", "fall", "feed", "feel",
        "fight", "find", "fly", "forget", "forgive", "get", "give", "go", "grow", "hang", "have",
        "hear", "hide", "hit", "hold", "hurt", "keep", "know", "lead", "leave", "lend", "let",
        "lie", "lose", "make", "mean", "meet", "pay", "put", "read", "ride", "rise", "run", "say",
        "see", "seek", "sell", "send", "set", "shake", "shoot", "show", "shut", "sing", "sit",
        "sleep", "speak", "spend", "stand", "steal", "stick", "swear", "sweep", "swim", "take",
        "teach", "tear", "tell", "think", "throw", "understand", "wake", "wear", "win", "write",
    ]

    func testDerivedListsKeepTheOldOnesAndAddTheNewForms() {
        let table = IrregularVerbs.shared
        // The shipped table's counts (same in lingleaf-android); a table edit updates them here.
        XCTAssertEqual(table.formToBase.count, 573)
        XCTAssertEqual(table.participles.count, 203)
        XCTAssertEqual(table.baseLikeParticiples.count, 26)
        XCTAssertEqual(table.hadBetterBases.count, 141)
        XCTAssertEqual(table.formToBase["stole"], nil, "\"stole\" is a homograph (a stole is a scarf)")
        XCTAssertEqual(table.formToBase["stolen"], "steal")
        XCTAssertEqual(table.formToBase["learnt"], "learn")
        XCTAssertEqual(table.formToBase["lying"], "lie")
        XCTAssertEqual(table.formToBase["lied"], "lie", "the regular homonym")
        XCTAssertEqual(table.formToBase["hanged"], "hang")
        XCTAssertEqual(table.formToBase["being"], "be")
        XCTAssertNil(table.formToBase["left"])
        XCTAssertFalse(Verbs.irregularParticiples.contains("got"), "\"have got\" means \"have\"")
        XCTAssertTrue(Verbs.irregularParticiples.isSuperset(of: oldParticiples))
        XCTAssertTrue(Verbs.irregularParticiples.isSuperset(of: ["sunk", "shone", "knelt", "lied", "gotten"]))
        XCTAssertTrue(Verbs.baseLikeParticiples.isSuperset(of: oldBaseLike.union(["come", "read", "bet"])))
        XCTAssertTrue(Verbs.irregularBases.isSuperset(of: oldBases))
        XCTAssertFalse(Verbs.isBase("light"), "mostly a noun: \"had better light\" is ordinary")
        XCTAssertTrue(Verbs.isBase("freeze"))
        XCTAssertTrue(Verbs.isParticiple("travelled"), "-ll: travelled → travel")
    }
}

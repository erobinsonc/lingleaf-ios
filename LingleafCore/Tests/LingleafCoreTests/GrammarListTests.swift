import XCTest
@testable import LingleafCore

/// The Grammar list (SPEC.md S20, S21): its layout, "Recent", and the language of the rule text.
final class GrammarListTests: XCTestCase {
    private var grammar: GrammarRules { GrammarRules.shared }
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Layout

    func testTheLayoutChangesAtTwentySixRules() {
        XCTAssertEqual(GrammarListLayout.layout(ruleCount: 0), .a)
        XCTAssertEqual(GrammarListLayout.layout(ruleCount: 25), .a)
        XCTAssertEqual(GrammarListLayout.layout(ruleCount: 26), .b)
        XCTAssertEqual(GrammarListLayout.layout(ruleCount: 200), .b)
        XCTAssertEqual(GrammarListLayout.layout(ruleCount: grammar.rules.count), .a, "wave 1 has 15 rules")
    }

    func testTheSectionsFollowTheFileAndSortEachCategoryByLevel() throws {
        let sections = GrammarListLayout.sections(in: grammar)
        XCTAssertEqual(sections.map(\.category.id), grammar.categories.map(\.id), "categories in file order")
        XCTAssertEqual(sections.flatMap(\.rules).count, grammar.rules.count, "every rule once")
        for section in sections {
            let levels = section.rules.map { GrammarLevel.rank($0.level) }
            XCTAssertEqual(levels, levels.sorted(), "\(section.category.id): levels never decrease")
            XCTAssertTrue(section.rules.allSatisfy { $0.category == section.category.id })
        }
        let firsts = try sections.map { GrammarLevel.rank(try XCTUnwrap($0.rules.first).level) }
        XCTAssertEqual(firsts, firsts.sorted(), "the first rule of each category is not harder than the first of the next")
    }

    func testRulesOfOneLevelKeepTheirFileOrder() {
        let file = grammar.rules(in: "verbs").map(\.id)
        let sorted = GrammarListLayout.sorted(grammar.rules(in: "verbs"))
        for level in ["A1", "A2", "B1"] {
            let expected = grammar.rules(in: "verbs").filter { $0.level == level }.map(\.id)
            XCTAssertEqual(sorted.filter { $0.level == level }.map(\.id), expected)
        }
        XCTAssertEqual(Set(file), Set(sorted.map(\.id)))
        XCTAssertEqual(GrammarListLayout.sorted([]), [])
    }

    func testACategoryWithoutRulesIsLeftOut() {
        let empty = GrammarRules(categories: grammar.categories, rules: grammar.rules.filter { $0.category == "verbs" })
        XCTAssertEqual(GrammarListLayout.sections(in: empty).map(\.category.id), ["verbs"])
    }

    // MARK: Recent

    /// Rules a, b, c, d in file order with these `opened` values (nil: never opened).
    private func recent(_ opened: [Int?], limit: Int = 3) -> [String] {
        let ids = ["a", "b", "c", "d"]
        var base = grammar.rules[0]
        var rules: [GrammarRule] = []
        for id in ids.prefix(opened.count) {
            base = GrammarRule(
                id: id, category: base.category, level: base.level, title: base.title, lines: base.lines, examples: base.examples,
                contrast: base.contrast, note: nil, spanish: nil, aliases: base.aliases, books: base.books, practice: base.practice
            )
            rules.append(base)
        }
        var entries: [String: RuleProgress] = [:]
        for (index, value) in opened.enumerated() {
            var entry = RuleProgress()
            entry.opened = value
            entries[ids[index]] = entry
        }
        let progress = GrammarProgress(rules: entries)
        let file = GrammarRules(categories: grammar.categories, rules: rules)
        return GrammarRecent.rules(progress: progress, in: file, limit: limit).map(\.id)
    }

    func testRecentVectorsOfTheSpec() {
        XCTAssertEqual(recent([100, 100, 100, 99]), ["a", "b", "c"], "equal values: the earlier rule in the file first")
        XCTAssertEqual(recent([99, 100, 100, 100]), ["b", "c", "d"])
        XCTAssertEqual(recent([100, 300, 200, 50]), ["b", "c", "a"])
        XCTAssertEqual(recent([100, 300, nil, nil]), [], "fewer than 3 opened: no Recent")
        XCTAssertEqual(recent([100, 300, 200, nil]), ["b", "c", "a"], "exactly 3 opened")
        XCTAssertEqual(recent([nil, nil, nil, nil]), [])
        XCTAssertEqual(recent([100, 300, 200, 50], limit: 1), ["b"])
        XCTAssertEqual(recent([100, 300, 200, 50], limit: 0), [])
    }

    func testRecentIgnoresRulesThatAreNotInTheBundledFileAndReflectsOpeningOrder() throws {
        var progress = GrammarProgress()
        let ids = grammar.rules.prefix(4).map(\.id)
        XCTAssertEqual(GrammarRecent.rules(progress: progress, in: grammar), [])
        for (index, id) in ids.enumerated() { progress.opened(id, at: moment.addingTimeInterval(Double(index))) }
        progress.opened("not-a-rule", at: moment.addingTimeInterval(99))
        XCTAssertEqual(GrammarRecent.rules(progress: progress, in: grammar).map(\.id), [ids[3], ids[2], ids[1]])
        progress.opened(ids[0], at: moment.addingTimeInterval(10))
        XCTAssertEqual(GrammarRecent.rules(progress: progress, in: grammar).map(\.id), [ids[0], ids[3], ids[2]])
        XCTAssertEqual(GrammarProgress.recentCount, 3)
    }

    // MARK: Language of the rule text

    func testTheLanguageVectorsOfTheSpec() {
        func effective(_ setting: Any?, _ translation: String, _ interface: String) -> GrammarLanguage {
            GrammarLanguage.effective(setting: setting, translationLanguage: translation, interfaceLanguage: interface)
        }
        XCTAssertEqual(effective(true, "en", "en"), .es)
        XCTAssertEqual(effective(false, "es", "es"), .en)
        XCTAssertEqual(effective(nil, "es", "en"), .es)
        XCTAssertEqual(effective(nil, "fr", "en"), .en)
        XCTAssertEqual(effective(nil, "en", "en"), .en)
        XCTAssertEqual(effective(nil, "en", "es"), .es)
        XCTAssertEqual(effective(nil, "es", "es"), .es)
        XCTAssertEqual(effective(nil, "es", "fr"), .en)
        XCTAssertEqual(effective(nil, "fr", "de"), .en)
        // Not a boolean is absent.
        XCTAssertEqual(effective("true", "es", "en"), .es)
        XCTAssertEqual(effective("yes", "en", "es"), .es)
        XCTAssertEqual(effective(1, "en", "en"), .en)
        XCTAssertEqual(effective(0, "es", "en"), .es)
        XCTAssertEqual(effective(1.0, "en", "en"), .en)
        XCTAssertEqual(effective(NSNull(), "es", "fr"), .en)
        XCTAssertEqual(effective([1, 2], "en", "es"), .es)
        XCTAssertEqual(effective(["a": 1], "es", "en"), .es)
    }

    func testARegionOrACaseInALanguageCodeDoesNotMatter() {
        func effective(_ translation: String?, _ interface: String) -> GrammarLanguage {
            GrammarLanguage.effective(setting: nil, translationLanguage: translation, interfaceLanguage: interface)
        }
        XCTAssertEqual(effective("es-419", "en-US"), .es)
        XCTAssertEqual(effective("ES", "EN"), .es)
        XCTAssertEqual(effective("pt_BR", "es_CO"), .es)
        XCTAssertEqual(effective(nil, "en"), .en, "no translation language yet")
        XCTAssertEqual(effective("es", "pt-BR"), .en)
    }

    func testTheChoiceIsStoredAsABooleanAndIsNeverAbsentAgain() {
        XCTAssertEqual(GrammarLanguage.settingKey, "grammarInSpanish")
        XCTAssertTrue(GrammarLanguage.es.stored)
        XCTAssertFalse(GrammarLanguage.en.stored)
        // (absent, translation es, interface en) selects Español; choosing English stores false and shows English; choosing
        // Español stores true; the stored value then wins over any language.
        XCTAssertEqual(GrammarLanguage.effective(setting: nil, translationLanguage: "es", interfaceLanguage: "en"), .es)
        func effective(_ setting: Any?, _ translation: String) -> GrammarLanguage {
            GrammarLanguage.effective(setting: setting, translationLanguage: translation, interfaceLanguage: "en")
        }
        XCTAssertEqual(effective(GrammarLanguage.en.stored, "es"), .en)
        XCTAssertEqual(effective(GrammarLanguage.es.stored, "fr"), .es)
        XCTAssertEqual(GrammarText(en: "a", es: "b").text(for: GrammarLanguage.es.rawValue), "b")
    }
}

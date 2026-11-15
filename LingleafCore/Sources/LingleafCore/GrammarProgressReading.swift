import Foundation

/// Reading `tips.json` back (SPEC.md, Grammar rules data, Progress). The file is the learner's own but may come
/// from a restored backup or a damaged disk, so it is read bounded and tolerantly: whatever cannot be right is
/// dropped or brought into range, and nothing in it can crash the app.
extension GrammarProgress {
    /// Reads saved progress. A file over `maxBytes`, that is not UTF-8 (after an optional UTF-8 BOM the first byte that
    /// is not white space must be `{`; no 0x00 byte; no invalid sequence), holding a raw control character inside a
    /// string, nested more than 8 containers deep (the root object is depth 1; counted on the raw bytes outside
    /// strings), that cannot be parsed or that holds another schema gives empty progress, as does a `now` that is
    /// not a number. Inside it: a key outside the schema is dropped; a rule or item id that is not 1-40 characters
    /// of a-z, 0-9 and hyphen, or not in the bundled rules (`known`: the rule ids with their item ids,
    /// `GrammarRules.knownItems`), is dropped; a day number (and `opened`, and `schema`) is an integer only when
    /// written as an integer literal (`GrammarJSON`: `5.0` and `1e1` are not), a day must be 0 to today (`due`: to
    /// today + 31), else it is dropped, before any date conversion; a value of the wrong type, or null, reads as
    /// 0 (counts), false (flags) or none (days, optional fields); `opened` must lie between 2020-01-01 and `now`
    /// (inclusive), else the entry keeps no time; counts are whole numbers or decimals (truncated toward zero),
    /// brought into 0...1000 and the box into 0...5 (saturating, never overflowing); rights never above attempts,
    /// missed never above seen; `lastPair` must be 2 different items of the rule; `rightDays` is read in file order,
    /// an entry that is invalid or does not fit is skipped and the next tried, until 2 are kept (different days,
    /// different items). A rule, item or `rightDays` entry that is not an object is dropped alone. At most 200
    /// entries (the ones opened longest ago go first; opened absent counts as 0; ties: the greater id is kept)
    /// and 12 items each.
    public static func decode(
        _ data: Data, known: [String: Set<String>], now: Date = Date(), in zone: TimeZone = .current
    ) -> GrammarProgress {
        // The whole file is validated first: on some Foundation versions `JSONDecoder` parses lazily and
        // traps (not throws) on a bad byte inside a part it only reaches while decoding tolerantly.
        let seconds = now.timeIntervalSince1970
        guard seconds.isFinite, data.count <= maxBytes, let text = utf8Object(data), JSONGuard.isShallow(text, maxDepth: 8),
              (try? JSONSerialization.jsonObject(with: text)) is [String: Any],
              let clean = GrammarJSON.scrubbed(text, integerKeys: integerKeys, policy: .tolerant),
              let file = try? JSONDecoder().decode(SavedFile.self, from: clean), file.schema == schemaVersion
        else { return GrammarProgress() }
        let limits = Limits(today: GrammarDay.number(of: now, in: zone), now: Int(min(max(seconds, 0), 1e15)))
        var result: [String: RuleProgress] = [:]
        for (id, saved) in file.rules where GrammarRules.isSlug(id) {
            guard let items = known[id], let saved = saved.value else { continue }
            result[id] = saved.progress(items: items, limits)
        }
        // Over the cap, the entries opened longest ago go first.
        let kept = result.sorted { ($0.value.opened ?? 0, $0.key) > ($1.value.opened ?? 0, $1.key) }.prefix(maxEntries)
        return GrammarProgress(rules: Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) }))
    }

    /// Members that hold a whole number read as an integer only when written as an integer literal.
    private static let integerKeys: Set<String> = ["schema", "opened", "day", "due", "tryMiss"]

    /// The file without an optional UTF-8 BOM, or nil when it is not UTF-8 that starts as a JSON object: the first
    /// byte that is not white space is `{`, there is no 0x00 byte (so no UTF-16 or UTF-32) and no invalid sequence.
    private static func utf8Object(_ data: Data) -> Data? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let first = bytes.first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        guard first == 0x7B, !bytes.contains(0), Data(String(decoding: bytes, as: UTF8.self).utf8) == bytes else { return nil }
        return Data(bytes)
    }

    fileprivate struct Limits {
        let today: Int
        let now: Int
    }

    /// A value that reads as nil instead of failing the whole file when it has the wrong shape.
    fileprivate struct Tolerant<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    fileprivate struct SavedFile: Decodable {
        let schema: Int
        let rules: [String: Tolerant<SavedRule>]
    }

    fileprivate struct SavedRule: Decodable {
        let opened: Int?
        let attempts: Int
        let rights: Int
        let inReview: Bool
        let pretestDone: Bool
        let pretestSkipped: Bool
        let lastPair: [String]?
        let rightDays: [Tolerant<SavedRightDay>]
        let items: [String: Tolerant<SavedItem>]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            opened = try? c.decode(Int.self, forKey: .opened)
            attempts = c.count(.attempts)
            rights = c.count(.rights)
            inReview = c.flag(.inReview)
            pretestDone = c.flag(.pretestDone)
            pretestSkipped = c.flag(.pretestSkipped)
            lastPair = try? c.decode([String].self, forKey: .lastPair)
            rightDays = (try? c.decode([Tolerant<SavedRightDay>].self, forKey: .rightDays)) ?? []
            items = (try? c.decode([String: Tolerant<SavedItem>].self, forKey: .items)) ?? [:]
        }

        enum Key: String, CodingKey { case opened, attempts, rights, inReview, pretestDone, pretestSkipped, lastPair, rightDays, items }

        func progress(items itemIDs: Set<String>, _ limits: Limits) -> RuleProgress {
            var result = RuleProgress()
            if let opened, opened >= GrammarProgress.earliest, opened <= limits.now { result.opened = opened }
            result.attempts = attempts
            result.rights = min(rights, attempts)
            result.inReview = inReview
            result.pretestDone = pretestDone
            result.pretestSkipped = pretestSkipped
            if let pair = lastPair, pair.count == 2, pair[0] != pair[1], pair.allSatisfy(itemIDs.contains) {
                result.lastPair = ItemPair(pair[0], pair[1])
            }
            for case let saved? in rightDays.map(\.value) {
                let entry = RightDay(day: saved.day, item: saved.item)
                guard itemIDs.contains(entry.item), entry.day >= 0, entry.day <= limits.today else { continue }
                if GrammarProgress.accepts(entry, after: result.rightDays) { result.rightDays.append(entry) }
            }
            let kept = items.filter { GrammarRules.isSlug($0.key) && itemIDs.contains($0.key) }.sorted { $0.key < $1.key }
            for (id, saved) in kept.prefix(GrammarProgress.maxItems) {
                if let saved = saved.value { result.items[id] = saved.progress(limits) }
            }
            return result
        }
    }

    fileprivate struct SavedRightDay: Decodable {
        let day: Int
        let item: String
    }

    fileprivate struct SavedItem: Decodable {
        let box: Int
        let due: Int?
        let seen: Int
        let missed: Int
        let tryMiss: Int?
        let reviewed: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            box = min(c.count(.box), GrammarProgress.maxBox)
            due = try? c.decode(Int.self, forKey: .due)
            seen = c.count(.seen)
            missed = c.count(.missed)
            tryMiss = try? c.decode(Int.self, forKey: .tryMiss)
            reviewed = c.flag(.reviewed)
        }

        enum Key: String, CodingKey { case box, due, seen, missed, tryMiss, reviewed }

        func progress(_ limits: Limits) -> ItemProgress {
            var result = ItemProgress()
            result.box = box
            result.seen = seen
            result.missed = min(missed, seen)
            // Comparisons, not ranges: a clock before 2001 makes `today` negative and a range would trap.
            if let due, due >= 0, due <= limits.today + GrammarProgress.maxDueAhead { result.due = due }
            if let tryMiss, tryMiss >= 0, tryMiss <= limits.today { result.tryMiss = tryMiss }
            result.reviewed = reviewed
            return result
        }
    }
}

private extension KeyedDecodingContainer {
    /// A count brought into 0...1000: a whole number or a decimal, however large (saturating); anything else is 0.
    func count(_ key: Key) -> Int {
        let limit = GrammarProgress.maxCount
        if let whole = try? decode(Int.self, forKey: key) { return min(max(whole, 0), limit) }
        if let decimal = try? decode(Double.self, forKey: key), decimal.isFinite { return Int(min(max(decimal, 0), Double(limit))) }
        return 0
    }

    /// A true/false; anything else is false.
    func flag(_ key: Key) -> Bool { (try? decode(Bool.self, forKey: key)) ?? false }
}

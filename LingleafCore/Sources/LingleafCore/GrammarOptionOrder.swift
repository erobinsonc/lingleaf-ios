import Foundation

/// The order in which the options of a practice item are shown (SPEC.md, Grammar rules data, "Option order"):
/// shuffled the same way on both platforms, from the item's id and how often it has been shown. `answer` and
/// `feedback` always refer to the file's order; position `k` of the returned order shows the file's option
/// `order[k]`.
public enum GrammarOptionOrder {
    /// The order for an item shown `seen` times before this time (0 the first time): the file's order for an item
    /// with `fixedOrder` (a, an, the; in, on, at), else the shuffle.
    public static func order(for item: PracticeItem, seen: Int) -> [Int] {
        item.fixedOrder ? Array(item.options.indices) : order(itemID: item.id, seen: seen, count: item.options.count)
    }

    /// The shuffle: seed = FNV-1a 64-bit of the UTF-8 bytes of `<id>#<seen>`, generator SplitMix64 started at the
    /// seed, Fisher-Yates from the end with `j = next() mod (i + 1)` (unsigned). A negative `seen` counts as 0.
    public static func order(itemID: String, seen: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var generator = SplitMix64(seed: fnv1a("\(itemID)#\(max(seen, 0))"))
        var order = Array(0..<count)
        for index in stride(from: count - 1, to: 0, by: -1) {
            order.swapAt(index, Int(generator.next() % UInt64(index + 1)))
        }
        return order
    }

    /// FNV-1a, 64 bit: offset 0xcbf29ce484222325, prime 0x100000001b3, each byte XORed and then multiplied.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

    /// SplitMix64: state += 0x9E3779B97F4A7C15, then two xor-shift-multiply rounds, all wrapping at 64 bits.
    struct SplitMix64 {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

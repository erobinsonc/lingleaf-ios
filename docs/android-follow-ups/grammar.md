# Android mirror: Grammar tab (target 0.5.0)

Copy SPEC.md wholesale from iOS at merge time (S20-S25 and "Grammar rules data" are shared logic). This is what has to match.

## Files that must be identical in both repos
- `grammar-rules.json` (15 rules, 101 items, wave 1), byte for byte; the SHA-256 in SPEC.md is the gate. Bundled in the core module next to `irregular-verbs.json`.
- Item field `fixedOrder` (optional boolean) is part of the schema: the decoder refuses a non-boolean.

## Logic to mirror and test with the same vectors
- **Option order** (SPEC "Option order"): FNV-1a 64-bit of `<item id>#<seen>` seeds SplitMix64; Fisher-Yates from the end with `next() mod (i + 1)` (unsigned). Use unsigned 64-bit arithmetic with wrapping (Kotlin `ULong`, which wraps; `Long` division and `%` are signed: do not use them). The six vectors in SPEC.md and the two hash vectors are the test. `answer` and `feedback` stay in file order; items with `fixedOrder` are never shuffled.
- **Practiced**: 2 right answers on 2 different review days (day = days since 2001-01-01 after shifting the clock back 4 hours), pretest excluded, stored as `rightDays` (at most 2 distinct days) in `tips.json` (schema 2); "In Review" overrides.
- **Progress file**: cap 384 KB (the file of rules stays 256 KB), bounded on read as in SPEC; if the rules did not load, the file is not written.
- **Search**: lower-case, strip accents, split on non-letters, every query word must prefix a word of title, rule lines, examples or aliases in both languages.
- **Settings**: one optional boolean `grammarInSpanish` (absent or any other type = default: `es` when the translation language is Spanish and the interface is English, else the interface language, `en` for any other). The rule page toggle names the OTHER language ("Show in English" while Spanish is shown) and writes it; it applies to every rule, notes and feedback.

## Behaviour to mirror (Compose)
- Tab "Grammar" / "Gramática", fifth tab between Words and Settings (a lightbulb icon).
- Try it: pretest item first time with "Skip to the rule"; later 3 items (never seen or missed first, items above the rule's level never drawn); at most 2 rounds (6 items) a rule a day, then "You've finished today's practice for this rule. Try another rule, or come back tomorrow." with "See other rules"; immediate feedback with icon and words (colour is never the only signal); after a right answer only the chosen option is explained ("Why not the others?" one tap away); "Not sure" counts as wrong. "Add to Review" is also offered once, at the end of the first completed Try it.
- Review (words first): the 20-item cap is shared; rule items take only the leftover slots, at most 6 a session (3 rules x 2); an item that does not fit waits without losing its box; each item is judged on its own; an item missed in Try it comes first in the next Review visit; mixed with words, never first. No verb Review items in 0.5.0.
- "In your books" is not shown in 0.5.0 and nothing stands in its place.
- No streaks, no percentages, no message about missed days. Fully offline (everything bundled); "Translation isn't available offline." only when an example translation is asked for in another language with no model.

## Android UI tests to write (mirror the iOS ones)
Option order is the SPEC's for a sample item and stable between launches; a `fixedOrder` item keeps the file's order; Try it feedback shows the explanation of the chosen option only after a right answer; the daily limit message after 2 rounds; Review leaves the words' slots alone; the language toggle is remembered.

## Added after the validator review (SPEC "Day", "Review selection", "Progress")
- **`.gitattributes`**: keep `*.json -text` on Android too, so no line-ending conversion changes the bytes (the SHA-256 gate).
- **Search**: lower-case with `lowercase(Locale.ROOT)`, NFD and drop combining marks, split on anything that is not Unicode category L.
- **SplitMix64** starts with `state = seed` (the FNV-1a hash). The vector `("do-does-did-1", 0, 3)` is `[2, 0, 1]` (3 options).
- **Day tests**: local 2001-01-02 03:59 -> 0; 04:00 -> 1; 2001-01-01 02:00 -> -1 (never stored); use the device time zone (test with two zones and a DST change).
- **rightDays clamp tests**: day numbers outside 0...today and `due` outside 0...today+31 are dropped before any date conversion; counts and box clamped with saturating arithmetic; unparseable JSON, more than 8 nested containers, or a file over 384 KB gives empty progress, never a crash; unknown keys and ids not in the rules are dropped; a non-boolean `grammarInSpanish` counts as absent.
- **Practiced boundary vectors** (entries `(day, item)`): [(5,A)] no; [(5,A),(5,B)] no; [(5,A),(6,A)] no; [(5,A),(6,B)] yes.
- **Review selection vectors** (placement after word number ceil((j+1) x W / (m+1))): W=10,m=6 -> 2,3,5,6,8,9; W=3,m=2 -> 1,2; W=1,m=2 -> 1,1; W=0,m=4 -> 0,0,0,0. Rules by (oldest due day, file position), at most min(3, G/2); items by (tryMiss flag from an earlier day, oldest due, file position); never the same pair as the last visit when a third item is due.
- **Copy**: "You've finished today's practice for this rule. Try another rule, or come back tomorrow." with "See other rules"; the end-of-round button is "Practice"; "Try it" only the first time; "That's okay. Right: ..." for "Not sure".
- **Newer rules (second review):** items with `textLang: "es"` (a Spanish sentence as the stimulus) are drawn only when the translation or interface language is Spanish; every rule keeps at least 3 items without it. A rule hides until the first pretest answer or Skip. A repeat after a miss comes at least 3 cards later. After "Add to Review" the button reads "Remove from Review" (Undo restores boxes and due days); "In Review" is only the row state. The Review end screen says "N grammar items are waiting for the next session." (only when some wait). Heading of the Spanish line: "If you speak Spanish" / "Si hablas español". `lastPair` and `waited` are in the progress schema. At most 1 new rule per session; a second new rule is skipped and the next rule takes its place. Selection vectors (today = day 6): rules R1 (new, due 8, pos 3), R2 (new, due 9, pos 1), R3 (due 10, pos 0), R4 (due 11, pos 2) at G=6 -> R1, R3, R4; items a (due 5, pos 2), b (due 5, pos 1), c (due 9, pos 3, tryMiss 4) -> [c, b]; with lastPair {c, b} -> [c, a]; with c's tryMiss 6 and c not due -> [b, a].

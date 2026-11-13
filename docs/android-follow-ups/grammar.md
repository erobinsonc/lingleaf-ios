# Android mirror: Grammar tab (target 0.5.0)

Copy SPEC.md wholesale from iOS at merge time (S20-S25 and "Grammar rules data" are shared logic). This is what has to match.

## Files that must be identical in both repos
- `grammar-rules.json` (15 rules, 98 items, wave 1), byte for byte; the SHA-256 in SPEC.md is the gate. Bundled in the core module next to `irregular-verbs.json`.
- Item field `fixedOrder` (optional boolean) is part of the schema: the decoder refuses a non-boolean.

## Logic to mirror and test with the same vectors
- **Option order** (SPEC "Option order"): FNV-1a 64-bit of `<item id>#<seen>` seeds SplitMix64; Fisher-Yates from the end with `next() mod (i + 1)` (unsigned). Use unsigned 64-bit arithmetic with wrapping (Kotlin `ULong`, which wraps; `Long` division and `%` are signed: do not use them). The six vectors in SPEC.md and the two hash vectors are the test. `answer` and `feedback` stay in file order; items with `fixedOrder` are never shuffled.
- **Practiced**: 2 right answers on 2 different review days (day = days since 2001-01-01 after shifting the clock back 4 hours), pretest excluded, stored as `rightDays` (at most 2 distinct days) in `tips.json` (schema 2); "In Review" overrides.
- **Progress file**: cap 384 KB (the file of rules stays 256 KB), bounded on read as in SPEC; if the rules did not load, the file is not written.
- **Search**: lower-case, strip accents, split on non-letters, every query word must prefix a word of title, rule lines, examples or aliases in both languages.
- **Settings**: one optional value `grammarInSpanish` (absent = default: Spanish when the translation language is Spanish and the interface is English). The rule page toggle writes it; it applies to every rule.

## Behaviour to mirror (Compose)
- Tab "Grammar" / "Gramática", fifth tab between Words and Settings (a lightbulb icon).
- Try it: pretest item first time with "Skip to the rule"; later 3 items (never seen or missed first, items above the rule's level never drawn); at most 2 rounds (6 items) a rule a day, then "Enough for today. Come back tomorrow."; immediate feedback with icon and words (colour is never the only signal); after a right answer only the chosen option is explained ("Why not the others?" one tap away); "Not sure" counts as wrong. "Add to Review" is also offered once, at the end of the first completed Try it.
- Review (words first): the 20-item cap is shared; rule items take only the leftover slots, at most 6 a session (3 rules x 2); an item that does not fit waits without losing its box; each item is judged on its own; an item missed in Try it comes first in the next Review visit; mixed with words, never first. No verb Review items in 0.5.0.
- "In your books" is not shown in 0.5.0 and nothing stands in its place.
- No streaks, no percentages, no message about missed days. Fully offline (everything bundled); "Translation isn't available offline." only when an example translation is asked for in another language with no model.

## Android UI tests to write (mirror the iOS ones)
Option order is the SPEC's for a sample item and stable between launches; a `fixedOrder` item keeps the file's order; Try it feedback shows the explanation of the chosen option only after a right answer; the daily limit message after 2 rounds; Review leaves the words' slots alone; the language toggle is remembered.

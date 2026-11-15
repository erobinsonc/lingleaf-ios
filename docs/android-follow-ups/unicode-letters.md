<!-- Kept in the repo so it isn't lost: what lingleaf-android must mirror from the Unicode-letters work
     (iOS PRs #52 and #63) when Android resumes. Remove this file once Android has it. -->

# Android mirror notes — Unicode letters (iOS PR #52 and its follow-up)

SPEC.md Shared logic is the contract (this repo's SPEC.md, "Shared logic", is the single source). Android is paused; when it resumes:

- Words: `(?:\p{L}\p{M}{0,4}+)++(?:['’](?:\p{L}\p{M}{0,4}+)++)*+` (Java supports possessive quantifiers; {0,4} counts code points).
  ZWNJ/ZWJ (Cf) are not letters or marks: they end a word.
- Keys: Java's `toLowerCase` applies the final-sigma rule ("ΟΔΟΣ" → "οδος"): lower-case each code point on its own
  (`String(codePoint).lowercase(Locale.ROOT)` is fine for one character; "İ" → "i̇" U+0069 U+0307), ’ → ', compose with
  `Normalizer.NFC` when any char is non-ASCII, then cut to 600 UTF-16 units with the cluster rule. ONE `key()` is used for every
  id (save, undo, translate, delete, review, setLearned, marking, group search) and for the reading's base before a look-up.
- English rules (base-form endings, irregular-verb table, verb-or-noun rule) apply to ASCII words only; an accented word is its
  own only key and reads as an ordinary word, or as a name when capitalised.
- "Capitalised" = first CODE POINT has the Unicode Uppercase property (`Character.isUpperCase(codePoint)`; a titlecase letter such as "ǅ" is not) and the rest has none,
  unless the word is one character or has an apostrophe; a name (capitalised in mid-sentence) also has a lower-case letter, so
  "I", "A", "NASA" are not names.
- Dictionary: `^\p{IsLatin}(?:\p{IsLatin}|\p{M}|['’])*\z`, ≤ 50 UTF-16 units on the key ("cat\n" is not looked up).
- Address text: UTF-8 percent-encoding, only A-Z a-z 0-9 literal, uppercase hex, space = %20 (`URLEncoder` gives `+`: custom
  encoder). A lone surrogate becomes U+FFFD (%EF%BF%BD) — `String.getBytes(UTF_8)` would give `?`: use a REPLACE encoder with
  "\uFFFD". Gutenberg search is cut to 200 units first: `search("Les Misérables 東京")` →
  `search=Les%20Mis%C3%A9rables%20%E6%9D%B1%E4%BA%AC`; dictionary "café" → `caf%C3%A9`.
- Cuts: up to 6 units back, never below start+1; continuation = trail surrogate, Mn/Mc/Me (BMP), U+FE00–FE0F, ZWJ and the unit
  after it. Residual: supplementary-plane marks.
- Sentence ends also `[。！？؟]+` plus closing marks (`"` `”` `’` `)` `]`, and 」』 after the full-width marks), no space needed.
- Import / saved sentence: strip Cf except ZWNJ/ZWJ (LRM, RLM, ALM, tag characters included), BEFORE any cut (strip, then cut at
  600); `openBook` strips books stored earlier and fixes `paragraphCount` and progress. Cf is the platform's Unicode tables (Swift stdlib
  on iOS, the Android API level's on Android): a residual. Cf also includes drawn Arabic signs (U+0600–0605, U+06DD, U+070F,
  U+0890–0891, U+08E2): they are stripped, said so in the SPEC.
- `occurrences(of: group)` searches the sentence as shown (case-insensitive, canonical equivalence) and returns offsets in it.
- The stories PR: the new stories DO contain non-ASCII letters (Sofía, Joaquín, Gül, São Paulo…); the currently bundled three do not.
- Tests: copy UnicodeWordsTests cases (names, NFC/NFD, 6 marks, naïve2, Jean-Luc, dogs', Chinese with 。, 』 case, ZWNJ,
  ΟΔΟΣ/İ keys, "cat\n", 50/51 letters, long key everywhere incl. answerReview/setLearned/deleteWord, strip format, old book
  opened, lone surrogate, capitalised/name, reading base "CAFE\u0301", linear 400k units < 10 s).

## openBook (iOS PR #63 follow-up)
- `Book.paragraphCount` is a `var` with an internal setter (was `val`/`let`), so the count can follow a stripped book.
- If the book's text cannot be read (null): return no paragraphs and change NOTHING (no count, no place, no lastOpenedAt, no save).
- Strip once: if `stripFormat(text) != text`, write the stripped text back, re-read it to confirm, and only then set the count to
  the new paragraph count and move the place back by the number of OLD paragraphs (split of the unstripped text) before the place
  that were only format characters (`min(max(place - removed, 0), max(count - 1, 0))`). If the write is not confirmed, show the
  stripped paragraphs and leave count and place alone (the next open tries again). If nothing is stripped, count and place are not touched.
- Sentence ends (regex, both platforms): `(?<![.!?])[.!?]++["”’)\]]*+(?=\s|$)|[。！？؟]++["”’)\]」』]*+`.

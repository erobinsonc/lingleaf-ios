# Android mirror: iOS UX follow-ups after 0.3.0 (PR #56)

SPEC.md changed in S3, S7, S18, S11 and the legal-notices bullet (the iOS diff is the text to copy).
Shared data and logic that must stay identical in both repos:

1. `irregular-verbs.json` (byte-identical):
   - New optional homograph field `nounEs` (1-2 Spanish groups, same text rules as `homonym.nounEs`) on every homograph
     with a noun except lead, leads, tear, tears (their sense depends on their sound). The forms of one noun agree
     (lives/leaves use life/leaf, wind/winds). Loader: optional key, "meanings without a noun" refused,
     `isSpanishMeanings`, forms of one noun must agree.
   - `lead`'s second `before` rule (/liːd/) gains: detective, investigator, counsel, attorney, developer, designer,
     engineer, researcher, author, negotiator, vocalist, dancer, performer, scientist, pilot.
   - `tear` and `tears`: the first `near` /tɪr/ rule gains "voice".
2. `tableMeaning(.noun, base)` = the twin's `nounEs`, else the homograph noun's `nounEs` (`homographNounEs`). Corrected
   nouns and unsure rows get their Spanish meaning from the table (tests changed: "left" -> "izquierda" without waiting).
3. `nounIPARule`: first matching rule as before, but when it matched only by `near` words and another rule with a
   different IPA also matches only by `near` words, there is no IPA.
4. Tests: RoundFourTests (`testAHomographsNounHasItsSpanishMeaningInTheTable`,
   `testWordsAroundItThatPointToTwoSoundsProveNeither...`, four new refusal cases), CorrectionsTests
   (`testACorrectedNounWithoutATableMeaningWaitsForItsTranslation`, changed first test), SensesTests
   (`testSavedReadingsGetTheirMeaningsFromTheTableOrTheTranslator` with a "tear" word).

UI behaviour to mirror (Compose):
- Word card: one order for both variants: word + IPA, translation + language button, sentence + translation +
  "Read from here", readings (unsure only), definition limited to 3 lines with "More"/"Más" (accessibility label
  "Show the full definition"/"Mostrar la definición completa"). The unsure card opens at its content's height and can be
  dragged to full; accessibility text sizes open full height.
- Offline unsure rows: if any row lacks its meaning, show none.
- Undo/confirmation snackbar: minimum height 52dp with or without the Undo action.
- Review: the finished screen's button is "Back to Words"/"Volver a Palabras" (was "Done"/"Listo"); at accessibility
  sizes a word saved unsure shows the sentence first and the readings after; soft fade above the fixed answers.
- Words: "Fixed"/"Corregida" tag on rows whose spelling a still-open correction ended on.
- Settings > About > Privacy policy: Custom Tab; the Spanish app opens
  `PRIVACY.md#política-de-privacidad-de-lingleaf-resumen-en-español` (percent-encoded).
- #14 (maintainer decision): About says "Recommended books are public domain worldwide." ("Los libros recomendados son
  de dominio público en todo el mundo."); the US-specific notice ("Project Gutenberg books are public domain in the US.
  Elsewhere, check your country's laws.") appears only under Discover's search results.
- Reader performance (found with the iOS UI tests): a fast flick in the reader kept the app busy because the set of
  visible paragraphs was view state written on every visibility change. Keep it out of observed state (Compose: a plain
  mutable set, not `mutableStateOf`) and check that a fling leaves the UI idle.
- Strings added: "Back to Words", "Fixed", "More", "Show the full definition", "Recommended books are public domain
  worldwide."; removed: "Done".

Not done: item 15 (the maintainer does not understand "keep before[] of merged corrections for a while": nothing changed).

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

## Parity notes (added with the 0.4.0 fixes)
- **SPEC.md:** copy it wholesale from iOS at merge time (it is identical in both repos); the lists above are the
  behaviour to build, not a substitute for it.
- **Android UI tests to write** (the iOS ones to mirror): a flick/fling in the reader leaves the UI idle; the definition
  folds with "More"/"Less"; the Words tag "Fixed" shows only on a word the open card changed (not on one merged into,
  not on one with the same spelling saved since); About shows the worldwide public-domain line and not the US one;
  Review's end button is "Back to Words"; the unsure card with no meaning on a row shows none on either.
- **Nouns without `nounEs`:** lead, leads, tear, tears (their sense depends on their sound) and fell, lay (rare nouns:
  a gloss would mislead). Offline their unsure rows show no meaning; the table is identical in both repos.
- **Also in this round:** Less/Menos toggle with a VoiceOver/TalkBack announcement; the card's fitted height resets for
  each new card; the Fixed tag moves to its own line at accessibility sizes.

## Reading progress reaches 100% (0.4.1)
- **Bug:** the progress bar stopped near 70% at the end of a book, because it followed the paragraph at the top of the
  screen, which is never the last one.
- **Rule (SPEC S2):** keep the resume place as the top paragraph; add a stored `furthestParagraph` (optional in the book
  record; absent in old data, where the resume place stands in) that only grows. Progress = furthest seen / (paragraphs - 1);
  a one-paragraph book is 100% once opened. It is clamped to the book on load and moves with the resume place when
  a stored book loses invisible-only paragraphs (SPEC "Invisible formatting").
- **Android:** raise it from the last visible item of the list (`LazyListState.layoutInfo.visibleItemsInfo`), not from
  the first one; keep it out of Compose state that recomposes the list on every scroll step. Core tests to mirror:
  `testProgressFollowsTheFurthestParagraphSeenAndNeverGoesBack`, `testAOneParagraphBookIsReadOnceItHasBeenOnScreen`,
  `testABookSavedBeforeFurthestParagraphLoadsWithItsPlaceAndAValueOutsideTheBookIsBroughtIn`,
  `testOpeningABookWhoseTextLostInvisibleParagraphsMovesTheFurthestParagraphToo`.

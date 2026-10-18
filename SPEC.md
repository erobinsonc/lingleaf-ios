# Lingleaf — product spec

Shared by [lingleaf-ios](https://github.com/erobinsonc/lingleaf-ios) and
[lingleaf-android](https://github.com/erobinsonc/lingleaf-android). Both
apps implement every scenario below; each scenario is covered by tests with
the same intent on both platforms. A change to behaviour updates this file in
**both** repositories.

## Principles

- Learn English by reading real books. The reader is the product.
- No accounts, ads or tracking. Data stays on the device.
- Network only for: Gutenberg search (`gutendex.com`), book downloads and covers
  (`www.gutenberg.org/cache/epub/`) and word definitions (`api.dictionaryapi.dev`). HTTPS only,
  to these hosts only: a redirect is followed only to them (at most 5); no cookies, no disk cache.
  Outside data is untrusted even from these hosts: dictionary fields are cut to 500 characters
  (definition) and 100 (word, IPA, part of speech); JSON nested deeper than 64 levels is refused;
  a search shows each book once, at most 32, and a recommended book always as shipped; titles and
  authors lose invisible control, formatting and blank-filler characters, keep at most 4 accents per
  letter and are at most 200 characters.
  Paragraphs over 2,000 characters are cut at the last sentence end that fits (else at a space);
  a word's saved sentence is at most 600 characters around the word. Files are read and written
  only under the app's own plain names. Saved data read back (also from a restored backup) is brought
  into range: the daily goal 5–60 minutes, the text size 14–34, the speech rate within its slider, reading
  progress inside the book, a date that can't be read becomes due now; a streak counts at most 3,650 days.
- Translation runs on the device (Apple Translation on iOS, Google ML Kit on Android).
- Interface in English and Spanish; more languages welcome.

## Scenarios

| ID | Scenario | Expected |
|---|---|---|
| S1 | First launch | Library shows 3 bundled stories (A1, A2, B1) and the daily goal card. |
| S2 | Open a book | Reader shows the text; returning later reopens at the same paragraph. |
| S3 | Tap a word | A card shows the base form ("animals" → "animal", "stole" → "steal"; for an irregular verb also offline), IPA, translation, definition, the sentence and its translation. A form that is also another word is read from its sentence: "she left" → "leave", "turn left" → "left", "a bit" → "bit"; when the sentence doesn't tell, the card shows the word as the dictionary gives it. Translation starts when the card opens, alongside the definition. The translation is in the learner's language; a small language button under it changes the language in place. |
| S4 | Save word | "Save word" (primary, right) saves the word for review; it is underlined in yellow in every book, including inflected forms ("steal" also marks "stole" and "stolen", "travel" also "travelled"); a form that is also another word is marked only where its sentence makes it that word (saving "leave" marks "she left", not "turn left"; saving "leaf" marks "the leaves", not "she leaves"). A message "“word” saved to Words" with Undo shows for 4 s, longer when the system asks for more time to act (Android's accessibility timeout); with a screen reader or switch control it stays until Undo, Close or a newer message. |
| S5 | I know it | "I know it" (secondary, left) saves the word as known; it is not underlined or reviewed. A message "“word” marked as known" with Undo shows like S4. |
| S6 | Listen | Word and sentence can be read aloud with an English voice. Read aloud reads continuously, sentence by sentence, from the top of the screen to the end of the book, highlighting the sentence being read on a neutral fill and scrolling only when it leaves the screen (no animation with Reduce Motion); scrolling by hand stops the following until that sentence is back on screen. Once started, a bar at the bottom (until leaving the reader or the end of the book) has "Previous sentence" (back to the start of the previous one and on), "Pause"/"Play" (Play goes on from the start of the paused sentence) and "Repeat sentence" (a toggle that loops the sentence being read; while on, the first button is "Add previous sentence" and grows the repeated stretch backwards one sentence at a time, reading it from its new start; the bar says "Repeating N sentences", the stretch has a neutral fill and a bar at its side; off, reading goes on forward). The top button only starts reading. Tapping a word pauses and opens its card; reading does not resume by itself. The word card's "Read from here" starts reading at its sentence. The speed setting applies from the next sentence. Reading moves the saved position. Leaving the reader or the app pauses: no reading without the text on screen. A call, an alarm, another app taking the sound or a voice that fails also pauses on that sentence, so the bar never shows Pause while nothing is heard. When the voice stops, other apps' sound returns to full volume. With no English voice on the device, reading aloud and Listen, on every screen, stop and say so ("Can't read aloud" · "This device has no English voice."), with a button to the voice settings where the system can open them (Android) or where to add one (iOS); once a voice is added, the next request speaks. |
| S7 | Review | Recall first: a due word shows alone with "Show meaning"; the meaning then shows the translation, the sentence it was saved from (the word in bold), that sentence's translation (in the current translation language, filled in on the device when missing) and a button to hear it, and only then "Again" and "I remembered". A new word is first due at the start of the next review day (days start at 04:00 local time); "I remembered" moves it to the next box, due at the start of the day 1, 3, 7, 14 then 30 days later, and after the last box it is learned; "Again" sends it back to the first box and repeats it in the session. A session holds at most 20 due words, interleaved by book, with "N of M" beside its progress bar. The Words tab shows how many words are due, updated after every answer, when the app comes back and when a new review day starts. At the end: "Done for today." and, when there are any, "N words tomorrow." ("Mañana tienes N palabras."); if more words are still due now, "Done for now. N more due today." with "Keep going". |
| S8 | Daily goal | Reading time counts while the reader is open; the card shows minutes today and the streak (days meeting the goal). |
| S9 | Discover | The recommended classics ship with the app (title, author, level) and show at once; their covers load from Project Gutenberg's file cache (decorative and hidden from screen readers: the row says the title and author; while a cover loads, or without internet, a drawn cover shows). UI tests load no covers, so they don't depend on the network. Search by title/author shows "Searching Project Gutenberg…", after 8 s also "Still searching. Project Gutenberg can be slow." with Cancel; a new search cancels the previous one; a failed search says "You're offline. Connect to the internet to search." or "Project Gutenberg didn't answer. Try again." with Retry, and the recommended books stay below. "Get" downloads the plain text straight from Project Gutenberg's file cache with a progress ring (tapping it cancels) and turns into "Read", which opens the book; a failed download says why in its row ("This book isn't available right now." for 403/404/410 or an empty book; offline; "Project Gutenberg didn't answer. Try again.") with Retry. Results, errors and a finished download are announced to screen readers. Offline means no connection, a lost connection, or a host that can't be found or reached. |
| S10 | Import | A plain-text `.txt` file can be imported; Gutenberg license headers are removed. |
| S11 | Settings | Daily goal, text size, speech speed and translation language persist. "Translate into" shows "Ask me when I tap a word" until a language is chosen. |
| S12 | Offline | Without internet the reader, saved words and review work; the card says translation/definition are unavailable (a platform may name the reason, e.g. Android needs Wi‑Fi once to download the language). Saving a word never waits for translation; a missing translation is filled in on the device as soon as it is available, and Review shows "No translation yet. Connect to the internet once to get it." until then. |
| S13 | Level filter | Discover shows chips "All" plus each level in the recommended list (A2–C2); "All" is selected by default, a level shows only its recommended books, in order; an empty level says "No recommended books at this level."; the chips stay with the recommended books, below any search results. |
| S14 | Translation language | The default is the first language in the device's preferred-language list that is supported and not English (Chinese → Simplified). If there is none, the first word card asks once "Translate into:" with up to 5 languages (the region's language first, then Español, Português, Français, 中文, العربية, without repeats) and "More languages"; the choice is saved. Each saved word records its translation language; words in another language are translated again when shown. |
| S15 | Saved state on the card | A saved word's card shows "Saved" or "I know it" checked (check icon, selected state, announced as "Remove from Words" action); tapping the checked button removes that state, with Undo (timing as in S4). Deleting a word in Words happens at once and offers Undo for 5 s with the same rules (no confirmation dialog). The language button under the translation is announced as "Translation language: <language>". |
| S16 | Helper and modal verbs | Tapping do/does/did used for a negative, a question or a prohibition ("did not go", "Did you see…?", "Don't touch"), or a modal (can, could, will, would, shall, should, must, may, might, with their negative forms), shows the base form ("do", "will"), "Helper verb" or "Modal verb", the verb group in the sentence ("did not go", "should have known") with its translation instead of the word's own, and one short note on what it does (e.g. "“didn't” (= “did not”) + base verb = past negative: “didn't go”, not “didn't went”."). No definition or IPA; Listen says the verb group. Saving stores the verb group as its own entry (the sentence when there is none), with its base form and kind; Words and Review show it. A question tag ("…, didn't you?") is explained as asking the listener to agree. A negative modal ("mustn't", "won't", "cannot", "must not") says it is the negative: "mustn't" = not allowed. "do" as a main verb ("I did my homework") is an ordinary word. have/has/had before a past participle ("has seen", "had never left", "Have you seen…?") is a "Helper verb" with a note on the perfect ("“has” + past participle: it happened before now and still matters: “seen”, not “saw”."; "had": "it happened before another past moment"); "had better"/"'d better" + verb is strong advice. A pronoun contraction ("it's", "I'll", "you'd", "let's") shows what it stands for as its base form ("it is", "I will", "let us"); with 'll or 'd as would it is a "Modal verb", with 've/'s/'d as have/has/had before a participle a "Helper verb", else it has no label and its note says "“it's” = “it is”." ("it's" also says "“its” (no apostrophe) = belonging to it."; "who's" contrasts "whose"; "let's" is a suggestion; "he'd put" shows "he had / he would", read aloud with "or", and the note "“he'd” can be “he had” or “he would”: the sentence's translation tells which."). The verb-group line is not shown when it is just the tapped word ("That's"). Saved, a contraction is its verb group or the contraction itself, with its expansion as base. have as a main verb ("I have a dog", "had a bath", "have to", "have got"), "its", and a noun + 's ("John's book") are ordinary words. |
| S17 | Selected word | While the card is open, the tapped word is marked in the reader (solid yellow marker, black text) and in bold in the card's sentence, underlined with its verb group if it has one. If the half-height card would cover it, the reader scrolls it into the upper part of the screen (without animation when Reduce Motion is on). |

## Shared logic (same rules, same tests on both platforms)

- Paragraphs: split on blank lines, hard-wrapped lines joined.
- Words: `[A-Za-z]+(['’][A-Za-z]+)*`; contractions stay whole.
- Irregular verbs (see `IrregularVerbs`): one table, `irregular-verbs.json` (identical in both repos, bundled in
  the core module), is the only list of irregular forms. Each verb has its base, past and participle (most common
  first, US spelling before UK: gotten/got, learned/learnt), -ing and -s forms, pattern group, level, Spanish
  meanings and, where a voice would misread a form, what to say instead (read past → "red"). It is read once and
  strictly: a schema version other than 1, a missing or unknown field, a form that is not a–z, an unknown group or
  level, or a file over 256 KB is refused, and the tests load the bundled file. From it: every form leads to its
  base (and a regular homonym's: lied → lie, hanged → hang), except the homographs below; `Verbs`' past participles
  are its participles ("got" excluded: "have got" means "have"); its base-like participles are those spelled like a
  base ("come", "read", "bet"); its base forms for "had better" are its bases not marked as mostly nouns ("light").
- Base forms (see `TextTools`): the irregular-verb table and a few irregular nouns and comparatives (children,
  feet, wives, better…), then the plural/past/-ing rules. A stem that doubles its last consonant also gives the
  single one, first (stopped → stop; not s, z or a vowel); a stem ending in -ll with two or more vowel groups before
  the last l does too (travelled → travel, controlling → control; called → call). A form of the table capitalised
  mid-sentence is a name: no irregular link ("Drew", "Rose").
- Verb or noun (see `IrregularVerbs`), for a homograph of the table (left, saw, felt, found, rose, fell, ground,
  wound, spoke, bit, shot, dove, thought, stole, slew, spat, spelt, smelt, lay, bore, bound, lives, leaves, lead,
  leads, tear, tears, wind, winds), from the words next to it (only spaces between) in its sentence; "up to 2
  adverbs" means listed ones or lower-case words in -ly. The first step that applies decides:
  1. name: capitalised mid-sentence ("Aunt Rose"; not all capitals) or part of a hyphenated word ("left-handed")
     → the word itself, not a verb.
  2. fixed: a phrase listed for the form ("turn left", "left hand", "right and left", "rose petals", "felt hat",
     "one fell swoop") → its noun; "bound for", "bound to" + a base verb → "bound", not a verb.
  3. noun: right after a determiner (a, an, the, my, your, his, her, its, our, their, whose, every, no), or after
     one listed adjective that follows one ("a little bit", "the red rose") → its noun. A possessive ("Tom's")
     counts as a determiner except before a form that can be a participle ("Tom's left" may be "Tom has left").
     An -s form also after a quantifier or number (these, many, nine…) or a preposition (of, in, with, to…), and
     with more listed adjectives ("dead leaves").
  4. base: after to, a modal or do (up to 2 adverbs between) → the form as a verb of its own ("to saw", "will
     lead", "to fell"; "to ground" is not); lay, lead, tear, wind opening the sentence (or after "Please") before
     an object word → that verb ("Lead the way").
  5. participle: left, felt, found, ground, wound, shot, thought, spat, spelt, smelt, bound after a form of
     have, be or get (up to 2 adverbs between) → the verb ("had left", "was found").
  6. subject (up to 2 adverbs between): after I, you, he, she, it, we, they, who, which, someone, nobody,
     something…; "one" only after no/every/not; "this"/"that" only before an -s form; "there"/"here" before lay,
     rose, fell; or after a capitalised name (when it opens the sentence: not a listed function word or adjective,
     not in -ly, not before an -s form) → the verb.
  7. subjectNoun: left, saw, felt, found, rose, fell, spoke, stole, slew, spat, spelt, smelt, lay, bore, bound
     after a determiner (+ one listed adjective) + a noun, when that determiner opens the sentence or a clause
     (after a comma, a semicolon, and, but, when, that, until…) → the verb ("The sun rose"; not "made of the
     finest felt", "wore a fur stole").
  8. conjunction: the past forms except ground after and, but, then (up to 2 adverbs between) → the verb.
  9. Else unsure: no irregular link, the word itself (only when its two bases are one: tears → tear).
  "lay" as a verb is "lay" (put) before an object word ("lay the table"; not "lay a long time"), else "lie"; after
  I/you/we/they with neither an object word nor a word like down, on, still, awake after it, it is unsure; after
  there/here it is "lie". Without a sentence every homograph is unsure. The word lists are in the table
  (`homographs`, `context`). The card's base form and dictionary look-up and the yellow underline use the same result:
  a verb looks its base up directly; a noun looks its own base up first, then the word as tapped, without following "past tense of …" in its
  definition; unsure looks the word up as before. Listen reads a form taken as a verb with the table's spoken form
  when it has one ("to tear" → "tare", "she dove" → "dohv"). A respelling applies only to the slot the reading proves (the base after to, a modal or do; the past in a past reading; the participle after have or a passive be); otherwise the form is spoken as written.
- Helper and modal verbs (see `FunctionWords`), within the tapped word's sentence:
  do/does/did/don't/doesn't/didn't followed by "not" or contracted → negative (past for did); else, in a
  sentence ending in "?", first word or after what/where/when/why/how/who/whom/whose/which → question;
  else an ordinary word. Modals: can/cannot/can't, could(n't), will/won't, would(n't), shall/shan't,
  should(n't), must(n't), may, might(n't) → base form; not a modal after a/an/the/my/your/his/her/
  its/our/their/free/good/ill, nor "May"/"Will" capitalized mid-sentence. Verb group: the word, then "not"
  if next, then a pronoun subject (I, you, he, she, it, we, they) if the sentence is a question, then up to
  4 of have/be/been/being/never/always/ever/really/just/also/still/even/only/already/probably/certainly/
  surely/often, then the next word; if the sentence ends first, up to its last word, and none when the word
  is the last one. A do-question without a pronoun subject has no verb group. A negative do/don't as the
  sentence's first word (after at most please/oh/now/so/and/but/then/well/no/yes/just), not in a question, is a prohibition. A modal is negative when contracted (n't), "cannot", or followed by "not". A do-form or modal after a comma, followed only by a pronoun and
  "?", is a question tag ("You went, didn't you?"): no verb group; a have-form there too.
- Perfect and contractions (see `FunctionWords`, `Verbs`), within the sentence:
  have/has/had/haven't/hasn't/hadn't, then (in a question or as the first word: "Had they known, …") a pronoun subject,
  or the/a/an/my/your/his/her/our/their/this/that/these/those + one word, then up to 4 of not/never/always/ever/really/
  just/also/still/even/only/already/probably/certainly/surely/often/recently/finally/almost/nearly/before/once/yet or
  any word ending in -ly, then a past participle → perfect (had → past perfect); else an ordinary word. A past
  participle is one of the irregular-verb table ("got" excluded) or an -ed form of a regular verb in `Verbs`' list,
  not part of a hyphenated word ("read-only"). Verb group: up to the participle, plus one word after "been" when it is -ing or a
  participle ("has been reading"; "has been here" → "has been"). had/'d + better (+ not) + a base verb (`Verbs`' list or the table) →
  "had better" (group up to the verb, or "not"); "had better luck" is ordinary.
  Pronoun contractions: I'm; you/we/they/what/who + 're; he/she/it/that/there/here/what/who/where/how + 's;
  I/you/we/they/who + 've; I/you/he/she/it/we/they/that/there/who + 'll and 'd; let's. 's = has before been/gone/had
  (perfect) or got (plain), else is. 've before a participle → perfect, else plain. 'd before better → had better;
  before a participle that is not also a base form → had (past perfect); before one that is (come, run, read, put, bet…)
  → "he had / he would" (plain, no verb group: only the sentence tells, so the card translates the sentence); else would (modal). 'll → will (modal). A modal
  contraction's verb group is as for modals, the contraction itself at the sentence's end; let's + next word; any other
  plain contraction's group is the word. The expansion keeps "I" capitalised, else lower case.
- Rule precision: a shared annotated corpus (`function-words-corpus.json`, identical in both repos' tests, with
  quoted, constructed and independently written held-out sentences) must expect each perfect/contraction rule at least
  30 times, and each rule must be right in at least 95% of the cases where it fires. The same for verb or noun:
  `homograph-corpus.json` (identical in both repos' tests; constructed and held-out sentences) has at least 30 cases
  for each family (plural or verb: lives, leaves…; past or noun: left, saw…; two verbs: found, lay, bore, bound;
  same base: lead, tear, wind) and 150 in all; each step (1–8) must claim at least 15 cases and be right (base and verb) in at least 95% of them.
- Reading aloud (see `ReadAloud`): a paragraph's sentences in order, as for the sentence of a word but whole; one
  longer than 600 UTF-16 units comes in consecutive pieces of at most 600, cut before a space. Reading starts at the
  sentence holding the offset (or the next one) and goes on to the next, skipping empty paragraphs, to the book's end.
  The previous sentence skips empty paragraphs too; a repeated stretch counts its sentences from first to last.
- Sentence of a word: the text between sentence ends (`[.!?]+` plus closing quotes, before a space or the end), trimmed.
- Spaced repetition: boxes with 1, 3, 7, 14, 30 day intervals, each due at the start of that review day (04:00 local time; 01:00 still belongs to the day before); a new word is due at the start of the next review day; "Again" → first box, due now.
- Marking a saved word in a sentence: its forms (match keys, with homographs read in the sentence as above), or a
  saved group of words, ignoring case.
- Review session: due words sorted by due time, grouped by book, taken one per book in turn, at most 20.
- Streak: consecutive days meeting the goal; an unfinished today doesn't break it.
- Translation language pick: preferred-language list order; skip English and unsupported; `zh-*` → Simplified Chinese; none → ask.
- Words needing translation: empty translation, or a translation language that is not recorded (words saved before it was) or differs from the current one.
- Book downloads: `https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt`; covers `…/pg{id}.cover.medium.jpg` (built from the id, never taken from the catalog; JPEG only (checked before decoding), at most 2 MB, refused over 4096 px a side or 4 megapixels, decoded as thumbnails of about 176×248 px). A weekly CI job checks every recommended book's text and cover link.
- Recommended books (Gutenberg id, level), easiest first: A2 21; B1 55, 16, 236; B2 11, 74, 120, 1661;
  C1 1342, 84, 174, 1400, 345; C2 2701, 219, 145. Levels: A1, A2, B1, B2, C1, C2. The level filter keeps order.
- Imported .txt: title is the file name without its extension (empty → "Book"); Gutenberg header/footer removed; files over 10 MB or with no text are refused.

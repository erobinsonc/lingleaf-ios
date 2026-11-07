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
- Translation runs on the device (Apple Translation on iOS, Google ML Kit on Android). On Android, ML Kit
  starts (and downloads nothing) only after the learner's first word tap, and the card says once
  "Translation uses Google's on-device model; Google receives diagnostics."
- Legal notices: links are fixed constants built by the app and open in the system browser. Settings → About
  links the privacy policy (`https://github.com/erobinsonc/lingleaf-ios/blob/main/PRIVACY.md`, the same file
  for both apps). Search results and About say "Project Gutenberg books are public domain in the US. Elsewhere,
  check your country's laws." Definitions credit Wiktionary (CC BY-SA). The app is for ages 13 and up; there is
  no age gate.
- Interface in English and Spanish; more languages welcome.

## Scenarios

| ID | Scenario | Expected |
|---|---|---|
| S1 | First launch | Library shows 3 bundled stories (A1, A2, B1) and the daily goal card. |
| S2 | Open a book | Reader shows the text; returning later reopens at the same paragraph. |
| S3 | Tap a word | A card shows the base form ("animals" → "animal", "stole" → "steal"; for an irregular verb also offline), IPA, translation, definition, the sentence and its translation. The definition ends, in smaller type, with "— Wiktionary, CC BY-SA" (cut with "…" and ", shortened" when the app cut it to 500 characters); a screen reader hears it as one element, "<definition>. Source: Wiktionary." (with the part of speech first when there is one). A past or participle of the irregular-verb table that is not also another word ("tore", "torn", "sprang", "lit", "lain") is always that verb, except as a name: its meaning is the table's Spanish meanings (else the translation of "to {base}"), its definition is a verb's; "lied" and "hanged" are the regular twin ("mentir", "ahorcar"). An -s or -ing form of the table ("lights", "bears", "springs", "meeting") is that verb only where its sentence proves it (Shared logic); elsewhere it is an ordinary word: the dictionary and the translation of the word as tapped, no table meaning ("the lights", "three bears", "a meeting"). "lying", "lies", "hanging", "hangs" take their sense from the next word ("lying to" → "mentir", "lying on" → "estar acostado"); when it doesn't tell, the card is unsure with the two senses: "to lie — estar acostado, tumbarse" / "to lie — mentir". "lies" no step proves a verb ("She tells lies") is unsure between the twin's noun and the verb: "the lie — mentira" / "to lie — estar, encontrarse" (the table's `nounEs` and `sEs`); after a determiner it is that noun ("his lies" → "lie"). An -s form of a base that is mostly a noun (`nounFirst`) after a noun subject with no object after it ("The bell rings") is unsure: "to ring — sonar" / "the ring — anillo" (the noun's regular lemma, spelled like the base; chosen, it is saved as "ring" with the label "the ring"). "bound for" and "bound to" + a verb are one expression: the card shows "bound for" / "bound to" with the table's meaning ("rumbo a, con destino a"; "seguro que · obligado a"; outside Spanish the translation of its `query`, "heading for", "certain to"), the dictionary's adjective definition of "bound" (nothing, not "No definition available.", when it has none), and Save stores the expression as one entry (like a verb group, S16). A form that is also another word is read from its sentence: "she left" → "leave", "turn left" → "left", "a bit" → "bit"; when the sentence doesn't tell (unsure), the card doesn't guess: the tapped word (no IPA, translation or definition), the sentence and its translation, a guide line and its two readings as a single choice (the guide says "The sentence's translation tells you which one:" while the sentence's translation shows or is on its way, else "Which one is it in this sentence?" — offline, translation failed or no translation language yet; with no language yet, the language choice comes right below the sentence, before the guide), most common first (`nounFirst`: the noun), none chosen: a verb as "to {base}", a noun as "the {noun}", each with its meaning ("to leave — irse, salir", "the left — izquierda"; "lay" after I/you/we/they or a plural noun subject: "to lie", "to lay"; a form with no noun: its two verbs). A verb reading's meaning is the table's first Spanish meaning in Spanish, else the translation of "to {base}", or of the table's English `query` for that sense when it has one ("to lie down" / "to tell a lie", "to hang up" / "to execute by hanging"); if the two rows' meanings still come out the same, each adds the sense's short English `gloss` ("recline", "say what isn't true"); a noun's, the translation of "the {noun}"; dictionary entry and definition match the reading's part of speech: when the table gives the base's IPA, the entry whose pronunciation matches it ("wind" /waɪnd/, not /wɪnd/), its first meaning of that part of speech; when no entry matches the table's IPA, no definition and the table's IPA. A noun of tear, lead or wind takes its pronunciation from its sentence (`nounIpa`, its rules in order, those on the next word before those on the word before: "tears in her eyes", "a tear rolled" → /tɪr/; "a tear in my shirt" → /tɛr/; "made of lead", "lead pipes" → /lɛd/; "took the lead", "the role of lead singer" → /liːd/; wind → /wɪnd/; with no clue, "tears" → /tɪr/ and "leads" → /liːd/, their usual sense) and the entry with that pronunciation; when the sentence doesn't tell ("the tear was small"), no IPA or definition from the dictionary. A noun is spoken as written, except a noun whose sentence proves a sound the voice wouldn't make: lead /lɛd/ is said "led", tear /tɛr/ "tare" (the plurals "leds", "tares"; the IPA shown is the headword's, /lɛd/, /tɛr/). The regular twin ("lied", "mentir") shows the base's IPA from the table (lie /laɪ/, hang /hæŋ/) and no definition; with no entry of that part of speech for the base, the word as tapped, else no definition (never another part of speech's); a reading nothing proves has no definition. Choosing one checks it (the other stays, to change it), shows its IPA and definition (aligned with the rows; "No definition available." only once its look-up has answered, never while it runs), and Listen and Save follow it. On iOS this card opens at full height. Translation starts when the card opens, alongside the definition. The translation is in the learner's language; a small language button under it changes the language in place. |
| S4 | Save word | "Save word" (primary, right) saves the word for review; it is underlined in yellow in every book, including inflected forms ("steal" also marks "stole" and "stolen", "travel" also "travelled"); a form that is also another word is marked only where its sentence makes it that word (saving "leave" marks "she left", not "turn left"; saving "leaf" marks "the leaves", not "she leaves"). A message "“word” saved to Words" with Undo shows for 4 s, longer when the system asks for more time to act (Android's accessibility timeout); with a screen reader or switch control it stays until Undo, Close or a newer message. Unsure with nothing chosen, Save and I know it store the tapped form ("left") with both readings' meanings; it marks that exact form everywhere. A certain or chosen reading stores its base with its sense (verb, noun or homonym) and marks only forms read as that sense ("the wind" doesn't mark "She wound the clock"). One spelling can be saved once per sense. Words and Review always show a sensed word whose spelling is a homograph of the table, a base marked mostly a noun (`nounFirst`) or a base with a regular twin with its sense label, even when only one sense is saved: "to wind" / "the wind", "to ring" / "the ring" (a mostly-noun -s chosen as the noun is saved as its lemma), "to lie"; in Words two verb senses of one spelling also show their first meaning: "to lie (estar acostado, tumbarse)" / "to lie (mentir)" (the table's first Spanish meaning in Spanish, else the first meaning of the translation). An occurrence its sentence leaves unsure never marks a word saved with a sense, whatever their bases. Saving a reading of a form saved unsure replaces it, keeping its review progress; Undo puts it back. |
| S5 | I know it | "I know it" (secondary, left) saves the word as known; it is not underlined or reviewed. A message "“word” marked as known" with Undo shows like S4. |
| S6 | Listen | Word and sentence can be read aloud with an English voice. Read aloud reads continuously, sentence by sentence, from the top of the screen to the end of the book, highlighting the sentence being read on a neutral fill and scrolling only when it leaves the screen (no animation with Reduce Motion); scrolling by hand stops the following until that sentence is back on screen. Once started, a bar at the bottom (until leaving the reader or the end of the book) has "Previous sentence" (back to the start of the previous one and on), "Pause"/"Play" (Play goes on from the start of the paused sentence) and "Repeat sentence" (a toggle that loops the sentence being read; while on, the first button is "Add previous sentence" and grows the repeated stretch backwards one sentence at a time, reading it from its new start; the bar says "Repeating N sentences", the stretch has a neutral fill and a bar at its side; off, reading goes on forward). The top button only starts reading. Tapping a word pauses and opens its card; reading does not resume by itself. The word card's "Read from here" starts reading at its sentence. The speed setting applies from the next sentence. Reading moves the saved position. Leaving the reader or the app pauses: no reading without the text on screen. A call, an alarm, another app taking the sound or a voice that fails also pauses on that sentence, so the bar never shows Pause while nothing is heard. When the voice stops, other apps' sound returns to full volume. With no English voice on the device, reading aloud and Listen, on every screen, stop and say so ("Can't read aloud" · "This device has no English voice."), with a button to the voice settings where the system can open them (Android) or where to add one (iOS); once a voice is added, the next request speaks. The card's Listen says the headword, then the word as in the text when it differs ("wind", "wound"), each with the table's spoken form for its proven slot (a noun as written, except lead /lɛd/ "led" and tear /tɛr/ "tare" when its sentence proves that sound); unsure with nothing chosen, the tapped form in each reading in the rows' order (once when they sound the same). |
| S7 | Review | Recall first: a due word shows alone with "Show meaning" and never with a meaning: its sense label when it has one (S4: "to wind", "to lie", never "to lie (mentir)"); when two senses of its spelling are saved, or when the label alone doesn't tell the sense (a verb with a regular twin, lie or hang, saved as the verb or as the twin, even with one sense saved), also the sentence it was saved from with the word in bold and no translation; the meaning then shows the translation, the sentence it was saved from (the word in bold), that sentence's translation (in the current translation language, filled in on the device when missing) and a button to hear it, and only then "Again" and "I remembered". A new word is first due at the start of the next review day (days start at 04:00 local time); "I remembered" moves it to the next box, due at the start of the day 1, 3, 7, 14 then 30 days later, and after the last box it is learned; "Again" sends it back to the first box and repeats it in the session. A session holds at most 20 due words, interleaved by book, with "N of M" beside its progress bar. The Words tab shows how many words are due, updated after every answer, when the app comes back and when a new review day starts. At the end: "Done for today." and, when there are any, "N words tomorrow." ("Mañana tienes N palabras."); if more words are still due now, "Done for now. N more due today." with "Keep going". The sentence shows in bold only the occurrence that was tapped. A word saved unsure shows both readings, as on the card, in place of its translation. Listen in Review and Words says a word saved as a verb or the regular twin with the table's spoken form of its base ("tare" for "tear"), a noun as written ("tear"), except a noun whose saved sentence proved a sound the voice wouldn't make (lead /lɛd/ "led", tear /tɛr/ "tare"); a word saved unsure, each saved reading's form in its reading, once when they sound the same (as on the card). |
| S8 | Daily goal | Reading time counts while the reader is open; the card shows minutes today and the streak (days meeting the goal). |
| S9 | Discover | The recommended classics ship with the app (title, author, level) and show at once, under "Free classics from Project Gutenberg." ("Our stories and free classics from Project Gutenberg." while a level shows the app's own stories, S13); "Read" is a button in the row, not a link on the whole row; their covers load from Project Gutenberg's file cache (decorative and hidden from screen readers: the row says the title and author; while a cover loads, or without internet, a drawn cover shows). UI tests load no covers, so they don't depend on the network. Search by title/author shows "Searching Project Gutenberg…", after 8 s also "Still searching. Project Gutenberg can be slow." with Cancel; a new search cancels the previous one; results end with the line "Project Gutenberg books are public domain in the US. Elsewhere, check your country's laws."; a failed search says "You're offline. Connect to the internet to search." or "Project Gutenberg didn't answer. Try again." with Retry, and the recommended books stay below. "Get" downloads the plain text straight from Project Gutenberg's file cache with a progress ring (tapping it cancels) and turns into "Read", which opens the book; a failed download says why in its row ("This book isn't available right now." for 403/404/410 or an empty book; offline; "Project Gutenberg didn't answer. Try again.") with Retry. Results, errors and a finished download are announced to screen readers. Offline means no connection, a lost connection, or a host that can't be found or reached. |
| S10 | Import | A plain-text `.txt` file can be imported; Gutenberg license headers are removed. |
| S11 | Settings | Daily goal, text size, speech speed and translation language persist. "Translate into" shows "Ask me when I tap a word" until a language is chosen. About has "Privacy policy" (opens the policy), the source code link, and the credits: "No accounts, no ads, no tracking.", the public-domain line of S9 and "Definitions from Wiktionary, CC BY-SA 3.0/4.0, via Free Dictionary API." (screen-reader hint "Contains links"; each name a link: `https://en.wiktionary.org/`, `https://creativecommons.org/licenses/by-sa/4.0/`, `https://dictionaryapi.dev/`). Android also lists the open-source licenses of its libraries. |
| S12 | Offline | Without internet the reader, saved words and review work; the card says translation/definition are unavailable (a platform may name the reason, e.g. Android needs Wi‑Fi once to download the language). Saving a word never waits for translation; a missing translation is filled in on the device as soon as it is available, and Review shows "No translation yet. Connect to the internet once to get it." until then. |
| S13 | Level filter | Discover shows chips "All" plus each level that has a recommended book or one of the app's own stories (A1–C2); "All" is selected by default and shows the recommended books; a level shows its own stories first ("Original story"; "Read" opens it in the reader, "Get" puts it back in the library at once if it was deleted), then its recommended books, in order, under the subtitle "Our stories and free classics from Project Gutenberg."; a level with neither says "No recommended books at this level."; the chips stay with the recommended books, below any search results. |
| S14 | Translation language | The default is the first language in the device's preferred-language list that is supported and not English (Chinese → Simplified). If there is none, the first word card asks once "Translate into:" with up to 5 languages (the region's language first, then Español, Português, Français, 中文, العربية, without repeats) and "More languages"; the choice is saved. Each saved word records its translation language; words in another language are translated again when shown. |
| S15 | Saved state on the card | A saved word's card shows "Saved" or "I know it" checked (check icon, selected state, announced as "Remove from Words" action); tapping the checked button removes that state, with Undo (timing as in S4). Deleting a word in Words happens at once and offers Undo for 5 s with the same rules (no confirmation dialog); the message and the row's Listen button name the word as Words shows it ("“the wind” deleted", "Listen to the wind"). The language button under the translation is announced as "Translation language: <language>". |
| S16 | Helper and modal verbs | Tapping do/does/did used for a negative, a question or a prohibition ("did not go", "Did you see…?", "Don't touch"), or a modal (can, could, will, would, shall, should, must, may, might, with their negative forms), shows the base form ("do", "will"), "Helper verb" or "Modal verb", the verb group in the sentence ("did not go", "should have known") with its translation instead of the word's own, and one short note on what it does (e.g. "“didn't” (= “did not”) + base verb = past negative: “didn't go”, not “didn't went”."). No definition or IPA; Listen says the verb group. Saving stores the verb group as its own entry (the sentence when there is none), with its base form and kind; Words and Review show it. A question tag ("…, didn't you?") is explained as asking the listener to agree. A negative modal ("mustn't", "won't", "cannot", "must not") says it is the negative: "mustn't" = not allowed. "do" as a main verb ("I did my homework") is an ordinary word. have/has/had before a past participle ("has seen", "had never left", "Have you seen…?") is a "Helper verb" with a note on the perfect ("“has” + past participle: it happened before now and still matters: “seen”, not “saw”."; "had": "it happened before another past moment"); "had better"/"'d better" + verb is strong advice. A pronoun contraction ("it's", "I'll", "you'd", "let's") shows what it stands for as its base form ("it is", "I will", "let us"); with 'll or 'd as would it is a "Modal verb", with 've/'s/'d as have/has/had before a participle a "Helper verb", else it has no label and its note says "“it's” = “it is”." ("it's" also says "“its” (no apostrophe) = belonging to it."; "who's" contrasts "whose"; "let's" is a suggestion; "he'd put" shows "he had / he would", read aloud with "or", and the note "“he'd” can be “he had” or “he would”: the sentence's translation tells which."). The verb-group line is not shown when it is just the tapped word ("That's"). Saved, a contraction is its verb group or the contraction itself, with its expansion as base. have as a main verb ("I have a dog", "had a bath", "have to", "have got"), "its", and a noun + 's ("John's book") are ordinary words. |
| S17 | Selected word | While the card is open, the tapped word is marked in the reader (solid yellow marker, black text) and in bold in the card's sentence, underlined with its verb group if it has one. If the half-height card would cover it, the reader scrolls it into the upper part of the screen (without animation when Reduce Motion is on). |
| S18 | Corrected words | Once after updating, each saved word whose sentence now reads differently is corrected on the device, newest saved first, at most 1,000 corrections per run (the rest in the next runs, so every correction can be undone) (a certain reading becomes that word; an unsure one the tapped form with both readings), translated again (later when offline, S12) and merged into an existing entry of the same name. A corrected word in Learning starts its review again: first box, due now, keeping when it was saved, its sentence and its book; due only once it has a meaning (else when its translation arrives, S12). A known word stays known. A corrected verb gets the table's IPA for its base; a corrected noun of tear, lead or wind gets its sentence's IPA (none when nothing proves it). Words shows one card until closed: "Fixed to match its sentence: “leave” → “left”." (several: "Fixed to match their sentences:", up to 3 lines and "and N more"), with Undo and Close. Undo puts back only the entries the correction changed or merged, each as it was (with its review box), latest first; an entry changed after the correction (reviewed, edited) stays as it is now, and a word deleted since is not brought back. Undo then shows a message like S4's (without Undo): "Words put back as before" ("Palabras restauradas como antes"), or when some stay as they are now "Put back, except N you've changed since" ("Restauradas, salvo N que cambiaste después"). |

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
  the last l does too (travelled → travel, controlling → control; called → call), except for the table's
  `llBases`, whose US double-l base comes first (installed → install, then instal; enrolled → enroll, then enrol). A form of the table capitalised
  mid-sentence is a name: no irregular link ("Drew", "Rose").
- Verb or noun (see `IrregularVerbs`), for a homograph of the table (left, saw, felt, found, rose, fell, ground,
  wound, spoke, bit, shot, dove, thought, stole, slew, spat, spelt, smelt, lay, bore, bound, lives, leaves, lead,
  leads, tear, tears, wind, winds), from the words next to it (only spaces between) in its sentence; "up to 2
  adverbs" means listed ones or lower-case words in -ly. The first step that applies decides:
  1. name: capitalised mid-sentence ("Aunt Rose"; not all capitals) or part of a hyphenated word ("left-handed")
     → the word itself, not a verb.
  2. fixed: a listed noun phrase ("the lost and found") → the word itself, not a verb, unless a subject, a form
     of have or be, or an adverb comes right before the phrase or an object word right after it ("she lost and
     found her keys"); a phrase listed for the form ("turn left", "left hand", "right and left", "rose petals", "felt hat",
     "one fell swoop") → its noun; an expression of the form (`expressions`: "bound for", "bound to" + a base verb) →
     that expression, not a verb.
  3. noun: right after a determiner (a, an, the, my, your, his, her, its, our, their, whose, every, no), or after
     one listed adjective that follows one ("a little bit", "the red rose") → its noun. A possessive ("Tom's")
     counts as a determiner except before a form that can be a participle ("Tom's left" may be "Tom has left").
     An -s form also after a quantifier or number (these, many, nine…) or a preposition (of, in, with, to…), and
     with more listed adjectives ("dead leaves").
  3b. opening participle: left, felt, found, ground, wound, shot, thought, spat, spelt, smelt, bound opening the
     sentence, before a listed word (alone, behind, guilty, dead, in, on, by, with…, or a word in -ly) and with a
     comma later in the sentence → the verb ("Left alone, she cried"; not "Felt hats, …", "Thought, like speech, …";
     "Bound for London, …" is step 2).
  4. base: after to, a modal or do (up to 2 adverbs between) → the form as a verb of its own ("to saw", "will
     lead", "to fell"; "to ground" is not); lay, lead, tear, wind opening the sentence (or after "Please") before
     an object word → that verb ("Lead the way").
  5. participle: left, felt, found, ground, wound, shot, thought, spat, spelt, smelt, bound after a form of
     have, be or get (up to 2 adverbs between) → the verb ("had left", "was found").
  6. subject (up to 2 adverbs between): after I, you, he, she, it, we, they, who, which, someone, nobody,
     something…; "one" only after no/every/not; "this"/"that" only before an -s form; "there"/"here" before lay,
     rose, fell; or after a capitalised name (when it opens the sentence: not a listed function word or adjective,
     not in -ly, not before an -s form) → the verb. lives and leaves after a capitalised word opening the sentence
     that is probably a name (not a listed function word, adjective, month, direction or plant name, not in -ly,
     -ful, -less, -ous, not a verb form in -ed/-ing), before a listed preposition or adverb (not "of") or a word in
     -ly, and with no finite verb later in their clause (is, are, had, can… or a listed past such as "shone"; at most
     the next 60 words are looked at) →
     the verb ("Tom lives in…"; not "Double lives in fiction are common").
  7. subjectNoun: left, saw, felt, found, rose, fell, spoke, stole, slew, spat, spelt, smelt, lay, bore, bound
     after a determiner (+ one listed adjective) + a noun, when that determiner opens the sentence or a clause
     (after a comma, a semicolon, and, but, when, that, until…) → the verb ("The sun rose"; not "made of the
     finest felt", "wore a fur stole").
     bit only before an object word or into, off, through, down, hard, deep, at ("The dog bit him"; not "The
     funny bit was…").
  7b. noun + -s form: lives, leaves after a determiner (+ one listed adjective) + a singular noun, the determiner
     opening the sentence or a clause, before a listed preposition or adverb (not "of") or a word in -ly, with no
     finite verb later in their clause → the verb ("The old man lives alone", "The bus leaves at six"; not "the
     willow leaves on the water": listed plant words before leaves are step 2).
  7c. quantifier: left, saw, felt, found, rose, fell, ground, wound, spoke, bit, shot, dove, thought, stole, slew,
     spat, spelt, lay after a quantifier or number (many, few, several, both, two…; also "all the", "both my",
     "some of the", "hundreds of") + (one listed adjective) + a plural noun (-s, or men, people, children…), the
     quantifier opening the sentence or a clause → the verb ("Many people left", "Both girls saw it"); "lay" as
     after "they". Not bore, bound, smelt: a present-tense twin fits a plural subject ("Long speeches bore me").
  8. conjunction: the past forms except ground after and, but, then (up to 2 adverbs between) → the verb.
  9. Else unsure: no irregular link, the word itself (only when its two bases are one: tears → tear).
  "lay" as a verb is "lay" (put) before an object word ("lay the table"; not "lay a long time"), else "lie"; after
  I/you/we/they with neither an object word nor a word like down, on, still, awake after it, it is unsure; after
  there/here it is "lie". Without a sentence every homograph is unsure. The word lists are in the table
  (`homographs`, `context`). The card's base form and dictionary look-up and the yellow underline use the same result (an unsure
  occurrence marks no word saved with a sense):
  a verb looks its base up directly; a noun looks its own base up first, then the word as tapped, without following "past tense of …" in its
  definition; unsure looks the word up as before. Listen reads a form taken as a verb (or the regular twin) with the table's spoken form
  when it has one ("to tear" → "tare", "she dove" → "dohv"), and a noun as written unless the `nounIpa` rule its
  sentence matched has a `spokenAs` ("made of lead" → "led", "a tear in my shirt" → "tare"); a plural's rule says
  the plural ("lead pipes and old roof leads" → "leds", "tears in the sail" → "tares") and the headword says the
  singular's spoken form for the same IPA. A respelling applies only to the slot the reading proves (the base after to, a modal or do; the past in a past reading; the participle after have or a passive be); otherwise the form is spoken as written.
- Other forms of the table (see `IrregularVerbs`), not homographs, from the same words around them. A name (step 1
  above) is the word itself. A past or participle (and am, are) → that verb; a form only of the regular twin (lied,
  hanged) → the twin's sense (`homonym`). An -s or -ing form → the verb only when a step proves it, else an ordinary
  word (no table link, no sense; its base forms are the regular -s rules, none for -ing: "the lights" → "light",
  "a meeting" → "meeting"): not right after a determiner, a quantifier or a number, a possessive, or a listed
  adjective after one; then -s after he, she, it, who, which, that, this, what, someone, nothing… (up to 2 adverbs
  between), after a capitalised name mid-sentence, after a lower-case word right after a closing quote ('"Look!"
  says Tom'), or after a name opening the sentence or a determiner (+ one listed adjective) + a singular noun
  opening the sentence or a clause, when the next word is an object word, or, for a base not marked as mostly a
  noun (`nounFirst`: light, ring, spring, bear…), any word or none with no finite verb later in the clause ("The dog
  is brown", "Tom runs home"; not "Street lights flickered", "the street lights in the city"); -ing after a form of
  be or after while, when, after, before, by, without, since, keep, stop, start, begin, finish, enjoy, go, like,
  love, hate… (up to 2 adverbs between), opening the sentence before an object word, a listed word or a word in
  -ly with a comma later ("Meeting the teacher, …"), or after a comma, "and" or "or" before an object word, a
  preposition or a word in -ly ("…, telling the children"). The -s and -ing forms the twin shares (lying, lies,
  hanging, hangs), not after a determiner: the next word listed in the table's `homonym` (`homonymBefore`:
  "lying to", "about", "through"; `verbBefore`: "lying on", "in", "down", "there", "awake"…) gives the sense;
  else unsure, with the two senses as the readings. An -s form the twin shares that has a noun (`homonym.noun`:
  "lies") is that noun after a determiner and, when no step proves the verb, unsure between that noun and the verb.
  An -s form of a `nounFirst` base after a determiner (+ one listed adjective) + a singular noun opening the
  sentence or a clause, with no object word after it and no finite verb later in the clause ("The bell rings"),
  is unsure between the verb and the word as a noun. The bundled stories have no form of the table left unsure or
  given a reading against its sentence (test).
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
- Recommended books (Gutenberg id, level), easiest first, public domain in almost every country (authors who
  died in 1925 or earlier) and without old spellings such as "to-day": B1 25519, 55, 54, 486, 517;
  B2 1874, 3536, 157, 11, 14522; C1 160, 208; C2 209. Levels: A1, A2, B1, B2, C1, C2. The level filter keeps order.
- Recommended ids: 25519, 55, 54, 486, 517, 1874, 3536, 157, 11, 14522, 160, 208, 209.
- Bundled stories (title, level): The Red Boat A1, A Day at the Market A2, The Lighthouse Keeper B1; author "Lingleaf".
- Imported .txt: title is the file name without its extension (empty → "Book"); Gutenberg header/footer removed; files over 10 MB or with no text are refused.

## Grammar tab (S20–S25)

The fifth tab, between Words and Settings: "Grammar" / "Gramática", a lightbulb icon. Rules, examples and practice
are bundled in the app (`grammar-rules.json`, below): no download, no new host, no account. The Grammar tab ships
together with its Review items (S25): it is not offered as a way to remember rules before that.

| ID | Scenario | Expected |
|---|---|---|
| S20 | Grammar list | The first row is "Irregular verbs" / "Verbos irregulares" (subtitle "take · took · taken"; S24). Then the categories, easiest first, each with its rule count; a category opens to its rules, easiest first (A1, A2, B1), each row with its title, its level ("A1 · Beginner" / "A1 · Principiante", "A2 · Elementary" / "Elemental", "B1 · Intermediate" / "Intermedio") and one of three states: "New" / "Nueva", "Practised" / "Practicada", "In Review" / "En el Repaso" (no percentage, no streak, no message about days missed). "Recent" / "Recientes" (the last 3 rules opened) shows above the categories only once 3 rules have been opened. Search ignores case and accents and looks in titles, rule lines, examples and aliases, in both languages ("pasado", "hay"); a verb is found by its Spanish meaning too. With more than 25 rules the list shows categories first, each with its count; with 25 or fewer the rules show directly under their category headings. A search with no match says "No rules match. Try: in, on, at" / "Ninguna regla coincide. Prueba: in, on, at". |
| S21 | Rule page | Title; level (as in S20); the rule in at most 4 lines, in the interface language (the English forms inside stay English); a line for Spanish speakers where Spanish interferes (`spanish`): with a Spanish interface it is the Spanish text, with another interface language it shows under "Spanish speakers" / "Hispanohablantes" in English; 2–4 examples, each with a Listen button and its Spanish translation (bundled; with another interface language the translation is made on the device as the word card does, S12, and the example shows none until then); one "Don't mix up" / "No confundas" line with two correct forms and an optional gloss; an optional note; "Try it" / "Pruébalo" (S22); "In your books" / "En tus libros" (S23); "Add to Review" / "Agregar al Repaso" (S25). With an English interface, "Show in Spanish" shows the rule and the feedback in Spanish. A rule, its examples and its contrast show only correct English: a wrong form appears only as a practice option and in the feedback to it. Opening a rule counts it for "Recent". |
| S22 | Try it | The learner chooses before anything is shown: the options show with no answer, no colour and no blur, in the file's order (no shuffling at run time: the shared file decides). An item is a `gap` (a sentence with one "___") or a `choose` (the instruction `ask` and a visible stimulus `text`: a situation, a question or a Spanish sentence). The first time a rule opens: one pretest item, the rule's first item, and a "Skip to the rule" / "Ir a la regla" button (the rule is then shown above, the item stays); later visits: "Practice" / "Practicar", 3 items drawn from the rule's items, items never seen or missed last time first (in file order), else the ones seen longest ago. Choosing an option shows at once, for every option, why: the chosen one "Right: …" / "Correcto: …" (green, check icon) or "Not quite: …" / "No del todo: …" (red, cross icon) and, after a wrong choice, the right option's "Right: …" below it; colour is never the only signal. "Not sure" / "No lo sé" counts as wrong and shows "No problem. Right: …" / "No pasa nada. Correcto: …". The feedback is the item's `feedback` line for that option, in the interface language. After the last item: "You got N of M right" / "Acertaste N de M" and an optional "Practice again" / "Practicar otra vez" (no reminders, no nudges). An item is never graded by typing. The option "(nothing)" shows as "(nothing)" / "(nada)". |
| S23 | In your books | A rule whose `books` is `{"mode": "none"}` shows no such section. A rule with patterns shows, below the practice, up to 3 sentences from the learner's own books that contain one of its patterns, with the pattern in bold and the book title: at most 25 words (15 for an A1 rule), few words the learner doesn't know (saved words and the rule's level), modern text first. The section is shown only when the patterns reach a precision of 95% or more on the bundled stories and the 13 recommended books (a test); a rule that fails the test is treated as `none`. With no sentence yet the section says "No sentences from your books yet. Keep reading and they'll show up here." / "Aún no hay frases de tus libros. Sigue leyendo y aparecerán aquí." A tap opens the sentence in the reader at its paragraph. The matcher is its own release slice; until it ships the section is not shown. |
| S24 | Irregular verbs | The first row of S20 opens the list of every verb of `irregular-verbs.json` (its count is that file's, not written here): two-line rows "take · took · taken" / "tomar, llevar" (the table's Spanish meanings; for another interface language the translation of "to take"), with an A–Z index or its pattern groups; Listen on a row says the three forms. A verb page shows Forms (base, past, participle, -ing, he/she/it) each with Listen, "In sentences" / "En frases" (10 curated: every day, past, before now, right now, in the middle in the past, plans, imagined, can, should, need to), "In your books" (S23) and "Save word" / "Guardar palabra". The word card, for an irregular form used as a verb, shows "take · **took** · taken ›" opening its verb page (planned for PR3). |
| S25 | Add to Review | "Add to Review" / "Agregar al Repaso" (secondary) puts the rule's items into Review, not the rule: the message "“<rule>” added to Review" / "“<regla>” agregada al Repaso" with Undo (timing as in S4) shows, then the button reads "In Review" / "En el Repaso". Every item has its own box of S7 (1, 3, 7, 14, 30 days) and its own counts. A Review visit to a rule draws 2 auto-graded items (`gap` or `choose`), never the same two as the last visit while the rule has more, missed ones first; both right moves both to the next box; a wrong one goes back to the first box and the pair is repeated in the session. In a session: at most 3 rules, at most 1 new rule a day, inside the 20-item cap, never first, mixed with other rules' items (not one rule after another); an item asks before it shows, with the choose-then-feedback of S22. Verbs are added in groups, at most 5 new verb items a day, recognition first (given "took", pick the base among real bases; the distractors are only real bases). Planned for PR4, in the same release as PR2. |

Grammar rules data (shared logic, same file and tests on both platforms):

- `grammar-rules.json` (identical in both repos, bundled in the core module) is the only source of Grammar
  content. It is read once and strictly: a schema version other than 1; a missing or unknown field at any level;
  an unknown category, level (A1, A2, B1), `kind` (`gap`, `choose`) or `books` mode (`none`, `patterns`); a duplicate
  category, rule or item id; an id that is not lower-case a–z, digits and hyphens (1–40); an item with fewer than 2 or
  more than 4 options or with a repeated option; an answer index outside the options; a `feedback` count different
  from the options'; a `gap` item without exactly one "___" or with an `ask`; a `choose` item without `ask` or
  without `text`; a rule with no or more than 4 rule lines, different line counts in English and Spanish, fewer than
  2 or more than 4 examples, a contrast without exactly 2 forms, no or more than 20 aliases (each at most 40 code
  points), fewer than 3 or more than 12 items, or a `patterns` list with none or more than 12 patterns (each 1–5 words
  of a–z, `|` and `*`); more than 200 rules or 20 categories; any text that is blank, over 400 code points (a combining
  mark counts), or that holds a control, format (bidirectional, zero-width), line or paragraph separator or private-use
  character (the same set as the irregular-verb table's texts); a file over 256 KB; or JSON nested deeper than 8
  levels is refused. The tests load the bundled file and compare its SHA-256 with the one below.
- Shape: `schema`, `categories[] {id, title{en,es}}`, `rules[] {id, category, level, title{en,es}, rule{en[],es[]},
  examples[] {en, es}, contrast {forms[2], gloss{en,es}?}, note{en,es}?, spanish{en,es}?, aliases[], books {mode,
  patterns[]?}, practice[] {id, level, kind, text?, ask{en,es}?, options[], answer, feedback[] {en, es}}}`. The first
  item of a rule is its pretest. Ids are stable (`time-prepositions`, `time-prepositions-1`): saved progress refers to
  them; an id is never reused.
- Content rules (tested): every rule has at least 6 items; the right answer is spread over the positions (no position
  holds more than 40% of the 3-option items of the file); every `choose` item has a visible stimulus; rules, examples
  and contrasts show only correct English.
- Rule ids in this release (wave 1, 13 rules): his-her-its, irregular-past, do-does-did, subject-it-there, the-a-nothing,
  there-then-than, question-order, present-s, adjective-noun, time-prepositions, place-prepositions, single-negative,
  indirect-questions. Later waves add rules and change the SHA-256 (this file is updated with them).
- Progress (`tips.json`, schema 2, in the app's own folder, plain name): per rule id when it was last opened, attempts
  and rights (display only), whether it is in Review, whether its first item has been answered (`pretestDone`), and
  per item `{box 0–5, due (a date or none), seen, missed}`. At most 200 entries (the ones opened longest ago go first),
  12 items each, counts 0–1,000, 256 KB. Read back bounded: an unknown rule or item id is dropped, counts are brought
  into range (rights never above attempts, missed never above seen), a date that can't be read, before 2020 or in
  the future becomes none, another schema gives empty progress. If the bundled rules did not load, progress is not
  written (the saved file stays as it is). Deleting the app's data removes it. No telemetry: nothing about Grammar
  leaves the device. Measured on the device only (never sent): per item the box, due day and results, so a later
  version can compare the first try of a pretest with the first practice and recall after 7 days.
- Search (`GrammarSearch`): lower-case, strip accents (NFD, no combining marks), split on non-letters; every query word
  must prefix a word of the rule's title, rule lines, examples or aliases (both languages).
- Examples are original text written for Lingleaf (CC0); the facts come from standard grammar references, not from any
  third-party course.
- `grammar-rules.json` SHA-256 (wave 1): `66f3a18bc02802e38e11bcabcc4dd9c4e8b279cebbb3401f9b5804d7ac780437`.

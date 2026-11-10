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
| S1 | First launch | Library shows the 21 bundled stories and the daily goal card, top to bottom from A1 to C2, the first three (The Red Boat A1, A Day at the Market A2, The Lighthouse Keeper B1) at the start of their own level, then the 18 stories with senses (S19), three at each level. The Library lists the newest book first, so a first launch adds them in the reverse order. Each bundled story's row says "Our story" where it would show the author. Reading them needs no internet. An install from before the 18 (it has the old `seeded` mark but not `seeded-stories-v2`) gets them once, at the next launch: only the 18, never the first three, below the books the learner has (which keep their places, and "Continue reading"), in the order A1 to C2, as ordinary books that can be deleted, with no message; a story already in the Library is not added again. |
| S2 | Open a book | Reader shows the text; returning later reopens at the same paragraph. |
| S3 | Tap a word | Any word of the text can be tapped, in any script (a word is a run of letters with their accents, Shared logic: names and loanwords such as "Joaquín", "café", "Kraków" are one word); the English help is for English words (the dictionary for Latin-script words only). A card shows the base form ("animals" → "animal", "stole" → "steal"; for an irregular verb also offline), IPA, translation, definition, the sentence and its translation. The definition ends, in smaller type, with "— Wiktionary, CC BY-SA" (cut with "…" and ", shortened" when the app cut it to 500 characters); a screen reader hears it as one element, "<definition>. Source: Wiktionary." (with the part of speech first when there is one). A past or participle of the irregular-verb table that is not also another word ("tore", "torn", "sprang", "lit", "lain") is always that verb, except as a name: its meaning is the table's Spanish meanings (else the translation of "to {base}"), its definition is a verb's; "lied" and "hanged" are the regular twin ("mentir", "ahorcar"). An -s or -ing form of the table ("lights", "bears", "springs", "meeting") is that verb only where its sentence proves it (Shared logic); elsewhere it is an ordinary word: the dictionary and the translation of the word as tapped, no table meaning ("the lights", "three bears", "a meeting"). "lying", "lies", "hanging", "hangs" take their sense from the next word ("lying to" → "mentir", "lying on" → "estar acostado"); when it doesn't tell, the card is unsure with the two senses: "to lie — estar acostado, tumbarse" / "to lie — mentir". "lies" no step proves a verb ("She tells lies") is unsure between the twin's noun and the verb: "the lie — mentira" / "to lie — estar, encontrarse" (the table's `nounEs` and `sEs`); after a determiner it is that noun ("his lies" → "lie"). An -s form of a base that is mostly a noun (`nounFirst`) after a noun subject with no object after it ("The bell rings") is unsure: "to ring — sonar" / "the ring — anillo" (the noun's regular lemma, spelled like the base; chosen, it is saved as "ring" with the label "the ring"). "bound for" and "bound to" + a verb are one expression: the card shows "bound for" / "bound to" with the table's meaning ("rumbo a, con destino a"; "seguro que · obligado a"; outside Spanish the translation of its `query`, "heading for", "certain to"), the dictionary's adjective definition of "bound" (nothing, not "No definition available.", when it has none), and Save stores the expression as one entry (like a verb group, S16). A form that is also another word is read from its sentence: "she left" → "leave", "turn left" → "left", "a bit" → "bit"; when the sentence doesn't tell (unsure), the card doesn't guess: the tapped word (no IPA, translation or definition), the sentence and its translation, a guide line and its two readings as a single choice (the guide says "The sentence's translation tells you which one:" while the sentence's translation shows or is on its way, else "Which one is it in this sentence?" — offline, translation failed or no translation language yet; with no language yet, the language choice comes right below the sentence, before the guide), most common first (`nounFirst`: the noun), none chosen: a verb as "to {base}", a noun as "the {noun}", each with its meaning ("to leave — irse, salir", "the left — izquierda"; "lay" after I/you/we/they or a plural noun subject: "to lie", "to lay"; a form with no noun: its two verbs). A verb reading's meaning is the table's first Spanish meaning in Spanish, else the translation of "to {base}", or of the table's English `query` for that sense when it has one ("to lie down" / "to tell a lie", "to hang up" / "to execute by hanging"); if the two rows' meanings still come out the same, each adds the sense's short English `gloss` ("recline", "say what isn't true"); a noun's, the translation of "the {noun}"; dictionary entry and definition match the reading's part of speech: when the table gives the base's IPA, the entry whose pronunciation matches it ("wind" /waɪnd/, not /wɪnd/), its first meaning of that part of speech; when no entry matches the table's IPA, no definition and the table's IPA. A noun of tear, lead or wind takes its pronunciation from its sentence (`nounIpa`, its rules in order, those on the next word before those on the word before: "tears in her eyes", "a tear rolled" → /tɪr/; "a tear in my shirt" → /tɛr/; "made of lead", "lead pipes" → /lɛd/; "took the lead", "the role of lead singer" → /liːd/; wind → /wɪnd/; with no clue, "tears" → /tɪr/ and "leads" → /liːd/, their usual sense) and the entry with that pronunciation; when the sentence doesn't tell ("the tear was small"), no IPA or definition from the dictionary. A noun is spoken as written, except a noun whose sentence proves a sound the voice wouldn't make: lead /lɛd/ is said "led", tear /tɛr/ "tare" (the plurals "leds", "tares"; the IPA shown is the headword's, /lɛd/, /tɛr/). The regular twin ("lied", "mentir") shows the base's IPA from the table (lie /laɪ/, hang /hæŋ/) and no definition; with no entry of that part of speech for the base, the word as tapped, else no definition (never another part of speech's); a reading nothing proves has no definition. Choosing one checks it (the other stays, to change it), shows its IPA and definition (aligned with the rows; "No definition available." only once its look-up has answered, never while it runs), and Listen and Save follow it. On iOS this card opens at full height. Translation starts when the card opens, alongside the definition. The translation is in the learner's language; a small language button under it changes the language in place. |
| S4 | Save word | "Save word" (primary, right) saves the word for review; it is underlined in yellow in every book, including inflected forms ("steal" also marks "stole" and "stolen", "travel" also "travelled"); a form that is also another word is marked only where its sentence makes it that word (saving "leave" marks "she left", not "turn left"; saving "leaf" marks "the leaves", not "she leaves"). A message "“word” saved to Words" with Undo shows for 4 s, longer when the system asks for more time to act (Android's accessibility timeout); with a screen reader or switch control it stays until Undo, Close or a newer message. Unsure with nothing chosen, Save and I know it store the tapped form ("left") with both readings' meanings; it marks that exact form everywhere. A certain or chosen reading stores its base with its sense (verb, noun or homonym) and marks only forms read as that sense ("the wind" doesn't mark "She wound the clock"). One spelling can be saved once per sense. Words and Review always show a sensed word whose spelling is a homograph of the table, a base marked mostly a noun (`nounFirst`) or a base with a regular twin with its sense label, even when only one sense is saved: "to wind" / "the wind", "to ring" / "the ring" (a mostly-noun -s chosen as the noun is saved as its lemma), "to lie"; in Words two verb senses of one spelling also show their first meaning: "to lie (estar acostado, tumbarse)" / "to lie (mentir)" (the table's first Spanish meaning in Spanish, else the first meaning of the translation). An occurrence its sentence leaves unsure never marks a word saved with a sense, whatever their bases. Saving a reading of a form saved unsure replaces it, keeping its review progress; Undo puts it back. |
| S5 | I know it | "I know it" (secondary, left) saves the word as known; it is not underlined or reviewed. A message "“word” marked as known" with Undo shows like S4. |
| S6 | Listen | Word and sentence can be read aloud with an English voice. Read aloud reads continuously, sentence by sentence, from the top of the screen to the end of the book, highlighting the sentence being read on a neutral fill and scrolling only when it leaves the screen (no animation with Reduce Motion); scrolling by hand stops the following until that sentence is back on screen. Once started, a bar at the bottom (until leaving the reader or the end of the book) has "Previous sentence" (back to the start of the previous one and on), "Pause"/"Play" (Play goes on from the start of the paused sentence) and "Repeat sentence" (a toggle that loops the sentence being read; while on, the first button is "Add previous sentence" and grows the repeated stretch backwards one sentence at a time, reading it from its new start; the bar says "Repeating N sentences", the stretch has a neutral fill and a bar at its side; off, reading goes on forward). The top button only starts reading. Tapping a word pauses and opens its card; reading does not resume by itself. The word card's "Read from here" starts reading at its sentence. The speed setting applies from the next sentence. Reading moves the saved position. Leaving the reader or the app pauses: no reading without the text on screen. A call, an alarm, another app taking the sound or a voice that fails also pauses on that sentence, so the bar never shows Pause while nothing is heard. When the voice stops, other apps' sound returns to full volume. With no English voice on the device, reading aloud and Listen, on every screen, stop and say so ("Can't read aloud" · "This device has no English voice."), with a button to the voice settings where the system can open them (Android) or where to add one (iOS); once a voice is added, the next request speaks. The card's Listen says the headword, then the word as in the text when it differs ("wind", "wound"), each with the table's spoken form for its proven slot (a noun as written, except lead /lɛd/ "led" and tear /tɛr/ "tare" when its sentence proves that sound); unsure with nothing chosen, the tapped form in each reading in the rows' order (once when they sound the same). |
| S7 | Review | Recall first: a due word shows alone with "Show meaning" and never with a meaning: its sense label when it has one (S4: "to wind", "to lie", never "to lie (mentir)"); when two senses of its spelling are saved, or when the label alone doesn't tell the sense (a verb with a regular twin, lie or hang, saved as the verb or as the twin, even with one sense saved), also the sentence it was saved from with the word in bold and no translation; the meaning then shows the translation, the sentence it was saved from (the word in bold), that sentence's translation (in the current translation language, filled in on the device when missing) and a button to hear it, and only then "Again" and "I remembered". A new word is first due at the start of the next review day (days start at 04:00 local time); "I remembered" moves it to the next box, due at the start of the day 1, 3, 7, 14 then 30 days later, and after the last box it is learned; "Again" sends it back to the first box and repeats it in the session. A session holds at most 20 due words, interleaved by book, with "N of M" beside its progress bar. The Words tab shows how many words are due, updated after every answer, when the app comes back and when a new review day starts. At the end: "Done for today." and, when there are any, "N words tomorrow." ("Mañana tienes N palabras."); if more words are still due now, "Done for now. N more due today." with "Keep going". The sentence shows in bold only the occurrence that was tapped. A word saved unsure shows both readings, as on the card, in place of its translation. Listen in Review and Words says a word saved as a verb or the regular twin with the table's spoken form of its base ("tare" for "tear"), a noun as written ("tear"), except a noun whose saved sentence proved a sound the voice wouldn't make (lead /lɛd/ "led", tear /tɛr/ "tare"); a word saved unsure, each saved reading's form in its reading, once when they sound the same (as on the card). |
| S8 | Daily goal | Reading time counts while the reader is open; the card shows minutes today and the streak (days meeting the goal). |
| S9 | Discover | The recommended classics ship with the app (title, author, level) and show at once, under "Free classics from Project Gutenberg." ("Our stories and free classics from Project Gutenberg." while a level shows the app's own stories, S13); "Read" is a button in the row, not a link on the whole row; their covers load from Project Gutenberg's file cache (decorative and hidden from screen readers: the row says the title and author; while a cover loads, or without internet, a drawn cover shows). UI tests load no covers, so they don't depend on the network. Search by title/author shows "Searching Project Gutenberg…", after 8 s also "Still searching. Project Gutenberg can be slow." with Cancel; a new search cancels the previous one; results end with the line "Project Gutenberg books are public domain in the US. Elsewhere, check your country's laws."; a failed search says "You're offline. Connect to the internet to search." or "Project Gutenberg didn't answer. Try again." with Retry, and the recommended books stay below. "Get" downloads the plain text straight from Project Gutenberg's file cache with a progress ring (tapping it cancels) and turns into "Read", which opens the book; a failed download says why in its row ("This book isn't available right now." for 403/404/410 or an empty book; offline; "Project Gutenberg didn't answer. Try again.") with Retry. Results, errors and a finished download are announced to screen readers. Offline means no connection, a lost connection, or a host that can't be found or reached. |
| S10 | Import | A plain-text `.txt` file can be imported; Gutenberg license headers are removed. |
| S11 | Settings | Daily goal, text size, speech speed and translation language persist. "Translate into" shows "Ask me when I tap a word" until a language is chosen. About has "Privacy policy" (opens the policy), the source code link, and the credits: "No accounts, no ads, no tracking.", the public-domain line of S9, "Our stories were written with AI help. Anyone can use them freely." and "Definitions from Wiktionary, CC BY-SA 3.0/4.0, via Free Dictionary API." (screen-reader hint "Contains links"; each name a link: `https://en.wiktionary.org/`, `https://creativecommons.org/licenses/by-sa/4.0/`, `https://dictionaryapi.dev/`). Android also lists the open-source licenses of its libraries. |
| S12 | Offline | Without internet the reader, saved words and review work; the card says translation/definition are unavailable (a platform may name the reason, e.g. Android needs Wi‑Fi once to download the language). Saving a word never waits for translation; a missing translation is filled in on the device as soon as it is available, and Review shows "No translation yet. Connect to the internet once to get it." until then. |
| S13 | Level filter | Discover shows chips "All" plus each level that has a recommended book or one of the app's own stories (A1–C2); "All" is selected by default and shows the recommended books; a level shows its own stories first ("Our story"; "Read" opens it in the reader, "Get" puts it back in the library at once if it was deleted), then its recommended books, in order, under the subtitle "Our stories and free classics from Project Gutenberg." and, after the stories, the line "Our stories were written with AI help. Anyone can use them freely." (three stories at every level, and the first three); a level with neither says "No recommended books at this level."; the chips stay with the recommended books, below any search results. |
| S14 | Translation language | The default is the first language in the device's preferred-language list that is supported and not English (Chinese → Simplified). If there is none, the first word card asks once "Translate into:" with up to 5 languages (the region's language first, then Español, Português, Français, 中文, العربية, without repeats) and "More languages"; the choice is saved. Each saved word records its translation language; words in another language are translated again when shown. |
| S15 | Saved state on the card | A saved word's card shows "Saved" or "I know it" checked (check icon, selected state, announced as "Remove from Words" action); tapping the checked button removes that state, with Undo (timing as in S4). Deleting a word in Words happens at once and offers Undo for 5 s with the same rules (no confirmation dialog); the message and the row's Listen button name the word as Words shows it ("“the wind” deleted", "Listen to the wind"). The language button under the translation is announced as "Translation language: <language>". |
| S16 | Helper and modal verbs | Tapping do/does/did used for a negative, a question or a prohibition ("did not go", "Did you see…?", "Don't touch"), or a modal (can, could, will, would, shall, should, must, may, might, with their negative forms), shows the base form ("do", "will"), "Helper verb" or "Modal verb", the verb group in the sentence ("did not go", "should have known") with its translation instead of the word's own, and one short note on what it does (e.g. "“didn't” (= “did not”) + base verb = past negative: “didn't go”, not “didn't went”."). No definition or IPA; Listen says the verb group. Saving stores the verb group as its own entry (the sentence when there is none), with its base form and kind; Words and Review show it. A question tag ("…, didn't you?") is explained as asking the listener to agree. A negative modal ("mustn't", "won't", "cannot", "must not") says it is the negative: "mustn't" = not allowed. "do" as a main verb ("I did my homework") is an ordinary word. have/has/had before a past participle ("has seen", "had never left", "Have you seen…?") is a "Helper verb" with a note on the perfect ("“has” + past participle: it happened before now and still matters: “seen”, not “saw”."; "had": "it happened before another past moment"); "had better"/"'d better" + verb is strong advice. A pronoun contraction ("it's", "I'll", "you'd", "let's") shows what it stands for as its base form ("it is", "I will", "let us"); with 'll or 'd as would it is a "Modal verb", with 've/'s/'d as have/has/had before a participle a "Helper verb", else it has no label and its note says "“it's” = “it is”." ("it's" also says "“its” (no apostrophe) = belonging to it."; "who's" contrasts "whose"; "let's" is a suggestion; "he'd put" shows "he had / he would", read aloud with "or", and the note "“he'd” can be “he had” or “he would”: the sentence's translation tells which."). The verb-group line is not shown when it is just the tapped word ("That's"). Saved, a contraction is its verb group or the contraction itself, with its expansion as base. have as a main verb ("I have a dog", "had a bath", "have to", "have got"), "its", and a noun + 's ("John's book") are ordinary words. |
| S17 | Selected word | While the card is open, the tapped word is marked in the reader (solid yellow marker, black text) and in bold in the card's sentence, underlined with its verb group if it has one. If the half-height card would cover it, the reader scrolls it into the upper part of the screen (without animation when Reduce Motion is on). |
| S18 | Corrected words | Once after updating, each saved word whose sentence now reads differently is corrected on the device, newest saved first, at most 1,000 corrections per run (the rest in the next runs, so every correction can be undone) (a certain reading becomes that word; an unsure one the tapped form with both readings), translated again (later when offline, S12) and merged into an existing entry of the same name. A corrected word in Learning starts its review again: first box, due now, keeping when it was saved, its sentence and its book; due only once it has a meaning (else when its translation arrives, S12). A known word stays known. A corrected verb gets the table's IPA for its base; a corrected noun of tear, lead or wind gets its sentence's IPA (none when nothing proves it). Words shows one card until closed: "Fixed to match its sentence: “leave” → “left”." (several: "Fixed to match their sentences:", up to 3 lines and "and N more"), with Undo and Close. Undo puts back only the entries the correction changed or merged, each as it was (with its review box), latest first; an entry changed after the correction (reviewed, edited) stays as it is now, and a word deleted since is not brought back. Undo then shows a message like S4's (without Undo): "Words put back as before" ("Palabras restauradas como antes"), or when some stay as they are now "Put back, except N you've changed since" ("Restauradas, salvo N que cambiaste después"). |
| S19 | Story senses | Each of the 18 original stories (S1) ships with a senses file (`<id>.senses.json`, schema version 1) that says how a word, or a group of words, is used at one place in the story: its base form, part of speech, IPA, its Spanish meaning in that sentence and, for a group, the group and its meaning ("his face went red": "se puso colorado"; "free" in "my oven is free": "libre, disponible", not "gratis"). When the tapped word of such a story has an entry, the card shows that sense before the verb-or-noun rule (S3) and the helper verbs (S16): the base form as headword ("In the text: went" when it differs), the sense's IPA between slashes (none when the file has none; never the dictionary's), and a small label (caption size, secondary colour): "Proper name" for a name that is also a word ("The Blue Table", "Mr. Long", "Cape Town"), "Word from another language" ("Bunica", "Amma", "san"), else "US English", "UK English" or "Local English" when the word or meaning is used only there. The meaning replaces the word's own translation: in Spanish the file's meaning; in another language the translation of its source (the source is one exact table (`StorySenseHit.translationSource`): a name or a word from another language: none; a group of words (kind chunk): the group's text, else the base form (the `en` gloss is ignored); a bare word (kind word): its `en` gloss, else its group's text, else none when the story has another sense of that base form or its Spanish meaning contains `no «` (or `no "`), else the base form. With no source the card shows no meaning for the word and the translated sentence tells); a name and a word from another language have none in another language, and a name's Spanish remark ("nombre de la empresa…") shows under the headword. A group is underlined in the card's sentence and shown below the meaning on one line, with its Spanish meaning ("his face went red — se puso colorado"; the group alone in another language). The definition shows only when the sense's kind is word or chunk, its base form is one word and its part of speech is noun, verb, adjective, adverb, preposition, interjection or modal (a modal looks up "verb"; phrasal verb, phrase, proper noun and suffix have none), and the dictionary has an entry of that part of speech; otherwise none: never the dictionary's first meaning of another part of speech. A sense's Spanish note shows under it, and a name's Spanish remark, in Spanish only; a name shows no language chip (it has no meaning). A name and a word from another language are not offered to save: the card has no "Save word" or "I know it", because their spelling is also a common word ("Long" in "Mr. Long"). Listen says the base form, with the sense's IPA when the base form is one word (a group is said as text; Android has no IPA input and says the base form as text). The IPA line is hidden from screen readers (Listen says the word); the headword is read as English and the meaning in the card's language; the group line is read "Group: …". "Save word" and "I know it" store the base form (a group's: "go red") with the sense (S4's `sense` is "s:" and the sense's key in the story's file, e.g. "s:get_fetch"), the story's id, the sense's meaning and IPA, the sentence, the tapped form and, for a group, where the group is in the sentence. A word is saved once per sense (the same base form and sense in two stories is one entry; `story` is the last one saved): "get" saved from two senses is two entries, which Words and Review name like S4 does, with the first meaning: the label "get (ponerse)" is added only when another entry with a sense of that spelling is saved, and its meaning is the first part of the saved translation (cut at " · "), cut at the first "," or "(" and trimmed; with only one sense saved Words and Review show the plain "get" (unlike S4, whose labels "to wind"/"the wind" come from the reading, not from the meaning). Review's prompt names it plain and shows the sentence when two or more senses of that spelling are saved. Words and Review mark the whole group in the sentence ("his face went red"). In the reader, a word being learned (not one marked "I know it") that was saved from a story sense in that story, with that base form, is underlined only at the places of the story with the same sense, a group as a whole; at a place of the same base form with another sense only that place's own range is left out of the generic underline; everywhere else (a word with no entry, another book) it is underlined as any saved word (S4). The saved sense, story and group are read back within bounds: a sense key outside a–z, 0–9 and `_` (40 at most), a story id that is not a–z/0–9 words joined by single dashes (60 at most), or a group that is not inside the sentence (it is dropped too when the sentence was cut or cleaned) or does not hold the tapped form is dropped; the story, the source and the group are kept only for a word with a story sense, no verb group and no unsure readings (a group is kept when there is no tapped-form range); a `#` in a word is removed.
  A word saved from a story sense also stores its translation source (the table in S19; nothing when the table gives none). Words are translated into another language only from that source, never from the bare spelling; with none, nothing is translated, the old meaning of another language is cleared when the language changes, and Review says "No single meaning out of context. See the sentence." ("Sin significado suelto fuera de contexto. Mira la frase.") instead of promising a translation, and keeps the translated sentence (S7). A plain word saved again as a story sense loses its old meaning and IPA, which are filled in again from the sense. A word without an entry behaves as before (S3, S4, S16). Entries apply only to the library's copy of a bundled story whose paragraphs are exactly those of the bundled text: a book imported or downloaded with the same title, or with that title and author but other text, has none, and a file the app refuses (Shared logic) leaves the story as if it had none. The tapped word of a group may be any of its words that has an entry. |

## Shared logic (same rules, same tests on both platforms)

- Paragraphs: split on blank lines, hard-wrapped lines joined.
- Words (what can be tapped, marked and saved): the pattern (ICU / Java syntax, possessive quantifiers)
  `(?:\p{L}\p{M}{0,4}+)++(?:['’](?:\p{L}\p{M}{0,4}+)++)*+`, applied to the text as it is, left to right, longest
  match. In words: a run of letters of any script, each with at most four combining marks after it ({0,4} counts code
  points, not UTF-16 units; `\p{M}` is Mn, Mc and Me), with an apostrophe (' or ’) between two letters kept inside
  ("don't", "l’homme", "O'Brien", "dogs'" is "dogs"). A word starts with a letter, so marks alone, digits, emoji,
  hyphens and punctuation are not words and end one ("Jean-Luc" is two words, "naïve2" is "naïve"); a letter with a
  fifth mark ends the word and the extra marks belong to no word. ZWNJ (U+200C) and ZWJ (U+200D) are format
  characters, neither letters nor marks: they end a word too (Persian "می‌خواهم" is two words). Composed ("é") and
  decomposed ("e" + U+0301) spellings are each one word, over different numbers of UTF-16 units. Scripts that write no
  spaces (Han, kana, Thai) give one word per run of letters. Offsets are UTF-16 units of the unchanged text. Reading
  and cutting text take time linear in its length, whatever it is made of (a long run of marks, letters or
  apostrophes is read in one pass).
- Word keys (saved words, undo, translations, marking, dictionary): the word with ’ → ', lower-cased with the Unicode
  full lower-case mapping of each character on its own (no locale, no final-sigma rule: "ΟΔΟΣ" → "οδοσ"; "İ" → "i" +
  U+0307), then composed (NFC) when it has a letter outside ASCII, then cut to 600 UTF-16 units (see Cuts). One
  function makes the key, and every id, look-up and match uses it, so a run of letters longer than 600 units (a Han
  run) is saved, found, translated, undone and marked under the same key. "Capitalised" (a name, a sentence start)
  means its first character has the Unicode Uppercase property and the rest of the word has none.
- English rules work on ASCII words only: base forms (plural, past and -ing endings), the irregular-verb table and the
  verb-or-noun rule never apply to a word with a letter outside ASCII; such a word is its own only key, and next to a
  verb form it counts as an ordinary word or, capitalised in mid-sentence or opening a sentence, as a name (a subject:
  "Joaquín left" reads like "Tom left").
- Dictionary look-up: the key is sent only when it matches `^\p{Latin}(?:\p{Latin}|\p{M}|['’])*\z` (Java:
  `\p{IsLatin}`; `\z`, so a trailing line break does not match) and is at most 50 UTF-16 units (measured on the key,
  after lower-casing and NFC): a Latin-script word with or without accents or apostrophes ("café", "naïve", "résumé",
  a name such as "Joaquín", which just has no entry). Another script (Cyrillic, Greek, Han, Arabic…), a mixed-script
  word or a longer one is never sent and shows "No definition available." with its translation. A reading's base is a
  key too (lower case, NFC) before it is looked up.
- Text in an address (a dictionary word, a catalog search): UTF-8, each byte outside A–Z a–z 0–9 written %XX with
  upper-case hexadecimal digits (space is %20, an apostrophe %27, "é" %C3%A9); nothing else stays as it is. A catalog
  search is cut to 200 UTF-16 units first: "Les Misérables 東京" is `search=Les%20Mis%C3%A9rables%20%E6%9D%B1%E4%BA%AC`.
- Invisible formatting: text imported or downloaded for a book, and a word's saved sentence, lose their format
  characters (Cf: bidi overrides and isolates, zero-width spaces, the byte-order mark, soft hyphens) except ZWNJ and
  ZWJ.
- Cuts: a cut at the paragraph (2,000), sentence (600) or any other cap moves back up to 6 UTF-16 units, never to less
  than one unit after the start of the piece, while the unit at the cut continues what comes before it: the second
  half of a surrogate pair; a combining mark (Mn, Mc, Me, in the BMP); a variation selector U+FE00–FE0F; a joiner
  U+200D, or the unit right after one. Residual: a combining mark outside the BMP (e.g. U+1D165) is not recognised and
  may be cut from its letter.
- Test vectors both platforms pass (names, forms, edges): "Joaquín" composed (one word of 7 units) and decomposed
  (one word of 8); "Zieliński", "Kraków", "São Paulo" (two words), "café naïve résumé"; a letter with 6 marks (a word
  with 4, the rest skipped); "\u0301\u0301" (no word); "naïve2" (one word, "naïve"); "Jean-Luc" (two); "dogs'" (one,
  "dogs"); "我爱你，你好。" (two words; sentences end at 。！？؟ with closing 」』 kept); "مرحبا بالعالم" (two);
  "Don’t"/"l’homme" (one each); "می\u200Cخواهم" (two); keys "ΟΔΟΣ" → "οδοσ", "İ" → "i\u0307", "CAFE\u0301" → "café";
  "Les Misérables 東京" in an address; 400,000 units of each hostile shape read in under 10 seconds.
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
- Sentence of a word: the text between sentence ends (`[.!?]+` plus closing quotes, before a space or the end; or `[。！？؟]+` plus closing quotes and 」』, with no space needed), trimmed.
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
- Bundled stories (title, level), in this order: The Red Boat, A Shoe in the Fridge, An Empty Apartment, Nour's Long Race
  (A1); A Day at the Market, A Part for Lila, The Oven Next Door, The Tree in the Second Row (A2); The Lighthouse Keeper,
  A Very Important Visitor, The Beat on the Hill, The Chess Table by the Lake (B1); Notes on the Fridge, The Presentation in
  Kisumu, Three in the Morning (B2); A Number in Osaka, An Apartment Full of Notes, Lane Four (C1); Five Minutes, Maximum,
  The Exit Interview, The Second Violin (C2); author "Lingleaf". The first three have no senses file. They are plain text (no title line, a
  paragraph per blank line), dedicated to the public domain (CC0 1.0); all 21 were written with AI help, which the
  app says (S11, S13). A saved copy is the shelf story with the same title, author "Lingleaf" and no Gutenberg id.
- Story senses (see `StorySenses`; `StorySensesTests` is the contract: port its refusal cases and the corpus test over all
  21 texts). Read once per story, strictly, like the irregular-verb table, against the story's own paragraphs. Any of
  these refuses the whole file: more than 262,144 bytes (at most one byte past the cap is read); JSON nested deeper than 8 levels or
  with a closing bracket before its opening; a schema version other than 1; a missing or unknown key at any level
  (`schemaVersion`, `story`, `senses`, `entries`; a sense has `lemma`, `pos`, `ipa`, `es`, `kind` required and
  `variety`, `note`, `en` optional; an entry has `p`, `start`, `end`, `text`, `sense` and optional `chunk` with `start`,
  `end`, `text`, `es`); `ipa` is required but may be null; a story id that is not the file's story or not a–z/0–9 words
  joined by single inner dashes (60 at most); a sense key outside a–z, 0–9 and `_` (40 at most); `pos` not one of
  noun, verb, adjective, adverb, preposition, phrasal verb, phrase, proper noun, modal, interjection, suffix; `kind` not
  word, chunk, name or foreign; `variety` not AmE, BrE or local; a lemma (1–60 code points) that does not start with an
  ASCII letter or digit or has a character other than ASCII letters, digits, space, `'`, `’`, `?` and `-`; an `ipa` of
  0 or over 80 code points, with a scalar outside the allowed set, not in NFC, or with only spaces (the allowed IPA scalars are
  the letters a b d e f g h i j k l m n o p r s t u v w x z, æ ð ŋ ɑ ɒ ɔ ə ɚ ɛ ɜ ɝ ɡ ɪ ɹ ɾ ʃ ʊ ʌ ʒ ʔ θ ʤ ʧ, ˈ ˌ ː ˑ and the full
  stop, U+0329 and U+0303, plus the space and ɕ ɴ ɯ); `es`, group `es`, `note` and `en` (140, 140, 200 and 60 code points) that are empty, not trimmed
  (whitespace and newlines), or contain a control, format, line or paragraph separator, private-use, unassigned or
  surrogate character, a Hangul or braille blank filler, more than 4 accents on a letter, or a doubled space (they
  must equal their own cleaned text); an entry `text` of 0 or over 40 code points or that is not the text at its
  offsets; offsets (UTF-16, within the paragraph) with `p` not below the paragraph count (at most 1,000 paragraphs),
  `start` not below `end`, or `end` over 2,000; an entry that is not a whole word as `TextTools` splits the paragraph;
  two entries for one word; more than 2,000 senses or 5,000 entries; a group (text 120 code points at most) that does
  not start and end on whole words, does not contain its entry's word, or is not the paragraph's text at its offsets.
  Format characters between accents do not start a new letter (an accent run is capped at 4 even through U+200B). Counts are of Unicode code points. A JSON null on an optional key (`variety`, `note`, `en`, `chunk`) reads as absent (`ipa` is required, but its value may be null); a repeated key is not detected: the last value wins, and the bundled files have none (a test checks). A group's text and an entry's text also go through the same text rules. "Unassigned" depends on the platform's Unicode version: the shipped files use only assigned scalars. A file is used only for a book whose paragraphs equal those of the bundled text.
  The tests load every bundled file and check every entry against the bundled text.
- Imported .txt: title is the file name without its extension (empty → "Book"); Gutenberg header/footer removed; files over 10 MB or with no text are refused.

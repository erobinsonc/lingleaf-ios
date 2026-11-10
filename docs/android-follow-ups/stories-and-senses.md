# Android follow-up: stories and senses (iOS PR #57, SPEC S1, S3/S4, S7, S9, S11, S13, S19)

Android is paused; this is everything it needs to match iOS later. SPEC.md is the contract (identical in both repos).

## What to copy
- The 21 texts and 18 senses files in `Lingleaf/Resources/Books` (identical bytes, LF line endings: add a `.gitattributes`
  keeping `Books/*` LF) and the CC0 `LICENSE` there. Check them against this list (sha256) after copying:

| File | sha256 |
|---|---|
| `LICENSE` | `7c60d0e545be6ab385820057fcc235d46c08b9305c1b3fda497e3a1a018ab0c2` |
| `a-day-at-the-market.txt` | `b0f9dbbf659c7c78327233c6e0328b27df3adff3cf3f04f6dd44713b8c723565` |
| `a-number-in-osaka.senses.json` | `a4a3e2f41426f0c4b0fc66011a8f3cbdc7bc1c51327ec5caaa49a814da999c18` |
| `a-number-in-osaka.txt` | `b579aa16045ca0191a93178503a0005402bcded04017a867cb178c0ba93ef4e7` |
| `a-part-for-lila.senses.json` | `644abc7a267135409753ec496f40c3e63b5584cffc41937a622b8e09e68ac83b` |
| `a-part-for-lila.txt` | `977c93b745a8d327b7af53e13cbcf51b4fa9f532c9ad2d2fc42f0ba470b26e0a` |
| `a-shoe-in-the-fridge.senses.json` | `601b1a7ad960d9ce6559d669b3262fa75d725cae197f84f902bdfb0548b6f574` |
| `a-shoe-in-the-fridge.txt` | `cfb2e8b3df895693e624743d816a984e469648d8ddb1a5a470175535e9c9141d` |
| `a-very-important-visitor.senses.json` | `5524c840f07fb89dd6fb41342098e6c9ce98a3c22f41e967ead3318971279523` |
| `a-very-important-visitor.txt` | `7800d1e62729f8acaf99643cc5c5f415fdb8f3918226398926ae2c8d9ace5b13` |
| `an-apartment-full-of-notes.senses.json` | `6060718387837a2cd709df76247980828ef5e456ecf953a18a6696b7c8a89445` |
| `an-apartment-full-of-notes.txt` | `f0ce84ae2561a019d2eb47acce1f8d1d8aca3741e9fd553cc8ad7ada7c7eecc7` |
| `an-empty-apartment.senses.json` | `69c345bb82eb86205762a53eb2109a8a657199190d971b1655aa94fd8039abdc` |
| `an-empty-apartment.txt` | `20df026c93491d1531ab438d45b70a7a8feef6adb1aa387769e1cde333f333a8` |
| `five-minutes-maximum.senses.json` | `9e4f518c66ca047d5f7f5e718a1ad227a4d7422d101e484e24a96a66dfaf5fc8` |
| `five-minutes-maximum.txt` | `3896f7c4d77f0105584ca93e6eb74805e1be52731e6cdf87fe4a9d02ca7049e9` |
| `lane-four.senses.json` | `7f56d8f6ace18f1f6cebe2d5d0a1b7880e518408bf1fb59e8553cb772a3fcb43` |
| `lane-four.txt` | `f98157868e04ab922bcefa86d629e4f130096de835d28433af8999702686837a` |
| `notes-on-the-fridge.senses.json` | `86ae47a3c5df6093fd906ba5bbd675e5f85dedcdacc57e78f9dabface09bc23f` |
| `notes-on-the-fridge.txt` | `a1e1a924821fdcc5582c1d8c18f5bc80dc8639c41ebeb745964466e1e5604bf7` |
| `nours-long-race.senses.json` | `e746414b4dde2d75d4a8a731592865fde644287618bb7ad0376de04b53ff0d97` |
| `nours-long-race.txt` | `8c90cf85cab3c7a5febcfaafe0c3901e469c52ee7c9f30fb6b1c10eed43a1f72` |
| `the-beat-on-the-hill.senses.json` | `538aca30aaedfc76344949b90535ca14380a3c218ae681c275e3f0b23097cb1e` |
| `the-beat-on-the-hill.txt` | `62183212c89844000706d15c0aab202ccd252ea7ea076326e314a3ada30757e1` |
| `the-chess-table-by-the-lake.senses.json` | `bc870ea76a705b13f2252d9759b1171c4f507d63b175ba9ae02b852c46921981` |
| `the-chess-table-by-the-lake.txt` | `0740507b82d1af3674bd695732c4111b81414fd3c5d23acdf8dfc53995ede500` |
| `the-exit-interview.senses.json` | `3b37a64573c23caa125b972ad4443027b829193f25d40096568e9f85a87442e0` |
| `the-exit-interview.txt` | `2ecfd88799b0d62119c4e82e0d20fcf59d1e325fdb40b90581f842045f1c1cba` |
| `the-lighthouse-keeper.txt` | `dfba714915a5ff7048bbfb291dec693235b016f385df1477c03ac73dfa8e21b5` |
| `the-oven-next-door.senses.json` | `22fd8c78ea32622843fbc3fbf923fa44cb0c13cec7aad685f503b88c7c74a1d6` |
| `the-oven-next-door.txt` | `f1919b19c767ccc0d62a010855add970b26861d355f3bc29255dbeca8d661652` |
| `the-presentation-in-kisumu.senses.json` | `17624ed1b50c5afed2431685ffefa4c12300804b260c34f2f0c8b13ab68b6f96` |
| `the-presentation-in-kisumu.txt` | `6ee8cd75fbb0908275b9de101a9dcd0c114890fc1d2dcc4d48d536784c3bff7d` |
| `the-red-boat.txt` | `b28d3ae112ab319ea14eeae22c0c537fcae37bc385b3765b6e9de7b2ed4d059e` |
| `the-second-violin.senses.json` | `65aa1218a35b66105949f62d50ca855ccd6a4ba12808ec06953e0196ea25fe9a` |
| `the-second-violin.txt` | `d5fe41d685f19510778a369dc6eb673e53b163fc005a5f829085ff969afa342a` |
| `the-tree-in-the-second-row.senses.json` | `5e8b4a1fdec98e3584070902581663c36b0708c96416caa2343dfd3869c33254` |
| `the-tree-in-the-second-row.txt` | `fae43c2e67a4083a9b4eebb933457ec986c34313e3130528b54f222ebdd3411b` |
| `three-in-the-morning.senses.json` | `e19cb76eb91ed82c0a5e18b6f9a8732fca9bce73158389a32980994168f529f6` |
| `three-in-the-morning.txt` | `e987ecb854bb5fb1d790a1baeca8e418c2eb122213b6b27a3562ce465b2ffef0` |

## Shelf and Library
- Android has no shelf today (only `BundledStory(title, level, text)` and 3 assets). Add `ShelfStory(resource, title, level, hasSenses)`,
  `BundledStory.shelf` (21, in the order of SPEC "Bundled stories": A1 to C2, the first three at the start of their level),
  `shelf(level:)`, `libraryCopy(of:in:)`, `shelfStory(for:)` (title + author "Lingleaf" + no Gutenberg id; the author is internal data,
  isolated in one constant because the app will be renamed). Level chips come from the shelf; Discover rows have Read/Get.
- Row label: one string, "Our story" / "Cuento propio" (may become "App story" or "AI story"), in the Library row where the author shows, and in Discover.
- `seedIfNeeded`: first launch only; add in the reverse of the shelf order (the Library lists the newest first); a missing asset is skipped.
- `addNewStoriesIfNeeded`: key `seeded-stories-v2`; only when the old `seeded` mark exists; adds only the stories with senses (never the first
  three), below the learner's books (the books keep their places), A1 to C2, ordinary deletable books; writes the key after the books are saved and
  only when there was something to add; a story already in the Library is not added again. Tests: new install, update with and without the first
  three deleted, empty Library, once, retry.

## Strict reader and word card
- Port `StorySenses` (SPEC "Story senses": 262,144-byte cap read as cap+1, depth 8 and a closing bracket before an opening one, strict keys, null
  optionals (`ipa` is required but may be null), a repeated key is not detected (the last value wins; a corpus test checks the bundled files have none), code-point counts, NFC, `Character.getType` for Cc Cf Zl Zp Co Cn Cs, text equals its cleaned text, IPA set,
  whole-word entries, groups). Senses load only when the book's paragraphs equal the bundled text's.
- Word card (S19): skip S16 and the verb-or-noun rule for a word with an entry; headword = base form; sense IPA (hidden from TalkBack; no IPA input on
  Android TTS: say the base form as text); label (Proper name, Word from another language, US English, UK English, Local English); Spanish meaning from the file;
  other languages, the translation source is exactly: name/foreign: none; kind chunk: the group's text, else the base form (`en` ignored); kind word: `en`, else the group's text,
  else none if the lemma has a sibling sense in the story or `es` contains `no «` (or `no "`), else the base form; name and foreign words are not translated and not offered to save; name remark and note only in Spanish; group underlined in the sentence
  (map its range into the sentence) and shown on one line; definition only of the same part of speech, one-word base forms, kind word or chunk,
  `modal` looks up verb.
- Saved word fields: `sense` = `s:<senseKey>`, `story`, `groupStart/groupEnd`, `translationSource` (bounded on read as in `VocabWord.bounded`).
  One entry per sense; labels "get (ponerse)" when another sense of the spelling is saved; Review marks the whole group; the translation worker
  translates only `translationSource` and nothing when it is nil (clear the old meaning when the language changes; Review keeps the translated
  sentence and says "No single meaning out of context. See the sentence." / "Sin significado suelto fuera de contexto. Mira la frase." instead of "No translation yet"); a plain word saved as a story sense loses its old meaning/IPA; reader underline only at the same-sense places of the story
  (`StorySenses.underlines`), generic S4 underline elsewhere.

## Strings (en / es)
Our story / Cuento propio; Proper name / Nombre propio; Word from another language / Palabra de otro idioma; US English / Inglés estadounidense;
UK English / Inglés británico; Local English / Inglés local; Group: %@ / Grupo: %@; "Our stories were written with AI help. Anyone can use them freely." /
"Nuestros cuentos se escribieron con ayuda de IA. Cualquiera puede usarlos libremente." (Settings About and under the stories of a level in Discover).

## SPEC sync
Android's main SPEC.md already differs from iOS's: the first Android PR of this work must bring SPEC.md back in sync with iOS `develop` before any code.

## Tests to port
`StorySensesTests` (every refusal case), `BundledStoriesTests` (corpus over all 21 texts, no repeated JSON key, no two senses of a base form with the same first meaning, `en` required for bare words with siblings, no Peninsular
Spanish), `LibraryTests` (read-back cases: `testAWordWithAHashDoesNotBecomeAnotherWordsSense`, `testWordsSavedBeforeStorySensesStillLoad`, `testStoryFieldsAreBounded` (story, source, group), first-run order, migration cases, two senses = two entries, group range, bounds, translation source, name/foreign not saved).

A Zalgo test vector for the text rules: `a` plus 2 U+0301, U+200B, 2 U+0301, U+200B, 2 U+0301 cleans to `a` plus 4 U+0301.

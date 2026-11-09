# Android follow-up: stories and senses (iOS PR #57, SPEC S1, S3/S4, S7, S9, S11, S13, S19)

Android is paused; this is everything it needs to match iOS later. SPEC.md is the contract (identical in both repos).

## What to copy
- The 21 texts and 18 senses files in `Lingleaf/Resources/Books` (identical bytes, LF line endings: add a `.gitattributes`
  keeping `Books/*` LF) and the CC0 `LICENSE` there. Check them against this list (sha256) after copying:

| File | sha256 |
|---|---|
| `LICENSE` | `7c60d0e545be6ab385820057fcc235d46c08b9305c1b3fda497e3a1a018ab0c2` |
| `a-day-at-the-market.txt` | `b0f9dbbf659c7c78327233c6e0328b27df3adff3cf3f04f6dd44713b8c723565` |
| `a-number-in-osaka.senses.json` | `b5caae904ec14bb59916879351fe1688c9c53a2b800ea6e35494b6fd9aabab6b` |
| `a-number-in-osaka.txt` | `b579aa16045ca0191a93178503a0005402bcded04017a867cb178c0ba93ef4e7` |
| `a-part-for-lila.senses.json` | `644abc7a267135409753ec496f40c3e63b5584cffc41937a622b8e09e68ac83b` |
| `a-part-for-lila.txt` | `977c93b745a8d327b7af53e13cbcf51b4fa9f532c9ad2d2fc42f0ba470b26e0a` |
| `a-shoe-in-the-fridge.senses.json` | `2c1485b174724e6b51ff27e0c68eb2f04eaae782d66163498dc23d9b504191eb` |
| `a-shoe-in-the-fridge.txt` | `cfb2e8b3df895693e624743d816a984e469648d8ddb1a5a470175535e9c9141d` |
| `a-very-important-visitor.senses.json` | `d29260d6860352c655f43ffc4128c22e1296f24400e58c36bdb44082dcaee9c0` |
| `a-very-important-visitor.txt` | `7800d1e62729f8acaf99643cc5c5f415fdb8f3918226398926ae2c8d9ace5b13` |
| `an-apartment-full-of-notes.senses.json` | `fafae0fe3a2e2f2ebeb138423c0b91a814456e7f1924f5159248b5fb2a5fd9ba` |
| `an-apartment-full-of-notes.txt` | `f0ce84ae2561a019d2eb47acce1f8d1d8aca3741e9fd553cc8ad7ada7c7eecc7` |
| `an-empty-apartment.senses.json` | `e2f8a803586401d347eceef8fff2d85ca4b27bae2780e365f6173bbda59d6064` |
| `an-empty-apartment.txt` | `20df026c93491d1531ab438d45b70a7a8feef6adb1aa387769e1cde333f333a8` |
| `five-minutes-maximum.senses.json` | `a0f82e17eb9b02d505fb74083eedaf58b390d3f2606b32046af94872276a640b` |
| `five-minutes-maximum.txt` | `3896f7c4d77f0105584ca93e6eb74805e1be52731e6cdf87fe4a9d02ca7049e9` |
| `lane-four.senses.json` | `458dc56414a2d0617f5125dd50378cfe85de332aa2609a8844818fc064bd8ad7` |
| `lane-four.txt` | `f98157868e04ab922bcefa86d629e4f130096de835d28433af8999702686837a` |
| `notes-on-the-fridge.senses.json` | `36b0481cdbc12e4bc4aa311f950044f0b4472c287c00f8c5d5d7baa52dd813fe` |
| `notes-on-the-fridge.txt` | `a1e1a924821fdcc5582c1d8c18f5bc80dc8639c41ebeb745964466e1e5604bf7` |
| `nours-long-race.senses.json` | `7da9ab8d99a7291bba0a34a0cbb3f86d825374b311c0af11db3abb35c9655728` |
| `nours-long-race.txt` | `8c90cf85cab3c7a5febcfaafe0c3901e469c52ee7c9f30fb6b1c10eed43a1f72` |
| `the-beat-on-the-hill.senses.json` | `3fb2bdaeac508b3f40b85fc9443546a1d025debf2d5730af185c043e209607ca` |
| `the-beat-on-the-hill.txt` | `62183212c89844000706d15c0aab202ccd252ea7ea076326e314a3ada30757e1` |
| `the-chess-table-by-the-lake.senses.json` | `97acca45ab88ae585c563fa6bafa43db56beaa1086db41da0aed0ee5595eb0c9` |
| `the-chess-table-by-the-lake.txt` | `0740507b82d1af3674bd695732c4111b81414fd3c5d23acdf8dfc53995ede500` |
| `the-exit-interview.senses.json` | `208fba867c69592e91478361dec44f2e546566b8041b985dd7adbdfebc938d20` |
| `the-exit-interview.txt` | `2ecfd88799b0d62119c4e82e0d20fcf59d1e325fdb40b90581f842045f1c1cba` |
| `the-lighthouse-keeper.txt` | `dfba714915a5ff7048bbfb291dec693235b016f385df1477c03ac73dfa8e21b5` |
| `the-oven-next-door.senses.json` | `5c3c52cf27a7fd51a4869ed6459fd862210edf4ce2a1e7cfa2c38fb5557d8650` |
| `the-oven-next-door.txt` | `f1919b19c767ccc0d62a010855add970b26861d355f3bc29255dbeca8d661652` |
| `the-presentation-in-kisumu.senses.json` | `3b947e42c7c7c7efc240b058fa7ce4a65a6ca9c2f581371db015af920b239b1b` |
| `the-presentation-in-kisumu.txt` | `6ee8cd75fbb0908275b9de101a9dcd0c114890fc1d2dcc4d48d536784c3bff7d` |
| `the-red-boat.txt` | `b28d3ae112ab319ea14eeae22c0c537fcae37bc385b3765b6e9de7b2ed4d059e` |
| `the-second-violin.senses.json` | `c56c4b0cb59c8460ef716d7ac016cf4ed713e41df86fe0e3edeae5b14a1da94a` |
| `the-second-violin.txt` | `d5fe41d685f19510778a369dc6eb673e53b163fc005a5f829085ff969afa342a` |
| `the-tree-in-the-second-row.senses.json` | `3bf8e3d3959ecc4f2183c9042c0a11090f3b4d734ec85d0fbd84a11b25db6a3b` |
| `the-tree-in-the-second-row.txt` | `fae43c2e67a4083a9b4eebb933457ec986c34313e3130528b54f222ebdd3411b` |
| `three-in-the-morning.senses.json` | `11d44a3841d72338456c8494d6244cdf29f1e9267ecdf8038d48639a978b090e` |
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
  optionals, duplicate keys refused, code-point counts, NFC, `Character.getType` for Cc Cf Zl Zp Co Cn Cs, text equals its cleaned text, IPA set,
  whole-word entries, groups). Senses load only when the book's paragraphs equal the bundled text's.
- Word card (S19): skip S16 and the verb-or-noun rule for a word with an entry; headword = base form; sense IPA (hidden from TalkBack; no IPA input on
  Android TTS: say the base form as text); label (Proper name, Word from another language, US English, UK English, Local English); Spanish meaning from the file;
  other languages: the group, or the `en` gloss, else the base form only when it cannot pick the wrong sense (no sibling sense, no `no "X"` warning in
  `es`); name and foreign words are not translated and not offered to save; name remark and note only in Spanish; group underlined in the sentence
  (map its range into the sentence) and shown on one line; definition only of the same part of speech, one-word base forms, kind word or chunk,
  `modal` looks up verb.
- Saved word fields: `sense` = `s:<senseKey>`, `story`, `groupStart/groupEnd`, `translationSource` (bounded on read as in `VocabWord.bounded`).
  One entry per sense; labels "get (ponerse)" when another sense of the spelling is saved; Review marks the whole group; the translation worker
  translates only `translationSource` and nothing when it is nil (clear the old meaning when the language changes; Review keeps the translated
  sentence); a plain word saved as a story sense loses its old meaning/IPA; reader underline only at the same-sense places of the story
  (`StorySenses.underlines`), generic S4 underline elsewhere.

## Strings (en / es)
Our story / Cuento propio; Proper name / Nombre propio; Word from another language / Palabra de otro idioma; US English / Inglés estadounidense;
UK English / Inglés británico; Local English / Inglés local; Group: %@ / Grupo: %@; "Our stories were written with AI help. Anyone can use them freely." /
"Nuestros cuentos se escribieron con ayuda de IA. Cualquiera puede usarlos libremente." (Settings About and under the stories of a level in Discover).

## Tests to port
`StorySensesTests` (every refusal case), `BundledStoriesTests` (corpus over all 21 texts, `en` required for bare words with siblings, no Peninsular
Spanish), `LibraryTests` (first-run order, migration cases, two senses = two entries, group range, bounds, translation source, name/foreign not saved).

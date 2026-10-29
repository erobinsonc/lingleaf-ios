<p align="center"><img src="docs/icon.png" width="96" alt=""></p>

# Lingleaf for iOS

**Learn English by reading real books.** Tap any word to see its translation,
pronunciation and meaning, and highlight what you learn. Free and open source.

> 🇪🇸 **Aprende inglés leyendo libros de verdad.** Toca cualquier palabra para ver su
> traducción, pronunciación y significado, y subraya lo que aprendes. Gratis y open source.

Android version: [lingleaf-android](https://github.com/erobinsonc/lingleaf-android) · Product spec: [SPEC.md](SPEC.md)

## Features

- **Tap a word**: base form, IPA, on-device translation (Apple Translation), definition, and the sentence translated.
- **Learn / Learned**: words you're learning get a yellow underline in every book, inflected forms too.
- **Review** with spaced repetition (1, 3, 7, 14, 30 days).
- **Read aloud** a word, a sentence or a paragraph (works with the ringer muted).
- **Thousands of free books** from Project Gutenberg, plus 3 original graded stories (A1–B1). Import your own `.txt`.
- **Recommended classics from B1 to C2**, public domain worldwide, filterable by level in Discover.
- **Daily goal and streak.**
- No accounts, no ads, no tracking.

## Build

Requirements: Xcode 26+ (iOS 26 SDK, required by App Store Connect), iOS 18+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen swiftlint
xcodegen generate && open Lingleaf.xcodeproj    # then ⌘R on your iPhone
swift test --package-path LingleafCore          # logic tests
swiftlint lint
```

Apple Translation doesn't run in the Simulator; try translations on a real device.

## Architecture

- `LingleafCore/` — Swift package, Foundation only: text tools, base forms, spaced repetition,
  streak, Gutenberg catalog, dictionary client, library storage. Same rules and tests as
  `core/` in lingleaf-android. ≥90% line coverage is enforced.
- `Lingleaf/` — SwiftUI app. Each paragraph is one `Text` whose words are links; tapping one opens the word card.
- `LingleafUITests/` — UI flows and Apple's accessibility audit, run against the app in an
  offline `-ui-testing` mode with canned answers.

## Quality gates (every pull request)

| Gate | Tool |
|---|---|
| Logic tests + coverage ≥90% | XCTest, llvm-cov |
| UI flows (tap a word → card → Learn; review) | XCUITest |
| Accessibility audit on every screen | `performAccessibilityAudit()` |
| Code style | SwiftLint |
| Secrets | gitleaks |
| Vulnerable dependencies | Dependabot, dependency review* |
| Static security analysis | CodeQL* |

\* Runs automatically once the repository is public (free for open source).

## Privacy

Lingleaf has no accounts, ads or analytics, and keeps your books and words on your
device (and in your iCloud/device backup, if you use one). Lingleaf is for ages 13 and up
(the open Project Gutenberg catalog includes books for adults). The app itself talks only to
`gutendex.com` / `www.gutenberg.org` (books) and `api.dictionaryapi.dev` (definitions),
always over HTTPS.

Translation runs on the device with Apple Translation; iOS downloads each language
from Apple the first time (it asks you first). Words and sentences are translated on
the device; only the English word you tap is sent to the dictionary to fetch its
definition. The app ships a privacy manifest declaring no tracking and no data
collection. Full policy: [PRIVACY.md](PRIVACY.md), also linked in the app (Settings → About).

## Credits

Definitions come from [Wiktionary](https://en.wiktionary.org/) under
[CC BY-SA 3.0/4.0](https://creativecommons.org/licenses/by-sa/4.0/), via the
[Free Dictionary API](https://dictionaryapi.dev/); the app may shorten them and says so on the word card.

## License

[MIT](LICENSE) for the code. The MIT licence does not cover the Lingleaf name and icon:
please don't use them for your own builds or forks. Bundled stories in `Lingleaf/Resources/Books`
are original and dedicated to the public domain ([CC0 1.0](Lingleaf/Resources/Books/LICENSE)).
Project Gutenberg books are public domain in the US; outside the US, check your country's laws.
The recommended books are public domain worldwide (every author died in 1925 or earlier).

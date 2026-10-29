# Lingleaf privacy policy

_Last updated: 2026-10-29. Applies to Lingleaf for iOS and Lingleaf for Android._

Lingleaf is a free, open-source app for learning English by reading books. It has
**no accounts, no ads, no analytics and no tracking**. We do not sell personal data.

## Who is responsible

The data controller ("responsable del tratamiento") is **[MAINTAINER NAME]**, the
maintainer of Lingleaf, acting as a private individual. Contact for any privacy
question or request: open an issue at https://github.com/erobinsonc/lingleaf-ios/issues
(for a request you'd rather not make in public, ask there for a private channel, or
write to lingleaf.feedback@gmail.com).

## What stays on your device

Your books, saved words, review progress, reading time and settings are stored only
on your device. We never receive them. Your operating system may include them in your
device or cloud backup (iCloud, Google) if you use one; that backup is between you and
Apple or Google. Deleting the app deletes them from the device.

## What the app sends over the internet

The app connects only to these services, always over HTTPS. It sends no account or
identifier of yours to them; like any website, they see your IP address:

- **Project Gutenberg** (`gutendex.com`, `www.gutenberg.org`): to list, search and
  download free books. They receive your search terms and the books you download.
- **Free Dictionary API** (`api.dictionaryapi.dev`): to show a word's definition and
  pronunciation. It receives the English word you tapped. Definitions come from
  Wiktionary (CC BY-SA).
- **Translation**:
  - iOS uses Apple Translation, which runs on the device. iOS downloads each language
    from Apple once (it asks you first). Words and sentences are not sent.
  - Android uses Google ML Kit, which runs on the device. It starts only after you
    first tap a word, and the word card tells you. It downloads each language model
    (about 30 MB) from Google once, over Wi‑Fi only. As Google documents for ML Kit,
    it sends Google **pseudonymous diagnostics**: device model, OS and app version,
    performance metrics and a per-installation identifier
    ([ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure),
    [ML Kit terms](https://developers.google.com/ml-kit/terms)). Words and sentences
    are not sent.

These services are run by third parties under their own privacy policies; we do not
receive what they receive.

## Suggestions you choose to send

Some versions of Lingleaf let you send a suggestion from the app. Nothing is sent
unless you tap Send in your own email app. A suggestion can include your text, a
screenshot or image you choose (which you can mark or cover first), basic device
information (app version, system version, phone or tablet, app and translation
language, screen) and, if you keep it, a summary of usage counts from the last 14 days
(numbers only, never books, words or text).

We use a suggestion only to improve Lingleaf. Each one becomes a **public GitHub
issue** so the community can see and discuss it. Your name and email address are
**never** published. Images are published only after a maintainer reviews them.

## How long we keep data

- On your device: until you delete it or the app.
- Suggestion emails: deleted once the issue is created and any image is reviewed,
  and in any case within 30 days.
- Public issues: they stay on GitHub until you ask us to delete them (or the parts
  that are yours).

## Transfers

The services above (Project Gutenberg, Free Dictionary API, Apple, Google, GitHub and
the email provider) may process data in the United States or other countries, under
their own safeguards. Your device sends the requests to them directly.

## Your rights

You can ask us to **access**, **rectify** or **delete** any personal data we hold about
you (in practice: a suggestion email or issue), to object to or restrict its use, and
to withdraw your consent at any time. Requests are free and we answer within 15
business days. Data held by the third-party services above is requested from them.

If you are not satisfied, you can complain to a data protection authority:

- Colombia: Superintendencia de Industria y Comercio (SIC), https://www.sic.gov.co
- European Union and EEA: the data protection authority of your country.
- Brazil: Autoridade Nacional de Proteção de Dados (ANPD), https://www.gov.br/anpd

## Ages

Lingleaf is for ages 13 and up: the open Project Gutenberg catalog includes books
written for adults. The app has no accounts and does not knowingly collect personal
data from children. If a child under 13 sent us a suggestion, ask us and we delete it.

## Changes

Changes to this policy are published in this file, with the date above. The full
history is public in the repository.

## Colombia (Ley 1581 de 2012, Decreto 1377 de 2013, art. 13)

- **Responsable:** [MAINTAINER NAME]. Contacto: https://github.com/erobinsonc/lingleaf-ios/issues
  o lingleaf.feedback@gmail.com.
- **Tratamiento y finalidad:** solo tratamos las sugerencias que decidas enviar (texto,
  imagen, datos básicos del dispositivo y conteos de uso), para mejorar Lingleaf y
  publicarlas como issue público sin tu nombre ni tu correo. Los datos de lectura
  quedan en tu dispositivo y no los recibimos.
- **Tus derechos como titular:** conocer, actualizar y rectificar tus datos; pedir
  prueba de la autorización; ser informado del uso que se les da; presentar quejas
  ante la SIC; revocar la autorización o pedir la supresión; y acceder a ellos gratis.
- **Quién atiende tus solicitudes:** el responsable, en el contacto de arriba.
- **Procedimiento:** escribe al contacto con tu solicitud y cómo responderte.
  Consultas: respuesta en máximo 10 días hábiles. Reclamos: máximo 15 días hábiles
  (prorrogables 8 días si te avisamos el motivo).
- **Vigencia:** esta política rige desde el 29 de octubre de 2026. Los correos de
  sugerencias se conservan como se indica arriba; los issues públicos, mientras
  exista el proyecto o hasta que pidas borrarlos.

---

# Política de privacidad de Lingleaf (resumen en español)

Lingleaf **no tiene cuentas, anuncios, analítica ni rastreo**, y no vendemos datos
personales. El responsable es [MAINTAINER NAME] (contacto: los issues del repositorio
o lingleaf.feedback@gmail.com). Tus libros, palabras y ajustes quedan en tu
dispositivo. La app solo se conecta por HTTPS a Project Gutenberg (libros; recibe tus
búsquedas), a Free Dictionary API (recibe la palabra en inglés que tocaste; las
definiciones vienen de Wiktionary, CC BY-SA) y, para traducir en el dispositivo, a
Apple o Google para descargar cada idioma una vez. En Android, ML Kit empieza solo
cuando tocas la primera palabra, descarga por Wi‑Fi y envía a Google diagnósticos
seudónimos (modelo del dispositivo, versión del sistema y de la app, métricas de
rendimiento y un identificador por instalación). Las sugerencias que decidas enviar
desde tu correo se publican como issues públicos en GitHub **sin tu nombre ni tu
correo**; el correo se borra en máximo 30 días. Puedes pedir acceso, corrección o
borrado, y quejarte ante la SIC (Colombia), la autoridad de tu país en la UE o la ANPD
(Brasil). Lingleaf es para mayores de 13 años.

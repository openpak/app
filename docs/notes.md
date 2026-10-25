# Notes: app

## Design

Your account, your friends and your invitations on a phone. One Flutter
codebase for Android and iOS (companion-apps PRD, decided 2026-09-08: this is
lists over an HTTP API, and two native codebases would double the work forever
for nothing a person would notice).

## Languages

English, German, French, Brazilian Portuguese, Italian and Spanish, following
the phone's language. The strings live in `lib/l10n/*.arb` (English,
`app_en.arb`, is the template and describes every key for translators);
Flutter's own gen-l10n turns them into `AppLocalizations` on `flutter pub get`,
so the generated Dart is not committed. Terms follow the website's glossary
(`website/docs/glossary.md`). `app_pt.arb` carries the same strings as
`app_pt_BR.arb`: gen-l10n needs a base `pt` for the regional one.

## Not here yet

- **Push.** The server side is built (`POST /api/v1/me/push` and a notifier);
  the app does not register a device token yet, and the server needs a Firebase
  service account before anything is delivered.
- **iOS.** Builds from a Mac, but push and TestFlight both need a paid Apple
  Developer account. Android needs none of that.

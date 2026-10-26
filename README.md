# Companion App

OpenPak's Companion App.

| | |
| --- | --- |
| Console | Android, iOS |
| Kind | Flutter app (Dart), one codebase for both |
| Download | [Releases](https://github.com/openpak/app/releases) (Android APKs, `vX.Y.Z` tags) |
| Licence | AGPL-3.0-only, see [LICENSE](LICENSE) |

## What it does

- Sign in with an OpenPak account (and its two-factor code, when it has one),
  or create one; the bearer is kept in the platform keystore. A forgotten
  password is reset by mail.
- Friends, with presence: who is online and what they are playing. Offline
  friends stay in the list rather than disappearing. Requests are accepted or
  declined; blocked accounts are listed with Unblock.
- Invitations waiting for you, and decline. Reading the inbox consumes nothing,
  so opening the app never takes an invitation away from your console.
- Titles: the latest news, what has a server, who is online per console
  network, and a request for the next game.
- Diagnostics: describe a connection problem and Pakka reports a diagnosis
  with the evidence behind it (needs a build pointed at a Pakka harness;
  there is no public endpoint yet).
- Saves: usage, each game's versions to restore, download or delete, and your
  own storage.
- Chat with friends: tap one to open the thread.
- Account: details, avatar (a built-in or your own photo), password, email
  (confirmation and change), two-factor, linked consoles (link a Wii or DS,
  unlink any), signed-in devices, and deleting the account.
- Crash reports: an unhandled error is saved on the phone (the last five) and
  offered on the spot or at the next launch; nothing is sent to
  `POST /api/v1/crash-reports` until the person says Send (or chose "Always
  send", changeable on the account page). `appVersion` in
  `lib/crash_reports.dart` must follow pubspec's version; a test checks it.

## Install

1. Download the APK for your phone from
   [Releases](https://github.com/openpak/app/releases): `arm64-v8a` for most
   phones, `armeabi-v7a` for older 32-bit ARM phones, `x86_64` for emulators.
2. Install it on the phone, or with `adb install app-arm64-v8a-release.apk`.
   The APKs are signed with the OpenPak release key, so each version installs
   over the last.

There is no iOS build on Releases; see [notes](docs/notes.md).

## Build

```sh
flutter pub get
flutter run                     # against https://openpak.org
```

See [deploy](docs/deploy.md).

## Docs

- [Protocol](docs/protocol.md)
- [Evidence](docs/evidence.md)
- [Deploy](docs/deploy.md)
- [Notes](docs/notes.md)
- [Docs index](docs/README.md)

## Licence

See [LICENSE](LICENSE). AGPL-3.0-only.

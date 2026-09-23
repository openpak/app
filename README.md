# OpenPak companion app

Your account, your friends and your invitations on a phone. One Flutter
codebase for Android and iOS (companion-apps PRD, decided 2026-09-08: this is
lists over an HTTP API, and two native codebases would double the work forever
for nothing a person would notice).

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

## Toolchain

Nothing here is system-installed; all of it lives under `~/development` and
`~/Android` and can be deleted without touching the machine.

| | |
|---|---|
| Flutter | `~/development/flutter` (3.47.2 stable) |
| Android SDK | `~/Android/Sdk` (platform 36, build-tools 36.0.0) |
| JDK | `~/development/jdk-21.0.12.1+1` — **required** |

The JDK line is not a preference. The system JDK here is 26, and the Android
Gradle plugin's `jlink` step fails on it (`Failed to transform
core-for-system-modules.jar`). Flutter is configured to use the 21 above via
`flutter config --jdk-dir`, so a plain `flutter build` works; a bare Gradle
invocation needs `JAVA_HOME` set to it.

```sh
export ANDROID_HOME=~/Android/Sdk
export PATH="$HOME/development/flutter/bin:$PATH"
```

## Running it

```sh
flutter pub get
flutter test
flutter run                     # against https://openpak.org
flutter run --dart-define=OPENPAK_BASE_URL=http://10.0.2.2:20010   # local stack
```

`10.0.2.2` is how the Android emulator reaches the host machine.

To put it on a phone:

```sh
flutter build apk --release --split-per-abi   # ~17 MB for arm64
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Release builds are signed with a stable keystore, so a new APK installs over
the previous one.

## The logo comes from the website

`assets/icon.svg` is a byte-for-byte copy of `website/web/static/icon.svg`, and
the Android launcher icons are rasterised from that same file. Nothing is
redrawn — a hand-made copy of a logo diverges the moment the real one changes,
and nothing notices. A test compares the two whenever the website repo is
checked out next door, and fails when they differ.

After the logo changes upstream:

```sh
cp ../website/web/static/icon.svg assets/icon.svg
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  rsvg-convert -w ${d##*:} -h ${d##*:} assets/icon.svg \
    -o android/app/src/main/res/mipmap-${d%%:*}/ic_launcher.png
done
```

## Languages

English, German, French, Brazilian Portuguese, Italian and Spanish, following
the phone's language. The strings live in `lib/l10n/*.arb` (English,
`app_en.arb`, is the template and describes every key for translators);
Flutter's own gen-l10n turns them into `AppLocalizations` on `flutter pub get`,
so the generated Dart is not committed. Terms follow the website's glossary
(`website/docs/glossary.md`). `app_pt.arb` carries the same strings as
`app_pt_BR.arb`: gen-l10n needs a base `pt` for the regional one.

Every call sends `Accept-Language` with the app's language, so the account
e-mails the website sends read in it too. API errors carry a stable `code`;
`apiErrorText` in `lib/l10n.dart` shows its translation, never the server's
English.

## The API client is hand-written

The PRD asks for a generated client. Thirteen endpoints of JSON in and JSON out
did not justify dio, built_value and a `build_runner` step, so `lib/api.dart`
implements the same contract by hand — every method names the path it serves.
The contract is still the source of truth: it lives in the website repo as
`openapi/openapi.yaml`, with a test there that fails when a served route is
missing from it. If this ever grows past a few dozen endpoints, generate it.

## Not here yet

- **Push.** The server side is built (`POST /api/v1/me/push` and a notifier);
  the app does not register a device token yet, and the server needs a Firebase
  service account before anything is delivered.
- **iOS.** Builds from a Mac, but push and TestFlight both need a paid Apple
  Developer account. Android needs none of that.

AGPL-3.0-only.

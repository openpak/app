# OpenPak companion app

Your account, your friends and your invitations on a phone. One Flutter
codebase for Android and iOS (companion-apps PRD, decided 2026-09-08: this is
lists over an HTTP API, and two native codebases would double the work forever
for nothing a person would notice).

## What it does

- Sign in with an OpenPak account; the bearer is kept in the platform keystore.
- Friends, with presence: who is online and what they are playing. Offline
  friends stay in the list rather than disappearing.
- Invitations waiting for you, and decline. Reading the inbox consumes nothing,
  so opening the app never takes an invitation away from your console.

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

Release builds are signed with the debug key for now — installable by hand,
not distributable. A real signing config is needed before any store.

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

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

## Running it

```sh
flutter pub get
flutter test
flutter run                     # against https://openpak.org
flutter run --dart-define=OPENPAK_BASE_URL=http://10.0.2.2:20010   # local stack
```

`10.0.2.2` is how the Android emulator reaches the host machine.

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

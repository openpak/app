# Protocol: app

## Languages

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

## Pakka diagnostics

`lib/pakka.dart` talks to the Pakka harness (`platforms/core/pakka` in the
workspace) the same hand-written way: `GET /healthz`, `POST /v1/runs`,
`POST /v1/investigations`. Failures are the same `ApiException`, so
`apiErrorText` and the load-failure screens word them; Pakka sends no error
codes and takes no bearer, so there is no sign-out on its errors.

The harness root is a build setting, `PAKKA_BASE_URL`, empty by default —
Pakka has no public endpoint yet. Point a dev build at a local harness with
`flutter run --dart-define=PAKKA_BASE_URL=http://10.0.2.2:24800`. Without it
the Titles tab shows no diagnostics entry, rather than a button that cannot
work. The app only ever sends `mode: live`; fixture scenarios are the
harness's own development vocabulary.

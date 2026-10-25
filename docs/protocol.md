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

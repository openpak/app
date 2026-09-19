# Next session — app

Updated 2026-09-19.

The Flutter companion app. Tags run to `v0.6.17`. Branch `parity-2026-09-19`
(not pushed, not tagged) brings it to parity with website v0.46.0 and bumps
`pubspec.yaml` to `0.7.0+18`; merge it to `main`, then tag `v0.7.0` to release.

## Parity with website v0.46.0 (branch parity-2026-09-19)

- Sign in: `POST /token` 202 → code step → `POST /token/2fa` (one field; six
  digits = `code`, else `recovery_code`, as the website's `SplitSecondFactor`).
  401 starts over from the password; 429 says 15 minutes.
- Account: Security panel (email confirmed/not + resend, change email,
  two-factor set up/turn off with the consoles warning and recovery codes once),
  Delete account (confirm, then password [+ code], then sign out).
  `lib/two_factor_page.dart` is the setup page.
- Friends: Decline beside Accept; Blocked section (`GET /me/blocked`) with Unblock.
- Titles: latest 3 news articles on top (`GET /news`), hidden when empty.
- Saves: the move button already existed; wording now matches the website.
- `/me` does not return the email address itself, so the app shows only whether
  it is confirmed. A 401 from `/me/2fa/enable|disable` means a wrong code, so
  those calls do not sign the app out (`_decode(signOutOn401: false)`).
- `Panel` is a `Material` now (ListTile ink inside it failed a debug assertion).

## Where things stand

- Built and shipping (git log, v0.3.0..v0.6.14): sign-in, friends with presence,
  invitations with decline, editable account details, Titles tab (playable first,
  by console, alphabetically; Request-a-game sheet; votes treated 409 as no-op),
  Saves (one-tap cloud first; own-storage WebDAV/Google Drive/OneDrive under
  advanced), console marks byte-for-byte from the website's logos, WD-0 linked
  consoles as platform names.
- Release APKs are signed with a stable keystore since b3d19ec — README's
  "signed with the debug key for now" and the "Not here yet" Saves line are
  stale; trust `git log` + `lib/`.
- Push: `registerPush`/`deletePush` exist in `lib/api.dart` but nothing calls
  them (no `firebase_messaging` dependency). Server side is built and waits on
  a Firebase service-account JSON; iOS also needs an APNs key behind a paid
  Apple Developer account.
- API client is hand-written against `website/openapi/openapi.yaml` (the
  contract, with a website-side test that fails when a served route is missing
  from it).
- Toolchain (all under `$HOME`): Flutter 3.47.2 `~/development/flutter`, SDK
  `~/Android/Sdk`, **JDK 21** `~/development/jdk-21.0.12.1+1` required — system
  JDK 26 breaks AGP's jlink step.

## Next steps

1. Merge `parity-2026-09-19`, tag `v0.7.0`.
2. Fix README: stable-keystore line, drop stale "Not here yet" items.
3. Wire push registration (call `registerPush` once FCM credentials exist on
   the server) — APP-05 remains the open functional requirement.
4. `flutter test` is the local gate; release: tag → `openpak_release.yml`
   builds split-ABI APKs and publishes a GitHub Release.

## Languages: DE, FR, PT-BR, IT, ES (with the website)

Decided 2026-09-19: German, French, Brazilian Portuguese, Italian and Spanish, shipped with
the website's (see `website/next-session.md`) so both say the same words.

- The app has no localisation yet: roughly 60–80 UI strings are hard-coded in `lib/*.dart`.
  1. Add `flutter_localizations` + `generate: true` and an `l10n.yaml`; ARB files
     `app_en.arb`, `app_de.arb`, `app_fr.arb`, `app_pt_BR.arb`, `app_it.arb`, `app_es.arb`;
     move every string into `app_en.arb` first (no behaviour change), then translate.
  2. Locale follows the device; add an in-app override on the account page.
  3. Send `Accept-Language` on every API call. Server error messages are English strings
     today; the website plans stable error `code`s for the app to translate — show the
     translated code, fall back to the message.
  4. Use the shared glossary in the website's `docs/` so terms match the site.

## Pointers

- README.md · CHANGELOG.md · prds/companion-apps-prd.md
- Contract: ../website/openapi/openapi.yaml
- WD-0 context: ../../prds/platform-wii-ds-prd.md

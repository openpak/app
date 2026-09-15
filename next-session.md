# Next session — app

Updated 2026-09-15.

The Flutter companion app. Tags run to `v0.6.14` with one unreleased commit on top
(fdc7f7b, WD-0: linked consoles render as platform names); `pubspec.yaml` still
says `0.6.6` — version bumps have not tracked the tags. Working tree: modified
`pubspec.lock` plus untracked `CHANGELOG.md`, `docs/`, `prds/` scaffolding.

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

1. Commit the scaffolding; bump `pubspec.yaml` to match the tag line before the
   next release.
2. Fix README: stable-keystore line, drop stale "Not here yet" items.
3. Wire push registration (call `registerPush` once FCM credentials exist on
   the server) — APP-05 remains the open functional requirement.
4. `flutter test` is the local gate; release: tag → `openpak_release.yml`
   builds split-ABI APKs and publishes a GitHub Release.

## Pointers

- README.md · CHANGELOG.md · prds/companion-apps-prd.md
- Contract: ../website/openapi/openapi.yaml
- WD-0 context: ../../prds/platform-wii-ds-prd.md

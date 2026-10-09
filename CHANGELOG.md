# Changelog — app

Generated from git history on 2026-09-15. `git log` stays the source
of truth; this file is the readable summary.

## v0.19.0 — 2026-10-09

- **The console system UI look, as on openpak.org v0.69.0.** Console-shell grey with white tiles (charcoal in dark mode), flat colours with no gradients, and sentence-case labels. Headings, labels and buttons use M PLUS Rounded 1c, bundled under `assets/fonts` (OFL, subset to Latin, Greek and Cyrillic).
- The cyan selection cursor marks the current tab in the bottom bar, and appears on a tappable row when it is hovered or focused. It breathes unless animations are turned off.
- The account page's profile is a flat tile with no cover, and the avatar is a flat accent circle.

## v0.18.0 — 2026-09-27

- **A console can be named**, so two under one account can be told apart: Rename in the console
  screen's app bar opens a field of up to 32 characters (`PUT /me/parental-controls/{moonID}/name`).
  It is prefilled only with a name the parent chose, and Save stays off until the name changes;
  empty goes back to the default. A refused name is shown on the field. The name stays on OpenPak
  and never goes to the console, so there is nothing to wait for. No second unlock: a name is not
  a secret, and the screen is already behind the phone's lock.
- The list and the console screen show the server's name for a console: the parent's, else one
  made from its serial number, else "Console". The status panel adds the serial number and system
  version, small, where the server has them.
- A console that has just paired without a name is offered one, once, in a snackbar with Rename.
- **Play activity says who played.** Under each title, one short line per user with their small
  picture (the Players section's) and their minutes, most first; a user since deleted from the
  console reads "A user no longer on this console", and time played with no user selected is its own
  line when there is any. From a server without the per-user split, titles show as before.
- Needs the website's naming route and the list's `named`, `serial_number` and `firmware`; an older
  website leaves them out and the screens read as before.

## v0.17.0 — 2026-09-27

- **Change restrictions**, from a console's screen. The level (None, Children, Young teens, Older
  teens, Custom); under Custom the age limit, rating system, communication, posting to social
  media and VR; the play timer, the same every day or different each day, each day with its
  limit (0–360 minutes) and bedtime alarm; and what happens when time is up. Only what the
  console's own parse table types, with its own bounds, checked in the form. A save sends back the
  whole document as it was served with only the changed parts replaced, so per-title exceptions,
  always-allowed titles and anything the form does not show go back untouched. A refusal from the
  server is shown on the field it names. After a save the console reads "Waiting for the console"
  until its receipt names the new document, never "applied", with how it picks changes up: the
  Update settings button in its Parental Controls, or its own timer.
- **Change PIN**, beside Show PIN: four digits, typed twice, on the number pad, and only after the
  phone's own unlock again (or the OpenPak password where the device has none). Afterwards the
  new PIN is the one shown, and the screen says the old one keeps working on the console until it
  syncs. Never written to the phone or logged.
- **Remove console**, after a confirmation that says the console itself stays linked until it is
  unlinked there with the PIN.
- **Play activity**: the last seven days, the console's time used per day and each title's time
  under it (by name, or by title id where there is none). One line when nothing was recorded.
- **Fixed: a console's screen, and the locked screen, started under the app bar**, so the top of
  the first panel (the last-synced time) could never be scrolled into view. Their padding was read
  from above the Scaffold, where only the status bar counts, instead of from its body, where the
  app bar does too. A test now opens each parental screen through the lock under a status bar and
  checks the first panel clears the bar.
- The console screen is tighter: the restrictions open the editor from any row and end in a
  Change restrictions row; the PIN panel is one row with its two actions under it. The PIN's help
  no longer says to change it on the console.
- **The parental screens are kept out of screenshots**: Android sets `FLAG_SECURE` while they are
  open (no screenshots or screen recording, a blank recent-apps picture) and clears it when they
  close; iOS covers the window whenever the app stops being active, so the app switcher shows no
  PIN. A `MethodChannel` in `MainActivity.kt` and `AppDelegate.swift`; no new dependency.
- Needs the website's `PUT …/setting`, `PUT …/pin`, `DELETE …/{moonID}` and `GET …/activity`.
  From an older website a save or a PIN change fails with its error, and activity shows as none.

## v0.16.0 — 2026-09-27

- **A console's own screen**, opened from its row: its name, whether it holds the current settings
  and when it last synced, its restrictions as the console is served them (the level; under
  Custom the age limit and rating system, communication, social posting and VR; the play timer
  when set), its players with the pictures the console uploaded, and the times a wrong PIN was
  typed on it. Read-only: nothing here changes a console yet. The row itself names the console and
  says "Up to date" or "Waiting for the console".
- **The console's PIN**, behind Show PIN. Fetched only then, never written to the phone, and gone
  again the moment the app leaves the foreground or the screen is closed.
- **Parental controls open behind the phone's own unlock**: fingerprint or face, falling back to
  its PIN, pattern or passcode (`local_auth`, the one new dependency). Back after more than 60
  seconds in the background, the parental screens close and ask again. A phone with no screen lock
  cannot open them and says how to set one. Where a device has no unlock of its own to ask, the
  OpenPak password stands in (`POST /me/parental-controls/unlock`).
- A console that unlinks drops off the list; one that does so while its screen is open closes it
  with a short message.
- Android: the activity is a `FlutterFragmentActivity` and the themes AppCompat, as the biometric
  prompt needs; `USE_BIOMETRIC`. iOS: `NSFaceIDUsageDescription`.
- Needs the website's phase A fields on `/me/parental-controls`; from an older website the rows
  keep their v0.15.0 pill and a console's screen shows only what was sent.

## v0.15.0 — 2026-09-26

- **Parental controls**, on the Account tab. Nintendo's parent surface is a separate smartphone
  app talking to the console's own API; this is ours. It mints the code to type in the console's
  *System Settings → Parental Controls → Use smartphone app*, shows it large enough to read off a
  phone while typing on a console, copies it on a tap, and lists the consoles this account
  manages. In all seven languages.
- It needs the server side to pair: nx-baas v0.34.0 holds the device records and the website
  route that reaches them is not deployed yet, so until both are live the screen answers "not
  available on this deployment". Nothing on a console changes either way — the PIN and the limits
  are applied by the console itself and keep working offline.
- No restriction editor yet: the console-facing sync is still being brought up, and an editor
  whose changes reached no console would lie about what it had done.
- CI gained a dispatch-only `check` job (`pub get`, `analyze`, `test`), so the app can be compiled
  without tagging and publishing a release.

## v0.14.1 — 2026-09-24

- v0.14.0 with the crash reports' version constant bumped too; v0.14.0's release stopped at that
  test and published nothing.

## v0.14.0 — 2026-09-24

- **Add a friend by Wii U NNID or by email.** The add-friend dialog lists both, typed as they are
  (no code formatting). By email the answer never says whether the address has an account
  (website v0.57.0).
- **Your email is among your friend codes** on the Account tab, with a copy button.
- **Console logos from Wikimedia Commons**, the website's (v0.56.2) byte for byte: Switch, 3DS,
  DS, Wii, Wii U, PS3, PSP, Vita and Xbox 360, each with a dark copy that lightens what is too
  dark and a light copy that darkens what is too faint. A test fails if they drift from the
  website's.
- The marks are 3:2 wordmarks, so they are drawn wider: 42x28 on title rows, 30x20 on the
  friend's platform pill, 44x29 in the saves card, and inside the label of the console filter
  chips (the chip's avatar box is square and trips Flutter's layout when widened).

## v0.13.1 — 2026-09-24

German, French and large accessibility text, checked on every screen at 100, 130 and 200%.

- **Account no longer goes blank with large text.** A row's button (Send the link again, Revoke,
  Turn off, the crash-report choice) could take the whole row, which a list tile refuses; they
  are capped at 40% of the width now and their labels wrap.
- **Tab bar** labels stop growing at 1.15× so "Einladungen" and "Sauvegardes" no longer break
  mid-word; the rest of the app scales in full.
- **Decline and Accept** go onto two lines when they do not fit side by side.
- **Section headings** wrap instead of pushing their count off screen; friend codes stay on one
  line and shrink rather than splitting; the country and code-type dropdowns ellipsize.
- **Titles**: the Titles/Network toggle drops its icons, as the site's; a status dot sits in an
  icon-sized box, as a chip expects.

## v0.13.0 — 2026-09-24

The last of the website's redesign: what the approved mockup has that the app did not.

- **Account** has the site's dashboard shapes: three stat cards under the profile (friends and how
  many are online, consoles linked, requests), a **Confirmed** badge beside the address, incoming
  friend requests in their own card with Decline and Accept, and a section nav under the header
  (Overview, Requests, Linked, Security, Signed in) that scrolls to each.
- **Glass**, as the site's header and tab bar: pages scroll under both, blurred; the tab bar has
  the site's hairline on top.
- **Titles**: the status chips carry each state's colour dot (so they double as the legend) and the
  list says how many it shows. **Online now** is one card of live rows, a dot that pulses while
  anyone is on (still when the system asks for less motion).
- **Saves**: the allowance meter is the site's, 4px indigo-to-violet (amber near full).
- Friend requests on Friends use the same outline Decline and primary Accept.
- The voice call's Mute button is red again when muted; the primary gradient had painted over it.

## v0.12.1 — 2026-09-24

The rest of the redesign, checked screen by screen.

- **Rows with actions** (friends, requests, blocked, invitations) put the name over its pill and the
  buttons on a line of their own, as the site's rows do; at phone width a friend's name and game
  were cut to a few letters.
- **Invitations** name the game from the catalog, as Friends does, instead of showing its title id.
- **Chats** sit in one card, like every other list.
- **Account details** drops its friend-code panel: the Account card above it lists every code.
- The last hard-coded greys on Titles use the palette's muted colour.

## v0.12.0 — 2026-09-23

The website's redesign (website v0.54.0), in the app: one product again.

- **Palette** from `website/web/src/input.css`: a greyer page with white cards in light, near-black
  with lifted cards in dark; the same indigo, green, amber and red.
- **Beta is indigo** (`RowState.beta`), as on the site: it runs, so it is no longer amber. `open`
  reads as amber, `active` green and `banned` red, like the site's `badgeClass`.
- **Pill buttons**, the primary one with the site's indigo gradient; 16px cards with a soft shadow,
  12px fields with an accent focus border, 20px dialogs and sheets, floating snackbars.
- **Tab bar** like the site's: glass, no pill behind the active tab, accent icon and label.
- **Account** opens with the site's profile card: gradient cover, avatar in a ring, the friend code
  in a well with its own copy button.
- **Titles** filter with chips instead of dropdowns: a row of statuses and a row of consoles (with
  their logos), the chosen one inverted.
- A blank avatar is the site's pink-to-violet gradient; screens have 20px side margins.
- **Friend codes** (website v0.55.1): the Account card lists every code you can be added by, from
  `/me`'s `friend_codes` in the site's order: OpenPak (OP-XXXX-XXXX), Switch, Wii U NNID once
  published, 3DS; each with a copy button. An older server still shows OpenPak and Switch. **Add friend** is the
  site's dialog: pick OpenPak, Switch or 3DS, and the field shapes what you type to that code
  (`fitFriendCode`, the same rules as the site's `data-friend-form`); the request carries `kind`.
- Invitations no longer trips a debug assertion on load (`setState` was handed a Future).

## v0.11.2 — 2026-09-23

- Voice chat no longer crashes the moment a second person joins: the app now declares the
  network-state permissions WebRTC needs once a peer connection exists.

## v0.11.1 — 2026-09-23

- The version the app reports in crash reports is its own again (it still said 0.9.0), which
  also unblocks the release build v0.11.0 failed on.

## v0.11.0 — 2026-09-23

Voice chat, the way Nintendo's worked: the game's lobby screen on the TV sends you to
the phone, and the phone carries the voice (website v0.53.0).

- Friends → the headset button opens **Voice chat**. It finds the room of the game you
  are in by itself (the matchmaking room, e.g. a Splatoon 2 Private or League Battle)
  and lists who is in it and who is already talking; or join a room by its six-character
  code (shown on the TV, or made here with "Create a room") to talk outside a game.
- In the call: everyone connected, a green ring on whoever is speaking, mute, loudspeaker
  and leave. Audio is WebRTC phone to phone (full mesh, eight to a room), relayed through
  OpenPak's TURN server when two phones cannot reach each other.
- Microphone permission on Android (`RECORD_AUDIO`, asked the first time you join) and
  iOS (`NSMicrophoneUsageDescription`). New dependency `flutter_webrtc`.
- Talking needs the app open: Android stops giving the microphone to an app in the
  background, and there is no foreground service yet.
- All new strings in every language the app speaks.

## v0.10.0 — 2026-09-23

- **Crash reports, sent only with consent.** Unhandled errors are kept (the last five) and
  offered in a dialog: Send, Don't send, Always send, Never send; the answer can be changed on
  the Account page. Reports go to `POST /api/v1/crash-reports`; a failed send stays for next
  time. No new dependency.

## v0.9.0 — 2026-09-23

Friends say where each friend is playing (website presence `platform`, `client`,
`label`, `title_name`):

- The pill reads "Mario Kart 8 Deluxe on Ryujinx", "Playing on Cemu" when the game
  has no name, and "Online on Switch" outside a game; offline is unchanged.
- The friend's detail shows the platform with a chip for the client (the console's
  mark and "Ryujinx", "Eden", "Citron", "Cemu", "Azahar", "Switch", "Wii U", "3DS").
- The game's name comes from the website first, then the catalog.
- An older server without those fields: the pill is what it was (the game, the
  platform and "In a game", or "Online").
- Friends show their profile pictures.

## v0.8.1 — 2026-09-20

- Friends: the game's name, and a row that opens.

## v0.8.0 — 2026-09-19

The app speaks German, French, Brazilian Portuguese, Italian and Spanish, like website
v0.47.0.

- Languages: every string lives in `lib/l10n/app_*.arb` (Flutter gen-l10n); the app
  follows the phone's language. The translations reuse the website's reviewed wording
  where the English matches, and the shared glossary (`website/docs/glossary.md`)
  elsewhere; `pt` gets the Brazilian text.
- API errors are shown by their stable `code` (website v0.47.0), in the app's language;
  unknown codes fall back by HTTP status.
- Every API call sends `Accept-Language`, so account emails follow the app's language.
- Dates in the locale's own format.

## v0.7.0 — 2026-09-19

Parity with the website (v0.46.0):

- Sign in: a code step for two-factor accounts (authenticator or recovery code)
- Account: email confirmed or not, with the link sent again; change the email
- Account: two-factor set up (key to copy or open in an authenticator app, the
  consoles warning, recovery codes shown once) and turned off
- Account: delete the account, asked twice, then signed out
- Friends: decline a request beside Accept; the accounts you blocked, with Unblock
- Titles: the latest news on top, opened in full with a tap
- Saves: "Move my saves here" in the website's words

## v0.6.17 — 2026-09-19

- Saves in alphabetical order, as on the website
- Friends: a block can be undone from its notice
- Titles: who is online now, per console network
- Sign in: create an account, and a reset mail for a forgotten password
- Account: change the password, link a Wii or DS by friend code, unlink a console
- Avatar: upload a photo from the gallery
- Chat: messages with friends, a conversation list, and a thread per friend

## v0.6.16 — 2026-09-18

- Saves: each game shows its name and icon; a version dropdown restores, and download
  (to the share sheet) and delete sit beside it, as on the website

## v0.6.15 — 2026-09-18

- Saves: the website's page — usage meter, the saves by game with icon, console and
  conflict badge, search and console filter, then your own storage
- WD-0: linked consoles render as platform names [fdc7f7b]


## v0.6.14 — 2026-09-11

- Titles: tests follow the Request-a-game sheet; plain empty state inside the list.

## v0.6.13 — 2026-09-11



## v0.6.12 — 2026-09-11



## v0.6.11 — 2026-09-11



## v0.6.10 — 2026-09-10



## v0.6.9 — 2026-09-10



## v0.6.8 — 2026-09-10



## v0.6.7 — 2026-09-10



## v0.6.6 — 2026-09-10



## v0.6.5 — 2026-09-10



## v0.6.4 — 2026-09-10



## v0.6.3 — 2026-09-10



## v0.6.2 — 2026-09-10



## v0.6.1 — 2026-09-10



## v0.6.0 — 2026-09-10



## v0.5.1 — 2026-09-10



## v0.5.0 — 2026-09-10



## v0.4.1 — 2026-09-08



## v0.4.0 — 2026-09-08



## v0.3.0 — 2026-09-08



## v0.2.1 — 2026-09-08



## v0.2.0 — 2026-09-08



## v0.1.1 — 2026-09-08



## v0.1.0 — 2026-09-08



## v0.1.0 — 2026-09-08

- Record the toolchain, including the JDK the Android build actually needs [249bd64]
- Sign in, friends with presence, and an invitations inbox [99b2f68]


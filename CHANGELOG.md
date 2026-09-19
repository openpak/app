# Changelog — app

Generated from git history on 2026-09-15. `git log` stays the source
of truth; this file is the readable summary.

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


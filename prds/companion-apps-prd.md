# OpenPak companion apps PRD (Android, iOS)

Status: **A0/A1 built** (2026-09-08, one Flutter codebase in `app`, Android installs). Original brief (2026-09-07): API-first: no app code before the mobile
API contract (website PRD, WEB-08) is published.

## 1. Product objective

Your account, your friends and your play sessions on the phone: see who is online and in
which game, receive and decline invitations, manage friends, and get a push notification
when a friend invites you, without touching the console.

## 2. Relationship to existing plans

- Depends on the website PRD's mobile API (`/api/v1`) and its token model. The app agent
  owns the client side and may propose additions; the website agent owns the server.
- Presence and live sessions come from the core Sessions contract, fed by adapters.
- Accepting an invitation from the phone needs a delivery target (the player's live console
  or emulator). Phase 1 shows and declines only; accept-to-join is a later phase.

## 3. Evidence and current baseline

Observed earlier (evidence only): Android and iOS apps exist with account, friends and
sessions views. No local source for either; scope comes from their public descriptions and
from the emulator's client surface (profile, friends, presence, invitations, history,
online counts).

## 4. Users and journeys

1. Log in with the OpenPak account; see friend code.
2. Friends list with presence (offline, online, playing plus title); request, accept, remove.
3. Invitations inbox: who invited you to what; decline; later accept and hand off.
4. Push on friend request and on invitation.
5. Sessions and devices: linked consoles and active sessions; revoke.

## 5. Scope and non-goals

In: **one cross-platform codebase** for Android and iOS — **Flutter**, decided 2026-09-08 (one
maintainer, and this client is lists over an HTTP API; two native codebases would double the
work forever for no user-visible gain). FCM push via a worker inside the website service.

The client is **hand-written, not generated** (`app/lib/api.dart`): thirteen endpoints of JSON
in and JSON out did not justify dio, built_value and a build_runner step. The contract stays
authoritative — it lives in `website/openapi/openapi.yaml` with a test that fails when a served
route is missing from it. Generate the client if this ever passes a few dozen endpoints.

Toolchain is all under `$HOME` (no passwordless sudo on the workstation): Flutter in
`~/development/flutter`, Android SDK in `~/Android/Sdk`, and **a JDK 21 in
`~/development/jdk-21.0.12.1+1` — required**, because the system JDK is 26 and the Android
Gradle plugin's jlink step fails on it. `apt full-upgrade` will not change that; Ubuntu 24.04
ships podman 4.9 and this box ships JDK 26. Out: game data, mods, cloud saves,
chat, store pipelines beyond a signed build, anything console-facing.

**Voice chat is in scope since 2026-09-23** (APP-08 below). It was out because it looked
console-facing; it is not. Nintendo's own voice chat never ran on the console: a Switch game
opened the Lobby applet (`web-<env>.znc.srv.nintendo.net/lobby/?app_id=…`), the page told the
player to open the phone app, and the phone carried the audio (the saved page,
`tmp/p2/lobby.html`, now the retired "Online Lounge", says as much: voice chat during Private
and League Battles, a room made with voice chat on, the voice in the smartphone app). OpenPak
does the same with this app.

## 6. Independent implementation rules (apply verbatim)

- Every earlier network repository is source-available; its noncompete clause forbids
  using that code in a competing product. earlier code, routes, schemas and prose are
  **evidence of observable behaviour only**, never implementation input. Do not copy,
  translate, or structurally mirror them. Cite them as evidence, then design from scratch.
- Go 1.26, module `github.com/openpak/<repo>`, AGPL-3.0-only, `LICENSE` verbatim from
  gnu.org. Server-rendered templates and minimal browser JavaScript for web surfaces.
  Native mobile code is the recorded non-Go exception.
- Talk to the account core **only** through its versioned contracts (gRPC: Identity, Links,
  Social, Sessions, Invitations, Events; HTTP `/v1/*`). Never read its database. If a
  contract is missing, write the proposal in this PRD's "Contract requests" section and
  raise it as an `account` issue; do not fork the core.
- Do not touch `Openpak/nx-baas` (the Switch adapter, owned by the T4/T5 agent) or the
  console-facing hostnames it serves. Console-side needs go into "Contract requests".
- No secrets, tokens, saves, or copyrighted game material in any repository. `example.env` only.
- Definition of done for every milestone: `go vet ./...` and `go test -race ./...` green in
  CI, a runbook in `README.md`, and the acceptance journey below reproduced by the owner.

## 7. Functional requirements

- APP-01 API contract first: OpenAPI 3.1 in `website` (`/api/v1`), versioned, with examples;
  generated clients checked into each app repo.
- APP-02 Auth: bearer token from `/api/v1/auth/login`, refresh, logout; tokens bound to a
  core web session so revocation on the site logs the app out.
- APP-03 Friends and presence: list with state and title; request, accept, decline, remove,
  block.
- APP-04 Invitations inbox (read and decline in phase 1).
- APP-05 Push: register device token; server sends on friend request and invitation (an
  Events-driven worker in the website; apps never touch the core).
- APP-06 Offline tolerant: cached last state, clear error states, no crash without network.
- APP-07 Privacy: no analytics SDKs; crash reporting opt-in only.
- APP-08 Voice chat (added 2026-09-23). A player in a game room opens the app → Voice chat and
  talks with the other players in that same room. The room is found by itself: the website
  asks the title server which matchmaking gathering the account is in (switch-nex
  `GET /internal/voice/gathering`, joined to accounts by the proven NEX login) and names the
  room by a six-character code, which the console's lobby page also shows on the TV. A code
  room is for friends outside a game. Audio is WebRTC with `flutter_webrtc`, full mesh, eight
  phones a room (the ceiling is in website `internal/voice`); signaling is a WebSocket on the
  website (`/api/v1/me/voice/ws`, the same bearer); NAT traversal is the production coturn
  with time-limited TURN REST credentials the website mints from its shared secret. Mute,
  loudspeaker, speaking indicators; microphone permission on both platforms; every string
  localized.

## 8. Architecture and ownership

Repos `app-android`, `app-ios` (native, AGPL-3.0). Server side stays in `website`
(api and push packages). Push credentials only in deployment secrets.

## 9. Contract requests

- CR-A1 `/api/v1` OpenAPI published by the website agent before app work starts. **Delivered.**
  It needed core additions, since `PollInvitations` is namespace-scoped and consumed by
  `AckInvitations`: a phone calling it would take invitations away from the console that has to
  deliver them. `account` v0.3.0 adds `Invitations.ListInvitations` (non-consuming, every
  namespace, no payload or nonce), `Invitations.RejectInvitation` (recipient-scoped) and
  `Sessions.GetPresence` (derived from session leases, so it cannot drift from them).
- CR-A2 Push delivery worker in the website; no new core contract.
- CR-A3 Accept-to-join from a phone: needs Sessions.ResolveSession and a join injection on
  the target client; design in phase 2 with the Switch adapter agent.

## 10. Milestones and acceptance

- A0 API contract published and mocked. Gate: contract tests green in `website` CI.
  **Done 2026-09-08.** `/api/v1` serves auth, `/me`, sessions, friends **with presence**, the
  invitations inbox with decline, profile editing, avatars, device-token registration, and a
  public `/status`. The OpenAPI is published and a contract test fails when a served route is
  missing from it — it caught three routes before I did.
- A1 Android. **App exists and ships**: `github.com/openpak/app`, one Flutter codebase, releases
  through v0.4.0 (sign in, friends with presence, invitations with decline, account details with
  avatar/name/country/date of birth, a Saves placeholder). Remaining for the gate: the app does
  not register a device token yet, and **push has no credentials** — the server side is built
  (`POST /api/v1/me/push` plus an events-driven notifier) and waits on a Firebase service
  account. Until then an invitation cannot arrive in 10 s because it cannot arrive at all.
- A1 Android: login, friends with presence, invitations inbox, push. Gate: an invitation sent
  from a Citron session appears on the phone within 10 s; decline removes it on both ends.
- A2 iOS parity with A1.
- A3 Accept-to-join (after CR-A3).
- A4 Voice chat (APP-08). **Built 2026-09-23** (app v0.11.0, website v0.53.0, switch-nex
  v0.3.1). Gate: two phones in the same Splatoon 2 private battle hear each other with the
  console showing the room code. Open: talking with the app in the background (Android needs a
  microphone foreground service), NPLN titles (their sessions are not asked yet), and the
  Wii U/3DS titles on `servers/nex`.

## 11. Risks

- Apps built before the API exists guarantee rework: A0 is a hard gate.
- Push providers need accounts and keys the agent cannot create: owner task. **Status
  2026-09-08:** Firebase project exists (Android push unblocked) but **the service-account JSON
  is not on the box**, so the notifier logs "notifications are disabled" and starts nothing. No
  Apple Developer account, so iOS has no APNs key and no TestFlight — note that Firebase does
  **not** avoid this: FCM reaches iOS by relaying through APNs, and alternative app stores do not
  help either, since notarization also requires that membership. The only push path on iOS
  without it is a home-screen PWA using Web Push.
- Accept-to-join is the only feature touching the console path; keep it last.

## 12. Evidence references

Emulator client surface (paths only) in `earlier-citron/src/web_service/legacy_api.cpp`;
core contracts in `account/proto`.

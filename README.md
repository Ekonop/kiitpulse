# KIITPulse

A hyper-local campus radar for KIIT. Students see what is surging **right now**,
in the zone they are physically standing in, and can drop into a topic room to
talk about it.

Built from the 57-page KIITPulse product blueprint: radar → topic room → voice
huddle, with an ephemeral-by-default model.

---

## The three ideas

**1. The radar is local, not global.** Your feed depends on where you are. A
topic in Campus 15 outranks the same topic seen from KP Hostels if the Campus 15
one is moving faster. Location resolves against bounding boxes, and the zone you
are standing in is the only radar you get.

**2. Velocity decides, not recency.** A topic's rank is

```
V = (M·1.0 + R·0.25 + L·3.5) / Δt^1.5,   decayed ×0.85 per minute
```

where `M` is messages, `R` reactions and `L` voice joins. A voice join is worth
3.5 messages because joining a stage is a much stronger intent signal than
typing. The `Δt^1.5` denominator means a brand-new quiet topic does not
outrank an established active one; the decay means a topic fades on its own
without anyone reading it.

**3. Rooms are ephemeral.** Topics and messages expire in 24 hours, and the
score decays below a purge floor in minutes. Nothing here needs a permanent
record — the value is entirely in what is happening now.

---

## Repository layout

```
apps/mobile/            Flutter app (Android, iOS, web, Linux desktop)
packages/kiit_ui/       Design system: palette, type, motion, foil badge shader
packages/kiit_contracts/ Wire types + velocity math + geofences
packages/kiit_api_client/ PulseGateway interface, demo and live implementations
services/backend/       Go + Gin API, Redis radar, WebSocket chat hub
migrations/             Postgres schema
infra/                  docker-compose for local dev
```

The app depends on `PulseGateway` and nothing else. Two implementations exist:

- **`DemoGateway`** — in-memory simulated campus. Default. No services needed,
  so a fresh clone runs immediately.
- **`LiveGateway`** — HTTP + WebSocket against the Go backend.

Swapping them is one `--dart-define`.

---

## Running it

### The app, with no backend

```bash
make demo       # phone / desktop
make demo-web   # browser, on http://localhost:8080
```

### In a browser

```bash
make serve-web  # release build, served on :8080
```

The app is responsive rather than scaled. The same widgets pick a shape from
the window width:

| Width | Shape | Navigation |
|---|---|---|
| `< 700px` | phone | bottom bar, edge-to-edge cards |
| `700–1100px` | tablet / small window | bottom bar, centred column |
| `> 1100px` | desktop browser | side rail, 720px reading column |

The column is capped because a radar card stretched across a 27-inch monitor is
unreadable — the eye cannot track from a title on the left to a velocity badge on
the right. `pulseFormFactorOf(context)` decides; a browser resize re-lays out
without a reload.

### The public deployment (one origin, real backend)

```bash
make serve-live   # builds the web app against the API, then serves both on :8080
```

One process serves the app and the API. That is deliberate:

- No CORS preflight, because there is only one origin.
- The WebSocket URL the browser derives is the host it loaded from, so a tunnel
  works without rebuilding. The build cannot know in advance whether it will be
  reached on `localhost`, a LAN address or a public URL, so
  `resolveApiBaseUrl()` reads `window.location.origin` at runtime.
- `?access_token=` carries the session on the socket, because a browser cannot
  set an `Authorization` header on a WebSocket handshake.

To expose it: `ngrok http 8080`. Verified through a tunnel with a real
`wss://` handshake returning `101 Switching Protocols`, a message echoed back,
and the radar score rising as a result.

The ngrok free tier shows a one-time "Visit Site" consent page. That is ngrok's
page, not the app's.

### The app, against a real backend

```bash
# Redis is required for the radar (it *is* the radar).
export KIITPULSE_JWT_SECRET="$(head -c 32 /dev/urandom | base64)"
make run          # terminal 1
make live         # terminal 2
```

### Everything in Docker

```bash
make up
```

### Tests

```bash
make check    # analyze + every suite
make test     # tests only
```

---

## What is actually verified

| Area | Status |
|---|---|
| Go backend | 64 tests, `-race` clean |
| Dart packages | 34 tests (18 client + 16 contracts) |
| Flutter app | 17 tests, `flutter analyze` clean |
| End-to-end flow | `integration/e2e_flow.py` against a real server + real Redis: sign in → create topic → radar ranks it → WebSocket message → persisted → replayed over REST → radar velocity rises → reaction accepted and scored → stage roster lists the joiner → hand-raise persists → passport awards badges |
| Backend HTTP surface | booted and curl'd: sign-in, 401, 403, 503, 400 paths |
| Android APK | builds with the location plugin in Kotlin and LiveKit's native WebRTC |
| **Postgres schema** | **not executed** — no Postgres available in the dev env |
| **On-device app run** | **not done** — needs a physical Android phone |
| LiveKit voice | verified against a real SFU built from source: listener token reaches a `101` handshake, a tampered token gets `401`, and the grant in the JWT says `canPublish=false` |
| **Voice audio** | **never heard** — no phone has joined a stage; only signalling is proven |

The last three are honest gaps, not omissions. See "Known gaps" below.

---

## Design decisions worth knowing

**The role machine is a security boundary.** A client may move itself
listener → handRaised. Only the server may grant `speaker` or `moderator`.
`/voice/token` refuses to return a publish grant even when asked for one, and a
test asserts it.

**Voice grants are cryptographic, not advisory.** `voice/token.go` mints real
LiveKit JWTs. A listener token carries no publish grant *in the signed token*,
so the SFU refuses to let it publish — the restriction does not depend on the
client behaving. Tests verify each token's signature and assert that a token
signed with the wrong secret fails verification.

**Mock-GPS detection is a speed bump, not proof.** `Location.isMock` is
deprecated from Android 12 and defeatable on a rooted device. The UI never
presents it as verification.

**Web presence is weaker than Android and says so.** The browser's Geolocation
API has no mock-provider flag at all — a spoofed laptop location is
undetectable. The web build therefore asks the browser for a real fix, refuses
fixes coarser than 250 m (a city-level fix cannot tell one campus zone from
another), and reports denial honestly. It does **not** fall back to a fixed
campus coordinate; an earlier version did, which meant every web visitor was
told they were on campus.

**Slow chat clients are dropped, not waited for.** Each client has a buffered
send channel; when it fills, that client is disconnected. One bad hostel
connection must not stall a 500-student room.

**Identity is server-derived.** A client may put any `sender_roll` on the wire;
the hub overwrites it from the verified session token. There is a test that
tries to spoof the KSAC head and asserts it fails.

**Geofences are duplicated in Dart and Go deliberately** — the client needs them
to work offline, the server needs to be authoritative. Tests on both sides pin
the same coordinates and assert no two boxes overlap.

---

## Known gaps

- **Postgres is written but never executed.** `migrations/001_init.sql` has not
  run against a live server. Treat it as unverified until it does.
- **No physical-device run.** The Android location plugin compiles and is
  implemented, but has not been exercised on hardware.
- **Web location is browser-dependent.** The web build has been exercised in
  headless Chromium with permission denied and with the demo gateway, but not
  with a real granted geolocation fix on a phone browser.
- **Voice audio has never been heard.** Signalling is verified end to end
  against a real LiveKit server (`integration/verify_voice_live.py`), but no
  phone has joined a stage, so whether audio actually flows is untested. Set
  `KIITPULSE_LIVEKIT_URL`, `_KEY` and `_SECRET` to enable voice; with them unset
  the endpoint says voice is off rather than handing out a token that cannot
  connect.
- **Lottie/Iconscout assets are not integrated.** Motion is hand-built with
  Flutter animations; the seams exist for Lottie later.
- **Passport badges report activity, not attendance.** The blueprint's badges
  are event credentials ("KIIT Fest · Core Team"). This server has no
  attendance feed and cannot verify them, so instead of printing a credential
  nobody checked, badges are earned from activity the server observed itself:
  messages sent, topics opened, voice stages joined, zones visited. Each badge
  carries the evidence in `event_name` and the UI must present it as evidence,
  never as attendance.
- **Reactions are scored but not aggregated per message.** A tap fans out to the
  room and counts toward velocity; there is no per-message tally persisted.

---

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it.

One caveat the license cannot speak for: MIT covers this source code, not the
KIIT name, logo, or the campus geofence data. Running a real deployment for
KIIT students is a decision for KIIT, not a permission this repository grants.

---

## The test that matters most

`apps/mobile/test/chat_controller_test.dart` has a regression test for a bug
where a failed history fetch left the room permanently silent — the live
subscription was only created after history succeeded. It asserts that a failed
`fetchRecentMessages` still leaves a working live stream. Reverting the fix makes
it fail with the message *"the live stream must be subscribed even if history
failed"*.

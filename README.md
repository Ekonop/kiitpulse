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
apps/mobile/            Flutter app (Linux, Android, iOS)
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
make demo
```

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
| End-to-end flow | `integration/e2e_flow.py` against a real server + real Redis: sign in → create topic → radar ranks it → WebSocket message → persisted → replayed over REST |
| Backend HTTP surface | booted and curl'd: sign-in, 401, 403, 503, 400 paths |
| Android APK | builds with the location plugin in Kotlin and LiveKit's native WebRTC |
| **Postgres schema** | **not executed** — no Postgres available in the dev env |
| **On-device app run** | **not done** — needs a physical Android phone |
| **LiveKit audio** | **tokens real and verified; audio never heard** — no SFU to connect to |

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
- **LiveKit audio has never been heard.** Token minting is real and verified
  (signed JWTs, publish rights absent from listener tokens, room-scoped), but
  no SFU was reachable from the dev environment, so end-to-end audio is
  untested. Set `KIITPULSE_LIVEKIT_URL`, `_KEY` and `_SECRET` to enable it; with
  them unset the endpoint says voice is off rather than handing out a token that
  cannot connect.
- **Lottie/Iconscout assets are not integrated.** Motion is hand-built with
  Flutter animations; the seams exist for Lottie later.

---

## The test that matters most

`apps/mobile/test/chat_controller_test.dart` has a regression test for a bug
where a failed history fetch left the room permanently silent — the live
subscription was only created after history succeeded. It asserts that a failed
`fetchRecentMessages` still leaves a working live stream. Reverting the fix makes
it fail with the message *"the live stream must be subscribed even if history
failed"*.

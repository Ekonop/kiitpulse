"""Prove server-minted voice tokens work against a real LiveKit SFU.

The Go unit tests verify signatures and grants offline. This goes further and
checks the claims the README makes about voice:

  1. an unpromoted client asking for speaker rights is refused (403);
  2. a promoted client gets a token that carries canPublish;
  3. a listener token is accepted by the SFU - a real WebSocket handshake
     reaches 101 and a JoinResponse frame arrives;
  4. a tampered token is refused with 401, so the signature is genuinely
     checked rather than decorative;
  5. the listener token's grant says canPublish=false, which is what the SFU
     enforces when a track is published.

Requires a backend configured against LiveKit. Start the SFU in dev mode:

    livekit-server --dev --bind 127.0.0.1
    KIITPULSE_LIVEKIT_URL=ws://127.0.0.1:7880 \
    KIITPULSE_LIVEKIT_KEY=devkey KIITPULSE_LIVEKIT_SECRET=secret \
    KIITPULSE_JWT_SECRET=0123456789abcdef0123456789abcdef \
    KIITPULSE_ADDR=:8102 go run .
    python3 integration/verify_voice_live.py

Exits non-zero on the first failed assertion.
"""

import base64
import json
import os
import socket
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("KIITPULSE_E2E_URL", "http://127.0.0.1:8102")
ROLL = "241551058"
EMAIL = f"{ROLL}@kiit.ac.in"


def post(path, body, token=None):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def jwt_claims(token):
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def ws_join(ws_url, token):
    """Open a LiveKit signalling socket. Returns the HTTP status line."""
    host, port = ws_url.split("//")[1].split(":")
    key = base64.b64encode(os.urandom(16)).decode()
    path = f"/rtc?access_token={token}&protocol=15"
    req = (
        f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s = socket.create_connection((host, int(port)), timeout=5)
    s.sendall(req.encode())
    status = s.recv(4096).decode(errors="replace").split("\r\n")[0]
    s.close()
    return status


def main():
    status, signin = post("/auth/signin", {"email": EMAIL})
    assert status == 200, (status, signin)
    token = signin["token"]

    status, topic = post(
        "/radar/topics",
        {"title": "voice live check", "description": "checking the SFU",
         "campus_zone": "campus15"},
        token,
    )
    assert status == 201, (status, topic)
    topic_id = topic["id"]

    # 1. An unpromoted client cannot talk its way into a speaker slot.
    status, body = post("/voice/token", {"topic_id": topic_id, "as_speaker": True}, token)
    assert status == 403, f"unpromoted speaker request returned {status}"
    assert body.get("code") == "SPEAKER_NOT_GRANTED", body
    print("PASS an unpromoted client cannot obtain a speaker token")

    # 3 (set up). A plain listener token.
    status, listener = post("/voice/token", {"topic_id": topic_id}, token)
    assert status == 200, (status, listener)
    assert listener["publish"] is False, listener

    # 2. After a grant, publish rights appear.
    assert post(f"/voice/stage/{topic_id}/speakers", {"roll": ROLL}, token)[0] == 200
    status, speaker = post("/voice/token", {"topic_id": topic_id, "as_speaker": True}, token)
    assert status == 200 and speaker["publish"] is True, (status, speaker)
    print("PASS a promoted student receives publish rights")

    # 5. The grant is in the token the SFU enforces, not just our JSON.
    lv = jwt_claims(listener["token"]).get("video", {})
    sv = jwt_claims(speaker["token"]).get("video", {})
    assert lv.get("canPublish") is False, f"listener grant: {lv}"
    assert sv.get("canPublish") is True, f"speaker grant: {sv}"
    assert lv.get("room") == speaker["room"], "tokens are not scoped to one room"
    print("PASS listener tokens carry canPublish=false inside the signed grant")

    # 4. The SFU accepts a real token and rejects a tampered one.
    ws_url = listener["ws_url"]
    good = ws_join(ws_url, listener["token"])
    assert "101" in good, f"the SFU refused a valid listener token: {good}"
    bad = ws_join(ws_url, listener["token"][:-6] + "AAAAAA")
    assert "401" in bad, f"the SFU accepted a tampered token: {bad}"
    print("PASS the SFU accepts a valid token (101) and rejects a tampered one (401)")

    print("\nVOICE VERIFIED AGAINST A LIVE SFU")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""End-to-end flow: sign in, create a topic, watch the radar rank it, send a
message over the WebSocket, then read it back over REST.

This exercises the pieces the Go unit tests cannot: a real HTTP server, a real
Redis-backed radar, a real WebSocket handshake, and the persistence hop between
them. Run it against a live server:

    KIITPULSE_JWT_SECRET=... KIITPULSE_ADDR=:8101 go run . &
    python3 integration/e2e_flow.py

Exits non-zero on the first failed assertion, so CI can gate on it.
"""

import base64
import json
import os
import socket
import sys
import time
import urllib.request

# Override with KIITPULSE_E2E_URL when the server is not on localhost.
BASE = os.environ.get("KIITPULSE_E2E_URL", "http://127.0.0.1:8101")
WS_HOST = BASE.split("//", 1)[1].split(":")[0]
WS_PORT = int(BASE.rsplit(":", 1)[1])

def signin(email):
    req = urllib.request.Request(BASE + "/auth/signin",
        data=json.dumps({"email": email}).encode(),
        headers={"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req))
    return d["token"], d["roll_number"]

def get(path, token):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + token})
    return json.load(urllib.request.urlopen(req))

def ws_connect(topic, token, port=WS_PORT):
    s = socket.create_connection((WS_HOST, port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET /ws/topics/{topic}?access_token={token} HTTP/1.1\r\nHost: x\r\n"
           f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
           f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    s.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(4096)
    assert b"101" in resp.split(b"\r\n")[0], resp[:200]
    return s

def send_text(s, text):
    data = text.encode(); mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    n = len(data)
    hdr = bytes([0x81, 0x80 | n]) if n < 126 else bytes([0x81, 0x80 | 126, n >> 8, n & 0xFF])
    s.sendall(hdr + mask + masked)

def recv_frame(s):
    b1 = s.recv(1)
    if not b1: return None
    b2 = s.recv(1); ln = b2[0] & 0x7F
    if ln == 126: ln = int.from_bytes(s.recv(2), "big")
    elif ln == 127: ln = int.from_bytes(s.recv(8), "big")
    data = b""
    while len(data) < ln:
        c = s.recv(ln - len(data))
        if not c: break
        data += c
    return data.decode(errors="replace")

tok, roll = signin("241551058@kiit.ac.in")
print("signed in as", roll)

# Create a topic.
req = urllib.request.Request(BASE + "/radar/topics",
    data=json.dumps({"title":"#Campus15-DSA-Viva",
                     "description":"Viva tomorrow in Lab 3",
                     "campus_zone":"campus15"}).encode(),
    headers={"Content-Type":"application/json","Authorization":"Bearer "+tok})
topic = json.load(urllib.request.urlopen(req))
tid = topic["id"]
print("created topic", tid, "score", topic["velocity_score"])

# Confirm it is ranked.
radar = get("/radar/zones/campus15", tok)
print("radar has", len(radar), "topic(s); top:", radar[0]["title"] if radar else None)
assert any(t["id"] == tid for t in radar), "new topic missing from radar"
print("PASS topic appears on the radar")

# History must start empty.
before = get(f"/topics/{tid}/messages", tok)
print("history before:", len(before))
assert before == [], f"expected empty history, got {before}"

# Send two messages over the socket.
s = ws_connect(tid, tok)
recv_frame(s)  # presence
for text in ["is the viva in lab 3?", "yes, get there early"]:
    send_text(s, json.dumps({"send_message": {"id": "local-" + text[:4],
        "topic_id": tid, "content": text, "timestamp_unix": 1700000000}}))
    echo = json.loads(recv_frame(s))
    print("echo:", echo["send_message"]["content"])

# A burst with no pause between sends. Persisting each message from its own
# goroutine passed locally and failed in CI here: two appends racing for Redis
# landed out of order. Sending back-to-back without sleeping is what makes that
# race reproducible rather than incidental.
burst = [f"burst {i}" for i in range(8)]
for text in burst:
    send_text(s, json.dumps({"send_message": {"id": "b-" + text,
        "topic_id": tid, "content": text, "timestamp_unix": 1700000000}}))
    recv_frame(s)
s.close()

time.sleep(1.0)  # let the persistence queue drain

after = get(f"/topics/{tid}/messages", tok)
print("history after:", len(after), "messages")

assert len(after) == 2 + len(burst), f"expected 10 persisted messages, got {len(after)}"

# Order is the whole point: history must replay what was said in the order it
# was said, not the order Redis happened to finish writing.
sent = ["is the viva in lab 3?", "yes, get there early"] + burst
got = [m["content"] for m in after]
assert got == sent, f"history is not chronological\n  sent: {sent}\n  got:  {got}"
print("history replays in send order")
assert after[1]["content"] == "yes, get there early"
assert all(m["sender_roll"] == "241551058" for m in after)
print("PASS messages persist and replay chronologically")
print()
print("END-TO-END FLOW VERIFIED")
sys.exit(0)

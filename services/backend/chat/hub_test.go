package chat

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/kiitpulse/backend/domain"
)

func quietLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(discard{}, &slog.HandlerOptions{
		Level: slog.LevelError,
	}))
}

type discard struct{}

func (discard) Write(p []byte) (int, error) { return len(p), nil }

// newRoomServer stands up a hub behind a real HTTP server so the tests exercise
// the actual websocket path rather than a fake connection.
func newRoomServer(t *testing.T, hub *Hub) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		topic := r.URL.Query().Get("topic")
		roll := r.URL.Query().Get("roll")
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
			InsecureSkipVerify: true,
		})
		if err != nil {
			return
		}
		hub.HandleSocket(conn, topic, domain.Student{
			RollNumber: roll,
			BranchTag:  "CSE-AIML '28",
		})
	}))
	t.Cleanup(srv.Close)
	return srv
}

func dial(t *testing.T, srv *httptest.Server, topic, roll string) *websocket.Conn {
	t.Helper()
	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "?topic=" + topic + "&roll=" + roll
	conn, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	return conn
}

// readUntil reads frames until one contains the given key, so tests are not
// coupled to how many presence frames a join happens to produce.
func readUntil(t *testing.T, conn *websocket.Conn, key string) map[string]json.RawMessage {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		frame := readFrame(t, conn)
		if _, ok := frame[key]; ok {
			return frame
		}
	}
	t.Fatalf("no %q frame arrived", key)
	return nil
}

// drainPresence consumes queued presence frames so the next read is the frame
// the test cares about.
//
// It must not cancel a read context to stop: a cancelled read tears down the
// connection (coder/websocket closes the socket on a failed read), which made
// every following assertion fail. Instead it waits for the presence frames it
// expects and stops once it has them.
func drainPresence(t *testing.T, conn *websocket.Conn, want int) {
	t.Helper()
	seen := 0
	for seen < want {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_, data, err := conn.Read(ctx)
		cancel()
		if err != nil {
			t.Fatalf("drain presence: %v", err)
		}
		var frame map[string]json.RawMessage
		if json.Unmarshal(data, &frame) == nil {
			if _, ok := frame["presence"]; ok {
				seen++
			}
		}
	}
}

// readFrame reads one frame and returns it decoded.
func readFrame(t *testing.T, conn *websocket.Conn) map[string]json.RawMessage {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var frame map[string]json.RawMessage
	if err := json.Unmarshal(data, &frame); err != nil {
		t.Fatalf("decode frame %q: %v", data, err)
	}
	return frame
}

func TestBroadcastReachesEveryMemberOfTheRoom(t *testing.T) {
	hub := NewHub(quietLogger(), nil)
	srv := newRoomServer(t, hub)

	a := dial(t, srv, "t1", "241551058")
	defer a.Close(websocket.StatusNormalClosure, "")
	b := dial(t, srv, "t1", "241551204")
	defer b.Close(websocket.StatusNormalClosure, "")

	deadline := time.Now().Add(3 * time.Second)
	for hub.RoomSize("t1") < 2 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if hub.RoomSize("t1") != 2 {
		t.Fatalf("room size = %d, want 2", hub.RoomSize("t1"))
	}

	drainPresence(t, a, 2)
	drainPresence(t, b, 1)

	hub.Broadcast("t1", domain.EphemeralMessage{
		ID:      "m1",
		TopicID: "t1",
		Content: "viva moved to lab 3",
	}, "send_message")

	for name, conn := range map[string]*websocket.Conn{"a": a, "b": b} {
		frame := readUntil(t, conn, "send_message")
		raw := frame["send_message"]
		var msg domain.EphemeralMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			t.Fatalf("%s: decode message: %v", name, err)
		}
		if msg.Content != "viva moved to lab 3" {
			t.Errorf("%s: content = %q", name, msg.Content)
		}
	}
}

// TestSenderCannotSpoofIdentity is the security test for the chat path: a
// client that puts someone else's roll in the frame must not be able to post
// as them.
func TestSenderCannotSpoofIdentity(t *testing.T) {
	hub := NewHub(quietLogger(), nil)
	srv := newRoomServer(t, hub)

	sender := dial(t, srv, "t1", "241551058")
	defer sender.Close(websocket.StatusNormalClosure, "")
	listener := dial(t, srv, "t1", "241551204")
	defer listener.Close(websocket.StatusNormalClosure, "")

	deadline := time.Now().Add(3 * time.Second)
	for hub.RoomSize("t1") < 2 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	drainPresence(t, listener, 1)

	// Try to post as the Head of KSAC.
	spoof := `{"send_message":{"id":"local-1","topic_id":"t1",
		"sender_roll":"210000001","sender_branch_tag":"CSE '24",
		"content":"free pizza at campus 15","timestamp_unix":1700000000}}`
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := sender.Write(ctx, websocket.MessageText, []byte(spoof)); err != nil {
		t.Fatalf("write: %v", err)
	}

	frame := readUntil(t, listener, "send_message")
	var msg domain.EphemeralMessage
	if err := json.Unmarshal(frame["send_message"], &msg); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if msg.SenderRoll == "210000001" {
		t.Fatal("a client was able to post as another student")
	}
	if msg.SenderRoll != "241551058" {
		t.Errorf("sender = %q, want the connected roll 241551058", msg.SenderRoll)
	}
	if msg.SenderBranchTag != "CSE-AIML '28" {
		t.Errorf("branch tag = %q, want the verified tag", msg.SenderBranchTag)
	}
}

// TestClientIdIsEchoedForReconciliation: the sender needs its own optimistic id
// back so it can match the ack exactly, while the server still assigns the real
// message id.
func TestClientIdIsEchoedForReconciliation(t *testing.T) {
	hub := NewHub(quietLogger(), nil)
	srv := newRoomServer(t, hub)

	conn := dial(t, srv, "t1", "241551058")
	defer conn.Close(websocket.StatusNormalClosure, "")

	deadline := time.Now().Add(3 * time.Second)
	for hub.RoomSize("t1") < 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	drainPresence(t, conn, 1)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	frame := `{"send_message":{"id":"local-42","topic_id":"t1","content":"hi"}}`
	if err := conn.Write(ctx, websocket.MessageText, []byte(frame)); err != nil {
		t.Fatalf("write: %v", err)
	}

	var msg domain.EphemeralMessage
	if err := json.Unmarshal(readUntil(t, conn, "send_message")["send_message"], &msg); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if msg.ClientID != "local-42" {
		t.Errorf("client_id = %q, want local-42", msg.ClientID)
	}
	if msg.ID == "" || msg.ID == "local-42" {
		t.Errorf("server did not assign its own message id: %q", msg.ID)
	}
	if msg.TimestampUnix == 0 {
		t.Error("server did not stamp a timestamp")
	}
}

func TestOversizedMessageIsDropped(t *testing.T) {
	hub := NewHub(quietLogger(), nil)
	srv := newRoomServer(t, hub)

	conn := dial(t, srv, "t1", "241551058")
	defer conn.Close(websocket.StatusNormalClosure, "")
	deadline := time.Now().Add(3 * time.Second)
	for hub.RoomSize("t1") < 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	drainPresence(t, conn, 1)

	huge := strings.Repeat("a", 501)
	payload, _ := json.Marshal(map[string]any{
		"send_message": map[string]any{
			"id": "x", "topic_id": "t1", "content": huge,
		},
	})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := conn.Write(ctx, websocket.MessageText, payload); err != nil {
		t.Fatalf("write: %v", err)
	}

	// Nothing should come back within a short window.
	readCtx, readCancel := context.WithTimeout(context.Background(), 400*time.Millisecond)
	defer readCancel()
	if _, _, err := conn.Read(readCtx); err == nil {
		t.Fatal("an oversized message was broadcast")
	}
}

func TestEmptyRoomIsForgotten(t *testing.T) {
	hub := NewHub(quietLogger(), nil)
	srv := newRoomServer(t, hub)

	conn := dial(t, srv, "t1", "241551058")
	deadline := time.Now().Add(3 * time.Second)
	for hub.RoomSize("t1") < 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	conn.Close(websocket.StatusNormalClosure, "")

	deadline = time.Now().Add(3 * time.Second)
	for hub.RoomSize("t1") != 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if hub.RoomSize("t1") != 0 {
		t.Errorf("room size = %d after the last client left, want 0", hub.RoomSize("t1"))
	}
}

// TestConcurrentJoinsAndBroadcasts races the hub under -race to catch map
// corruption. Room membership is read from HTTP handlers and written from read
// loops, so an unlocked map would be a data race in production.
func TestConcurrentJoinsAndBroadcasts(t *testing.T) {
	hub := NewHub(quietLogger(), nil)
	srv := newRoomServer(t, hub)

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			conn := dial(t, srv, "t1", "roll"+string(rune('0'+i)))
			defer conn.Close(websocket.StatusNormalClosure, "")
			// Drain in the background so the send buffer never fills.
			go func() {
				for {
					if _, _, err := conn.Read(context.Background()); err != nil {
						return
					}
				}
			}()
		}(i)
	}

	go func() {
		for i := 0; i < 50; i++ {
			hub.Broadcast("t1", domain.EphemeralMessage{ID: "m", Content: "spam"}, "send_message")
			_ = hub.Members("t1")
			_ = hub.RoomSize("t1")
			time.Sleep(2 * time.Millisecond)
		}
	}()

	wg.Wait()
	hub.CloseAll()
}

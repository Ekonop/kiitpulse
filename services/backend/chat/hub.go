// Package chat implements the ephemeral topic rooms.
//
// One hub holds every room. Each client gets a buffered send channel and a
// dedicated writer goroutine, so a slow reader on a bad hostel connection can
// never block a broadcast to everyone else: when the buffer fills, that client
// is dropped rather than stalling the room. That single decision is what keeps
// a 500-student topic responsive.
package chat

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"github.com/kiitpulse/backend/domain"
)

const (
	// sendBuffer is per-client. A reader more than this far behind is dropped.
	sendBuffer = 64

	// writeTimeout bounds a single frame write.
	writeTimeout = 10 * time.Second

	// pingInterval / pongTimeout detect a half-open socket.
	pingInterval = 25 * time.Second
	pongTimeout  = 60 * time.Second
)

// Client is one connected socket in a room.
type Client struct {
	hub     *Hub
	conn    *websocket.Conn
	topicID string
	student domain.Student

	send      chan []byte
	closed    atomic.Bool
	closeOnce sync.Once

	// sendMu guards sends against close. `closed.Load()` followed by a send is
	// not atomic: close() could fire in between, and sending on a closed
	// channel panics. Holding the read lock across the send makes the pair
	// safe.
	sendMu sync.RWMutex
}

// Hub tracks rooms and their members.
type Hub struct {
	mu    sync.RWMutex
	rooms map[string]map[*Client]struct{}

	log *slog.Logger

	// joined is called when a client enters a room (presence/velocity hook).
	joined func(topicID string)
}

// NewHub builds an empty hub.
func NewHub(log *slog.Logger, onJoin func(topicID string)) *Hub {
	if log == nil {
		log = slog.Default()
	}
	return &Hub{
		rooms:  make(map[string]map[*Client]struct{}),
		log:    log,
		joined: onJoin,
	}
}

// HandleSocket takes over an upgraded connection for a topic room.
//
// This is the `func(*gin.Context)`-free core: the Gin route upgrades the
// request and hands the connection here, which keeps the hub testable without
// an HTTP server.
func (h *Hub) HandleSocket(conn *websocket.Conn, topicID string, student domain.Student) {
	c := &Client{
		hub:     h,
		conn:    conn,
		topicID: topicID,
		student: student,
		send:    make(chan []byte, sendBuffer),
	}

	h.join(c)
	defer h.leave(c)

	// Announce presence to the room.
	h.Broadcast(topicID, domain.PresenceFrame{
		TopicID: topicID,
		Count:   h.RoomSize(topicID),
		Members: h.Members(topicID),
	}, "presence")

	if h.joined != nil {
		h.joined(topicID)
	}

	// One goroutine writes; this one reads.
	go c.writeLoop()

	c.readLoop()
}

func (h *Hub) join(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.rooms[c.topicID] == nil {
		h.rooms[c.topicID] = make(map[*Client]struct{})
	}
	h.rooms[c.topicID][c] = struct{}{}
}

func (h *Hub) leave(c *Client) {
	h.mu.Lock()
	if room, ok := h.rooms[c.topicID]; ok {
		delete(room, c)
		if len(room) == 0 {
			delete(h.rooms, c.topicID)
		}
	}
	h.mu.Unlock()

	c.close()
}

// RoomSize reports how many sockets are in a room.
func (h *Hub) RoomSize(topicID string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.rooms[topicID])
}

// Members lists the roll numbers currently in a room.
func (h *Hub) Members(topicID string) []string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	room := h.rooms[topicID]
	out := make([]string, 0, len(room))
	for c := range room {
		out = append(out, c.student.RollNumber)
	}
	return out
}

// Broadcast sends a payload to every client in a room.
//
// The payload is marshalled once, not per client. Slow clients are dropped
// rather than blocking the room.
func (h *Hub) Broadcast(topicID string, payload any, kind string) {
	body, err := json.Marshal(map[string]any{kind: payload})
	if err != nil {
		h.log.Error("chat: marshal broadcast", "topic", topicID, "err", err)
		return
	}

	h.mu.RLock()
	room := h.rooms[topicID]
	targets := make([]*Client, 0, len(room))
	for c := range room {
		targets = append(targets, c)
	}
	h.mu.RUnlock()

	for _, c := range targets {
		if c.trySend(body) {
			continue
		}
		// Buffer full (or already closed): this client is not keeping up.
		// Disconnecting it is better than stalling every other student.
		h.log.Warn("chat: dropping slow client",
			"topic", topicID, "roll", c.student.RollNumber)
		c.close()
	}
}

// ClientCount is the total number of live sockets across all rooms.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	n := 0
	for _, room := range h.rooms {
		n += len(room)
	}
	return n
}

// CloseAll shuts every socket down, used on server shutdown.
func (h *Hub) CloseAll() {
	h.mu.Lock()
	clients := make([]*Client, 0)
	for _, room := range h.rooms {
		for c := range room {
			clients = append(clients, c)
		}
	}
	h.mu.Unlock()
	for _, c := range clients {
		c.close()
	}
}

// ---- client ------------------------------------------------------------

// trySend delivers a frame without risking a send on a closed channel.
// Returns false if the client is closed or its buffer is full.
func (c *Client) trySend(body []byte) bool {
	c.sendMu.RLock()
	defer c.sendMu.RUnlock()
	if c.closed.Load() {
		return false
	}
	select {
	case c.send <- body:
		return true
	default:
		return false
	}
}

func (c *Client) close() {
	c.closeOnce.Do(func() {
		// Take the write lock so no broadcast is mid-send when the channel
		// closes. Order matters: flag first, then close under the lock.
		c.sendMu.Lock()
		c.closed.Store(true)
		close(c.send)
		c.sendMu.Unlock()
	})
}

func (c *Client) readLoop() {
	ctx := context.Background()
	for {
		typ, data, err := c.conn.Read(ctx)
		if err != nil {
			if !errors.Is(err, context.Canceled) {
				c.hub.log.Debug("chat: read closed",
					"topic", c.topicID, "roll", c.student.RollNumber, "err", err)
			}
			return
		}
		if typ != websocket.MessageText {
			continue
		}

		var frame map[string]json.RawMessage
		if err := json.Unmarshal(data, &frame); err != nil {
			continue
		}

		if raw, ok := frame["send_message"]; ok {
			c.handleMessage(raw)
		}
		// Reaction and hand-raise frames are routed by their own services;
		// the hub only fans text out.
	}
}

func (c *Client) handleMessage(raw json.RawMessage) {
	var incoming domain.EphemeralMessage
	if err := json.Unmarshal(raw, &incoming); err != nil {
		return
	}
	if incoming.Content == "" || len(incoming.Content) > 500 {
		return
	}
	// Never trust the sender fields from the wire: a client could post as
	// anyone. Identity comes from the verified session.
	incoming.TopicID = c.topicID
	incoming.SenderRoll = c.student.RollNumber
	incoming.SenderBranchTag = c.student.BranchTag

	// The client sends its optimistic id in `id`; keep it as ClientID so the
	// sender can match the echo exactly, then issue the real id.
	incoming.ClientID = incoming.ID
	incoming.ID = newMessageID()
	if incoming.TimestampUnix == 0 {
		incoming.TimestampUnix = time.Now().Unix()
	}

	c.hub.Broadcast(c.topicID, incoming, "send_message")
}

func (c *Client) writeLoop() {
	ctx := context.Background()
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	for {
		select {
		case body, ok := <-c.send:
			if !ok {
				c.conn.Close(websocket.StatusNormalClosure, "bye")
				return
			}
			writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Write(writeCtx, websocket.MessageText, body)
			cancel()
			if err != nil {
				return
			}
		case <-ticker.C:
			pingCtx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Ping(pingCtx)
			cancel()
			if err != nil {
				return
			}
		}
	}
}

// newMessageID issues a server-side message id.
//
// Random rather than a counter: message ids are not security-sensitive, but a
// per-process counter would collide across replicas and the client uses the id
// for dedupe.
func newMessageID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "m-" + strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return "m-" + hex.EncodeToString(b)
}

// Package voice mints LiveKit access tokens for topic stages.
//
// The security model, stated once:
//
//   - A listener token can subscribe and nothing else. It is what the hand-raise
//     flow starts from.
//   - A speaker token can publish. It is only ever minted when the server has
//     decided the student may speak (a moderator granted it), never because a
//     client asked.
//   - The room name is derived from the topic id, so a token for one room cannot
//     be replayed into another.
//
// Without this package the endpoint returns a stub, which meant "voice stages"
// were a drawing in the UI. With it they are real rooms on a real SFU.
package voice

import (
	"errors"
	"fmt"
	"time"

	"github.com/livekit/protocol/auth"
)

// ErrNotConfigured means no LiveKit server is set up for this deployment.
var ErrNotConfigured = errors.New("voice is not configured on this deployment")

// Config is the LiveKit connection settings.
type Config struct {
	// URL is the SFU websocket URL, e.g. wss://voice.kiitpulse.app
	URL string
	// APIKey and APISecret sign participant tokens.
	APIKey    string
	APISecret string
}

// Configured reports whether voice can be served.
func (c Config) Configured() bool {
	return c.URL != "" && c.APIKey != "" && c.APISecret != ""
}

// RoomName returns the LiveKit room for a topic.
//
// Prefixed so topics cannot collide with any other room on a shared SFU.
func RoomName(topicID string) string { return "kiit-huddle-" + topicID }

// TokenRequest describes what a student should be allowed to do.
type TokenRequest struct {
	TopicID    string
	Roll       string
	CanPublish bool
}

// Mint issues an access token.
//
// The caller decides CanPublish; this function does not consult the client. A
// listener token is genuinely publish-free at the SFU, not merely un-intended
// by the app - the grant is absent from the signed token.
func Mint(cfg Config, req TokenRequest) (string, string, error) {
	if !cfg.Configured() {
		return "", "", ErrNotConfigured
	}
	if req.TopicID == "" || req.Roll == "" {
		return "", "", fmt.Errorf("voice: topic id and roll number are required")
	}

	room := RoomName(req.TopicID)
	at := auth.NewAccessToken(cfg.APIKey, cfg.APISecret)

	// Identity must be unique per participant. The roll alone would collide if a
	// student opens the app on two devices, which silently kicks one out.
	grant := &auth.VideoGrant{
		RoomJoin:     true,
		Room:         room,
		CanPublish:   &req.CanPublish,
		CanSubscribe: boolPtr(true),
	}
	at.SetVideoGrant(grant).
		SetIdentity(req.Roll).
		SetName(req.Roll).
		// A stage is a session, not a subscription: the token must not outlive
		// the room by much.
		SetValidFor(2 * time.Hour)

	token, err := at.ToJWT()
	if err != nil {
		return "", "", fmt.Errorf("voice: sign token: %w", err)
	}
	return token, room, nil
}

func boolPtr(b bool) *bool { return &b }

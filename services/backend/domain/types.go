// Package domain holds the wire types shared by every service.
//
// These mirror contracts/proto/kiitpulse/v1 and the Dart types in
// packages/kiit_contracts. JSON field names are the contract: they are what
// the Flutter client decodes, so they must not drift.
package domain

import "time"

// TopicPulse is one trending node on the campus radar.
type TopicPulse struct {
	ID                  string  `json:"id"`
	Title               string  `json:"title"`
	Description         string  `json:"description"`
	Zone                int32   `json:"zone"`
	VelocityScore       float64 `json:"velocity_score"`
	HasActiveVoiceStage bool    `json:"has_active_voice_stage"`
	ActiveSpeakers      int32   `json:"active_speakers"`
	ActiveListeners     int32   `json:"active_listeners"`
	MessageCount        int32   `json:"message_count"`
	CreatedAtUnix       int64   `json:"created_at_unix"`
	LastActivityUnix    int64   `json:"last_activity_unix"`
	Tag                 string  `json:"tag,omitempty"`
}

// EphemeralMessage is a single chat message inside a topic room.
type EphemeralMessage struct {
	ID      string `json:"id"`
	TopicID string `json:"topic_id"`

	// ClientID is the sender's optimistic id, echoed back so the client can
	// reconcile its own message by identity instead of guessing from
	// sender+content. Two identical messages from one student would otherwise
	// cross-match and one would appear to vanish.
	ClientID string `json:"client_id,omitempty"`

	SenderRoll      string `json:"sender_roll"`
	SenderBranchTag string `json:"sender_branch_tag"`
	Content         string `json:"content"`
	TimestampUnix   int64  `json:"timestamp_unix"`
}

// PresenceFrame tells a room how many students are in it.
type PresenceFrame struct {
	TopicID string   `json:"topic_id"`
	Count   int      `json:"count"`
	Members []string `json:"members,omitempty"`
}

// VelocityTick is pushed when a topic's score changes.
type VelocityTick struct {
	TopicID         string  `json:"topic_id"`
	UpdatedVelocity float64 `json:"updated_velocity"`
	ActiveListeners int32   `json:"active_listeners"`
}

// Participant is one person on a voice stage.
type Participant struct {
	Identity   string `json:"identity"`
	Roll       string `json:"roll"`
	BranchTag  string `json:"branch_tag"`
	Role       string `json:"role"`
	IsSpeaking bool   `json:"is_speaking"`
	IsMuted    bool   `json:"is_muted"`
	JoinedUnix int64  `json:"joined_unix"`
}

// Stage roles. Only the server can grant `speaker` or `moderator`.
const (
	RoleListener   = "listener"
	RoleHandRaised = "hand_raised"
	RoleSpeaker    = "speaker"
	RoleModerator  = "moderator"
)

// Student is the authenticated identity carried on every request.
type Student struct {
	Email      string `json:"email"`
	RollNumber string `json:"roll_number"`
	BranchTag  string `json:"branch_tag"`
}

// NewEphemeralMessage stamps the time so callers cannot lie about it.
func NewEphemeralMessage(id, topicID, roll, branch, content string) EphemeralMessage {
	return EphemeralMessage{
		ID:              id,
		TopicID:         topicID,
		SenderRoll:      roll,
		SenderBranchTag: branch,
		Content:         content,
		TimestampUnix:   time.Now().Unix(),
	}
}

// StageRole is a student's place on a topic's voice stage.
//
// The wire values match the Dart StageRole enum exactly, because the client
// switches on these strings. A mismatch would be a silent role bug.
type StageRole string

const (
	StageRoleListener   StageRole = "listener"
	StageRoleHandRaised StageRole = "handRaised"
	StageRoleSpeaker    StageRole = "speaker"
	StageRoleModerator  StageRole = "moderator"
)

// StageMember is one person on a stage.
type StageMember struct {
	Roll string    `json:"roll"`
	Role StageRole `json:"role"`
}

// ReactionKind is the emoji-independent reaction a student can add.
//
// Deliberately a closed set: a free-text reaction field is an abuse vector on a
// campus app with no moderation queue, and three kinds cover what a topic room
// actually needs.
type ReactionKind string

const (
	ReactionFire  ReactionKind = "fire"
	ReactionAgree ReactionKind = "agree"
	ReactionAsk   ReactionKind = "ask"
)

// Valid reports whether a kind is one we accept.
func (k ReactionKind) Valid() bool {
	switch k {
	case ReactionFire, ReactionAgree, ReactionAsk:
		return true
	}
	return false
}

// Badge is one entry on a student's passport.
//
// EventName carries the evidence that earned it, not an event the student
// attended: this deployment has no attendance feed. The field name matches the
// wire contract the app already reads.
type Badge struct {
	ID          string `json:"id"`
	StudentRoll string `json:"student_roll"`
	Type        string `json:"badge_type"`
	Label       string `json:"label"`
	EventName   string `json:"event_name,omitempty"`
	IssuedAt    int64  `json:"issued_at_unix"`
	AccentArgb  uint32 `json:"accent_argb"`
	Verified    bool   `json:"verified"`
}

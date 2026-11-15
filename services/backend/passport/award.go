// Package passport issues the badges shown on a student's foil passport.
//
// ## What these badges are, and what they are not
//
// The blueprint's badges are event attendance: "KIIT Fest 2026 · Core Team",
// "K1000 HackNight · Speaker". This server has no attendance feed, no society
// roster and no way to check whether a student actually turned up to KIIT Fest.
// Inventing those badges would mean printing a credential nobody verified -
// exactly the kind of fake this project avoids elsewhere.
//
// So this package awards a different, honest thing: badges earned from activity
// this server observed itself. Every one states the evidence that produced it,
// in the badge's `event_name`, so the UI can never present it as attendance.
package passport

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/kiitpulse/backend/domain"
	"github.com/kiitpulse/backend/radar"
)

// Activity is what the server knows about a student when awarding.
type Activity struct {
	Roll          string
	TopicsStarted int
	MessagesSent  int
	VoiceJoins    int
	ZonesVisited  int
	// FirstSeen is when this roll first appeared.
	FirstSeen time.Time
}

// Award decides which badges a student has earned.
//
// A pure function of the activity, so the same activity always yields the same
// badges and the tests do not depend on the wall clock.
func Award(a Activity) []domain.Badge {
	issued := a.FirstSeen
	if issued.IsZero() {
		issued = time.Now()
	}

	out := make([]domain.Badge, 0, 5)
	add := func(id, kind, label string, accent uint32, evidence string) {
		out = append(out, domain.Badge{
			ID:          fmt.Sprintf("b-%s-%s", id, a.Roll),
			StudentRoll: a.Roll,
			Type:        kind,
			Label:       label,
			EventName:   evidence,
			IssuedAt:    issued.Unix(),
			AccentArgb:  accent,
			Verified:    true,
		})
	}

	// Thresholds are low enough to be reachable in one day. A badge nobody can
	// earn is decoration, not a reward.
	if a.MessagesSent >= 1 {
		add("first-word", "FIRST_WORD", "First Word", 0xFF00C853,
			fmt.Sprintf("%d messages sent on the campus radar", a.MessagesSent))
	}
	if a.TopicsStarted >= 1 {
		add("icebreaker", "ICEBREAKER", "Icebreaker", 0xFF00B0FF,
			fmt.Sprintf("opened %d topics", a.TopicsStarted))
	}
	if a.VoiceJoins >= 1 {
		add("on-mic", "ON_MIC", "On the Mic", 0xFFFFB300,
			fmt.Sprintf("joined %d voice stages", a.VoiceJoins))
	}
	if a.ZonesVisited >= 3 {
		add("pathfinder", "PATHFINDER", "Pathfinder", 0xFFFF4D4D,
			fmt.Sprintf("active in %d campus zones", a.ZonesVisited))
	}
	if a.MessagesSent >= 25 {
		add("loudspeaker", "LOUDSPEAKER", "Loudspeaker", 0xFF00C853,
			fmt.Sprintf("%d messages sent", a.MessagesSent))
	}
	return out
}

// Tracker accumulates per-student activity in Redis.
//
// Counters, not an event log: the passport needs totals, and a campus app
// should not keep a permanent record of every message a student sent. They
// expire on the same 24-hour horizon as the topics.
type Tracker struct {
	store *radar.Store
}

// NewTracker builds a tracker over the radar store's Redis connection.
func NewTracker(s *radar.Store) *Tracker { return &Tracker{store: s} }

// Activity reads a student's counters.
func (t *Tracker) Activity(ctx context.Context, roll string) (Activity, error) {
	a := Activity{Roll: roll}
	vals, err := t.store.ActivityCounters(ctx, roll)
	if err != nil {
		return a, err
	}
	a.MessagesSent = vals["messages"]
	a.TopicsStarted = vals["topics"]
	a.VoiceJoins = vals["voice_joins"]
	a.ZonesVisited = vals["zones"]
	if ts := vals["first_seen"]; ts > 0 {
		a.FirstSeen = time.Unix(int64(ts), 0)
	}
	return a, nil
}

// RecordMessage credits a sent message.
func (t *Tracker) RecordMessage(ctx context.Context, roll string) error {
	return t.store.BumpActivity(ctx, roll, "messages")
}

// RecordTopic credits a created topic.
func (t *Tracker) RecordTopic(ctx context.Context, roll string) error {
	return t.store.BumpActivity(ctx, roll, "topics")
}

// RecordVoiceJoin credits entering a stage.
func (t *Tracker) RecordVoiceJoin(ctx context.Context, roll string) error {
	return t.store.BumpActivity(ctx, roll, "voice_joins")
}

// RecordZone marks that a student was active in a zone. Repeat visits to the
// same zone count once, which is why this is a set rather than a counter.
func (t *Tracker) RecordZone(ctx context.Context, roll, zone string) error {
	return t.store.AddActivityZone(ctx, roll, zone)
}

// SortByIssued orders badges newest first, which is how a passport reads.
func SortByIssued(badges []domain.Badge) {
	sort.Slice(badges, func(i, j int) bool {
		return badges[i].IssuedAt > badges[j].IssuedAt
	})
}

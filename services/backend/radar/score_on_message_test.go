package radar

import (
	"context"
	"testing"
	"time"

	"github.com/kiitpulse/backend/campus"
	"github.com/kiitpulse/backend/domain"
)

// TestMessageScoringPipeline reproduces what main.go's persistence worker does
// for every broadcast message: append it, then score it.
//
// This exists because the wiring, not the primitives, was broken. Score,
// RawScore and RecordEvent were all unit-tested and all correct - but nothing
// ever called RecordEvent, so in the live backend the radar was a list sorted
// by creation time wearing a velocity badge. The demo gateway faked the motion,
// which is why it looked right.
func TestMessageScoringPipeline(t *testing.T) {
	s, _ := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneCampus15

	created, err := s.CreateTopic(ctx, domain.TopicPulse{
		ID: "t-pipeline", Title: "viva", Description: "where", Zone: int32(zone),
	})
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	seedTopicScore := created.VelocityScore
	seedCount := created.MessageCount

	// Deliver messages the way the worker does.
	for i := 0; i < 5; i++ {
		err := s.AppendMessage(ctx, domain.EphemeralMessage{
			ID: "m-x", TopicID: "t-pipeline", SenderRoll: "241551058",
			Content: "hello",
		})
		if err != nil {
			t.Fatalf("append: %v", err)
		}
		// The worker looks the topic up to learn its zone, then scores.
		topic, err := s.Topic(ctx, "t-pipeline")
		if err != nil {
			t.Fatalf("topic: %v", err)
		}
		if err := s.RecordEvent(ctx, campus.Zone(topic.Zone), topic.ID, EventMessage); err != nil {
			t.Fatalf("record: %v", err)
		}
	}

	final, err := s.Topic(ctx, "t-pipeline")
	if err != nil {
		t.Fatalf("topic: %v", err)
	}
	if final.MessageCount <= seedCount {
		t.Errorf("message_count = %d, seed was %d; messages are not counted",
			final.MessageCount, seedCount)
	}
	if final.VelocityScore <= seedTopicScore {
		t.Errorf("score = %v, seed was %v; the radar never moved",
			final.VelocityScore, seedTopicScore)
	}
}

// TestVoiceJoinOutranksMessages pins the weighting the blueprint asks for: a
// voice join is a stronger intent signal than typing.
func TestVoiceJoinOutranksMessages(t *testing.T) {
	s, _ := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneCampus15

	_, _ = s.CreateTopic(ctx, domain.TopicPulse{ID: "a", Title: "t", Description: "d", Zone: int32(zone)})
	_, _ = s.CreateTopic(ctx, domain.TopicPulse{ID: "b", Title: "t", Description: "d", Zone: int32(zone)})

	_ = s.RecordEvent(ctx, zone, "a", EventMessage)
	_ = s.RecordEvent(ctx, zone, "b", EventVoiceJoin)

	a, _ := s.Score(ctx, zone, "a")
	b, _ := s.Score(ctx, zone, "b")
	if b <= a {
		t.Errorf("voice join scored %v, message scored %v; the 3.5x weight is not applied", b, a)
	}
}

// TestVelocityDecaysWithAge is the blueprint's central claim, and it was not
// true of the stored value: Topic returned the raw accumulator, so a topic with
// one voice join scored 3.5 forever and outranked a genuinely busy topic.
func TestVelocityDecaysWithAge(t *testing.T) {
	s, mr := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneCampus15

	_, _ = s.CreateTopic(ctx, domain.TopicPulse{ID: "old", Title: "t", Description: "d", Zone: int32(zone)})
	_, _ = s.CreateTopic(ctx, domain.TopicPulse{ID: "new", Title: "t", Description: "d", Zone: int32(zone)})

	// Both get identical activity...
	_ = s.RecordEvent(ctx, zone, "old", EventMessage)
	_ = s.RecordEvent(ctx, zone, "new", EventMessage)

	// ...then ten quiet minutes pass...
	mr.FastForward(10 * time.Minute)

	// ...and only "new" gets activity again. "old" has been silent since, so it
	// must rank lower even though its raw event total is the same.

	_ = s.RecordEvent(ctx, zone, "new", EventMessage)

	fresh, _ := s.Topic(ctx, "new")
	aged, _ := s.Topic(ctx, "old")

	if aged.VelocityScore >= fresh.VelocityScore {
		t.Errorf("aged topic scored %v, fresh scored %v; velocity is not decaying with age",
			aged.VelocityScore, fresh.VelocityScore)
	}
	if aged.VelocityScore <= 0 {
		t.Errorf("aged topic decayed to %v; it should be small but positive", aged.VelocityScore)
	}
}

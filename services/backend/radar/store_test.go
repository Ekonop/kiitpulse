package radar

import (
	"context"
	"testing"

	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/kiitpulse/backend/campus"
	"github.com/kiitpulse/backend/domain"
)

// newTestStore runs against an in-memory Redis so the real ZSET operations the
// trending radar depends on are exercised: ZINCRBY weights, ZREVRANGE ranking,
// and the rewrite-based decay.
func newTestStore(t *testing.T) (*Store, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	return NewStore(rdb), mr
}

func topic(id string, zone campus.Zone, title string) domain.TopicPulse {
	return domain.TopicPulse{
		ID:           id,
		Title:        title,
		Zone:         int32(zone),
		MessageCount: 1,
	}
}

func TestZoneTopicsRankedByVelocity(t *testing.T) {
	s, _ := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneCampus15

	for _, tp := range []domain.TopicPulse{
		topic("hot", zone, "DSA viva tomorrow"),
		topic("warm", zone, "canteen menu"),
		topic("mid", zone, "tiffin share"),
	} {
		if err := s.CreateTopic(ctx, tp); err != nil {
			t.Fatalf("create %s: %v", tp.ID, err)
		}
	}

	// The hot topic gets a message plus a couple of voice joins.
	_ = s.RecordEvent(ctx, zone, "hot", EventMessage)
	_ = s.RecordEvent(ctx, zone, "hot", EventVoiceJoin)
	_ = s.RecordEvent(ctx, zone, "hot", EventVoiceJoin)
	_ = s.RecordEvent(ctx, zone, "warm", EventReaction)

	topics, err := s.ZoneTopics(ctx, zone, 10)
	if err != nil {
		t.Fatalf("ZoneTopics: %v", err)
	}
	if len(topics) != 3 {
		t.Fatalf("got %d topics, want 3", len(topics))
	}

	if topics[0].ID != "hot" {
		t.Errorf("rank 1 = %s, want hot", topics[0].ID)
	}
	if topics[0].VelocityScore <= topics[1].VelocityScore {
		t.Errorf("hot score %v not above warm %v",
			topics[0].VelocityScore, topics[1].VelocityScore)
	}
	// A voice join (3.5) must dominate a message (1.0) + reaction (0.25).
	if topics[1].ID != "warm" {
		t.Errorf("rank 2 = %s, want warm; hot drew ahead on voice joins",
			topics[1].ID)
	}
}

func TestDecayAllPurgesColdTopics(t *testing.T) {
	s, mr := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneCampus15

	_ = s.CreateTopic(ctx, topic("busy", zone, "busy room"))
	// A hot topic that stops getting engagement.
	_ = s.RecordEvent(ctx, zone, "busy", EventMessage)
	_ = s.RecordEvent(ctx, zone, "busy", EventMessage)
	_ = s.RecordEvent(ctx, zone, "busy", EventMessage)

	// CreateTopic seeds 1 message; three more events put it at 4.0.
	score, _ := s.Score(ctx, zone, "busy")
	if score <= 0 {
		t.Fatalf("seed score = %v, want something worth decaying", score)
	}

	// Rust on the ground: an undeleted stale member with a floor-crossing score.
	mr.ZAdd("kiit:radar:"+zone.Key(), 0.05, "stale")
	mr.HSet("kiit:topic:stale", "id", "stale")

	purged, err := s.DecayAll(ctx)
	if err != nil {
		t.Fatalf("DecayAll: %v", err)
	}
	if purged == 0 {
		t.Fatal("expected the stale member to be purged")
	}

	// The busy topic must survive, just decayed.
	after, err := s.Score(ctx, zone, "busy")
	if err != nil {
		t.Fatalf("busy topic vanished: %v", err)
	}
	if after >= score {
		t.Errorf("busy score = %v after one decay, want < %v", after, score)
	}

	// And the stale member must be gone from ranking.
	topics, _ := s.ZoneTopics(ctx, zone, 10)
	for _, tp := range topics {
		if tp.ID == "stale" {
			t.Error("stale member still ranked after purge")
		}
	}
}

func TestRecordEventRefreshesTTL(t *testing.T) {
	s, mr := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneCampus15

	_ = s.CreateTopic(ctx, topic("t1", zone, "one"))
	key := "kiit:topic:t1"

	mr.FastForward(3 * time.Hour)
	ttl := mr.TTL(key)
	if ttl <= 0 {
		t.Fatalf("topic ttl = %v after creation", ttl)
	}

	// An event after 3 hours must refresh the TTL back to ~24h.
	_ = s.RecordEvent(ctx, zone, "t1", EventMessage)
	ttl2 := mr.TTL(key)
	if ttl2 < 20*time.Hour {
		t.Errorf("ttl after event = %v, want refreshed toward 24h", ttl2)
	}
}

func TestCreateTopicRejectsUnknownZone(t *testing.T) {
	s, _ := newTestStore(t)
	ctx := context.Background()
	err := s.CreateTopic(ctx, topic("bad", campus.ZoneOffCampus, "x"))
	if err == nil {
		t.Fatal("creating a topic in offCampus must fail")
	}
}

func TestZonePopulation(t *testing.T) {
	s, _ := newTestStore(t)
	ctx := context.Background()
	zone := campus.ZoneKPHostels

	n, err := s.JoinPresence(ctx, zone, "241551058")
	if err != nil || n != 1 {
		t.Fatalf("first join: n=%d err=%v, want 1", n, err)
	}
	n, err = s.JoinPresence(ctx, zone, "241551204")
	if err != nil || n != 2 {
		t.Fatalf("second join: n=%d err=%v, want 2", n, err)
	}
	// Same roll again: presence is a set, so no change.
	n, _ = s.JoinPresence(ctx, zone, "241551058")
	if n != 2 {
		t.Errorf("rejoin: n=%d, want 2 (presence is a set)", n)
	}

	pop, err := s.ZonePopulation(ctx, zone)
	if err != nil || pop != 2 {
		t.Errorf("population = %d err=%v, want 2", pop, err)
	}
}

func TestMergeZones(t *testing.T) {
	a := []domain.TopicPulse{
		{ID: "a1", VelocityScore: 40},
		{ID: "a2", VelocityScore: 90},
	}
	b := []domain.TopicPulse{
		{ID: "b1", VelocityScore: 20},
	}

	merged := MergeZones(a, b)
	if len(merged) != 3 {
		t.Fatalf("merged = %d items, want 3", len(merged))
	}
	// Descending score.
	if merged[0].ID != "a2" || merged[1].ID != "a1" || merged[2].ID != "b1" {
		t.Errorf("merge order wrong: %v", merged)
	}
}

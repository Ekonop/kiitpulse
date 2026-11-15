package stage

import (
	"sync"
	"testing"

	"github.com/kiitpulse/backend/domain"
)

func TestGrantAndCheck(t *testing.T) {
	r := New()

	if r.IsSpeaker("t1", "241551058") {
		t.Fatal("nobody is a speaker before being granted")
	}

	r.GrantSpeaker("t1", "241551058")
	if !r.IsSpeaker("t1", "241551058") {
		t.Error("granted speaker not recognised")
	}

	// Grants are per topic.
	if r.IsSpeaker("t2", "241551058") {
		t.Error("a grant in t1 leaked into t2")
	}

	r.RevokeSpeaker("t1", "241551058")
	if r.IsSpeaker("t1", "241551058") {
		t.Error("revoked speaker still recognised")
	}
}

func TestMaxSpeakersIsEnforced(t *testing.T) {
	r := New()
	r.MaxSpeakers = 2

	r.GrantSpeaker("t1", "a")
	r.GrantSpeaker("t1", "b")
	r.GrantSpeaker("t1", "c") // over the cap

	if got := len(r.Speakers("t1")); got != 2 {
		t.Errorf("speakers = %d, want the cap of 2", got)
	}
	if r.IsSpeaker("t1", "c") {
		t.Error("a speaker was granted past the cap")
	}
}

func TestSpeakersList(t *testing.T) {
	r := New()
	r.GrantSpeaker("t1", "a")
	r.GrantSpeaker("t1", "b")

	got := r.Speakers("t1")
	if len(got) != 2 {
		t.Fatalf("speakers = %v", got)
	}
	if r.Speakers("nonexistent") == nil {
		t.Error("Speakers should return an empty slice, not nil")
	}
}

func TestEmptyTopicIsForgotten(t *testing.T) {
	r := New()
	r.Join("t1", "a")
	r.Leave("t1", "a")

	r.mu.RLock()
	_, exists := r.topic["t1"]
	r.mu.RUnlock()
	if exists {
		t.Error("an empty topic was left in the map; a long-lived server leaks")
	}
}

// TestRevokingSpeakerDemotesRatherThanRemoves: revoking the mic must not also
// kick the student out of the room. They stay on the stage as a listener.
func TestRevokingSpeakerDemotesRatherThanRemoves(t *testing.T) {
	r := New()
	r.Join("t1", "a")
	r.GrantSpeaker("t1", "a")
	r.RevokeSpeaker("t1", "a")

	if r.Role("t1", "a") != domain.StageRoleListener {
		t.Errorf("role = %q, want listener after revoke", r.Role("t1", "a"))
	}
	if r.Size("t1") != 1 {
		t.Error("revoking a speaker removed them from the stage entirely")
	}
}

// TestJoinIsIdempotent is the reconnect case: a dropped socket must not demote
// a speaker when they come back.
func TestJoinIsIdempotent(t *testing.T) {
	r := New()
	r.Join("t1", "a")
	r.GrantSpeaker("t1", "a")
	r.Join("t1", "a") // reconnect

	if !r.IsSpeaker("t1", "a") {
		t.Error("reconnecting revoked the microphone grant")
	}
}

func TestSpeakerKeepsMicWhenLoweringHand(t *testing.T) {
	r := New()
	r.Join("t1", "a")
	r.GrantSpeaker("t1", "a")
	r.SetHand("t1", "a", false)

	if !r.IsSpeaker("t1", "a") {
		t.Error("lowering a hand cut a speaker's microphone")
	}
}

// TestConcurrentAccess runs under -race: stages are read from HTTP handlers
// while being written from promotion events.
func TestConcurrentAccess(t *testing.T) {
	r := New()
	r.MaxSpeakers = 100

	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			roll := string(rune('a' + i))
			for j := 0; j < 50; j++ {
				r.GrantSpeaker("t1", roll)
				_ = r.IsSpeaker("t1", roll)
				_ = r.Speakers("t1")
				r.RevokeSpeaker("t1", roll)
			}
		}(i)
	}
	wg.Wait()
}

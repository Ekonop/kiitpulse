package passport

import (
	"testing"
	"time"
)

func TestNoActivityNoBadges(t *testing.T) {
	// A brand-new student has earned nothing. An empty passport is the honest
	// answer; inventing event badges would be claiming attendance we never saw.
	if got := Award(Activity{Roll: "241551058"}); len(got) != 0 {
		t.Fatalf("a new student has %d badges, want 0", len(got))
	}
}

func TestFirstMessageEarnsFirstWord(t *testing.T) {
	got := Award(Activity{Roll: "241551058", MessagesSent: 1})
	if len(got) != 1 || got[0].Type != "FIRST_WORD" {
		t.Fatalf("badges = %+v", got)
	}
}

func TestBadgesStateTheirEvidence(t *testing.T) {
	got := Award(Activity{Roll: "241551058", MessagesSent: 7})
	if len(got) == 0 {
		t.Fatal("no badges")
	}
	for _, b := range got {
		if b.EventName == "" {
			t.Errorf("badge %q has no evidence text; the UI cannot explain it", b.Label)
		}
		if !b.Verified {
			t.Errorf("badge %q is not marked verified", b.Label)
		}
		if b.StudentRoll != "241551058" {
			t.Errorf("badge issued to %q, want the requesting roll", b.StudentRoll)
		}
	}
}

func TestThresholds(t *testing.T) {
	cases := []struct {
		name string
		a    Activity
		want int
	}{
		{"one message", Activity{MessagesSent: 1}, 1},
		{"one topic", Activity{TopicsStarted: 1}, 1},
		{"one voice join", Activity{VoiceJoins: 1}, 1},
		{"two zones is not enough", Activity{ZonesVisited: 2}, 0},
		{"three zones earns pathfinder", Activity{ZonesVisited: 3}, 1},
		{"25 messages earns loudspeaker too", Activity{MessagesSent: 25}, 2},
		{"everything", Activity{MessagesSent: 30, TopicsStarted: 1, VoiceJoins: 2, ZonesVisited: 4}, 5},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			c.a.Roll = "241551058"
			if got := len(Award(c.a)); got != c.want {
				t.Errorf("got %d badges, want %d: %+v", got, c.want, Award(c.a))
			}
		})
	}
}

func TestAwardIsDeterministic(t *testing.T) {
	a := Activity{
		Roll:          "241551058",
		MessagesSent:  3,
		TopicsStarted: 1,
		FirstSeen:     time.Unix(1700000000, 0),
	}
	first := Award(a)
	second := Award(a)
	if len(first) != len(second) {
		t.Fatalf("two calls disagreed: %d vs %d", len(first), len(second))
	}
	for i := range first {
		if first[i].ID != second[i].ID || first[i].IssuedAt != second[i].IssuedAt {
			t.Errorf("badge %d is not stable across calls", i)
		}
	}
}

func TestBadgeIDsAreUniquePerStudent(t *testing.T) {
	a := Activity{Roll: "241551058", MessagesSent: 30, TopicsStarted: 1, VoiceJoins: 1, ZonesVisited: 3}
	seen := map[string]bool{}
	for _, b := range Award(a) {
		if seen[b.ID] {
			t.Errorf("duplicate badge id %q", b.ID)
		}
		seen[b.ID] = true
	}
}

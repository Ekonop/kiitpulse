package radar

import (
	"math"
	"testing"
)

func TestRawScoreWeights(t *testing.T) {
	// 10 messages + 4 reactions + 2 voice joins
	// = 10*1.0 + 4*0.25 + 2*3.5 = 10 + 1 + 7 = 18
	got := RawScore(10, 4, 2)
	if math.Abs(got-18) > 1e-9 {
		t.Errorf("RawScore = %v, want 18", got)
	}
}

func TestScoreAppliesTimeDenominator(t *testing.T) {
	// At exactly one minute the denominator is 1^1.5 = 1.
	got := Score(10, 4, 2, 60)
	if math.Abs(got-18) > 1e-9 {
		t.Errorf("Score at 1min = %v, want 18", got)
	}

	// Four minutes: 18 / 4^1.5 = 18 / 8 = 2.25
	got = Score(10, 4, 2, 240)
	if math.Abs(got-2.25) > 1e-9 {
		t.Errorf("Score at 4min = %v, want 2.25", got)
	}
}

func TestScoreClampsSubMinuteElapsed(t *testing.T) {
	// A brand new topic must not divide by ~zero and explode.
	got := Score(10, 0, 0, 1) // one second
	if got != RawScore(10, 0, 0) {
		t.Errorf("Score at 1s = %v, want the raw score %v",
			got, RawScore(10, 0, 0))
	}
}

func TestDecay(t *testing.T) {
	// 0.85 per minute.
	if got := Decay(100, 1); math.Abs(got-85) > 1e-9 {
		t.Errorf("Decay(100,1) = %v, want 85", got)
	}
	if got := Decay(100, 0); math.Abs(got-100) > 1e-9 {
		t.Errorf("Decay(100,0) = %v, want 100", got)
	}
	// Ten minutes takes a 100 down to ~19.7, i.e. through HOT into COOLING.
	if got := Decay(100, 10); got >= 20 {
		t.Errorf("Decay(100,10) = %v, expected < 20", got)
	}
}

func TestDecayEventualPurge(t *testing.T) {
	// A score must actually reach the purge floor; otherwise the ZSET grows
	// forever and the 24h guarantee is a lie.
	score := 1.0
	minutes := 0
	for score >= PurgeFloor && minutes < 1000 {
		score = Decay(score, 1)
		minutes++
	}
	if score >= PurgeFloor {
		t.Fatalf("a 1.0 score never fell below the purge floor in %d minutes", minutes)
	}
	t.Logf("1.0 decays below %.1f after %d minutes", PurgeFloor, minutes)
}

func TestEventWeights(t *testing.T) {
	if EventMessage.Weight() != WeightMessage {
		t.Error("message weight mismatch")
	}
	if EventReaction.Weight() != WeightReaction {
		t.Error("reaction weight mismatch")
	}
	if EventVoiceJoin.Weight() != WeightVoiceJoin {
		t.Error("voice weight mismatch")
	}
	// A voice join must be worth more than a message: joining a stage is a
	// stronger signal of engagement than typing.
	if WeightVoiceJoin <= WeightMessage {
		t.Error("voice join should outweigh a message")
	}
}

func TestLabel(t *testing.T) {
	cases := map[float64]string{
		200: "SURGING",
		100: "HOT",
		50:  "RISING",
		15:  "WARM",
		1:   "COOLING",
	}
	for score, want := range cases {
		if got := Label(score); got != want {
			t.Errorf("Label(%v) = %q, want %q", score, got, want)
		}
	}
}

// Package radar implements the campus velocity engine.
//
// The score is
//
//	V = (Σ M·w_m + R·w_r + L·w_l) / Δt^γ
//
// with MESSAGE=1.0, REACTION=0.25, VOICE_JOIN=3.5 and γ=1.5. Redis holds one
// sorted set per zone (`kiit:radar:<zone>`), so ranking a zone is a single
// ZREVRANGE instead of a table scan. A cron job applies a 0.85 multiplicative
// decay every minute and drops anything that falls below the purge floor.
//
// Why two mechanisms (a decay multiplier *and* a time denominator): the
// denominator makes a new topic start low even if it is busy, and the decay
// makes an old topic fade without waiting for it to be read. Together they give
// the "surging now" ranking the product needs.
package radar

import "math"

// Event weights from the product spec.
const (
	WeightMessage   = 1.0
	WeightReaction  = 0.25
	WeightVoiceJoin = 3.5

	// Gamma is the time-decay exponent.
	Gamma = 1.5

	// DecayFactor is applied per minute by the decay job.
	DecayFactor = 0.85

	// PurgeFloor is the score below which a topic is removed from the ZSET.
	PurgeFloor = 0.1

	// TopicTTL is how long a topic survives after its last engagement.
	TopicTTL = 24 * 60 * 60 // seconds
)

// EventKind is a thing a student can do that moves the score.
type EventKind string

const (
	EventMessage   EventKind = "MESSAGE"
	EventReaction  EventKind = "REACTION"
	EventVoiceJoin EventKind = "VOICE_JOIN"
)

// Weight returns the score contribution of an event.
func (e EventKind) Weight() float64 {
	switch e {
	case EventMessage:
		return WeightMessage
	case EventReaction:
		return WeightReaction
	case EventVoiceJoin:
		return WeightVoiceJoin
	default:
		return WeightMessage
	}
}

// Score computes the raw, undecayed score for a set of counters over an
// elapsed window. Elapsed is clamped to one minute so a brand new topic does
// not divide by ~zero.
func Score(messages, reactions, voiceJoins int, elapsedSeconds float64) float64 {
	minutes := elapsedSeconds / 60.0
	if minutes < 1 {
		minutes = 1
	}
	return RawScore(messages, reactions, voiceJoins) / math.Pow(minutes, Gamma)
}

// RawScore is the weighted event sum without the time denominator.
func RawScore(messages, reactions, voiceJoins int) float64 {
	return float64(messages)*WeightMessage +
		float64(reactions)*WeightReaction +
		float64(voiceJoins)*WeightVoiceJoin
}

// Decay applies n minutes of decay to a score.
func Decay(current float64, minutes int) float64 {
	return current * math.Pow(DecayFactor, float64(minutes))
}

// Label names a score band for the UI.
func Label(score float64) string {
	switch {
	case score >= 150:
		return "SURGING"
	case score >= 80:
		return "HOT"
	case score >= 30:
		return "RISING"
	case score >= 10:
		return "WARM"
	default:
		return "COOLING"
	}
}
